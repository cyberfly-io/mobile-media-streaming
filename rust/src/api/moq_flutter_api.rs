//! Flutter-Rust bridge API for MoQ (Media over QUIC) protocol features
//!
//! This provides access to advanced MoQ features:
//! - Track/Group/Subgroup hierarchy
//! - Subscription filters (LatestGroup, NextGroup, AbsoluteRange, etc.)
//! - Priority scheduling (0-255, lower = higher priority)
//! - Namespace discovery
//! - FETCH for historical content

use std::sync::Arc;
use std::time::Duration;
use flutter_rust_bridge::frb;

use super::moq_protocol::{
    Namespace, FullTrackName, MoqObject, ObjectStatus,
    GroupOrder, FilterType, SubscriptionParams, TrackStatus, TrackStatusCode,
    NamespaceAnnouncement, NamespaceManager, TrackStore, PriorityScheduler,
    FetchRequest,
};

// ============================================================================
// GLOBAL STATE
// ============================================================================

static TRACK_STORE: once_cell::sync::OnceCell<Arc<TrackStore>> = once_cell::sync::OnceCell::new();
static NAMESPACE_MANAGER: once_cell::sync::OnceCell<Arc<NamespaceManager>> = once_cell::sync::OnceCell::new();
static PRIORITY_SCHEDULER: once_cell::sync::OnceCell<Arc<PriorityScheduler>> = once_cell::sync::OnceCell::new();

fn get_track_store() -> &'static Arc<TrackStore> {
    TRACK_STORE.get_or_init(|| Arc::new(TrackStore::new(Duration::from_secs(300), 100)))
}

fn get_namespace_manager() -> &'static Arc<NamespaceManager> {
    NAMESPACE_MANAGER.get_or_init(|| Arc::new(NamespaceManager::new()))
}

fn get_scheduler() -> &'static Arc<PriorityScheduler> {
    PRIORITY_SCHEDULER.get_or_init(|| Arc::new(PriorityScheduler::new(1000)))
}

// ============================================================================
// FLUTTER TYPES - GROUP ORDER
// ============================================================================

/// Group delivery order for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterGroupOrder {
    /// Oldest groups first (default for live)
    Ascending,
    /// Newest groups first (for catch-up)
    Descending,
    /// Use publisher's default
    PublisherDefault,
}

impl From<FlutterGroupOrder> for GroupOrder {
    fn from(o: FlutterGroupOrder) -> Self {
        match o {
            FlutterGroupOrder::Ascending => GroupOrder::Ascending,
            FlutterGroupOrder::Descending => GroupOrder::Descending,
            FlutterGroupOrder::PublisherDefault => GroupOrder::PublisherDefault,
        }
    }
}

impl From<GroupOrder> for FlutterGroupOrder {
    fn from(o: GroupOrder) -> Self {
        match o {
            GroupOrder::Ascending => FlutterGroupOrder::Ascending,
            GroupOrder::Descending => FlutterGroupOrder::Descending,
            GroupOrder::PublisherDefault => FlutterGroupOrder::PublisherDefault,
        }
    }
}

// ============================================================================
// FLUTTER TYPES - SUBSCRIPTION FILTER
// ============================================================================

/// Subscription filter type for Flutter
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlutterFilterType {
    /// Start from the latest complete group
    LatestGroup,
    /// Start from the latest object
    LatestObject,
    /// Start from next group (live edge, real-time only)
    NextGroup,
    /// Start from absolute position
    AbsoluteStart { start_group: u64, start_object: u64 },
    /// Request a range of objects (for VOD/catch-up)
    AbsoluteRange { 
        start_group: u64, 
        start_object: u64, 
        end_group: u64, 
        end_object: Option<u64>,
    },
}

