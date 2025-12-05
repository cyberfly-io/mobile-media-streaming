//! MoQ (Media over QUIC) Protocol Implementation
//!
//! This module implements core MoQ Transport concepts from IETF draft-ietf-moq-transport
//! including:
//! - Track hierarchy (Track → Group → Subgroup → Object)
//! - Subscription filters (LatestGroup, LatestObject, NextGroup, AbsoluteStart, AbsoluteRange)
//! - Priority scheduling (publisher + subscriber priorities)
//! - Namespace discovery and management
//! - Delivery timeout and object expiration

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
// tracing macros available if needed

// ============================================================================
// MoQ DATA MODEL
// ============================================================================

/// A namespace is a collection of tracks (like a channel or broadcaster)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Namespace {
    /// Tuple of namespace components (e.g., ["broadcast", "channel1"])
    pub components: Vec<String>,
}

impl Namespace {
    pub fn new(components: Vec<String>) -> Self {
        Self { components }
    }

    pub fn from_str(s: &str) -> Self {
        let components = s.split('/').map(|s| s.to_string()).collect();
        Self { components }
    }

    pub fn to_string_path(&self) -> String {
        self.components.join("/")
    }

    /// Check if this namespace is a prefix of another
    pub fn is_prefix_of(&self, other: &Namespace) -> bool {
        if self.components.len() > other.components.len() {
            return false;
        }
        self.components.iter().zip(&other.components).all(|(a, b)| a == b)
    }
}

impl std::fmt::Display for Namespace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_string_path())
    }
}

/// Full track identifier = Namespace + Track Name
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FullTrackName {
    pub namespace: Namespace,
    pub track_name: String,
}

impl FullTrackName {
    pub fn new(namespace: Namespace, track_name: &str) -> Self {
        Self {
            namespace,
            track_name: track_name.to_string(),
        }
    }

    pub fn from_path(path: &str) -> Self {
        let parts: Vec<&str> = path.rsplitn(2, '/').collect();
        if parts.len() == 2 {
            Self {
                namespace: Namespace::from_str(parts[1]),
                track_name: parts[0].to_string(),
            }
        } else {
            Self {
                namespace: Namespace::new(vec![]),
                track_name: path.to_string(),
            }
        }
    }

    pub fn to_path(&self) -> String {
        if self.namespace.components.is_empty() {
            self.track_name.clone()
        } else {
            format!("{}/{}", self.namespace, self.track_name)
        }
    }
}

impl std::fmt::Display for FullTrackName {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_path())
    }
}

/// Object ID within a group
pub type ObjectId = u64;

/// Group ID within a track
pub type GroupId = u64;

/// Subgroup ID within a group (for parallel delivery)
pub type SubgroupId = u64;

/// A MoQ Object - the fundamental unit of media data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoqObject {
    /// Group this object belongs to
    pub group_id: GroupId,
    /// Subgroup within the group (for parallel delivery)
    pub subgroup_id: SubgroupId,
    /// Object ID within the group
    pub object_id: ObjectId,
    /// Publisher priority (0-255, lower = higher priority)
    pub publisher_priority: u8,
    /// Delivery timeout (when this object expires)
    pub expires_at: Option<u64>,
    /// Object status
    pub status: ObjectStatus,
    /// Extensions (custom metadata)
    pub extensions: HashMap<String, Vec<u8>>,
    /// Payload data
    pub payload: Vec<u8>,
    /// Timestamp when created
    pub created_at: u64,
}

impl MoqObject {
    pub fn new(group_id: GroupId, subgroup_id: SubgroupId, object_id: ObjectId, payload: Vec<u8>) -> Self {
        Self {
            group_id,
            subgroup_id,
            object_id,
            publisher_priority: 128, // Default middle priority
            expires_at: None,
            status: ObjectStatus::Normal,
            extensions: HashMap::new(),
            payload,
            created_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
        }
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.publisher_priority = priority;
        self
    }

    pub fn with_ttl(mut self, ttl_ms: u64) -> Self {
        self.expires_at = Some(self.created_at + ttl_ms);
        self
    }

    pub fn with_extension(mut self, key: &str, value: Vec<u8>) -> Self {
        self.extensions.insert(key.to_string(), value);
        self
    }

