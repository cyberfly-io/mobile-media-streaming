//! Direct P2P streaming using iroh direct connections (not gossip)
//!
//! This module provides reliable bidirectional streaming by establishing
//! direct QUIC connections between peers instead of using gossip protocol.
//! This solves NAT traversal issues where gossip relay doesn't forward messages.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow};
use iroh::{Endpoint, EndpointAddr, EndpointId, SecretKey, RelayUrl};
use iroh::endpoint::Connection;
use n0_future::time::{Duration, SystemTime};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, mpsc, RwLock};
use tracing::{info, warn, error, debug};

/// ALPN protocol for our streaming
pub const STREAMING_ALPN: &[u8] = b"cyberfly/streaming/0";

/// Direct message types for the protocol
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DirectMessage {
    /// Request metadata from broadcaster
    RequestMetadata,
    /// Metadata response
    Metadata {
        file_name: String,
        file_size: u64,
        mime_type: String,
        total_chunks: u32,
        duration: Option<f64>,
    },
    /// Request a specific chunk
    RequestChunk { index: u32 },
    /// Chunk data
    Chunk {
        index: u32,
        data: Vec<u8>,
    },
    /// Presence/ping
    Presence { name: String },
    /// Generic signal (for backwards compatibility)
    Signal { data: Vec<u8> },
}

impl DirectMessage {
    pub fn encode(&self) -> Result<Vec<u8>> {
        postcard::to_stdvec(self).map_err(Into::into)
    }

    pub fn decode(data: &[u8]) -> Result<Self> {
        postcard::from_bytes(data).map_err(Into::into)
    }
}

/// Peer connection info
#[derive(Debug, Clone)]
pub struct PeerInfo {
    pub endpoint_id: EndpointId,
    pub relay_url: Option<RelayUrl>,
}

/// Direct streaming endpoint
pub struct DirectStreamingEndpoint {
    endpoint: Endpoint,
    secret_key: SecretKey,
    /// Active connections to peers
    connections: Arc<RwLock<HashMap<EndpointId, Arc<Connection>>>>,
    /// Event sender for incoming messages
    event_tx: mpsc::UnboundedSender<DirectStreamEvent>,
    /// Event receiver (for polling)
    event_rx: Arc<Mutex<mpsc::UnboundedReceiver<DirectStreamEvent>>>,
    /// Whether we're accepting connections (broadcaster mode)
    is_broadcaster: bool,
}

/// Events from direct streaming
#[derive(Debug, Clone)]
pub enum DirectStreamEvent {
    /// Peer connected
    PeerConnected { endpoint_id: String },
    /// Peer disconnected
    PeerDisconnected { endpoint_id: String },
    /// Received a message from peer
    Message {
        from: String,
        message: DirectMessage,
        timestamp: u64,
    },
    /// Error occurred
    Error { message: String },
}

impl DirectStreamingEndpoint {
    /// Create a new direct streaming endpoint
    pub async fn new(secret_key: Option<SecretKey>) -> Result<Self> {
        let secret_key = secret_key.unwrap_or_else(|| SecretKey::generate(&mut rand::rng()));
        
        let endpoint = Endpoint::builder()
            .secret_key(secret_key.clone())
            .alpns(vec![STREAMING_ALPN.to_vec()])
            .bind()
            .await?;

        info!("Direct streaming endpoint bound, id: {}", endpoint.id());
        
        // Wait for relay connection
        info!("Waiting for endpoint to come online...");
        let online_result = n0_future::time::timeout(
            Duration::from_secs(10),
            endpoint.online()
        ).await;
        
        match online_result {
            Ok(()) => info!("Endpoint is online"),
            Err(_) => warn!("Timeout waiting for relay, continuing anyway"),
        }

        let (event_tx, event_rx) = mpsc::unbounded_channel();

        Ok(Self {
            endpoint,
            secret_key,
            connections: Arc::new(RwLock::new(HashMap::new())),
            event_tx,
            event_rx: Arc::new(Mutex::new(event_rx)),
            is_broadcaster: false,
        })
    }

    /// Get our endpoint ID
    pub fn endpoint_id(&self) -> EndpointId {
        self.endpoint.id()
    }

    /// Get our endpoint address (for sharing with peers)
    pub fn endpoint_addr(&self) -> EndpointAddr {
        self.endpoint.addr()
    }

    /// Get relay URL if available
    pub fn relay_url(&self) -> Option<RelayUrl> {
        self.endpoint.addr().relay_urls().next().cloned()
    }

