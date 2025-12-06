//! Live streaming protocol handler and session management
//!
//! This module provides the core `Live` struct that manages:
//! - Accepting incoming connections via iroh protocol handler
//! - Managing active broadcast sessions
//! - Publishing broadcasts to connected peers
//! - Subscribing to remote broadcasts

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Context, Result};
use iroh::{Endpoint, EndpointAddr, EndpointId};
use iroh::endpoint::Connection;
use iroh::protocol::ProtocolHandler;
use moq_lite::{BroadcastConsumer, BroadcastProducer, Origin, OriginConsumer, OriginProducer};
use n0_future::task::AbortOnDropHandle;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use tracing::{debug, error, info, instrument, warn, Instrument, error_span};

use super::webtransport::Session;

/// ALPN protocol identifier for iroh-live
pub const ALPN: &[u8] = b"iroh-live/1";

/// Broadcast name type alias
type BroadcastName = String;

/// Messages sent to the Live actor
enum ActorMessage {
    /// Handle a new incoming session
    HandleSession(LiveSession),
    /// Publish a broadcast
    PublishBroadcast(BroadcastName, BroadcastProducer),
    /// Remove a broadcast
    RemoveBroadcast(BroadcastName),
}

/// Live streaming coordinator
/// 
/// This is the main entry point for live streaming. It manages:
/// - The iroh endpoint
/// - Active broadcasts (as publisher)
/// - Connected sessions (peers)
#[derive(Debug, Clone)]
pub struct Live {
    endpoint: Endpoint,
    tx: mpsc::Sender<ActorMessage>,
    shutdown_token: CancellationToken,
    _actor_handle: Arc<AbortOnDropHandle<()>>,
}

impl Live {
    /// Create a new Live instance with the given endpoint
    pub fn new(endpoint: Endpoint) -> Self {
        let (tx, rx) = mpsc::channel(16);
        let actor = Actor::default();
        let shutdown_token = actor.shutdown_token.clone();
        
        let actor_task = tokio::spawn(async move {
            actor.run(rx).instrument(error_span!("LiveActor")).await
        });
        
        Self {
            endpoint,
            tx,
            shutdown_token,
            _actor_handle: Arc::new(AbortOnDropHandle::new(actor_task)),
        }
    }

    /// Get a protocol handler for accepting incoming connections
    pub fn protocol_handler(&self) -> LiveProtocolHandler {
        LiveProtocolHandler {
            tx: self.tx.clone(),
        }
    }

    /// Publish a broadcast
    /// 
    /// The broadcast will be announced to all connected peers
    /// and available for subscription.
    pub async fn publish(&self, name: impl ToString, producer: BroadcastProducer) -> Result<()> {
        self.tx
            .send(ActorMessage::PublishBroadcast(name.to_string(), producer))
            .await
            .map_err(|_| anyhow::anyhow!("live actor died"))?;
        Ok(())
    }

    /// Remove a published broadcast
    pub async fn unpublish(&self, name: impl ToString) -> Result<()> {
        self.tx
            .send(ActorMessage::RemoveBroadcast(name.to_string()))
            .await
            .map_err(|_| anyhow::anyhow!("live actor died"))?;
        Ok(())
    }

    /// Connect to a remote peer and create a session
    pub async fn connect(&self, addr: impl Into<EndpointAddr>) -> Result<LiveSession> {
        LiveSession::connect(&self.endpoint, addr).await
    }

    /// Shutdown the live streaming service
    pub fn shutdown(&self) {
        self.shutdown_token.cancel();
    }

    /// Get the endpoint
    pub fn endpoint(&self) -> &Endpoint {
        &self.endpoint
    }
}

/// Protocol handler for accepting incoming live connections
#[derive(Debug, Clone)]
pub struct LiveProtocolHandler {
    tx: mpsc::Sender<ActorMessage>,
}