    pub fn is_expired(&self) -> bool {
        if let Some(expires) = self.expires_at {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64;
            now > expires
        } else {
            false
        }
    }

    pub fn size(&self) -> usize {
        self.payload.len()
    }
}

/// Object delivery status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectStatus {
    /// Normal object with payload
    Normal,
    /// Object does not exist
    DoesNotExist,
    /// End of group marker
    EndOfGroup,
    /// End of track marker
    EndOfTrack,
    /// End of subgroup marker
    EndOfSubgroup,
}

/// A Group contains multiple objects (like a GOP in video)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoqGroup {
    pub group_id: GroupId,
    /// Objects within this group, organized by subgroup
    pub subgroups: HashMap<SubgroupId, Vec<MoqObject>>,
    /// Whether this group is complete
    pub is_complete: bool,
    /// Group creation timestamp
    pub created_at: u64,
}

impl MoqGroup {
    pub fn new(group_id: GroupId) -> Self {
        Self {
            group_id,
            subgroups: HashMap::new(),
            is_complete: false,
            created_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
        }
    }

    pub fn add_object(&mut self, obj: MoqObject) {
        let subgroup = self.subgroups.entry(obj.subgroup_id).or_insert_with(Vec::new);
        subgroup.push(obj);
    }

    pub fn mark_complete(&mut self) {
        self.is_complete = true;
    }

    pub fn object_count(&self) -> usize {
        self.subgroups.values().map(|v| v.len()).sum()
    }

    pub fn total_size(&self) -> usize {
        self.subgroups.values()
            .flat_map(|v| v.iter())
            .map(|o| o.size())
            .sum()
    }
}

// ============================================================================
// SUBSCRIPTION FILTERS (from MoQ spec)
// ============================================================================

/// Group ordering for subscription delivery
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GroupOrder {
    /// Deliver in ascending order (oldest first)
    Ascending,
    /// Deliver in descending order (newest first)
    Descending,
    /// Publisher decides (relay must know publisher's preference)
    PublisherDefault,
}

/// Subscription filter type (determines starting point)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum FilterType {
    /// Start from the latest group
    LatestGroup,
    /// Start from the latest object
    LatestObject,
    /// Start from the next group (live edge)
    NextGroup,
    /// Start from a specific absolute position
    AbsoluteStart {
        start_group: GroupId,
        start_object: ObjectId,
    },
    /// Request a specific range of objects
    AbsoluteRange {
        start_group: GroupId,
        start_object: ObjectId,
        end_group: GroupId,
        end_object: Option<ObjectId>,
    },
}

/// Subscription parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubscriptionParams {
    /// Track to subscribe to
    pub track: FullTrackName,
    /// Subscription filter
    pub filter: FilterType,
    /// Group ordering preference
    pub group_order: GroupOrder,
    /// Subscriber priority (0-255, lower = higher priority)
    pub subscriber_priority: u8,
    /// Delivery timeout in milliseconds (0 = no timeout)
    pub delivery_timeout_ms: u64,
    /// Max cache duration to request (milliseconds)
    pub max_cache_duration_ms: Option<u64>,
}

impl SubscriptionParams {
    pub fn new(track: FullTrackName) -> Self {
        Self {
            track,
            filter: FilterType::LatestGroup,
            group_order: GroupOrder::Ascending,
            subscriber_priority: 128,
            delivery_timeout_ms: 0,
            max_cache_duration_ms: None,
        }
    }

    pub fn with_filter(mut self, filter: FilterType) -> Self {
        self.filter = filter;
        self
    }

    pub fn with_order(mut self, order: GroupOrder) -> Self {
        self.group_order = order;
        self
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.subscriber_priority = priority;
        self
    }

    pub fn with_timeout(mut self, timeout_ms: u64) -> Self {
        self.delivery_timeout_ms = timeout_ms;
        self
    }

    /// Calculate effective priority (subscriber takes precedence)
    pub fn effective_priority(&self, publisher_priority: u8) -> u8 {
        // Per MoQ spec: subscriber priority takes precedence when relaying
        self.subscriber_priority
    }
}

// ============================================================================
// TRACK STATUS
// ============================================================================