impl From<FlutterFilterType> for FilterType {
    fn from(f: FlutterFilterType) -> Self {
        match f {
            FlutterFilterType::LatestGroup => FilterType::LatestGroup,
            FlutterFilterType::LatestObject => FilterType::LatestObject,
            FlutterFilterType::NextGroup => FilterType::NextGroup,
            FlutterFilterType::AbsoluteStart { start_group, start_object } => {
                FilterType::AbsoluteStart { start_group, start_object }
            }
            FlutterFilterType::AbsoluteRange { start_group, start_object, end_group, end_object } => {
                FilterType::AbsoluteRange { start_group, start_object, end_group, end_object }
            }
        }
    }
}

// ============================================================================
// FLUTTER TYPES - OBJECT STATUS
// ============================================================================

/// Object delivery status for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterObjectStatus {
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

impl From<ObjectStatus> for FlutterObjectStatus {
    fn from(s: ObjectStatus) -> Self {
        match s {
            ObjectStatus::Normal => FlutterObjectStatus::Normal,
            ObjectStatus::DoesNotExist => FlutterObjectStatus::DoesNotExist,
            ObjectStatus::EndOfGroup => FlutterObjectStatus::EndOfGroup,
            ObjectStatus::EndOfTrack => FlutterObjectStatus::EndOfTrack,
            ObjectStatus::EndOfSubgroup => FlutterObjectStatus::EndOfSubgroup,
        }
    }
}

// ============================================================================
// FLUTTER TYPES - TRACK STATUS
// ============================================================================

/// Track status code for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterTrackStatusCode {
    Active,
    NotFound,
    Paused,
    Ended,
    Unknown,
}

impl From<TrackStatusCode> for FlutterTrackStatusCode {
    fn from(s: TrackStatusCode) -> Self {
        match s {
            TrackStatusCode::Active => FlutterTrackStatusCode::Active,
            TrackStatusCode::NotFound => FlutterTrackStatusCode::NotFound,
            TrackStatusCode::Paused => FlutterTrackStatusCode::Paused,
            TrackStatusCode::Ended => FlutterTrackStatusCode::Ended,
            TrackStatusCode::Unknown => FlutterTrackStatusCode::Unknown,
        }
    }
}

/// Track status info for Flutter
#[derive(Debug, Clone)]
pub struct FlutterTrackStatus {
    pub track_path: String,
    pub status: FlutterTrackStatusCode,
    pub latest_group_id: Option<u64>,
    pub latest_object_id: Option<u64>,
    pub group_order: FlutterGroupOrder,
    pub publisher_priority: u8,
}

impl From<&TrackStatus> for FlutterTrackStatus {
    fn from(s: &TrackStatus) -> Self {
        Self {
            track_path: s.track.to_path(),
            status: s.status.into(),
            latest_group_id: s.latest_group_id,
            latest_object_id: s.latest_object_id,
            group_order: s.group_order.into(),
            publisher_priority: s.publisher_priority,
        }
    }
}

// ============================================================================
// FLUTTER TYPES - MOQ OBJECT
// ============================================================================

/// MoQ Object for Flutter
#[derive(Debug, Clone)]
pub struct FlutterMoqObject {
    pub group_id: u64,
    pub subgroup_id: u64,
    pub object_id: u64,
    pub publisher_priority: u8,
    pub expires_at: Option<u64>,
    pub status: FlutterObjectStatus,
    pub payload: Vec<u8>,
    pub created_at: u64,
    pub is_expired: bool,
}

impl From<&MoqObject> for FlutterMoqObject {
    fn from(o: &MoqObject) -> Self {
        Self {
            group_id: o.group_id,
            subgroup_id: o.subgroup_id,
            object_id: o.object_id,
            publisher_priority: o.publisher_priority,
            expires_at: o.expires_at,
            status: o.status.into(),
            payload: o.payload.clone(),
            created_at: o.created_at,
            is_expired: o.is_expired(),
        }
    }
}

// ============================================================================
// FLUTTER TYPES - NAMESPACE
// ============================================================================

