//! Flutter-Rust bridge API for live streaming functionality
//!
//! This provides a high-level API for Flutter similar to iroh-live

use std::sync::Arc;
use tokio::sync::Mutex;
use flutter_rust_bridge::frb;

use super::live_streaming::{
    LiveBroadcast, LiveSubscription, LiveTicket, BroadcastCatalog,
    VideoQuality, VideoTrackConfig,
    ConnectionStats, DirectStreamEvent, DirectMessage,
};
use super::direct_streaming::DirectStreamTicket;

/// Global live broadcast instance
static LIVE_BROADCAST: once_cell::sync::OnceCell<Arc<Mutex<Option<LiveBroadcast>>>> = 
    once_cell::sync::OnceCell::new();

/// Global live subscription instance
static LIVE_SUBSCRIPTION: once_cell::sync::OnceCell<Arc<Mutex<Option<LiveSubscription>>>> = 
    once_cell::sync::OnceCell::new();

/// Global event queue for live streaming
static LIVE_EVENT_QUEUE: once_cell::sync::OnceCell<Arc<Mutex<Vec<FlutterLiveEvent>>>> = 
    once_cell::sync::OnceCell::new();

fn get_broadcast_holder() -> &'static Arc<Mutex<Option<LiveBroadcast>>> {
    LIVE_BROADCAST.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_subscription_holder() -> &'static Arc<Mutex<Option<LiveSubscription>>> {
    LIVE_SUBSCRIPTION.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_live_event_queue() -> &'static Arc<Mutex<Vec<FlutterLiveEvent>>> {
    LIVE_EVENT_QUEUE.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

// ============================================================================
// FLUTTER TYPES
// ============================================================================

/// Video quality enum for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterVideoQuality {
    P180,
    P360,
    P720,
    P1080,
}

impl From<FlutterVideoQuality> for VideoQuality {
    fn from(q: FlutterVideoQuality) -> Self {
        match q {
            FlutterVideoQuality::P180 => VideoQuality::P180,
            FlutterVideoQuality::P360 => VideoQuality::P360,
            FlutterVideoQuality::P720 => VideoQuality::P720,
            FlutterVideoQuality::P1080 => VideoQuality::P1080,
        }
    }
}

impl From<VideoQuality> for FlutterVideoQuality {
    fn from(q: VideoQuality) -> Self {
        match q {
            VideoQuality::P180 => FlutterVideoQuality::P180,
            VideoQuality::P360 => FlutterVideoQuality::P360,
            VideoQuality::P720 => FlutterVideoQuality::P720,
            VideoQuality::P1080 => FlutterVideoQuality::P1080,
        }
    }
}

/// Video track info for Flutter
#[derive(Debug, Clone)]
pub struct FlutterVideoTrack {
    pub name: String,
    pub quality: FlutterVideoQuality,
    pub codec: String,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate_kbps: u32,
}

impl From<&VideoTrackConfig> for FlutterVideoTrack {
    fn from(t: &VideoTrackConfig) -> Self {
        Self {
            name: t.track_name(),
            quality: t.quality.into(),
            codec: t.codec.clone(),
            width: t.width,
            height: t.height,
            fps: t.fps,
            bitrate_kbps: t.bitrate_kbps,
        }
    }
}

/// Broadcast catalog for Flutter
#[derive(Debug, Clone)]
pub struct FlutterCatalog {
    pub name: String,
    pub description: Option<String>,
    pub video_tracks: Vec<FlutterVideoTrack>,
    pub is_live: bool,
    pub duration_secs: Option<f64>,
}

impl From<&BroadcastCatalog> for FlutterCatalog {
    fn from(c: &BroadcastCatalog) -> Self {
        Self {
            name: c.name.clone(),
            description: c.description.clone(),
            video_tracks: c.video_tracks.values().map(|t| t.into()).collect(),
            is_live: c.is_live,
            duration_secs: c.duration_secs,
        }
    }
}

/// Connection stats for Flutter
#[derive(Debug, Clone)]
pub struct FlutterConnectionStats {
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub chunks_sent: u64,
    pub chunks_received: u64,
    pub bandwidth_bps: u64,
    pub rtt_ms: u64,
    pub quality_score: u32,
    pub recommended_quality: FlutterVideoQuality,
}

impl From<&ConnectionStats> for FlutterConnectionStats {
    fn from(s: &ConnectionStats) -> Self {
        Self {
            bytes_sent: s.bytes_sent,
            bytes_received: s.bytes_received,
            chunks_sent: s.chunks_sent,
            chunks_received: s.chunks_received,
            bandwidth_bps: s.bandwidth_bps,
            rtt_ms: s.rtt_ms,
            quality_score: s.quality_score,
            recommended_quality: s.recommended_quality().into(),
        }
    }
}