/// Track status (for SUBSCRIBE_OK, TRACK_STATUS)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackStatus {
    /// Track name
    pub track: FullTrackName,
    /// Current status
    pub status: TrackStatusCode,
    /// Latest group ID available
    pub latest_group_id: Option<GroupId>,
    /// Latest object ID in latest group
    pub latest_object_id: Option<ObjectId>,
    /// Group order used by publisher
    pub group_order: GroupOrder,
    /// Publisher priority
    pub publisher_priority: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrackStatusCode {
    /// Track is active and receiving data
    Active,
    /// Track is not available
    NotFound,
    /// Track is paused
    Paused,
    /// Track has ended
    Ended,
    /// Unknown status (relay doesn't know)
    Unknown,
}

// ============================================================================
// PRIORITY SCHEDULER
// ============================================================================

/// Priority-based delivery scheduler
/// Implements MoQ priority semantics where lower numbers = higher priority
pub struct PriorityScheduler {
    /// Pending objects sorted by effective priority
    pending: Arc<RwLock<Vec<PendingDelivery>>>,
    /// Maximum queue size
    max_queue_size: usize,
}

#[derive(Debug, Clone)]
struct PendingDelivery {
    object: MoqObject,
    subscriber_priority: u8,
    effective_priority: u8,
    queued_at: Instant,
}

impl PriorityScheduler {
    pub fn new(max_queue_size: usize) -> Self {
        Self {
            pending: Arc::new(RwLock::new(Vec::new())),
            max_queue_size,
        }
    }

    /// Enqueue an object for delivery
    pub async fn enqueue(&self, object: MoqObject, subscriber_priority: u8) {
        let effective_priority = subscriber_priority; // MoQ: subscriber takes precedence
        
        let delivery = PendingDelivery {
            object,
            subscriber_priority,
            effective_priority,
            queued_at: Instant::now(),
        };

        let mut pending = self.pending.write().await;
        
        // Insert in priority order
        let pos = pending.iter()
            .position(|d| d.effective_priority > effective_priority)
            .unwrap_or(pending.len());
        
        pending.insert(pos, delivery);

        // Trim if over max size (drop lowest priority items)
        while pending.len() > self.max_queue_size {
            pending.pop();
        }
    }

    /// Dequeue the highest priority object
    pub async fn dequeue(&self) -> Option<MoqObject> {
        let mut pending = self.pending.write().await;
        
        // Remove expired objects first
        pending.retain(|d| !d.object.is_expired());
        
        if pending.is_empty() {
            None
        } else {
            Some(pending.remove(0).object)
        }
    }

    /// Get queue length
    pub async fn queue_len(&self) -> usize {
        self.pending.read().await.len()
    }

    /// Drop objects with priority lower than threshold during congestion
    pub async fn drop_low_priority(&self, threshold: u8) -> usize {
        let mut pending = self.pending.write().await;
        let before = pending.len();
        pending.retain(|d| d.effective_priority <= threshold);
        before - pending.len()
    }
}

// ============================================================================
// TRACK STORE
// ============================================================================

/// In-memory track data store with retention policy
pub struct TrackStore {
    /// Track data: track_name -> groups
    tracks: Arc<RwLock<HashMap<String, TrackData>>>,
    /// Max retention duration
    max_retention: Duration,
    /// Max groups to retain per track
    max_groups: usize,
}

struct TrackData {
    status: TrackStatus,
    groups: HashMap<GroupId, MoqGroup>,
    next_group_id: GroupId,
    next_object_id: HashMap<GroupId, ObjectId>,
}

impl TrackStore {
    pub fn new(max_retention: Duration, max_groups: usize) -> Self {
        Self {
            tracks: Arc::new(RwLock::new(HashMap::new())),
            max_retention,
            max_groups,
        }
    }

    /// Create or get a track
    pub async fn get_or_create_track(&self, track: &FullTrackName) -> TrackStatus {
        let mut tracks = self.tracks.write().await;
        let key = track.to_path();
        
        tracks.entry(key).or_insert_with(|| TrackData {
            status: TrackStatus {
                track: track.clone(),
                status: TrackStatusCode::Active,
                latest_group_id: None,
                latest_object_id: None,
                group_order: GroupOrder::Ascending,
                publisher_priority: 128,
            },
            groups: HashMap::new(),
            next_group_id: 0,
            next_object_id: HashMap::new(),
        }).status.clone()
    }

