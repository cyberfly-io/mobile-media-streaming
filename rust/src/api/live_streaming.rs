//! Live streaming module inspired by iroh-live
//!
//! This module provides a high-level streaming API similar to iroh-live,
//! with support for:
//! - Catalog system (metadata about available tracks)
//! - Video quality renditions (180p, 360p, 720p, 1080p)
//! - Simple LiveTicket format
//! - Connection statistics

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Result, anyhow};
use iroh::{EndpointAddr, EndpointId, PublicKey};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use tracing::{info, debug};

// Re-export the direct streaming types
pub use super::direct_streaming::{
    DirectStreamingEndpoint, DirectStreamEvent, DirectMessage,
};

// ============================================================================
// CATALOG SYSTEM
// ============================================================================

/// Video quality preset (similar to iroh-live VideoPreset)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum VideoQuality {
    /// 320x180, low bandwidth
    P180,
    /// 640x360, medium quality
    P360,
    /// 1280x720, HD quality
    P720,
    /// 1920x1080, Full HD
    P1080,
}

impl VideoQuality {
    /// Get dimensions for this quality preset
    pub fn dimensions(&self) -> (u32, u32) {
        match self {
            Self::P180 => (320, 180),
            Self::P360 => (640, 360),
            Self::P720 => (1280, 720),
            Self::P1080 => (1920, 1080),
        }
    }

    /// Get recommended bitrate in kbps
    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            Self::P180 => 300,
            Self::P360 => 800,
            Self::P720 => 2500,
            Self::P1080 => 5000,
        }
    }

    /// Get recommended framerate
    pub fn fps(&self) -> u32 {
        30
    }

    /// Get quality name
    pub fn name(&self) -> &'static str {
        match self {
            Self::P180 => "180p",
            Self::P360 => "360p",
            Self::P720 => "720p",
            Self::P1080 => "1080p",
        }
    }

    /// Get all qualities in order from lowest to highest
    pub fn all() -> [VideoQuality; 4] {
        [Self::P180, Self::P360, Self::P720, Self::P1080]
    }

    /// Parse from string
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "180p" | "p180" => Some(Self::P180),
            "360p" | "p360" => Some(Self::P360),
            "720p" | "p720" => Some(Self::P720),
            "1080p" | "p1080" => Some(Self::P1080),
            _ => None,
        }
    }
}

/// Audio quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AudioQuality {
    /// Low quality (mono, lower bitrate)
    Low,
    /// High quality (stereo, higher bitrate)
    High,
}

impl AudioQuality {
    pub fn sample_rate(&self) -> u32 {
        match self {
            Self::Low => 22050,
            Self::High => 48000,
        }
    }

    pub fn channels(&self) -> u32 {
        match self {
            Self::Low => 1,
            Self::High => 2,
        }
    }

    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            Self::Low => 64,
            Self::High => 128,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::High => "high",
        }
    }
}

/// Video track configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoTrackConfig {
    /// Quality preset
    pub quality: VideoQuality,
    /// Codec name (e.g., "h264", "vp8")
    pub codec: String,
    /// Width in pixels
    pub width: u32,
    /// Height in pixels
    pub height: u32,
    /// Framerate
    pub fps: u32,
    /// Bitrate in kbps
    pub bitrate_kbps: u32,
}

impl VideoTrackConfig {
    pub fn new(quality: VideoQuality, codec: &str) -> Self {
        let (width, height) = quality.dimensions();
        Self {
            quality,
            codec: codec.to_string(),
            width,
            height,
            fps: quality.fps(),
            bitrate_kbps: quality.bitrate_kbps(),
        }
    }

    /// Track name following iroh-live convention: "video-{quality}"
    pub fn track_name(&self) -> String {
        format!("video-{}", self.quality.name())
    }
}

/// Audio track configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioTrackConfig {
    pub quality: AudioQuality,
    pub codec: String,
    pub sample_rate: u32,
    pub channels: u32,
    pub bitrate_kbps: u32,
}