/// Live event types for Flutter
#[derive(Debug, Clone)]
pub enum FlutterLiveEvent {
    /// Peer connected
    PeerConnected { peer_id: String },
    /// Peer disconnected
    PeerDisconnected { peer_id: String },
    /// Catalog received
    CatalogReceived { catalog: FlutterCatalog },
    /// Metadata received (for video file streaming)
    MetadataReceived {
        from: String,
        file_name: String,
        file_size: u64,
        mime_type: String,
        total_chunks: u32,
        duration: Option<f64>,
    },
    /// Chunk request received (for broadcaster)
    ChunkRequested { from: String, index: u32 },
    /// Chunk received (for viewer)
    ChunkReceived { from: String, index: u32, data: Vec<u8> },
    /// Metadata request received
    MetadataRequested { from: String },
    /// Stats updated
    StatsUpdated { stats: FlutterConnectionStats },
    /// Error occurred
    Error { message: String },
}

// ============================================================================
// BROADCASTER API
// ============================================================================

/// Create a new live broadcast
#[frb]
pub async fn create_live_broadcast(name: String) -> Result<String, String> {
    let holder = get_broadcast_holder();
    let mut guard = holder.lock().await;
    
    if guard.is_some() {
        return Err("Broadcast already active".to_string());
    }
    
    let broadcast = LiveBroadcast::new(&name)
        .await
        .map_err(|e| e.to_string())?;
    
    let ticket = broadcast.ticket_string();
    *guard = Some(broadcast);
    
    // Start event polling task
    let broadcast_holder = get_broadcast_holder().clone();
    let event_queue = get_live_event_queue().clone();
    
    tokio::spawn(async move {
        tracing::info!("[LiveBroadcast] Event polling started");
        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            
            let events = {
                let guard = broadcast_holder.lock().await;
                match guard.as_ref() {
                    Some(b) => b.poll_events().await,
                    None => break,
                }
            };
            
            if !events.is_empty() {
                let mut queue = event_queue.lock().await;
                for event in events {
                    queue.push(convert_direct_event(event));
                }
            }
        }
        tracing::info!("[LiveBroadcast] Event polling stopped");
    });
    
    tracing::info!("[LiveBroadcast] Created: {}", ticket);
    Ok(ticket)
}

/// Get the live broadcast ticket (simpler format)
#[frb]
pub async fn get_live_ticket() -> Result<String, String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => Ok(b.ticket_string()),
        None => Err("No active broadcast".to_string()),
    }
}

/// Get the direct connection ticket (full address)
#[frb]
pub async fn get_direct_ticket() -> Result<String, String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => {
            let addr = b.endpoint.endpoint_addr();
            let ticket = DirectStreamTicket::new(addr);
            Ok(ticket.serialize())
        }
        None => Err("No active broadcast".to_string()),
    }
}

/// Add a video track to the catalog
#[frb]
pub async fn add_video_track(quality: FlutterVideoQuality, codec: String) -> Result<(), String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => {
            b.add_video_track(quality.into(), &codec).await;
            Ok(())
        }
        None => Err("No active broadcast".to_string()),
    }
}

/// Broadcast catalog to all viewers
#[frb]
pub async fn broadcast_catalog() -> Result<(), String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => b.broadcast_catalog().await.map_err(|e| e.to_string()),
        None => Err("No active broadcast".to_string()),
    }
}

/// Broadcast a video chunk
#[frb]
pub async fn live_broadcast_chunk(index: u32, data: Vec<u8>) -> Result<(), String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => b.broadcast_chunk(index, data).await.map_err(|e| e.to_string()),
        None => Err("No active broadcast".to_string()),
    }
}

/// Broadcast metadata for a video file
#[frb]
pub async fn live_broadcast_metadata(
    file_name: String,
    file_size: u64,
    mime_type: String,
    total_chunks: u32,
    duration: Option<f64>,
) -> Result<(), String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => {
            let msg = DirectMessage::Metadata {
                file_name,
                file_size,
                mime_type,
                total_chunks,
                duration,
            };
            b.endpoint.broadcast(&msg).await.map_err(|e| e.to_string())
        }
        None => Err("No active broadcast".to_string()),
    }
}