    /// Start a new group
    pub async fn start_group(&self, track: &FullTrackName) -> GroupId {
        let mut tracks = self.tracks.write().await;
        let key = track.to_path();
        
        if let Some(data) = tracks.get_mut(&key) {
            let group_id = data.next_group_id;
            data.next_group_id += 1;
            data.groups.insert(group_id, MoqGroup::new(group_id));
            data.next_object_id.insert(group_id, 0);
            data.status.latest_group_id = Some(group_id);
            
            // Cleanup old groups
            self.cleanup_old_groups(data);
            
            group_id
        } else {
            0
        }
    }

    /// Add an object to a group
    pub async fn add_object(&self, track: &FullTrackName, group_id: GroupId, 
                            subgroup_id: SubgroupId, payload: Vec<u8>) -> Option<MoqObject> {
        let mut tracks = self.tracks.write().await;
        let key = track.to_path();
        
        if let Some(data) = tracks.get_mut(&key) {
            let object_id = data.next_object_id.entry(group_id).or_insert(0);
            let obj = MoqObject::new(group_id, subgroup_id, *object_id, payload);
            *object_id += 1;
            
            data.status.latest_object_id = Some(obj.object_id);
            
            if let Some(group) = data.groups.get_mut(&group_id) {
                group.add_object(obj.clone());
            }
            
            Some(obj)
        } else {
            None
        }
    }

    /// Get objects based on subscription filter
    pub async fn get_objects(&self, params: &SubscriptionParams) -> Vec<MoqObject> {
        let tracks = self.tracks.read().await;
        let key = params.track.to_path();
        
        if let Some(data) = tracks.get(&key) {
            let mut objects: Vec<MoqObject> = match &params.filter {
                FilterType::LatestGroup => {
                    // Get all objects from the latest group
                    if let Some(group_id) = data.status.latest_group_id {
                        if let Some(group) = data.groups.get(&group_id) {
                            group.subgroups.values().flat_map(|v| v.clone()).collect()
                        } else {
                            vec![]
                        }
                    } else {
                        vec![]
                    }
                }
                FilterType::LatestObject => {
                    // Get just the latest object
                    if let (Some(group_id), Some(object_id)) = 
                        (data.status.latest_group_id, data.status.latest_object_id) {
                        if let Some(group) = data.groups.get(&group_id) {
                            group.subgroups.values()
                                .flat_map(|v| v.iter())
                                .filter(|o| o.object_id == object_id)
                                .cloned()
                                .collect()
                        } else {
                            vec![]
                        }
                    } else {
                        vec![]
                    }
                }
                FilterType::NextGroup => {
                    // Empty - we'll deliver new objects as they arrive
                    vec![]
                }
                FilterType::AbsoluteStart { start_group, start_object } => {
                    // Get all objects starting from specified position
                    data.groups.iter()
                        .filter(|(gid, _)| **gid >= *start_group)
                        .flat_map(|(gid, g)| {
                            g.subgroups.values().flat_map(|v| v.iter())
                                .filter(|o| *gid > *start_group || o.object_id >= *start_object)
                                .cloned()
                        })
                        .collect()
                }
                FilterType::AbsoluteRange { start_group, start_object, end_group, end_object } => {
                    data.groups.iter()
                        .filter(|(gid, _)| **gid >= *start_group && **gid <= *end_group)
                        .flat_map(|(gid, g)| {
                            g.subgroups.values().flat_map(|v| v.iter())
                                .filter(|o| {
                                    let after_start = *gid > *start_group || o.object_id >= *start_object;
                                    let before_end = *gid < *end_group || 
                                        end_object.map_or(true, |eo| o.object_id <= eo);
                                    after_start && before_end
                                })
                                .cloned()
                        })
                        .collect()
                }
            };

            // Sort by group order
            match params.group_order {
                GroupOrder::Ascending | GroupOrder::PublisherDefault => {
                    objects.sort_by(|a, b| {
                        a.group_id.cmp(&b.group_id)
                            .then_with(|| a.object_id.cmp(&b.object_id))
                    });
                }
                GroupOrder::Descending => {
                    objects.sort_by(|a, b| {
                        b.group_id.cmp(&a.group_id)
                            .then_with(|| b.object_id.cmp(&a.object_id))
                    });
                }
            }

            // Filter expired objects
            objects.retain(|o| !o.is_expired());

            objects
        } else {
            vec![]
        }
    }