/// Namespace announcement for Flutter
#[derive(Debug, Clone)]
pub struct FlutterNamespaceAnnouncement {
    pub namespace_path: String,
    pub tracks: Vec<String>,
    pub accepts_publishing: bool,
}

impl From<&NamespaceAnnouncement> for FlutterNamespaceAnnouncement {
    fn from(a: &NamespaceAnnouncement) -> Self {
        Self {
            namespace_path: a.namespace.to_string_path(),
            tracks: a.tracks.clone(),
            accepts_publishing: a.accepts_publishing,
        }
    }
}

// ============================================================================
// TRACK MANAGEMENT API
// ============================================================================

/// Create a new track (publisher)
#[frb]
pub async fn moq_create_track(track_path: String) -> Result<FlutterTrackStatus, String> {
    let track = FullTrackName::from_path(&track_path);
    let status = get_track_store().get_or_create_track(&track).await;
    Ok((&status).into())
}

/// Start a new group in a track (returns group_id)
#[frb]
pub async fn moq_start_group(track_path: String) -> Result<u64, String> {
    let track = FullTrackName::from_path(&track_path);
    let group_id = get_track_store().start_group(&track).await;
    Ok(group_id)
}

/// Add an object to a group
/// - priority: 0-255, lower = higher priority (default 128)
/// - ttl_ms: optional time-to-live in milliseconds
#[frb]
pub async fn moq_add_object(
    track_path: String,
    group_id: u64,
    subgroup_id: u64,
    payload: Vec<u8>,
    priority: Option<u8>,
    ttl_ms: Option<u64>,
) -> Result<FlutterMoqObject, String> {
    let track = FullTrackName::from_path(&track_path);
    
    let obj = get_track_store()
        .add_object(&track, group_id, subgroup_id, payload)
        .await
        .ok_or_else(|| "Track not found".to_string())?;
    
    // Apply priority and TTL
    let mut obj = obj;
    if let Some(p) = priority {
        obj.publisher_priority = p;
    }
    if let Some(ttl) = ttl_ms {
        obj.expires_at = Some(obj.created_at + ttl);
    }
    
    Ok((&obj).into())
}

/// Get track status
#[frb]
pub async fn moq_get_track_status(track_path: String) -> Result<FlutterTrackStatus, String> {
    let track = FullTrackName::from_path(&track_path);
    let status = get_track_store()
        .get_track_status(&track)
        .await
        .ok_or_else(|| "Track not found".to_string())?;
    Ok((&status).into())
}

// ============================================================================
// SUBSCRIPTION API
// ============================================================================

/// Subscribe to a track with filter
#[frb]
pub async fn moq_subscribe(
    track_path: String,
    filter: FlutterFilterType,
    group_order: FlutterGroupOrder,
    subscriber_priority: u8,
) -> Result<Vec<FlutterMoqObject>, String> {
    let track = FullTrackName::from_path(&track_path);
    
    let params = SubscriptionParams::new(track)
        .with_filter(filter.into())
        .with_order(group_order.into())
        .with_priority(subscriber_priority);
    
    let objects = get_track_store().get_objects(&params).await;
    Ok(objects.iter().map(|o| o.into()).collect())
}

/// Subscribe starting from latest group (convenience function)
#[frb]
pub async fn moq_subscribe_latest_group(track_path: String) -> Result<Vec<FlutterMoqObject>, String> {
    moq_subscribe(
        track_path,
        FlutterFilterType::LatestGroup,
        FlutterGroupOrder::Ascending,
        128,
    ).await
}

/// Subscribe to live edge (NextGroup - real-time only)
#[frb]
pub async fn moq_subscribe_live(track_path: String) -> Result<Vec<FlutterMoqObject>, String> {
    moq_subscribe(
        track_path,
        FlutterFilterType::NextGroup,
        FlutterGroupOrder::Ascending,
        64, // Higher priority for live
    ).await
}

