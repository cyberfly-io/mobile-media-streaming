//! P2P media streaming node using iroh-gossip
//!
//! This module provides real-time P2P streaming using gossip protocol,
//! which works reliably in WASM environments.
//! Based on the browser-chat example from iroh-examples.
//! 
//! Copied from: https://github.com/cyberfly-io/cyberfly-node-web-dashboard/tree/main/iroh-streaming

use std::collections::BTreeSet;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
pub use iroh::EndpointId;
use iroh::{PublicKey, SecretKey, Signature, protocol::Router};
pub use iroh_gossip::proto::TopicId;
use iroh_gossip::{
    api::{Event as GossipEvent, GossipSender},
    net::{GOSSIP_ALPN, Gossip},
};
use iroh_tickets::Ticket;
use n0_future::{
    StreamExt,
    boxed::BoxStream,
    time::{Duration, SystemTime},
};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex as TokioMutex;
use tracing::{info, warn};

pub const STREAM_PREFIX: &str = "iroh-streaming/0:";

/// Stream ticket for sharing with peers
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
    
    pub fn deserialize_ticket(input: &str) -> Result<Self> {
        <Self as Ticket>::deserialize(input).map_err(Into::into)
    }
    
    pub fn serialize_ticket(&self) -> String {
        <Self as Ticket>::serialize(self)
    }
}

impl Ticket for StreamTicket {
    const KIND: &'static str = "stream";

    fn to_bytes(&self) -> Vec<u8> {
        postcard::to_stdvec(&self).unwrap()
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, iroh_tickets::ParseError> {
        let ticket = postcard::from_bytes(bytes)?;
        Ok(ticket)
    }
}

/// Streaming node - uses gossip for real-time P2P communication
pub struct StreamingNode {
    secret_key: SecretKey,
    router: Router,
    gossip: Gossip,
}

impl StreamingNode {
    /// Spawn a new streaming node
    pub async fn spawn(secret_key: Option<SecretKey>) -> Result<Self> {
        let secret_key = secret_key.unwrap_or_else(|| SecretKey::generate(&mut rand::rng()));
        let endpoint = iroh::Endpoint::builder()
            .secret_key(secret_key.clone())
            .alpns(vec![GOSSIP_ALPN.to_vec()])
            .bind()
            .await?;

        let endpoint_id = endpoint.id();
        info!("endpoint bound");
        info!("endpoint id: {endpoint_id:#?}");
        
        // Wait for relay connection to be established (with timeout)
        info!("waiting for endpoint to come online...");
        let online_timeout = n0_future::time::timeout(
            Duration::from_secs(10),
            endpoint.online()
        ).await;
        match online_timeout {
            Ok(()) => info!("endpoint is online"),
            Err(_) => warn!("timeout waiting for relay connection, continuing anyway"),
        }

        let gossip = Gossip::builder()
            .max_message_size(65536) // 64KB max message size for media chunks
            .spawn(endpoint.clone());
        info!("gossip spawned with 64KB max message size");
        
        let router = Router::builder(endpoint)
            .accept(GOSSIP_ALPN, gossip.clone())
            .spawn();
        info!("router spawned");
        
        Ok(Self {
            gossip,
            router,
            secret_key,
        })
    }

    /// Get the endpoint ID for this node
    pub fn endpoint_id(&self) -> EndpointId {
        self.router.endpoint().id()
    }