    /// Get track status
    pub async fn get_track_status(&self, track: &FullTrackName) -> Option<TrackStatus> {
        let tracks = self.tracks.read().await;
        tracks.get(&track.to_path()).map(|d| d.status.clone())
    }

    fn cleanup_old_groups(&self, data: &mut TrackData) {
        if data.groups.len() > self.max_groups {
            let mut group_ids: Vec<_> = data.groups.keys().copied().collect();
            group_ids.sort();
            
            let to_remove = data.groups.len() - self.max_groups;
            for gid in group_ids.into_iter().take(to_remove) {
                data.groups.remove(&gid);
                data.next_object_id.remove(&gid);
            }
        }
    }
}

// ============================================================================
// NAMESPACE MANAGER
// ============================================================================

/// Namespace announcement and discovery
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamespaceAnnouncement {
    pub namespace: Namespace,
    /// Available tracks in this namespace
    pub tracks: Vec<String>,
    /// Whether new tracks can be published
    pub accepts_publishing: bool,
    /// Authorization token (optional)
    pub auth_token: Option<String>,
}

/// Namespace manager for PUBLISH_NAMESPACE / SUBSCRIBE_NAMESPACE
pub struct NamespaceManager {
    /// Published namespaces
    published: Arc<RwLock<HashMap<String, NamespaceAnnouncement>>>,
    /// Subscribed namespaces
    subscribed: Arc<RwLock<HashMap<String, NamespaceAnnouncement>>>,
}

impl NamespaceManager {
    pub fn new() -> Self {
        Self {
            published: Arc::new(RwLock::new(HashMap::new())),
            subscribed: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Announce a namespace (PUBLISH_NAMESPACE equivalent)
    pub async fn announce(&self, announcement: NamespaceAnnouncement) {
        let key = announcement.namespace.to_string_path();
        self.published.write().await.insert(key, announcement);
    }

    /// Subscribe to a namespace prefix (SUBSCRIBE_NAMESPACE equivalent)
    pub async fn subscribe(&self, namespace_prefix: Namespace) -> Vec<NamespaceAnnouncement> {
        let published = self.published.read().await;
        published.values()
            .filter(|a| namespace_prefix.is_prefix_of(&a.namespace))
            .cloned()
            .collect()
    }

    /// List all published namespaces
    pub async fn list_published(&self) -> Vec<NamespaceAnnouncement> {
        self.published.read().await.values().cloned().collect()
    }

    /// Get announcement for specific namespace
    pub async fn get_announcement(&self, namespace: &Namespace) -> Option<NamespaceAnnouncement> {
        self.published.read().await.get(&namespace.to_string_path()).cloned()
    }
}

impl Default for NamespaceManager {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// FETCH SUPPORT
// ============================================================================

/// FETCH request for historical content (from MoQ spec)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FetchRequest {
    /// Track to fetch from
    pub track: FullTrackName,
    /// Subscriber priority
    pub subscriber_priority: u8,
    /// Group order preference
    pub group_order: GroupOrder,
    /// Start group
    pub start_group: GroupId,
    /// Start object
    pub start_object: ObjectId,
    /// End group
    pub end_group: GroupId,
    /// End object (if None, fetch until end of group)
    pub end_object: Option<ObjectId>,
}

impl FetchRequest {
    pub fn new(track: FullTrackName, start_group: GroupId, start_object: ObjectId,
               end_group: GroupId, end_object: Option<ObjectId>) -> Self {
        Self {
            track,
            subscriber_priority: 128,
            group_order: GroupOrder::Ascending,
            start_group,
            start_object,
            end_group,
            end_object,
        }
    }

    pub fn with_priority(mut self, priority: u8) -> Self {
        self.subscriber_priority = priority;
        self
    }

    /// Convert to subscription params for reuse
    pub fn to_subscription_params(&self) -> SubscriptionParams {
        SubscriptionParams {
            track: self.track.clone(),
            filter: FilterType::AbsoluteRange {
                start_group: self.start_group,
                start_object: self.start_object,
                end_group: self.end_group,
                end_object: self.end_object,
            },
            group_order: self.group_order,
            subscriber_priority: self.subscriber_priority,
            delivery_timeout_ms: 0,
            max_cache_duration_ms: None,
        }
    }
}

// ============================================================================
// MoQ PROTOCOL MESSAGES
// ============================================================================

/// MoQ protocol message types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MoqMessage {
    // Session messages
    ClientSetup { supported_versions: Vec<u32>, params: HashMap<String, Vec<u8>> },
    ServerSetup { selected_version: u32, params: HashMap<String, Vec<u8>> },
    
    // Namespace messages
    AnnounceNamespace { namespace: Namespace, tracks: Vec<String> },
    AnnounceNamespaceOk { namespace: Namespace },
    AnnounceNamespaceError { namespace: Namespace, error: String },
    UnannounceNamespace { namespace: Namespace },
    SubscribeNamespace { namespace_prefix: Namespace },
    SubscribeNamespaceOk { namespace_prefix: Namespace },
    SubscribeNamespaceError { namespace_prefix: Namespace, error: String },
    
    // Track messages
    Subscribe { subscribe_id: u64, params: SubscriptionParams },
    SubscribeOk { subscribe_id: u64, status: TrackStatus },
    SubscribeError { subscribe_id: u64, error: String },
    SubscribeUpdate { subscribe_id: u64, params: SubscriptionParams },
    Unsubscribe { subscribe_id: u64 },
    SubscribeDone { subscribe_id: u64, reason: String },
    
    // Data messages
    Object { subscribe_id: u64, object: MoqObject },
    ObjectAck { subscribe_id: u64, group_id: GroupId, object_id: ObjectId },
    
    // Fetch messages
    Fetch { fetch_id: u64, request: FetchRequest },
    FetchOk { fetch_id: u64, status: TrackStatus },
    FetchError { fetch_id: u64, error: String },
    FetchCancel { fetch_id: u64 },
    
    // Track status
    TrackStatusRequest { track: FullTrackName },
    TrackStatusResponse { status: TrackStatus },
    
    // Error/close
    GoAway { new_uri: Option<String> },
}

impl MoqMessage {
    pub fn encode(&self) -> Result<Vec<u8>> {
        postcard::to_stdvec(self).map_err(Into::into)
    }