/// Subscribe with range (for catch-up/VOD)
#[frb]
pub async fn moq_subscribe_range(
    track_path: String,
    start_group: u64,
    start_object: u64,
    end_group: u64,
    end_object: Option<u64>,
) -> Result<Vec<FlutterMoqObject>, String> {
    moq_subscribe(
        track_path,
        FlutterFilterType::AbsoluteRange { 
            start_group, 
            start_object, 
            end_group, 
            end_object,
        },
        FlutterGroupOrder::Ascending,
        128,
    ).await
}

// ============================================================================
// FETCH API (for historical content)
// ============================================================================

/// Fetch historical objects from a track
#[frb]
pub async fn moq_fetch(
    track_path: String,
    start_group: u64,
    start_object: u64,
    end_group: u64,
    end_object: Option<u64>,
    priority: Option<u8>,
) -> Result<Vec<FlutterMoqObject>, String> {
    let track = FullTrackName::from_path(&track_path);
    
    let request = FetchRequest::new(
        track,
        start_group,
        start_object,
        end_group,
        end_object,
    ).with_priority(priority.unwrap_or(128));
    
    let params = request.to_subscription_params();
    let objects = get_track_store().get_objects(&params).await;
    
    Ok(objects.iter().map(|o| o.into()).collect())
}

// ============================================================================
// PRIORITY SCHEDULER API
// ============================================================================

/// Enqueue an object for priority-based delivery
#[frb]
pub async fn moq_enqueue_object(
    group_id: u64,
    subgroup_id: u64,
    object_id: u64,
    payload: Vec<u8>,
    publisher_priority: u8,
    subscriber_priority: u8,
    ttl_ms: Option<u64>,
) -> Result<(), String> {
    let mut obj = MoqObject::new(group_id, subgroup_id, object_id, payload)
        .with_priority(publisher_priority);
    
    if let Some(ttl) = ttl_ms {
        obj = obj.with_ttl(ttl);
    }
    
    get_scheduler().enqueue(obj, subscriber_priority).await;
    Ok(())
}

/// Dequeue the highest priority object
#[frb]
pub async fn moq_dequeue_object() -> Result<Option<FlutterMoqObject>, String> {
    let obj = get_scheduler().dequeue().await;
    Ok(obj.as_ref().map(|o| o.into()))
}

/// Get scheduler queue length
#[frb]
pub async fn moq_get_queue_length() -> Result<u32, String> {
    Ok(get_scheduler().queue_len().await as u32)
}

/// Drop low priority objects during congestion
/// Returns number of objects dropped
#[frb]
pub async fn moq_drop_low_priority(threshold: u8) -> Result<u32, String> {
    Ok(get_scheduler().drop_low_priority(threshold).await as u32)
}

// ============================================================================
// NAMESPACE API
// ============================================================================

/// Announce a namespace (make tracks available for discovery)
#[frb]
pub async fn moq_announce_namespace(
    namespace_path: String,
    tracks: Vec<String>,
    accepts_publishing: bool,
) -> Result<(), String> {
    let announcement = NamespaceAnnouncement {
        namespace: Namespace::from_str(&namespace_path),
        tracks,
        accepts_publishing,
        auth_token: None,
    };
    
    get_namespace_manager().announce(announcement).await;
    Ok(())
}

/// Subscribe to a namespace prefix (discover namespaces)
#[frb]
pub async fn moq_subscribe_namespace(
    namespace_prefix: String,
) -> Result<Vec<FlutterNamespaceAnnouncement>, String> {
    let prefix = Namespace::from_str(&namespace_prefix);
    let announcements = get_namespace_manager().subscribe(prefix).await;
    Ok(announcements.iter().map(|a| a.into()).collect())
}

/// List all published namespaces
#[frb]
pub async fn moq_list_namespaces() -> Result<Vec<FlutterNamespaceAnnouncement>, String> {
    let announcements = get_namespace_manager().list_published().await;
    Ok(announcements.iter().map(|a| a.into()).collect())
}