    /// Start accepting connections (for broadcaster)
    pub async fn start_accepting(&mut self) -> Result<()> {
        self.is_broadcaster = true;
        
        let endpoint = self.endpoint.clone();
        let connections = self.connections.clone();
        let event_tx = self.event_tx.clone();

        // Spawn task to accept incoming connections
        tokio::spawn(async move {
            info!("[Broadcaster] Starting to accept connections...");
            
            while let Some(incoming) = endpoint.accept().await {
                info!("[Broadcaster] Incoming connection...");
                
                match incoming.accept() {
                    Ok(accepting) => {
                        let connections = connections.clone();
                        let event_tx = event_tx.clone();
                        
                        tokio::spawn(async move {
                            match accepting.await {
                                Ok(conn) => {
                                    let remote_id = conn.remote_id();
                                    info!("[Broadcaster] Connection accepted from: {}", remote_id);
                                    
                                    // Store connection
                                    {
                                        let mut conns = connections.write().await;
                                        conns.insert(remote_id, Arc::new(conn.clone()));
                                    }
                                    
                                    // Notify about new peer
                                    let _ = event_tx.send(DirectStreamEvent::PeerConnected {
                                        endpoint_id: remote_id.to_string(),
                                    });
                                    
                                    // Handle incoming streams from this connection
                                    Self::handle_connection(conn, event_tx, connections).await;
                                }
                                Err(e) => {
                                    error!("[Broadcaster] Failed to accept connection: {}", e);
                                }
                            }
                        });
                    }
                    Err(e) => {
                        error!("[Broadcaster] Failed to accept incoming: {}", e);
                    }
                }
            }
            
            info!("[Broadcaster] Accept loop ended");
        });

        Ok(())
    }

    /// Connect to a peer (for viewer)
    pub async fn connect_to_peer(&self, peer_addr: EndpointAddr) -> Result<EndpointId> {
        let remote_id = peer_addr.id;
        info!("[Viewer] Connecting to peer: {}", remote_id);
        
        let conn = self.endpoint
            .connect(peer_addr, STREAMING_ALPN)
            .await
            .context("Failed to connect to peer")?;
        
        info!("[Viewer] Connected to: {}", remote_id);
        
        // Store connection
        {
            let mut conns = self.connections.write().await;
            conns.insert(remote_id, Arc::new(conn.clone()));
        }
        
        // Notify about connection
        let _ = self.event_tx.send(DirectStreamEvent::PeerConnected {
            endpoint_id: remote_id.to_string(),
        });
        
        // Spawn handler for incoming streams
        let connections = self.connections.clone();
        let event_tx = self.event_tx.clone();
        tokio::spawn(async move {
            Self::handle_connection(conn, event_tx, connections).await;
        });
        
        Ok(remote_id)
    }

    /// Handle a connection (both directions)
    async fn handle_connection(
        conn: Connection,
        event_tx: mpsc::UnboundedSender<DirectStreamEvent>,
        connections: Arc<RwLock<HashMap<EndpointId, Arc<Connection>>>>,
    ) {
        let remote_id = conn.remote_id();
        info!("[Connection] Handling connection with: {}", remote_id);
        
        loop {
            // Accept bidirectional streams
            match conn.accept_bi().await {
                Ok((send, mut recv)) => {
                    let event_tx = event_tx.clone();
                    let remote_id_str = remote_id.to_string();
                    
                    tokio::spawn(async move {
                        // Read message
                        match recv.read_to_end(1024 * 1024).await {
                            Ok(data) => {
                                match DirectMessage::decode(&data) {
                                    Ok(message) => {
                                        let timestamp = SystemTime::now()
                                            .duration_since(SystemTime::UNIX_EPOCH)
                                            .unwrap()
                                            .as_micros() as u64;
                                        
                                        debug!("[Connection] Received message from {}: {:?}", 
                                            &remote_id_str[..16.min(remote_id_str.len())], 
                                            std::mem::discriminant(&message));
                                        
                                        let _ = event_tx.send(DirectStreamEvent::Message {
                                            from: remote_id_str,
                                            message,
                                            timestamp,
                                        });
                                    }
                                    Err(e) => {
                                        warn!("[Connection] Failed to decode message: {}", e);
                                    }
                                }
                            }
                            Err(e) => {
                                warn!("[Connection] Failed to read from stream: {}", e);
                            }
                        }
                        drop(send); // Close the send side
                    });
                }
                Err(e) => {
                    info!("[Connection] Connection closed: {}", e);
                    break;
                }
            }
        }
        
        // Remove from connections
        {
            let mut conns = connections.write().await;
            conns.remove(&remote_id);
        }
        
        // Notify about disconnection
        let _ = event_tx.send(DirectStreamEvent::PeerDisconnected {
            endpoint_id: remote_id.to_string(),
        });
    }