impl AudioTrackConfig {
    pub fn new(quality: AudioQuality, codec: &str) -> Self {
        Self {
            quality,
            codec: codec.to_string(),
            sample_rate: quality.sample_rate(),
            channels: quality.channels(),
            bitrate_kbps: quality.bitrate_kbps(),
        }
    }

    pub fn track_name(&self) -> String {
        format!("audio-{}", self.quality.name())
    }
}

/// Broadcast catalog - metadata about available tracks
/// Similar to hang::Catalog in iroh-live
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BroadcastCatalog {
    /// Broadcast name/title
    pub name: String,
    /// Description
    pub description: Option<String>,
    /// Available video tracks (quality -> config)
    pub video_tracks: HashMap<String, VideoTrackConfig>,
    /// Available audio tracks (quality -> config)
    pub audio_tracks: HashMap<String, AudioTrackConfig>,
    /// Total duration (for VOD content)
    pub duration_secs: Option<f64>,
    /// Is this a live broadcast?
    pub is_live: bool,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
    /// Timestamp when catalog was last updated
    pub updated_at: u64,
}

impl BroadcastCatalog {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            is_live: true,
            updated_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            ..Default::default()
        }
    }

    /// Add a video track
    pub fn add_video_track(&mut self, config: VideoTrackConfig) {
        let name = config.track_name();
        self.video_tracks.insert(name, config);
        self.touch();
    }

    /// Add an audio track
    pub fn add_audio_track(&mut self, config: AudioTrackConfig) {
        let name = config.track_name();
        self.audio_tracks.insert(name, config);
        self.touch();
    }

    /// Get the best video track for requested quality
    pub fn get_video_track(&self, quality: VideoQuality) -> Option<&VideoTrackConfig> {
        let name = format!("video-{}", quality.name());
        self.video_tracks.get(&name)
    }

    /// Get the best available video track (highest quality)
    pub fn best_video_track(&self) -> Option<&VideoTrackConfig> {
        for quality in VideoQuality::all().iter().rev() {
            if let Some(track) = self.get_video_track(*quality) {
                return Some(track);
            }
        }
        None
    }

    /// Get available video qualities
    pub fn available_video_qualities(&self) -> Vec<VideoQuality> {
        self.video_tracks
            .values()
            .map(|t| t.quality)
            .collect()
    }

    fn touch(&mut self) {
        self.updated_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
    }

    pub fn encode(&self) -> Result<Vec<u8>> {
        postcard::to_stdvec(self).map_err(Into::into)
    }

    pub fn decode(data: &[u8]) -> Result<Self> {
        postcard::from_bytes(data).map_err(Into::into)
    }
}

// ============================================================================
// LIVE TICKET (simpler format like iroh-live)
// ============================================================================

/// Simple ticket format: broadcast_name@endpoint_id
/// 
/// Example: "mycam@d2jkql3r4hmz5g6qnkuqwqmx5h3jm6t7"
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LiveTicket {
    /// Name of the broadcast to subscribe to
    pub broadcast_name: String,
    /// Endpoint ID of the broadcaster
    pub endpoint_id: EndpointId,
}

impl LiveTicket {
    pub fn new(broadcast_name: &str, endpoint_id: EndpointId) -> Self {
        Self {
            broadcast_name: broadcast_name.to_string(),
            endpoint_id,
        }
    }

    /// Serialize to human-readable string: "name@base32(endpoint_id)"
    pub fn serialize(&self) -> String {
        let id_bytes = self.endpoint_id.as_bytes();
        let id_encoded = data_encoding::BASE32_NOPAD.encode(id_bytes);
        format!("{}@{}", self.broadcast_name, id_encoded.to_lowercase())
    }

