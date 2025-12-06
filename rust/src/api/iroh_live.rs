//! Real iroh-live implementation using MoQ (Media over QUIC)
//!
//! This module implements P2P live streaming following the iroh-live architecture:
//! - Uses moq-lite for Media over QUIC protocol
//! - Direct QUIC connections between publisher and subscriber
//! - Catalog-based track management with hang crate
//! - WebTransport session management

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::{Context, Result};
use bytes::Bytes;
use hang::{Catalog, CatalogConsumer, CatalogProducer, TrackConsumer};
use iroh::{Endpoint, EndpointAddr, EndpointId, RelayUrl, SecretKey, protocol::Router};
use iroh::endpoint::Connection;
use moq_lite::{BroadcastConsumer, BroadcastProducer, OriginConsumer, OriginProducer};
use n0_future::time::Duration;
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock, mpsc, broadcast};
use tokio_util::sync::CancellationToken;
use tracing::{info, warn, error, debug, instrument};

/// Video frame packet for network transport
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoPacket {
    pub timestamp_ms: u64,
    pub width: u32,
    pub height: u32,
    pub is_keyframe: bool,
    pub data: Vec<u8>,
}

impl VideoPacket {
    pub fn to_bytes(&self) -> Vec<u8> {
        postcard::to_stdvec(self).unwrap_or_default()
    }
    
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        Ok(postcard::from_bytes(bytes)?)
    }
}

/// ALPN protocol identifier for iroh-live
pub const ALPN: &[u8] = b"iroh-live/1";

/// Live streaming ticket for sharing broadcast info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveTicket {
    pub endpoint_id: EndpointId,
    pub broadcast_name: String,
    /// Relay URL for NAT traversal
    pub relay_url: Option<String>,
    /// Direct addresses if available
    #[serde(default)]
    pub direct_addrs: Vec<SocketAddr>,
}

impl LiveTicket {
    pub fn new(endpoint_id: EndpointId, broadcast_name: impl ToString) -> Self {
        Self {
            endpoint_id,
            broadcast_name: broadcast_name.to_string(),
            relay_url: None,
            direct_addrs: Vec::new(),
        }
    }
    
    pub fn with_addr(addr: EndpointAddr, broadcast_name: impl ToString) -> Self {
        Self {
            endpoint_id: addr.id,
            broadcast_name: broadcast_name.to_string(),
            relay_url: addr.relay_urls().next().map(|u| u.to_string()),
            direct_addrs: addr.ip_addrs().cloned().collect(),
        }
    }
    
    /// Convert to EndpointAddr for connection
    pub fn to_endpoint_addr(&self) -> EndpointAddr {
        let mut addr = EndpointAddr::new(self.endpoint_id);
        if let Some(relay) = &self.relay_url {
            if let Ok(url) = relay.parse::<RelayUrl>() {
                addr = addr.with_relay_url(url);
            }
        }
        for ip in &self.direct_addrs {
            addr = addr.with_ip_addr(*ip);
        }
        addr
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        postcard::to_stdvec(self).unwrap()
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        let ticket = postcard::from_bytes(bytes)?;
        Ok(ticket)
    }

    /// Serialize to base32 encoded postcard format (includes all addressing info)
    pub fn serialize(&self) -> String {
        let bytes = postcard::to_stdvec(self).unwrap();
        data_encoding::BASE32_NOPAD.encode(&bytes).to_ascii_lowercase()
    }

    /// Deserialize from base32 encoded postcard format
    pub fn deserialize(s: &str) -> Result<Self> {
        let bytes = data_encoding::BASE32_NOPAD
            .decode(s.to_ascii_uppercase().as_bytes())?;
        let ticket: LiveTicket = postcard::from_bytes(&bytes)?;
        Ok(ticket)
    }
    
    /// Simple format for display: name@endpoint_id (truncated)
    pub fn display(&self) -> String {
        let id_str = self.endpoint_id.to_string();
        let short_id = if id_str.len() > 8 { &id_str[..8] } else { &id_str };
        format!("{}@{}...", self.broadcast_name, short_id)
    }
}