    /// Send a message to a specific peer
    pub async fn send_to_peer(&self, peer_id: &EndpointId, message: &DirectMessage) -> Result<()> {
        let conns = self.connections.read().await;
        let conn = conns.get(peer_id)
            .ok_or_else(|| anyhow!("Not connected to peer: {}", peer_id))?;
        
        let data = message.encode()?;
        
        // Open a bidirectional stream
        let (mut send, _recv) = conn.open_bi().await
            .map_err(|e| anyhow!("Failed to open stream: {}", e))?;
        
        // Send the message
        send.write_all(&data).await
            .map_err(|e| anyhow!("Failed to write: {}", e))?;
        send.finish()
            .map_err(|e| anyhow!("Failed to finish: {}", e))?;
        
        debug!("[Send] Sent message to {}: {:?}", 
            &peer_id.to_string()[..16.min(peer_id.to_string().len())],
            std::mem::discriminant(message));
        
        Ok(())
    }

    /// Broadcast a message to all connected peers
    pub async fn broadcast(&self, message: &DirectMessage) -> Result<()> {
        let conns = self.connections.read().await;
        
        if conns.is_empty() {
            warn!("[Broadcast] No connected peers");
            return Ok(());
        }
        
        let data = message.encode()?;
        
        for (peer_id, conn) in conns.iter() {
            match conn.open_bi().await {
                Ok((mut send, _recv)) => {
                    if let Err(e) = send.write_all(&data).await {
                        warn!("[Broadcast] Failed to send to {}: {}", peer_id, e);
                        continue;
                    }
                    if let Err(e) = send.finish() {
                        warn!("[Broadcast] Failed to finish stream to {}: {}", peer_id, e);
                    }
                }
                Err(e) => {
                    warn!("[Broadcast] Failed to open stream to {}: {}", peer_id, e);
                }
            }
        }
        
        debug!("[Broadcast] Sent to {} peers", conns.len());
        Ok(())
    }

    /// Poll for events
    pub async fn poll_events(&self) -> Vec<DirectStreamEvent> {
        let mut events = Vec::new();
        let mut rx = self.event_rx.lock().await;
        
        while let Ok(event) = rx.try_recv() {
            events.push(event);
        }
        
        events
    }

    /// Get number of connected peers
    pub async fn peer_count(&self) -> usize {
        self.connections.read().await.len()
    }

    /// Get list of connected peer IDs
    pub async fn connected_peers(&self) -> Vec<EndpointId> {
        self.connections.read().await.keys().cloned().collect()
    }

    /// Disconnect from a peer
    pub async fn disconnect_peer(&self, peer_id: &EndpointId) {
        let mut conns = self.connections.write().await;
        if let Some(conn) = conns.remove(peer_id) {
            conn.close(0u32.into(), b"disconnect");
        }
    }

    /// Close all connections and shutdown
    pub async fn shutdown(&self) {
        info!("Shutting down direct streaming endpoint...");
        
        // Close all connections
        let mut conns = self.connections.write().await;
        for (_, conn) in conns.drain() {
            conn.close(0u32.into(), b"shutdown");
        }
        
        // Close the endpoint
        self.endpoint.close().await;
        
        info!("Direct streaming endpoint shutdown complete");
    }
}

/// Ticket for direct connection (contains endpoint address info)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectStreamTicket {
    /// The endpoint ID of the broadcaster
    pub endpoint_id: EndpointId,
    /// Relay URL for NAT traversal
    pub relay_url: Option<RelayUrl>,
    /// Direct IP addresses (if available)
    pub direct_addrs: Vec<std::net::SocketAddr>,
}

impl DirectStreamTicket {
    pub fn new(addr: EndpointAddr) -> Self {
        Self {
            endpoint_id: addr.id,
            relay_url: addr.relay_urls().next().cloned(),
            direct_addrs: addr.ip_addrs().cloned().collect(),
        }
    }

    pub fn serialize(&self) -> String {
        let bytes = postcard::to_stdvec(self).unwrap();
        data_encoding::BASE32_NOPAD.encode(&bytes)
    }

    pub fn deserialize(input: &str) -> Result<Self> {
        let bytes = data_encoding::BASE32_NOPAD.decode(input.as_bytes())
            .map_err(|e| anyhow!("Invalid ticket encoding: {}", e))?;
        postcard::from_bytes(&bytes).map_err(Into::into)
    }

    pub fn to_endpoint_addr(&self) -> EndpointAddr {
        let mut addr = EndpointAddr::new(self.endpoint_id);
        if let Some(relay) = &self.relay_url {
            addr = addr.with_relay_url(relay.clone());
        }
        for ip in &self.direct_addrs {
            addr = addr.with_ip_addr(*ip);
        }
        addr
    }
}