/// Get announcement for specific namespace
#[frb]
pub async fn moq_get_namespace(
    namespace_path: String,
) -> Result<Option<FlutterNamespaceAnnouncement>, String> {
    let namespace = Namespace::from_str(&namespace_path);
    let announcement = get_namespace_manager().get_announcement(&namespace).await;
    Ok(announcement.as_ref().map(|a| a.into()))
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Get all available filter types (for UI)
#[frb]
pub fn moq_get_filter_types() -> Vec<String> {
    vec![
        "LatestGroup".to_string(),
        "LatestObject".to_string(),
        "NextGroup".to_string(),
        "AbsoluteStart".to_string(),
        "AbsoluteRange".to_string(),
    ]
}

/// Get all group order options
#[frb]
pub fn moq_get_group_orders() -> Vec<String> {
    vec![
        "Ascending".to_string(),
        "Descending".to_string(),
        "PublisherDefault".to_string(),
    ]
}

/// Get priority range info
#[frb]
pub fn moq_get_priority_info() -> (u8, u8, u8) {
    // (min, max, default)
    // Lower number = higher priority
    (0, 255, 128)
}

/// Parse a track path into namespace and track name
#[frb]
pub fn moq_parse_track_path(track_path: String) -> (String, String) {
    let track = FullTrackName::from_path(&track_path);
    (track.namespace.to_string_path(), track.track_name)
}

/// Create a track path from namespace and track name
#[frb]
pub fn moq_create_track_path(namespace: String, track_name: String) -> String {
    let ns = Namespace::from_str(&namespace);
    let track = FullTrackName::new(ns, &track_name);
    track.to_path()
}

/// Check if one namespace is a prefix of another
#[frb]
pub fn moq_namespace_is_prefix(prefix: String, full_path: String) -> bool {
    let prefix_ns = Namespace::from_str(&prefix);
    let full_ns = Namespace::from_str(&full_path);
    prefix_ns.is_prefix_of(&full_ns)
}

// ============================================================================
// OBJECT HELPERS
// ============================================================================

/// Create an end-of-group marker object
#[frb]
pub async fn moq_create_end_of_group(
    track_path: String,
    group_id: u64,
) -> Result<FlutterMoqObject, String> {
    let mut obj = MoqObject::new(group_id, 0, u64::MAX, vec![]);
    obj.status = ObjectStatus::EndOfGroup;
    Ok((&obj).into())
}

/// Create an end-of-track marker object
#[frb]
pub async fn moq_create_end_of_track(
    track_path: String,
    group_id: u64,
) -> Result<FlutterMoqObject, String> {
    let mut obj = MoqObject::new(group_id, 0, u64::MAX, vec![]);
    obj.status = ObjectStatus::EndOfTrack;
    Ok((&obj).into())
}

/// Get estimated delivery time based on priority
#[frb]
pub fn moq_estimate_delivery_time(priority: u8, queue_length: u32) -> u32 {
    // Simple estimation: higher priority objects get through faster
    // Base time per object is 10ms, priority 0 gets 0.5x, priority 255 gets 2x
    let priority_factor = 0.5 + (priority as f64 / 255.0) * 1.5;
    let base_time = 10.0 * queue_length as f64;
    (base_time * priority_factor) as u32
}

// ============================================================================
// DEBUG/STATS
// ============================================================================

/// Get MoQ system statistics
#[derive(Debug, Clone)]
pub struct FlutterMoqStats {
    pub scheduler_queue_length: u32,
    pub namespace_count: u32,
}

#[frb]
pub async fn moq_get_stats() -> Result<FlutterMoqStats, String> {
    Ok(FlutterMoqStats {
        scheduler_queue_length: get_scheduler().queue_len().await as u32,
        namespace_count: get_namespace_manager().list_published().await.len() as u32,
    })
}