    /// Deserialize from string
    pub fn deserialize(input: &str) -> Result<Self> {
        let (name, id_part) = input
            .rsplit_once('@')
            .ok_or_else(|| anyhow!("Invalid ticket format: missing '@'"))?;
        
        let id_bytes = data_encoding::BASE32_NOPAD
            .decode(id_part.to_uppercase().as_bytes())
            .map_err(|e| anyhow!("Invalid endpoint ID encoding: {}", e))?;
        
        let id_array: [u8; 32] = id_bytes
            .try_into()
            .map_err(|_| anyhow!("Invalid endpoint ID length"))?;
        
        let public_key = PublicKey::from_bytes(&id_array)
            .map_err(|e| anyhow!("Invalid public key: {}", e))?;
        let endpoint_id = EndpointId::from(public_key);
        
        Ok(Self {
            broadcast_name: name.to_string(),
            endpoint_id,
        })
    }
}

impl std::fmt::Display for LiveTicket {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.serialize())
    }
}

// ============================================================================
// CONNECTION STATISTICS
// ============================================================================

/// Connection statistics similar to iroh-live StatsSmoother
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ConnectionStats {
    /// Bytes sent total
    pub bytes_sent: u64,
    /// Bytes received total
    pub bytes_received: u64,
    /// Chunks sent
    pub chunks_sent: u64,
    /// Chunks received
    pub chunks_received: u64,
    /// Current estimated bandwidth (bytes/sec)
    pub bandwidth_bps: u64,
    /// Round-trip time in milliseconds
    pub rtt_ms: u64,
    /// Packet loss rate (0.0 - 1.0)
    pub packet_loss: f64,
    /// Connection quality score (0-100)
    pub quality_score: u32,
    /// Timestamp of last update
    pub last_updated: u64,
}

impl ConnectionStats {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn record_sent(&mut self, bytes: u64) {
        self.bytes_sent += bytes;
        self.chunks_sent += 1;
        self.touch();
    }

    pub fn record_received(&mut self, bytes: u64) {
        self.bytes_received += bytes;
        self.chunks_received += 1;
        self.touch();
    }

    pub fn update_rtt(&mut self, rtt_ms: u64) {
        // Exponential moving average
        self.rtt_ms = (self.rtt_ms * 7 + rtt_ms) / 8;
        self.update_quality_score();
        self.touch();
    }

    pub fn update_bandwidth(&mut self, bps: u64) {
        // Exponential moving average
        self.bandwidth_bps = (self.bandwidth_bps * 7 + bps) / 8;
        self.update_quality_score();
        self.touch();
    }

    fn update_quality_score(&mut self) {
        // Simple quality score based on RTT and bandwidth
        let rtt_score = if self.rtt_ms < 50 { 100 }
            else if self.rtt_ms < 100 { 80 }
            else if self.rtt_ms < 200 { 60 }
            else if self.rtt_ms < 500 { 40 }
            else { 20 };
        
        let bandwidth_score = if self.bandwidth_bps > 5_000_000 { 100 }
            else if self.bandwidth_bps > 2_500_000 { 80 }
            else if self.bandwidth_bps > 1_000_000 { 60 }
            else if self.bandwidth_bps > 500_000 { 40 }
            else { 20 };
        
        let loss_score = ((1.0 - self.packet_loss) * 100.0) as u32;
        
        self.quality_score = (rtt_score + bandwidth_score + loss_score) / 3;
    }

    fn touch(&mut self) {
        self.last_updated = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
    }

    /// Get recommended video quality based on current stats
    pub fn recommended_quality(&self) -> VideoQuality {
        let bandwidth_kbps = self.bandwidth_bps / 1000;
        
        if bandwidth_kbps >= VideoQuality::P1080.bitrate_kbps() as u64 * 2 {
            VideoQuality::P1080
        } else if bandwidth_kbps >= VideoQuality::P720.bitrate_kbps() as u64 * 2 {
            VideoQuality::P720
        } else if bandwidth_kbps >= VideoQuality::P360.bitrate_kbps() as u64 * 2 {
            VideoQuality::P360
        } else {
            VideoQuality::P180
        }
    }
}

// ============================================================================
// LIVE STREAMING SESSION
// ============================================================================