    /// Create a new stream (broadcaster)
    pub async fn join(&self, ticket: &StreamTicket, name: String) -> Result<(StreamSender, BoxStream<Result<StreamEvent>>)> {
        let topic_id = ticket.topic_id;
        let bootstrap: Vec<EndpointId> = ticket.bootstrap.iter().cloned().collect();

        info!(?bootstrap, "joining stream {topic_id}");

        // Subscribe to the gossip topic - this should be instant
        info!("calling gossip.subscribe...");
        let gossip_topic = self.gossip.subscribe(topic_id, bootstrap).await?;
        info!("gossip.subscribe completed");
        
        info!("calling split...");
        let (sender, receiver) = gossip_topic.split();
        info!("split complete");

        let nickname = Arc::new(Mutex::new(name));
        let sender = Arc::new(TokioMutex::new(sender));

        // Create a stream of events from the receiver
        let receiver = n0_future::stream::try_unfold(receiver, {
            move |mut receiver| {
                async move {
                    loop {
                        // Fetch the next event
                        let Some(event) = receiver.try_next().await? else {
                            return Ok(None);
                        };
                        
                        // Convert into our event type
                        let event: StreamEvent = match event.try_into() {
                            Ok(event) => event,
                            Err(err) => {
                                warn!("received invalid message: {err}");
                                continue;
                            }
                        };
                        
                        break Ok(Some((event, receiver)));
                    }
                }
            }
        });

        let sender = StreamSender {
            secret_key: self.secret_key.clone(),
            nickname,
            sender,
        };
        
        info!("join complete, returning sender and receiver");
        Ok((sender, Box::pin(receiver)))
    }
    
    pub async fn shutdown(&self) {
        if let Err(err) = self.router.shutdown().await {
            warn!("failed to shutdown router cleanly: {err}");
        }
        self.router.endpoint().close().await;
    }
}

/// Stream sender for broadcasting data
#[derive(Clone)]
pub struct StreamSender {
    nickname: Arc<Mutex<String>>,
    secret_key: SecretKey,
    sender: Arc<TokioMutex<GossipSender>>,
}

impl StreamSender {
    /// Broadcast a video/audio chunk
    pub async fn broadcast_chunk(&self, data: Vec<u8>, sequence: u64) -> Result<()> {
        let message = StreamMessage::MediaChunk { 
            data, 
            sequence,
        };
        let signed = SignedMessage::sign_and_encode(&self.secret_key, message)?;
        info!("broadcasting chunk seq={}, signed message size={} bytes", sequence, signed.len());
        self.sender.lock().await.broadcast(signed.into()).await?;
        Ok(())
    }

    /// Send a presence message
    pub async fn send_presence(&self) -> Result<()> {
        let name = self.nickname.lock().expect("poisened").clone();
        let message = StreamMessage::Presence { name };
        let signed = SignedMessage::sign_and_encode(&self.secret_key, message)?;
        self.sender.lock().await.broadcast(signed.into()).await?;
        Ok(())
    }

    /// Send an arbitrary signaling payload
    pub async fn send_signal(&self, data: Vec<u8>) -> Result<()> {
        info!("[Signal] Sending signal, payload size: {} bytes", data.len());
        
        // Log the raw signal data (should be UTF-8 JSON)
        if let Ok(json_str) = std::str::from_utf8(&data) {
            info!("[Signal] Payload JSON: {}", json_str);
        } else {
            info!("[Signal] Payload (hex): {:02x?}", &data[..data.len().min(100)]);
        }
        
        let message = StreamMessage::Signal { data };
        info!("[Signal] StreamMessage::Signal created, discriminant should be 2");
        
        let signed = SignedMessage::sign_and_encode(&self.secret_key, message)?;
        info!("[Signal] Signed message size: {} bytes", signed.len());
        
        // Log first few bytes of signed message to verify format
        info!("[Signal] Signed message header (first 32 bytes hex): {:02x?}", &signed[..signed.len().min(32)]);
        
        info!("[Signal] Broadcasting via gossip...");
        self.sender.lock().await.broadcast(signed.into()).await?;
        info!("[Signal] Signal broadcast complete");
        Ok(())
    }

    /// Set the broadcaster name
    pub fn set_name(&self, name: String) {
        *self.nickname.lock().expect("poisened") = name;
    }
}

/// Events received from a stream
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

impl TryFrom<GossipEvent> for StreamEvent {
    type Error = anyhow::Error;