impl LiveProtocolHandler {
    async fn handle_connection(&self, connection: Connection) -> Result<()> {
        info!(remote = %connection.remote_id().fmt_short(), "accepting connection");
        
        // Create WebTransport session
        let session = Session::new(connection);
        
        // Create MoQ session (accept mode - we're the server)
        let live_session = LiveSession::session_accept(session).await?;
        
        // Send to actor for management
        self.tx
            .send(ActorMessage::HandleSession(live_session))
            .await
            .map_err(|_| anyhow::anyhow!("live actor died"))?;
        
        Ok(())
    }
}

impl ProtocolHandler for LiveProtocolHandler {
    async fn accept(&self, connection: Connection) -> Result<(), iroh::protocol::AcceptError> {
        if let Err(err) = self.handle_connection(connection).await {
            warn!("failed to handle connection: {err:#}");
        }
        Ok(())
    }
}

/// A live streaming session with a remote peer
pub struct LiveSession {
    /// Remote endpoint ID
    pub remote: EndpointId,
    /// WebTransport session
    wt_session: Session,
    /// MoQ session
    moq_session: moq_lite::Session<Session>,
    /// Origin producer - for publishing to this peer
    publish: OriginProducer,
    /// Origin consumer - for subscribing from this peer
    subscribe: OriginConsumer,
}

impl LiveSession {
    /// Connect to a remote peer
    #[instrument(skip_all, fields(remote = tracing::field::Empty))]
    pub async fn connect(
        endpoint: &Endpoint,
        remote_addr: impl Into<EndpointAddr>,
    ) -> Result<Self> {
        let addr = remote_addr.into();
        info!("connecting to {:?}", addr);
        
        let conn = endpoint.connect(addr, ALPN).await
            .context("failed to connect")?;
        
        let remote = conn.remote_id();
        tracing::Span::current().record("remote", tracing::field::display(remote.fmt_short()));
        info!("connected");
        
        let session = Session::new(conn);
        Self::session_connect(session).await
    }

    /// Create a session in connect mode (we're the client)
    pub async fn session_connect(wt_session: Session) -> Result<Self> {
        let remote = wt_session.remote_id();
        
        // Create MoQ origins for bidirectional pub/sub
        let publish = moq_lite::Origin::produce();
        let subscribe = moq_lite::Origin::produce();
        
        // Connect MoQ session
        let moq_session = moq_lite::Session::connect(
            wt_session.clone(),
            publish.consumer,
            subscribe.producer,
        ).await?;
        
        Ok(Self {
            remote,
            wt_session,
            moq_session,
            publish: publish.producer,
            subscribe: subscribe.consumer,
        })
    }

    /// Create a session in accept mode (we're the server)
    pub async fn session_accept(wt_session: Session) -> Result<Self> {
        let remote = wt_session.remote_id();
        
        // Create MoQ origins for bidirectional pub/sub
        let publish = moq_lite::Origin::produce();
        let subscribe = moq_lite::Origin::produce();
        
        // Accept MoQ session
        let moq_session = moq_lite::Session::accept(
            wt_session.clone(),
            publish.consumer,
            subscribe.producer,
        ).await?;
        
        Ok(Self {
            remote,
            wt_session,
            moq_session,
            publish: publish.producer,
            subscribe: subscribe.consumer,
        })
    }

    /// Get the underlying connection
    pub fn conn(&self) -> &Connection {
        self.wt_session.conn()
    }

    /// Subscribe to a broadcast from this peer
    pub async fn subscribe(&mut self, name: &str) -> Result<BroadcastConsumer> {
        let consumer = self.wait_for_broadcast(name).await?;
        Ok(consumer)
    }

    /// Publish a broadcast to this peer
    pub fn publish(&self, name: String, broadcast: BroadcastConsumer) {
        self.publish.publish_broadcast(name, broadcast);
    }