/// Extended message types for live streaming
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum LiveMessage {
    /// Direct message (from original protocol)
    Direct(DirectMessage),
    /// Catalog update
    Catalog(BroadcastCatalog),
    /// Request catalog
    RequestCatalog,
    /// Subscribe to a track
    Subscribe { track_name: String },
    /// Unsubscribe from a track
    Unsubscribe { track_name: String },
    /// Ping for RTT measurement
    Ping { timestamp: u64 },
    /// Pong response
    Pong { timestamp: u64 },
    /// Quality change request
    QualityChange { quality: String },
}

impl LiveMessage {
    pub fn encode(&self) -> Result<Vec<u8>> {
        postcard::to_stdvec(self).map_err(Into::into)
    }

    pub fn decode(data: &[u8]) -> Result<Self> {
        postcard::from_bytes(data).map_err(Into::into)
    }
}

/// Live streaming broadcast handle (for broadcaster)
pub struct LiveBroadcast {
    /// Underlying direct streaming endpoint
    pub endpoint: DirectStreamingEndpoint,
    /// Broadcast catalog
    pub catalog: Arc<RwLock<BroadcastCatalog>>,
    /// Connection stats per peer
    pub stats: Arc<RwLock<HashMap<String, ConnectionStats>>>,
    /// Live ticket for this broadcast
    pub ticket: LiveTicket,
}

impl LiveBroadcast {
    /// Create a new live broadcast
    pub async fn new(broadcast_name: &str) -> Result<Self> {
        let mut endpoint = DirectStreamingEndpoint::new(None).await?;
        endpoint.start_accepting().await?;
        
        let endpoint_id = endpoint.endpoint_id();
        let catalog = BroadcastCatalog::new(broadcast_name);
        let ticket = LiveTicket::new(broadcast_name, endpoint_id);
        
        info!("[LiveBroadcast] Created: {}", ticket);
        
        Ok(Self {
            endpoint,
            catalog: Arc::new(RwLock::new(catalog)),
            stats: Arc::new(RwLock::new(HashMap::new())),
            ticket,
        })
    }

    /// Get the ticket string for sharing
    pub fn ticket_string(&self) -> String {
        self.ticket.serialize()
    }

    /// Add a video track to the catalog
    pub async fn add_video_track(&self, quality: VideoQuality, codec: &str) {
        let mut catalog = self.catalog.write().await;
        catalog.add_video_track(VideoTrackConfig::new(quality, codec));
    }

    /// Broadcast catalog to all connected peers
    pub async fn broadcast_catalog(&self) -> Result<()> {
        let catalog = self.catalog.read().await.clone();
        let msg = LiveMessage::Catalog(catalog);
        let data = msg.encode()?;
        
        // Wrap in DirectMessage::Signal for compatibility
        let direct_msg = DirectMessage::Signal { data };
        self.endpoint.broadcast(&direct_msg).await
    }

    /// Broadcast a video chunk to all viewers
    pub async fn broadcast_chunk(&self, index: u32, data: Vec<u8>) -> Result<()> {
        let msg = DirectMessage::Chunk { index, data: data.clone() };
        
        // Update stats
        {
            let mut stats = self.stats.write().await;
            for (_, stat) in stats.iter_mut() {
                stat.record_sent(data.len() as u64);
            }
        }
        
        self.endpoint.broadcast(&msg).await
    }

    /// Get connection statistics
    pub async fn get_stats(&self) -> HashMap<String, ConnectionStats> {
        self.stats.read().await.clone()
    }

    /// Get peer count
    pub async fn peer_count(&self) -> usize {
        self.endpoint.peer_count().await
    }

    /// Poll for events
    pub async fn poll_events(&self) -> Vec<DirectStreamEvent> {
        self.endpoint.poll_events().await
    }

    /// Shutdown the broadcast
    pub async fn shutdown(&self) {
        self.endpoint.shutdown().await;
    }
}