/// Video frame data (raw, unencoded)
#[derive(Debug, Clone)]
pub struct VideoFrame {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
    pub timestamp_ms: u64,
    pub format: String,
    pub is_keyframe: bool,
}

/// Encoded video packet (H264/H265)
#[derive(Debug, Clone)]
pub struct EncodedVideoPacket {
    pub data: Vec<u8>,
    pub timestamp_ms: u64,
    pub is_keyframe: bool,
    pub codec: String, // "h264", "h265"
    pub width: u32,
    pub height: u32,
}

/// Encoded audio packet (Opus/AAC)
#[derive(Debug, Clone)]
pub struct EncodedAudioPacket {
    pub data: Vec<u8>,
    pub timestamp_ms: u64,
    pub codec: String, // "opus", "aac"
    pub sample_rate: u32,
    pub channels: u16,
}

/// Audio frame data  
#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub data: Vec<u8>,
    pub sample_rate: u32,
    pub channels: u16,
    pub timestamp_ms: u64,
}

/// Video quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum VideoPreset {
    P180,  // 320x180 @ 15fps
    P360,  // 640x360 @ 24fps
    P720,  // 1280x720 @ 30fps
    P1080, // 1920x1080 @ 30fps
}

impl VideoPreset {
    pub fn resolution(&self) -> (u32, u32) {
        match self {
            VideoPreset::P180 => (320, 180),
            VideoPreset::P360 => (640, 360),
            VideoPreset::P720 => (1280, 720),
            VideoPreset::P1080 => (1920, 1080),
        }
    }

    pub fn fps(&self) -> u32 {
        match self {
            VideoPreset::P180 => 15,
            VideoPreset::P360 => 24,
            VideoPreset::P720 | VideoPreset::P1080 => 30,
        }
    }

    pub fn bitrate(&self) -> u32 {
        match self {
            VideoPreset::P180 => 150_000,
            VideoPreset::P360 => 500_000,
            VideoPreset::P720 => 2_000_000,
            VideoPreset::P1080 => 4_500_000,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            VideoPreset::P180 => "180p",
            VideoPreset::P360 => "360p", 
            VideoPreset::P720 => "720p",
            VideoPreset::P1080 => "1080p",
        }
    }
}

/// Publisher state
pub struct Publisher {
    pub id: String,
    pub broadcast_name: String,
    pub is_active: bool,
    pub frames_published: u64,
    pub bytes_sent: u64,
    pub video_preset: VideoPreset,
    producer: Option<BroadcastProducer>,
    catalog: Option<CatalogProducer>,
    shutdown: CancellationToken,
    /// Broadcast channel for sending frames to all subscribers
    frame_broadcaster: broadcast::Sender<VideoPacket>,
    /// Connected subscriber connections
    subscriber_connections: Arc<RwLock<Vec<Connection>>>,
}

impl Publisher {
    pub fn new(id: String, broadcast_name: String) -> Self {
        let (frame_broadcaster, _) = broadcast::channel(16);
        Self {
            id,
            broadcast_name,
            is_active: false,
            frames_published: 0,
            bytes_sent: 0,
            video_preset: VideoPreset::P720,
            producer: None,
            catalog: None,
            shutdown: CancellationToken::new(),
            frame_broadcaster,
            subscriber_connections: Arc::new(RwLock::new(Vec::new())),
        }
    }
    
    /// Add a subscriber connection
    pub async fn add_subscriber(&self, conn: Connection) {
        let mut conns = self.subscriber_connections.write().await;
        info!("Adding subscriber connection, total: {}", conns.len() + 1);
        conns.push(conn);
    }
    
    /// Subscribe to receive video frames
    pub fn subscribe_frames(&self) -> broadcast::Receiver<VideoPacket> {
        self.frame_broadcaster.subscribe()
    }
}

/// Subscriber state
pub struct Subscriber {
    pub id: String,
    pub broadcast_id: String,
    pub is_connected: bool,
    pub frames_received: u64,
    pub bytes_received: u64,
    pub current_quality: String,
    pub buffer_health: f32,
    consumer: Option<BroadcastConsumer>,
    catalog: Option<Catalog>,
    shutdown: CancellationToken,
    /// Connection to publisher
    connection: Option<Connection>,
    /// Channel to receive video frames
    frame_rx: Option<mpsc::UnboundedReceiver<VideoPacket>>,
    /// Sender for frame channel (stored to create receiver)
    frame_tx: mpsc::UnboundedSender<VideoPacket>,
}