    fn try_from(event: GossipEvent) -> Result<Self, Self::Error> {
        let converted = match event {
            GossipEvent::NeighborUp(endpoint_id) => Self::NeighborUp { endpoint_id },
            GossipEvent::NeighborDown(endpoint_id) => Self::NeighborDown { endpoint_id },
            GossipEvent::Lagged => Self::Lagged,
            GossipEvent::Received(message) => {
                info!("received gossip message, {} bytes", message.content.len());
                
                // Log first bytes to help debug
                let first_bytes = &message.content[..message.content.len().min(32)];
                info!("message header (first 32 bytes hex): {:02x?}", first_bytes);
                
                let received = SignedMessage::verify_and_decode(&message.content)
                    .context("failed to parse and verify signed message")?;
                
                // Use different representations to show enum discriminant
                let msg_type = match &received.message {
                    StreamMessage::Presence { .. } => "Presence (discriminant 0)",
                    StreamMessage::MediaChunk { .. } => "MediaChunk (discriminant 1)",
                    StreamMessage::Signal { .. } => "Signal (discriminant 2)",
                };
                info!("decoded message type: {}", msg_type);
                
                match received.message {
                    StreamMessage::Presence { name } => Self::Presence {
                        from: received.from,
                        name,
                        sent_timestamp: received.timestamp,
                    },
                    StreamMessage::MediaChunk { data, sequence } => {
                        info!("received media chunk seq={} size={}", sequence, data.len());
                        Self::MediaChunk {
                            from: received.from,
                            data,
                            sequence,
                            timestamp: received.timestamp,
                        }
                    }
                    StreamMessage::Signal { data } => {
                        info!("received signal size={}", data.len());
                        // Also log the signal content if it's JSON
                        if let Ok(json_str) = std::str::from_utf8(&data) {
                            info!("signal payload JSON: {}", json_str);
                        }
                        Self::Signal {
                            from: received.from,
                            data,
                            timestamp: received.timestamp,
                        }
                    }
                }
            }
        };
        Ok(converted)
    }
}

/// Wire message format
#[derive(Debug, Serialize, Deserialize)]
pub enum WireMessage {
    V0 { timestamp: u64, message: StreamMessage },
}

/// Stream message types
#[derive(Debug, Serialize, Deserialize)]
pub enum StreamMessage {
    /// Presence announcement
    Presence { name: String },
    /// Media chunk (video/audio data)
    MediaChunk { 
        data: Vec<u8>, 
        sequence: u64,
    },
    /// Arbitrary signaling payloads (WebRTC, etc)
    Signal { data: Vec<u8> },
}

/// Received message after verification
#[derive(Debug)]
pub struct ReceivedMessage {
    pub timestamp: u64,
    pub from: EndpointId,
    pub message: StreamMessage,
}

/// Signed message wrapper
#[derive(Debug, Serialize, Deserialize)]
struct SignedMessage {
    from: PublicKey,
    data: Vec<u8>,
    signature: Signature,
}

impl SignedMessage {
    pub fn verify_and_decode(bytes: &[u8]) -> Result<ReceivedMessage> {
        let signed_message: Self = postcard::from_bytes(bytes)?;
        let key: PublicKey = signed_message.from;
        key.verify(&signed_message.data, &signed_message.signature)?;
        let wire_message: WireMessage = postcard::from_bytes(&signed_message.data)?;
        let WireMessage::V0 { timestamp, message } = wire_message;
        Ok(ReceivedMessage {
            from: EndpointId::from(signed_message.from),
            timestamp,
            message,
        })
    }

    pub fn sign_and_encode(secret_key: &SecretKey, message: StreamMessage) -> Result<Vec<u8>> {
        let timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_micros() as u64;
        let wire_message = WireMessage::V0 { timestamp, message };
        let data = postcard::to_stdvec(&wire_message)?;
        let signature = secret_key.sign(&data);
        let from: PublicKey = secret_key.public();
        let signed_message = Self {
            from,
            data,
            signature,
        };
        let encoded = postcard::to_stdvec(&signed_message)?;
        Ok(encoded)
    }
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