/// Get broadcast peer count
#[frb]
pub async fn live_broadcast_peer_count() -> Result<u32, String> {
    let holder = get_broadcast_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(b) => Ok(b.peer_count().await as u32),
        None => Err("No active broadcast".to_string()),
    }
}

/// Stop the live broadcast
#[frb]
pub async fn stop_live_broadcast() -> Result<(), String> {
    let holder = get_broadcast_holder();
    let mut guard = holder.lock().await;
    
    if let Some(broadcast) = guard.take() {
        broadcast.shutdown().await;
        tracing::info!("[LiveBroadcast] Stopped");
    }
    
    Ok(())
}

// ============================================================================
// SUBSCRIPTION API
// ============================================================================

/// Join a live broadcast using ticket string
#[frb]
pub async fn join_live_broadcast(ticket_str: String) -> Result<String, String> {
    let holder = get_subscription_holder();
    let mut guard = holder.lock().await;
    
    if guard.is_some() {
        return Err("Already subscribed to a broadcast".to_string());
    }
    
    // Try to parse as LiveTicket first, then as DirectStreamTicket
    let endpoint_addr = if ticket_str.contains('@') {
        // Simple LiveTicket format
        let ticket = LiveTicket::deserialize(&ticket_str)
            .map_err(|e| format!("Invalid ticket: {}", e))?;
        iroh::EndpointAddr::new(ticket.endpoint_id)
    } else {
        // Full DirectStreamTicket format
        let ticket = DirectStreamTicket::deserialize(&ticket_str)
            .map_err(|e| format!("Invalid ticket: {}", e))?;
        ticket.to_endpoint_addr()
    };
    
    let subscription = LiveSubscription::connect(
        &LiveTicket::new("stream", endpoint_addr.id),
        endpoint_addr.clone(),
    )
    .await
    .map_err(|e| e.to_string())?;
    
    let remote_id = subscription.remote_id.to_string();
    *guard = Some(subscription);
    
    // Start event polling task
    let sub_holder = get_subscription_holder().clone();
    let event_queue = get_live_event_queue().clone();
    
    tokio::spawn(async move {
        tracing::info!("[LiveSubscription] Event polling started");
        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            
            let events = {
                let guard = sub_holder.lock().await;
                match guard.as_ref() {
                    Some(s) => s.poll_events().await,
                    None => break,
                }
            };
            
            if !events.is_empty() {
                let mut queue = event_queue.lock().await;
                for event in events {
                    queue.push(convert_direct_event(event));
                }
            }
        }
        tracing::info!("[LiveSubscription] Event polling stopped");
    });
    
    tracing::info!("[LiveSubscription] Joined: {}", remote_id);
    Ok(remote_id)
}

/// Request catalog from broadcaster
#[frb]
pub async fn request_live_catalog() -> Result<(), String> {
    let holder = get_subscription_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(s) => s.request_catalog().await.map_err(|e| e.to_string()),
        None => Err("Not subscribed to any broadcast".to_string()),
    }
}

/// Request a specific chunk
#[frb]
pub async fn live_request_chunk(index: u32) -> Result<(), String> {
    let holder = get_subscription_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(s) => s.request_chunk(index).await.map_err(|e| e.to_string()),
        None => Err("Not subscribed to any broadcast".to_string()),
    }
}

/// Set preferred video quality
#[frb]
pub async fn set_video_quality(quality: FlutterVideoQuality) -> Result<(), String> {
    let holder = get_subscription_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(s) => {
            s.set_quality(quality.into()).await;
            Ok(())
        }
        None => Err("Not subscribed to any broadcast".to_string()),
    }
}

/// Get recommended quality based on connection stats
#[frb]
pub async fn get_recommended_quality() -> Result<FlutterVideoQuality, String> {
    let holder = get_subscription_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(s) => Ok(s.recommended_quality().await.into()),
        None => Err("Not subscribed to any broadcast".to_string()),
    }
}

/// Get connection stats
#[frb]
pub async fn get_live_connection_stats() -> Result<FlutterConnectionStats, String> {
    let holder = get_subscription_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(s) => Ok((&s.get_stats().await).into()),
        None => Err("Not subscribed to any broadcast".to_string()),
    }
}

/// Leave the live broadcast
#[frb]
pub async fn leave_live_broadcast() -> Result<(), String> {
    let holder = get_subscription_holder();
    let mut guard = holder.lock().await;
    
    if let Some(subscription) = guard.take() {
        subscription.disconnect().await;
        tracing::info!("[LiveSubscription] Left");
    }
    
    Ok(())
}

// ============================================================================
// SHARED API
// ============================================================================