    /// Wait for a specific broadcast to be announced
    async fn wait_for_broadcast(&mut self, name: &str) -> Result<BroadcastConsumer> {
        // Check if already announced
        if let Some(consumer) = self.subscribe.consume_broadcast(name) {
            return Ok(consumer);
        }
        
        // Wait for announcement
        loop {
            let (path, consumer) = self.subscribe
                .announced()
                .await
                .ok_or_else(|| anyhow::anyhow!("broadcast not announced"))?;
            
            debug!("peer announced broadcast: {path}");
            
            if path.as_str() == name {
                return consumer.ok_or_else(|| anyhow::anyhow!("broadcast closed"));
            }
        }
    }
}

impl std::fmt::Debug for LiveSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LiveSession")
            .field("remote", &self.remote.fmt_short().to_string())
            .finish()
    }
}

/// State for a connected session
struct SessionState {
    /// Origin producer for publishing to this peer
    publish: OriginProducer,
}

/// Background actor managing live sessions
#[derive(Default)]
struct Actor {
    shutdown_token: CancellationToken,
    /// Published broadcasts
    broadcasts: HashMap<BroadcastName, BroadcastProducer>,
    /// Connected sessions
    sessions: HashMap<EndpointId, SessionState>,
    /// Session tasks
    session_tasks: tokio::task::JoinSet<(EndpointId, Result<(), moq_lite::Error>)>,
}

impl Actor {
    /// Run the actor event loop
    pub async fn run(mut self, mut inbox: mpsc::Receiver<ActorMessage>) {
        loop {
            tokio::select! {
                msg = inbox.recv() => {
                    match msg {
                        None => break,
                        Some(msg) => self.handle_message(msg),
                    }
                }
                Some(res) = self.session_tasks.join_next(), if !self.session_tasks.is_empty() => {
                    match res {
                        Ok((endpoint_id, result)) => {
                            info!(remote = %endpoint_id.fmt_short(), "session closed: {result:?}");
                            self.sessions.remove(&endpoint_id);
                        }
                        Err(e) => {
                            error!("session task panicked: {e}");
                        }
                    }
                }
                _ = self.shutdown_token.cancelled() => {
                    info!("live actor shutting down");
                    break;
                }
            }
        }
        
        // Cleanup
        self.session_tasks.abort_all();
    }

    fn handle_message(&mut self, msg: ActorMessage) {
        match msg {
            ActorMessage::HandleSession(session) => self.handle_incoming_session(session),
            ActorMessage::PublishBroadcast(name, producer) => {
                self.handle_publish_broadcast(name, producer)
            }
            ActorMessage::RemoveBroadcast(name) => {
                self.handle_remove_broadcast(name)
            }
        }
    }

    fn handle_incoming_session(&mut self, session: LiveSession) {
        info!(remote = %session.remote.fmt_short(), "handling new session");
        
        let LiveSession {
            remote,
            moq_session,
            publish,
            subscribe: _,
            ..
        } = session;
        
        // Publish all existing broadcasts to this peer
        for (name, producer) in self.broadcasts.iter() {
            publish.publish_broadcast(name.clone(), producer.consume());
        }
        
        // Store session state
        self.sessions.insert(remote, SessionState { publish });
        
        // Spawn task to monitor session
        let shutdown = self.shutdown_token.child_token();
        self.session_tasks.spawn(async move {
            let res = tokio::select! {
                _ = shutdown.cancelled() => {
                    moq_session.close(moq_lite::Error::Cancel);
                    Ok(())
                }
                result = moq_session.closed() => result,
            };
            (remote, res)
        });
    }

    fn handle_publish_broadcast(&mut self, name: BroadcastName, producer: BroadcastProducer) {
        info!("publishing broadcast: {name}");
        
        // Publish to all connected sessions
        for session in self.sessions.values() {
            session.publish.publish_broadcast(name.clone(), producer.consume());
        }
        
        // Store for future sessions
        self.broadcasts.insert(name, producer);
    }

    fn handle_remove_broadcast(&mut self, name: BroadcastName) {
        info!("removing broadcast: {name}");
        self.broadcasts.remove(&name);
    }
}