    pub fn decode(data: &[u8]) -> Result<Self> {
        postcard::from_bytes(data).map_err(Into::into)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_namespace_prefix() {
        let ns1 = Namespace::from_str("broadcast/channel1");
        let ns2 = Namespace::from_str("broadcast/channel1/video");
        let ns3 = Namespace::from_str("broadcast/channel2");
        
        assert!(ns1.is_prefix_of(&ns2));
        assert!(!ns1.is_prefix_of(&ns3));
    }

    #[test]
    fn test_full_track_name() {
        let track = FullTrackName::from_path("broadcast/channel1/video-720p");
        assert_eq!(track.namespace.to_string_path(), "broadcast/channel1");
        assert_eq!(track.track_name, "video-720p");
    }

    #[test]
    fn test_priority_ordering() {
        // Lower priority number = higher priority
        let high = MoqObject::new(0, 0, 0, vec![]).with_priority(0);
        let med = MoqObject::new(0, 0, 1, vec![]).with_priority(128);
        let low = MoqObject::new(0, 0, 2, vec![]).with_priority(255);
        
        assert!(high.publisher_priority < med.publisher_priority);
        assert!(med.publisher_priority < low.publisher_priority);
    }

    #[test]
    fn test_object_expiration() {
        let obj = MoqObject::new(0, 0, 0, vec![]).with_ttl(0); // Expire immediately
        std::thread::sleep(std::time::Duration::from_millis(1));
        assert!(obj.is_expired());
    }

    #[tokio::test]
    async fn test_track_store() {
        let store = TrackStore::new(Duration::from_secs(60), 10);
        let track = FullTrackName::from_path("test/video");
        
        store.get_or_create_track(&track).await;
        let group_id = store.start_group(&track).await;
        
        store.add_object(&track, group_id, 0, vec![1, 2, 3]).await;
        store.add_object(&track, group_id, 0, vec![4, 5, 6]).await;
        
        let params = SubscriptionParams::new(track.clone())
            .with_filter(FilterType::LatestGroup);
        let objects = store.get_objects(&params).await;
        
        assert_eq!(objects.len(), 2);
    }
}