/// Live streaming subscription handle (for viewer)
pub struct LiveSubscription {
    /// Underlying direct streaming endpoint
    pub endpoint: DirectStreamingEndpoint,
    /// Remote broadcaster's endpoint ID
    pub remote_id: EndpointId,
    /// Received catalog
    pub catalog: Arc<RwLock<Option<BroadcastCatalog>>>,
    /// Connection stats
    pub stats: Arc<RwLock<ConnectionStats>>,
    /// Current subscribed quality
    pub current_quality: Arc<RwLock<Option<VideoQuality>>>,
}

impl LiveSubscription {
    /// Connect to a live broadcast
    pub async fn connect(ticket: &LiveTicket, endpoint_addr: EndpointAddr) -> Result<Self> {
        let endpoint = DirectStreamingEndpoint::new(None).await?;
        
        info!("[LiveSubscription] Connecting to: {}", ticket);
        
        let remote_id = endpoint.connect_to_peer(endpoint_addr).await?;
        
        info!("[LiveSubscription] Connected to: {}", remote_id);
        
        Ok(Self {
            endpoint,
            remote_id,
            catalog: Arc::new(RwLock::new(None)),
            stats: Arc::new(RwLock::new(ConnectionStats::new())),
            current_quality: Arc::new(RwLock::new(None)),
        })
    }

    /// Request catalog from broadcaster
    pub async fn request_catalog(&self) -> Result<()> {
        let msg = DirectMessage::RequestMetadata;
        self.endpoint.send_to_peer(&self.remote_id, &msg).await
    }

    /// Request a specific chunk
    pub async fn request_chunk(&self, index: u32) -> Result<()> {
        let msg = DirectMessage::RequestChunk { index };
        self.endpoint.send_to_peer(&self.remote_id, &msg).await
    }

    /// Set preferred video quality
    pub async fn set_quality(&self, quality: VideoQuality) {
        let mut current = self.current_quality.write().await;
        *current = Some(quality);
        
        debug!("[LiveSubscription] Quality set to: {:?}", quality);
    }

    /// Get current quality
    pub async fn get_quality(&self) -> Option<VideoQuality> {
        *self.current_quality.read().await
    }

    /// Get adaptive quality recommendation
    pub async fn recommended_quality(&self) -> VideoQuality {
        self.stats.read().await.recommended_quality()
    }

    /// Update stats from received data
    pub async fn record_received(&self, bytes: u64) {
        self.stats.write().await.record_received(bytes);
    }

    /// Get connection stats
    pub async fn get_stats(&self) -> ConnectionStats {
        self.stats.read().await.clone()
    }

    /// Poll for events
    pub async fn poll_events(&self) -> Vec<DirectStreamEvent> {
        self.endpoint.poll_events().await
    }

    /// Disconnect
    pub async fn disconnect(&self) {
        self.endpoint.disconnect_peer(&self.remote_id).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_live_ticket_roundtrip() {
        let endpoint_id = EndpointId::from([42u8; 32]);
        let ticket = LiveTicket::new("mystream", endpoint_id);
        
        let serialized = ticket.serialize();
        let deserialized = LiveTicket::deserialize(&serialized).unwrap();
        
        assert_eq!(ticket, deserialized);
    }

    #[test]
    fn test_video_quality() {
        assert_eq!(VideoQuality::P720.dimensions(), (1280, 720));
        assert_eq!(VideoQuality::P1080.bitrate_kbps(), 5000);
        assert_eq!(VideoQuality::from_str("720p"), Some(VideoQuality::P720));
    }

    #[test]
    fn test_catalog_serialization() {
        let mut catalog = BroadcastCatalog::new("test");
        catalog.add_video_track(VideoTrackConfig::new(VideoQuality::P720, "h264"));
        
        let encoded = catalog.encode().unwrap();
        let decoded = BroadcastCatalog::decode(&encoded).unwrap();
        
        assert_eq!(decoded.name, "test");
        assert!(decoded.video_tracks.contains_key("video-720p"));
    }
}
