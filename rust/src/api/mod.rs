pub mod simple;

// ============================================================================
// IROH-LIVE BASED STREAMING (MoQ - Media over QUIC)
// ============================================================================

// Core iroh-live implementation
pub mod iroh_live;

// Flutter API for iroh-live features
pub mod iroh_live_flutter_api;

// WebTransport session layer (required by moq-lite)
pub mod webtransport;

// Live protocol handler and session management
pub mod live_protocol;

// Broadcast publishing (video/audio renditions)
pub mod publish_broadcast;

// Broadcast subscription (receiving media)
pub mod subscribe_broadcast;

// FFmpeg encoder following iroh-live patterns (requires ffmpeg feature)
#[cfg(feature = "ffmpeg")]
pub mod ffmpeg_encoder;

// Legacy modules (will be deprecated)
mod streaming;  // Old gossip-based - not used
mod direct_streaming;  // Old direct QUIC - not used
mod live_streaming;  // Old implementation - not used

// These are kept for reference but not actively used
pub mod flutter_api;
pub mod direct_flutter_api;
pub mod live_flutter_api;
pub mod moq_protocol;
pub mod moq_flutter_api;
pub mod ffmpeg;
pub mod ffmpeg_flutter_api;
pub mod av;
pub mod capture;
pub mod publish;
pub mod subscribe;