/// Poll for live streaming events
#[frb]
pub async fn poll_live_events() -> Vec<FlutterLiveEvent> {
    let queue = get_live_event_queue();
    let mut events = Vec::new();
    
    {
        let mut guard = queue.lock().await;
        events.append(&mut *guard);
    }
    
    events
}

/// Parse a LiveTicket string and return its components
#[frb]
pub fn parse_live_ticket(ticket_str: String) -> Result<(String, String), String> {
    let ticket = LiveTicket::deserialize(&ticket_str)
        .map_err(|e| format!("Invalid ticket: {}", e))?;
    Ok((ticket.broadcast_name, ticket.endpoint_id.to_string()))
}

/// Create a LiveTicket string from components
#[frb]
pub fn create_live_ticket(broadcast_name: String, endpoint_id_hex: String) -> Result<String, String> {
    // Parse hex endpoint ID
    let id_bytes = data_encoding::HEXLOWER_PERMISSIVE
        .decode(endpoint_id_hex.as_bytes())
        .map_err(|e| format!("Invalid endpoint ID: {}", e))?;
    
    let id_array: [u8; 32] = id_bytes
        .try_into()
        .map_err(|_| "Invalid endpoint ID length")?;
    
    let public_key = iroh::PublicKey::from_bytes(&id_array)
        .map_err(|e| format!("Invalid public key: {}", e))?;
    let endpoint_id = iroh::EndpointId::from(public_key);
    let ticket = LiveTicket::new(&broadcast_name, endpoint_id);
    
    Ok(ticket.serialize())
}

/// Check if there's an active broadcast
#[frb]
pub fn has_active_broadcast() -> bool {
    if let Some(holder) = LIVE_BROADCAST.get() {
        if let Ok(guard) = holder.try_lock() {
            return guard.is_some();
        }
    }
    false
}

/// Check if there's an active subscription
#[frb]
pub fn has_active_subscription() -> bool {
    if let Some(holder) = LIVE_SUBSCRIPTION.get() {
        if let Ok(guard) = holder.try_lock() {
            return guard.is_some();
        }
    }
    false
}

/// Get video quality dimensions
#[frb]
pub fn get_quality_dimensions(quality: FlutterVideoQuality) -> (u32, u32) {
    let q: VideoQuality = quality.into();
    q.dimensions()
}

/// Get video quality bitrate recommendation
#[frb]
pub fn get_quality_bitrate(quality: FlutterVideoQuality) -> u32 {
    let q: VideoQuality = quality.into();
    q.bitrate_kbps()
}

/// Get all video qualities
#[frb]
pub fn get_all_video_qualities() -> Vec<FlutterVideoQuality> {
    vec![
        FlutterVideoQuality::P180,
        FlutterVideoQuality::P360,
        FlutterVideoQuality::P720,
        FlutterVideoQuality::P1080,
    ]
}

// ============================================================================
// HELPERS
// ============================================================================

fn convert_direct_event(event: DirectStreamEvent) -> FlutterLiveEvent {
    match event {
        DirectStreamEvent::PeerConnected { endpoint_id } => {
            FlutterLiveEvent::PeerConnected { peer_id: endpoint_id }
        }
        DirectStreamEvent::PeerDisconnected { endpoint_id } => {
            FlutterLiveEvent::PeerDisconnected { peer_id: endpoint_id }
        }
        DirectStreamEvent::Message { from, message, .. } => {
            match message {
                DirectMessage::RequestMetadata => {
                    FlutterLiveEvent::MetadataRequested { from }
                }
                DirectMessage::Metadata { file_name, file_size, mime_type, total_chunks, duration } => {
                    FlutterLiveEvent::MetadataReceived {
                        from,
                        file_name,
                        file_size,
                        mime_type,
                        total_chunks,
                        duration,
                    }
                }
                DirectMessage::RequestChunk { index } => {
                    FlutterLiveEvent::ChunkRequested { from, index }
                }
                DirectMessage::Chunk { index, data } => {
                    FlutterLiveEvent::ChunkReceived { from, index, data }
                }
                DirectMessage::Presence { .. } => {
                    // Ignore presence messages for now
                    FlutterLiveEvent::PeerConnected { peer_id: from }
                }
                DirectMessage::Signal { .. } => {
                    // Try to decode as catalog or other live message
                    FlutterLiveEvent::Error { message: "Received unknown signal".to_string() }
                }
            }
        }
        DirectStreamEvent::Error { message } => {
            FlutterLiveEvent::Error { message }
        }
    }
}
