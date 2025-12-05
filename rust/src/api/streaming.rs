//! DEPRECATED: Gossip-based streaming module
//!
//! This module was the original gossip-based P2P streaming implementation.
//! It has been replaced by iroh-live based streaming using MoQ (Media over QUIC).
//! 
//! These types are kept as stubs for backwards compatibility during transition.

use std::collections::BTreeSet;
use anyhow::Result;
pub use iroh::EndpointId;
use iroh::SecretKey;
use n0_future::boxed::BoxStream;
use serde::{Deserialize, Serialize};

pub const STREAM_PREFIX: &str = "iroh-streaming/0:";

/// Topic ID (stub - was from iroh_gossip)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct TopicId([u8; 32]);

impl TopicId {
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
    
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Display for TopicId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", data_encoding::BASE32_NOPAD.encode(&self.0[..8]))
    }
}

/// Stream ticket for sharing with peers (DEPRECATED)
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct StreamTicket {
    pub topic_id: TopicId,
    pub bootstrap: BTreeSet<EndpointId>,
}

impl StreamTicket {
    pub fn new(topic_id: TopicId) -> Self {
        Self {
            topic_id,
            bootstrap: Default::default(),
        }
    }

    pub fn new_random() -> Self {
        let topic_id = TopicId::from_bytes(rand::random());
        Self::new(topic_id)
    }
    
    pub fn deserialize_ticket(_input: &str) -> Result<Self> {
        anyhow::bail!("Gossip-based streaming is deprecated. Use iroh-live instead.")
    }
    
    pub fn serialize_ticket(&self) -> String {
        "deprecated".to_string()
    }
}

/// Streaming node - DEPRECATED
/// 
/// This was the gossip-based streaming node. Use iroh-live `Live` instead.
pub struct StreamingNode {
    _secret_key: SecretKey,
}

impl StreamingNode {
    /// Spawn a new streaming node - DEPRECATED
    pub async fn spawn(secret_key: Option<SecretKey>) -> Result<Self> {
        let secret_key = secret_key.unwrap_or_else(|| SecretKey::generate(&mut rand::rng()));
        Ok(Self {
            _secret_key: secret_key,
        })
    }

    /// Get the endpoint ID for this node
    pub fn endpoint_id(&self) -> EndpointId {
        EndpointId::from(self._secret_key.public())
    }

    /// Join a stream - DEPRECATED
    #[allow(clippy::type_complexity)]
    pub async fn join(&self, _ticket: &StreamTicket, _name: String) -> Result<(StreamSender, BoxStream<Result<StreamEvent>>)> {
        anyhow::bail!("Gossip-based streaming is deprecated. Use iroh-live instead.")
    }
    
    pub async fn shutdown(&self) {
        // No-op for stub
    }
}

/// Stream sender for broadcasting data - DEPRECATED
#[derive(Clone)]
pub struct StreamSender;

impl StreamSender {
    /// Broadcast a video/audio chunk
    pub async fn broadcast_chunk(&self, _data: Vec<u8>, _sequence: u64) -> Result<()> {
        anyhow::bail!("Gossip-based streaming is deprecated")
    }

    /// Send a presence message
    pub async fn send_presence(&self) -> Result<()> {
        anyhow::bail!("Gossip-based streaming is deprecated")
    }

    /// Send an arbitrary signaling payload
    pub async fn send_signal(&self, _data: Vec<u8>) -> Result<()> {
        anyhow::bail!("Gossip-based streaming is deprecated")
    }

    /// Set the broadcaster name
    pub fn set_name(&self, _name: String) {
        // No-op
    }
}

/// Events received from a stream - DEPRECATED
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum StreamEvent {
    #[serde(rename_all = "camelCase")]
    NeighborUp { endpoint_id: EndpointId },
    #[serde(rename_all = "camelCase")]
    NeighborDown { endpoint_id: EndpointId },
    #[serde(rename_all = "camelCase")]
    Presence {
        from: EndpointId,
        name: String,
        sent_timestamp: u64,
    },
    #[serde(rename_all = "camelCase")]
    MediaChunk {
        from: EndpointId,
        data: Vec<u8>,
        sequence: u64,
        timestamp: u64,
    },
    #[serde(rename_all = "camelCase")]
    Signal {
        from: EndpointId,
        data: Vec<u8>,
        timestamp: u64,
    },
    Lagged,
}

/// Stream quality presets
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum StreamQuality {
    Low,    // 360p, 15fps
    Medium, // 480p, 24fps
    High,   // 720p, 30fps
    Ultra,  // 1080p, 30fps
}

impl StreamQuality {
    pub fn video_constraints(&self) -> (u32, u32, u32) {
        match self {
            StreamQuality::Low => (640, 360, 15),
            StreamQuality::Medium => (854, 480, 24),
            StreamQuality::High => (1280, 720, 30),
            StreamQuality::Ultra => (1920, 1080, 30),
        }
    }

    pub fn audio_bitrate(&self) -> u32 {
        match self {
            StreamQuality::Low => 32000,
            StreamQuality::Medium => 64000,
            StreamQuality::High => 128000,
            StreamQuality::Ultra => 192000,
        }
    }
}