impl Subscriber {
    pub fn new(id: String, broadcast_id: String) -> Self {
        let (frame_tx, frame_rx) = mpsc::unbounded_channel();
        Self {
            id,
            broadcast_id,
            is_connected: false,
            frames_received: 0,
            bytes_received: 0,
            current_quality: "auto".to_string(),
            buffer_health: 1.0,
            consumer: None,
            catalog: None,
            shutdown: CancellationToken::new(),
            connection: None,
            frame_rx: Some(frame_rx),
            frame_tx,
        }
    }
    
    /// Take the frame receiver (can only be called once)
    pub fn take_frame_rx(&mut self) -> Option<mpsc::UnboundedReceiver<VideoPacket>> {
        self.frame_rx.take()
    }
}

/// Live streaming node - manages endpoint, publishers, and subscribers
pub struct LiveNode {
    endpoint: Endpoint,
    router: Option<Router>,
    secret_key: SecretKey,
    publishers: Arc<RwLock<HashMap<String, Publisher>>>,
    subscribers: Arc<RwLock<HashMap<String, Subscriber>>>,
    shutdown: CancellationToken,
    /// Channel for receiving video frames from Flutter
    frame_tx: mpsc::UnboundedSender<(String, VideoFrame)>,
    frame_rx: Arc<Mutex<mpsc::UnboundedReceiver<(String, VideoFrame)>>>,
}

impl LiveNode {
    /// Create a new live streaming node
    pub async fn new(secret_key: Option<SecretKey>) -> Result<Self> {
        let secret_key = secret_key.unwrap_or_else(|| SecretKey::generate(&mut rand::rng()));
        
        let endpoint = Endpoint::builder()
            .secret_key(secret_key.clone())
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await?;

        info!("LiveNode bound, endpoint_id: {}", endpoint.id());

        // Wait for relay connection with better logging
        let online_result = n0_future::time::timeout(
            Duration::from_secs(15),
            endpoint.online()
        ).await;
        
        match online_result {
            Ok(()) => {
                info!("LiveNode is online and connected to relay");
                // Log endpoint address for debugging
                let addr = endpoint.addr();
                info!("Endpoint address: {:?}", addr);
            },
            Err(_) => warn!("Timeout waiting for relay connection - P2P may not work reliably"),
        }

        let (frame_tx, frame_rx) = mpsc::unbounded_channel();

        let node = Self {
            endpoint: endpoint.clone(),
            router: None,
            secret_key,
            publishers: Arc::new(RwLock::new(HashMap::new())),
            subscribers: Arc::new(RwLock::new(HashMap::new())),
            shutdown: CancellationToken::new(),
            frame_tx,
            frame_rx: Arc::new(Mutex::new(frame_rx)),
        };
        
        Ok(node)
    }
    
    /// Start accepting incoming connections (MUST be called for publisher to work)
    pub async fn start_accepting(&self) -> Result<()> {
        let endpoint = self.endpoint.clone();
        let publishers = self.publishers.clone();
        let shutdown = self.shutdown.clone();
        
        info!("Starting to accept incoming connections...");
        
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = shutdown.cancelled() => {
                        info!("Stopping connection acceptor");
                        break;
                    }
                    incoming_opt = endpoint.accept() => {
                        match incoming_opt {
                            Some(incoming) => {
                                info!("Incoming connection received");
                                
                                // Await the incoming to get the Connection
                                match incoming.await {
                                    Ok(conn) => {
                                        let remote_id = conn.remote_id();
                                        info!("Connection established from: {}", remote_id);
                                        
                                        let publishers = publishers.clone();
                                        tokio::spawn(async move {
                                            if let Err(e) = Self::handle_subscriber_connection(conn, publishers).await {
                                                error!("Error handling subscriber: {}", e);
                                            }
                                        });
                                    }
                                    Err(e) => error!("Failed to complete connection: {}", e),
                                }
                            }
                            None => {
                                info!("Endpoint closed");
                                break;
                            }
                        }
                    }
                }
            }
        });
        
        Ok(())
    }
    
    /// Handle an incoming subscriber connection
    async fn handle_subscriber_connection(
        conn: Connection,
        publishers: Arc<RwLock<HashMap<String, Publisher>>>,
    ) -> Result<()> {
        info!("Handling subscriber connection from: {:?}", conn.remote_id());
        
        // First, receive the broadcast name the subscriber wants to join
        // We'll use a uni stream for the initial handshake
        let mut recv_stream = match conn.accept_uni().await {
            Ok(stream) => stream,
            Err(e) => {
                // Fallback: just add to first active publisher
                info!("No handshake stream, using first active publisher: {}", e);
                let publishers_read = publishers.read().await;
                if let Some((_, publisher)) = publishers_read.iter().find(|(_, p)| p.is_active) {
                    let subscriber_connections = publisher.subscriber_connections.clone();
                    let mut frame_rx = publisher.frame_broadcaster.subscribe();
                    drop(publishers_read);
                    
                    // Add connection to publisher's subscriber list
                    subscriber_connections.write().await.push(conn.clone());
                    
                    // Forward frames to this subscriber
                    tokio::spawn(async move {
                        info!("Starting frame forwarding to subscriber");
                        while let Ok(packet) = frame_rx.recv().await {
                            let data = packet.to_bytes();
                            if let Err(e) = conn.send_datagram(Bytes::from(data)) {
                                info!("Failed to send datagram to subscriber: {}", e);
                                break;
                            }
                        }
                        info!("Frame forwarding ended");
                    });
                    
                    return Ok(());
                }
                anyhow::bail!("No active publishers");
            }
        };
        
        // Read broadcast name from subscriber
        let mut buf = vec![0u8; 256];
        let n = recv_stream.read(&mut buf).await?.unwrap_or(0);
        let broadcast_name = String::from_utf8_lossy(&buf[..n]).to_string();
        info!("Subscriber wants to join broadcast: {}", broadcast_name);
        
        // Find matching publisher
        let publishers_read = publishers.read().await;
        let publisher = publishers_read.iter()
            .find(|(_, p)| p.broadcast_name == broadcast_name && p.is_active)
            .map(|(_, p)| p);
        
        if let Some(publisher) = publisher {
            let subscriber_connections = publisher.subscriber_connections.clone();
            let mut frame_rx = publisher.frame_broadcaster.subscribe();
            drop(publishers_read);
            
            // Add connection to publisher's subscriber list
            subscriber_connections.write().await.push(conn.clone());
            
            info!("Subscriber connected to broadcast: {}", broadcast_name);
            
            // Forward frames to this subscriber via datagrams
            tokio::spawn(async move {
                info!("Starting frame forwarding to subscriber");
                while let Ok(packet) = frame_rx.recv().await {
                    let data = packet.to_bytes();
                    if let Err(e) = conn.send_datagram(Bytes::from(data)) {
                        info!("Failed to send datagram to subscriber: {}", e);
                        break;
                    }
                }
                info!("Frame forwarding ended");
            });
        } else {
            warn!("No active publisher found for broadcast: {}", broadcast_name);
        }
        
        Ok(())
    }

    /// Get endpoint ID
    pub fn endpoint_id(&self) -> EndpointId {
        self.endpoint.id()
    }

    /// Get endpoint address for sharing
    pub fn endpoint_addr(&self) -> EndpointAddr {
        self.endpoint.addr()
    }

    /// Create a publisher
    pub async fn create_publisher(&self, publisher_id: String, broadcast_name: String) -> Result<LiveTicket> {
        let mut publishers = self.publishers.write().await;
        
        if publishers.contains_key(&publisher_id) {
            anyhow::bail!("Publisher already exists: {}", publisher_id);
        }

        let publisher = Publisher::new(publisher_id.clone(), broadcast_name.clone());
        publishers.insert(publisher_id.clone(), publisher);

        // Create ticket with full addressing info (including relay URL)
        let addr = self.endpoint.addr();
        let ticket = LiveTicket::with_addr(addr, broadcast_name);
        info!("Created publisher: {}, ticket: {}", publisher_id, ticket.display());
        info!("Full ticket (for sharing): {}", ticket.serialize());
        info!("Relay URL: {:?}", ticket.relay_url);
        info!("Direct addrs: {:?}", ticket.direct_addrs);
        
        Ok(ticket)
    }

    /// Start publishing
    pub async fn start_publishing(&self, publisher_id: &str) -> Result<()> {
        let mut publishers = self.publishers.write().await;
        let publisher = publishers.get_mut(publisher_id)
            .context("Publisher not found")?;
        
        // Create MoQ broadcast producer
        let mut producer = BroadcastProducer::default();
        let catalog = Catalog::default().produce();
        producer.insert_track(catalog.consumer.track);
        
        publisher.producer = Some(producer);
        publisher.catalog = Some(catalog.producer);
        publisher.is_active = true;

        info!("Started publishing: {}", publisher_id);
        Ok(())
    }

    /// Stop publishing
    pub async fn stop_publishing(&self, publisher_id: &str) -> Result<()> {
        let mut publishers = self.publishers.write().await;
        let publisher = publishers.get_mut(publisher_id)
            .context("Publisher not found")?;
        
        publisher.is_active = false;
        publisher.shutdown.cancel();
        
        info!("Stopped publishing: {}", publisher_id);
        Ok(())
    }

    /// Push a video frame to a publisher
    pub async fn push_video_frame(&self, publisher_id: &str, frame: VideoFrame) -> Result<()> {
        let mut publishers = self.publishers.write().await;
        let publisher = publishers.get_mut(publisher_id)
            .context("Publisher not found")?;
        
        if !publisher.is_active {
            anyhow::bail!("Publisher is not active");
        }

        let frame_size = frame.data.len() as u64;
        publisher.frames_published += 1;
        publisher.bytes_sent += frame_size;

        // In a real implementation, this would:
        // 1. Encode the frame (if not already encoded)
        // 2. Chunk it into MoQ groups
        // 3. Send via the broadcast producer
        
        // For now, we send via channel for processing
        self.frame_tx.send((publisher_id.to_string(), frame))?;

        Ok(())
    }

    /// Push an already-encoded video packet to a publisher
    /// 
    /// This is the preferred method when encoding is done on the Flutter side
    /// (e.g., using FFmpegKit for mobile platforms)
    pub async fn push_encoded_video(&self, publisher_id: &str, packet: EncodedVideoPacket) -> Result<()> {
        let mut publishers = self.publishers.write().await;
        let publisher = publishers.get_mut(publisher_id)
            .context("Publisher not found")?;
        
        if !publisher.is_active {
            anyhow::bail!("Publisher is not active");
        }

        let packet_size = packet.data.len() as u64;
        publisher.frames_published += 1;
        publisher.bytes_sent += packet_size;

        // Create a VideoPacket for broadcast
        let video_packet = VideoPacket {
            timestamp_ms: packet.timestamp_ms,
            width: packet.width,
            height: packet.height,
            is_keyframe: packet.is_keyframe,
            data: packet.data.clone(),
        };
        
        // Broadcast to all subscribers via the channel
        let _ = publisher.frame_broadcaster.send(video_packet);
        
        debug!(
            "Push encoded video: {} bytes, keyframe={}, ts={}, subscribers={}",
            packet_size, packet.is_keyframe, packet.timestamp_ms,
            publisher.frame_broadcaster.receiver_count()
        );

        Ok(())
    }

    /// Push an already-encoded audio packet to a publisher
    pub async fn push_encoded_audio(&self, publisher_id: &str, packet: EncodedAudioPacket) -> Result<()> {
        let mut publishers = self.publishers.write().await;
        let publisher = publishers.get_mut(publisher_id)
            .context("Publisher not found")?;
        
        if !publisher.is_active {
            anyhow::bail!("Publisher is not active");
        }

        let packet_size = packet.data.len() as u64;
        publisher.bytes_sent += packet_size;

        debug!(
            "Push encoded audio: {} bytes, ts={}",
            packet_size, packet.timestamp_ms
        );

        Ok(())
    }

    /// Create a subscriber
    pub async fn create_subscriber(&self, subscriber_id: String, broadcast_id: String) -> Result<()> {
        let mut subscribers = self.subscribers.write().await;
        
        if subscribers.contains_key(&subscriber_id) {
            anyhow::bail!("Subscriber already exists: {}", subscriber_id);
        }

        let subscriber = Subscriber::new(subscriber_id.clone(), broadcast_id);
        subscribers.insert(subscriber_id.clone(), subscriber);

        info!("Created subscriber: {}", subscriber_id);
        Ok(())
    }

    /// Connect subscriber to a broadcast
    pub async fn connect_subscriber(&self, subscriber_id: &str, ticket: &LiveTicket) -> Result<()> {
        // Convert ticket to EndpointAddr (includes relay and direct addresses)
        let target_addr = ticket.to_endpoint_addr();
        
        info!("Connecting to endpoint {} for broadcast '{}'", ticket.endpoint_id, ticket.broadcast_name);
        info!("Target relay: {:?}", ticket.relay_url);
        info!("Target direct addrs: {:?}", ticket.direct_addrs);
        info!("Local endpoint: {}", self.endpoint_id());
        
        // Log our endpoint address for debugging
        let our_addr = self.endpoint.addr();
        info!("Our endpoint address: {:?}", our_addr);
        
        // Try to connect with a timeout using full address
        let connect_result = n0_future::time::timeout(
            Duration::from_secs(30),
            self.endpoint.connect(target_addr, ALPN)
        ).await;
        
        let conn = match connect_result {
            Ok(Ok(conn)) => {
                info!("Successfully connected to publisher: {}", ticket.endpoint_id);
                conn
            },
            Ok(Err(e)) => {
                error!("Connection error to {}: {}", ticket.endpoint_id, e);
                // Provide more helpful error message
                if e.to_string().contains("timeout") || e.to_string().contains("Timeout") {
                    anyhow::bail!(
                        "Connection timeout - publisher may be offline or unreachable. \
                        Make sure the broadcaster is still streaming and both devices can reach each other."
                    );
                } else if e.to_string().contains("refused") {
                    anyhow::bail!(
                        "Connection refused - publisher is not accepting connections. \
                        The broadcast may have ended."
                    );
                } else {
                    anyhow::bail!("Failed to connect to publisher: {}", e);
                }
            },
            Err(_) => {
                error!("Connection timeout after 30s to {}", ticket.endpoint_id);
                anyhow::bail!(
                    "Connection timeout after 30 seconds. \
                    The publisher may be offline, behind a restrictive firewall, or unreachable. \
                    Try ensuring both devices are on the same network or have good internet connectivity."
                );
            }
        };

        let mut subscribers = self.subscribers.write().await;
        let subscriber = subscribers.get_mut(subscriber_id)
            .context("Subscriber not found")?;
        
        subscriber.is_connected = true;
        subscriber.connection = Some(conn.clone());

        info!("Subscriber {} connected to broadcast '{}'", subscriber_id, ticket.broadcast_name);

        // Send handshake with broadcast name via uni stream
        match conn.open_uni().await {
            Ok(mut send_stream) => {
                if let Err(e) = send_stream.write_all(ticket.broadcast_name.as_bytes()).await {
                    warn!("Failed to send broadcast name: {}", e);
                }
                let _ = send_stream.finish();
            }
            Err(e) => {
                warn!("Failed to open handshake stream: {}", e);
            }
        }

        // Start receiving frames from publisher
        let frame_tx = subscriber.frame_tx.clone();
        let shutdown = subscriber.shutdown.clone();
        let subscriber_id_clone = subscriber_id.to_string();
        
        tokio::spawn(async move {
            info!("Starting frame receiver for subscriber {}", subscriber_id_clone);
            loop {
                tokio::select! {
                    _ = shutdown.cancelled() => {
                        info!("Frame receiver stopped for {}", subscriber_id_clone);
                        break;
                    }
                    result = conn.read_datagram() => {
                        match result {
                            Ok(data) => {
                                match VideoPacket::from_bytes(&data) {
                                    Ok(packet) => {
                                        debug!("Received video packet: {}x{}, {} bytes", 
                                            packet.width, packet.height, packet.data.len());
                                        if let Err(e) = frame_tx.send(packet) {
                                            warn!("Failed to forward frame: {}", e);
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        debug!("Failed to parse video packet: {}", e);
                                    }
                                }
                            }
                            Err(e) => {
                                info!("Connection closed for subscriber {}: {}", subscriber_id_clone, e);
                                break;
                            }
                        }
                    }
                }
            }
        });
        
        Ok(())
    }

    /// Disconnect subscriber
    pub async fn disconnect_subscriber(&self, subscriber_id: &str) -> Result<()> {
        let mut subscribers = self.subscribers.write().await;
        let subscriber = subscribers.get_mut(subscriber_id)
            .context("Subscriber not found")?;
        
        subscriber.is_connected = false;
        subscriber.shutdown.cancel();

        info!("Disconnected subscriber: {}", subscriber_id);
        Ok(())
    }

    /// Get publisher status
    pub async fn get_publisher_status(&self, publisher_id: &str) -> Option<PublisherStatus> {
        let publishers = self.publishers.read().await;
        publishers.get(publisher_id).map(|p| PublisherStatus {
            publisher_id: p.id.clone(),
            broadcast_name: p.broadcast_name.clone(),
            is_active: p.is_active,
            frames_published: p.frames_published,
            bytes_sent: p.bytes_sent,
            video_preset: p.video_preset.name().to_string(),
        })
    }

    /// Get subscriber status
    pub async fn get_subscriber_status(&self, subscriber_id: &str) -> Option<SubscriberStatus> {
        let subscribers = self.subscribers.read().await;
        subscribers.get(subscriber_id).map(|s| SubscriberStatus {
            subscriber_id: s.id.clone(),
            broadcast_id: s.broadcast_id.clone(),
            is_connected: s.is_connected,
            frames_received: s.frames_received,
            bytes_received: s.bytes_received,
            current_quality: s.current_quality.clone(),
            buffer_health: s.buffer_health,
        })
    }

    /// Receive a video frame from subscriber (non-blocking)
    /// Returns None if no frame is available
    pub async fn receive_video_frame(&self, subscriber_id: &str) -> Option<VideoPacket> {
        let mut subscribers = self.subscribers.write().await;
        let subscriber = subscribers.get_mut(subscriber_id)?;
        
        if let Some(ref mut rx) = subscriber.frame_rx {
            match rx.try_recv() {
                Ok(packet) => {
                    subscriber.frames_received += 1;
                    subscriber.bytes_received += packet.data.len() as u64;
                    Some(packet)
                }
                Err(_) => None
            }
        } else {
            None
        }
    }

    /// Simulate receiving video for testing
    pub async fn simulate_video_receive(&self, subscriber_id: &str, frame_size: u64) -> Result<()> {
        let mut subscribers = self.subscribers.write().await;
        let subscriber = subscribers.get_mut(subscriber_id)
            .context("Subscriber not found")?;
        
        if subscriber.is_connected {
            subscriber.frames_received += 1;
            subscriber.bytes_received += frame_size;
        }
        
        Ok(())
    }

    /// Shutdown the node
    pub async fn shutdown(&self) {
        info!("Shutting down LiveNode");
        self.shutdown.cancel();
        self.endpoint.close().await;
    }
}

/// Publisher status for Flutter
#[derive(Debug, Clone)]
pub struct PublisherStatus {
    pub publisher_id: String,
    pub broadcast_name: String,
    pub is_active: bool,
    pub frames_published: u64,
    pub bytes_sent: u64,
    pub video_preset: String,
}

/// Subscriber status for Flutter
#[derive(Debug, Clone)]
pub struct SubscriberStatus {
    pub subscriber_id: String,
    pub broadcast_id: String,
    pub is_connected: bool,
    pub frames_received: u64,
    pub bytes_received: u64,
    pub current_quality: String,
    pub buffer_health: f32,
}
