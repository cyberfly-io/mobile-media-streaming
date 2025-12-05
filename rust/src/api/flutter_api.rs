//! Flutter-Rust bridge API for streaming functionality

use std::sync::Arc;
use tokio::sync::Mutex;
use flutter_rust_bridge::frb;
use n0_future::StreamExt;

use super::streaming::{
    StreamingNode, StreamTicket, StreamSender, StreamEvent, StreamQuality,
};

/// Global streaming node instance
static STREAMING_NODE: once_cell::sync::OnceCell<Arc<Mutex<Option<StreamingNode>>>> = 
    once_cell::sync::OnceCell::new();

/// Global stream sender for the current stream
static STREAM_SENDER: once_cell::sync::OnceCell<Arc<Mutex<Option<StreamSender>>>> = 
    once_cell::sync::OnceCell::new();

/// Global event receiver (stored as a queue)
static EVENT_QUEUE: once_cell::sync::OnceCell<Arc<Mutex<Vec<FlutterStreamEvent>>>> = 
    once_cell::sync::OnceCell::new();

fn get_node_holder() -> &'static Arc<Mutex<Option<StreamingNode>>> {
    STREAMING_NODE.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_sender_holder() -> &'static Arc<Mutex<Option<StreamSender>>> {
    STREAM_SENDER.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_event_queue() -> &'static Arc<Mutex<Vec<FlutterStreamEvent>>> {
    EVENT_QUEUE.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

/// Stream event for Flutter
#[derive(Debug, Clone)]
pub enum FlutterStreamEvent {
    NeighborUp { endpoint_id: String },
    NeighborDown { endpoint_id: String },
    Presence { from: String, name: String, timestamp: u64 },
    MediaChunk { from: String, data: Vec<u8>, sequence: u64, timestamp: u64 },
    Signal { from: String, data: Vec<u8>, timestamp: u64 },
    Lagged,
    Error { message: String },
}

impl From<StreamEvent> for FlutterStreamEvent {
    fn from(event: StreamEvent) -> Self {
        match event {
            StreamEvent::NeighborUp { endpoint_id } => FlutterStreamEvent::NeighborUp { 
                endpoint_id: endpoint_id.to_string() 
            },
            StreamEvent::NeighborDown { endpoint_id } => FlutterStreamEvent::NeighborDown { 
                endpoint_id: endpoint_id.to_string() 
            },
            StreamEvent::Presence { from, name, sent_timestamp } => FlutterStreamEvent::Presence { 
                from: from.to_string(), 
                name, 
                timestamp: sent_timestamp 
            },
            StreamEvent::MediaChunk { from, data, sequence, timestamp } => FlutterStreamEvent::MediaChunk { 
                from: from.to_string(), 
                data, 
                sequence, 
                timestamp 
            },
            StreamEvent::Signal { from, data, timestamp } => FlutterStreamEvent::Signal { 
                from: from.to_string(), 
                data, 
                timestamp 
            },
            StreamEvent::Lagged => FlutterStreamEvent::Lagged,
        }
    }
}

/// Quality preset for streaming
#[derive(Debug, Clone, Copy)]
pub enum Quality {
    Low,
    Medium,
    High,
    Ultra,
}

impl From<Quality> for StreamQuality {
    fn from(q: Quality) -> Self {
        match q {
            Quality::Low => StreamQuality::Low,
            Quality::Medium => StreamQuality::Medium,
            Quality::High => StreamQuality::High,
            Quality::Ultra => StreamQuality::Ultra,
        }
    }
}

/// Quality constraints returned to Flutter
#[derive(Debug, Clone)]
pub struct QualityConstraints {
    pub width: u32,
    pub height: u32,
    pub framerate: u32,
    pub audio_bitrate: u32,
}

/// Initialize the streaming node
#[frb]
pub async fn init_streaming_node() -> Result<String, String> {
    let holder = get_node_holder();
    let mut guard = holder.lock().await;
    
    if guard.is_some() {
        if let Some(node) = guard.as_ref() {
            return Ok(node.endpoint_id().to_string());
        }
    }
    
    let node = StreamingNode::spawn(None)
        .await
        .map_err(|e| e.to_string())?;
    
    let endpoint_id = node.endpoint_id().to_string();
    *guard = Some(node);
    
    Ok(endpoint_id)
}

/// Get the endpoint ID
#[frb]
pub async fn get_endpoint_id() -> Result<String, String> {
    let holder = get_node_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(node) => Ok(node.endpoint_id().to_string()),
        None => Err("Streaming node not initialized".to_string()),
    }
}

/// Create a new stream (as broadcaster) and return the ticket
#[frb]
pub async fn create_stream(name: String) -> Result<String, String> {
    let holder = get_node_holder();
    let guard = holder.lock().await;
    
    let node = guard.as_ref()
        .ok_or_else(|| "Streaming node not initialized".to_string())?;
    
    // Create ticket with our endpoint ID as bootstrap (like web dashboard)
    let mut ticket = StreamTicket::new_random();
    ticket.bootstrap.insert(node.endpoint_id());
    let ticket_str = ticket.serialize_ticket();
    
    // Join the stream
    let (sender, mut receiver) = node.join(&ticket, name)
        .await
        .map_err(|e| e.to_string())?;
    
    // Store the sender
    {
        let mut sender_guard = get_sender_holder().lock().await;
        *sender_guard = Some(sender);
    }
    
    // Start a background task to collect events
    let event_queue = get_event_queue().clone();
    tokio::spawn(async move {
        tracing::info!("[Broadcaster] Event collection loop started");
        while let Some(result) = receiver.next().await {
            match result {
                Ok(event) => {
                    // Log event type for debugging
                    match &event {
                        StreamEvent::Signal { from, data, .. } => {
                            tracing::info!("[Broadcaster] RECEIVED SIGNAL from {} size={}", from, data.len());
                            // Try to decode as JSON
                            if let Ok(json_str) = std::str::from_utf8(data) {
                                tracing::info!("[Broadcaster] Signal content: {}", json_str);
                            }
                        }
                        StreamEvent::Presence { from, name, .. } => {
                            tracing::info!("[Broadcaster] RECEIVED PRESENCE from {} name={}", from, name);
                        }
                        StreamEvent::MediaChunk { from, sequence, .. } => {
                            tracing::info!("[Broadcaster] RECEIVED CHUNK from {} seq={}", from, sequence);
                        }
                        StreamEvent::NeighborUp { endpoint_id } => {
                            tracing::info!("[Broadcaster] NEIGHBOR UP: {}", endpoint_id);
                        }
                        StreamEvent::NeighborDown { endpoint_id } => {
                            tracing::info!("[Broadcaster] NEIGHBOR DOWN: {}", endpoint_id);
                        }
                        StreamEvent::Lagged => {
                            tracing::warn!("[Broadcaster] LAGGED");
                        }
                    }
                    let flutter_event: FlutterStreamEvent = event.into();
                    let mut queue = event_queue.lock().await;
                    queue.push(flutter_event);
                    tracing::info!("[Broadcaster] Event pushed to queue, queue size: {}", queue.len());
                }
                Err(e) => {
                    tracing::error!("[Broadcaster] Event error: {}", e);
                    let mut queue = event_queue.lock().await;
                    queue.push(FlutterStreamEvent::Error { message: e.to_string() });
                }
            }
        }
        tracing::info!("[Broadcaster] Event collection loop ended");
    });
    
    Ok(ticket_str)
}

/// Join an existing stream as a viewer
#[frb]
pub async fn join_stream(ticket_str: String, name: String) -> Result<String, String> {
    let holder = get_node_holder();
    let guard = holder.lock().await;
    
    let node = guard.as_ref()
        .ok_or_else(|| "Streaming node not initialized".to_string())?;
    
    let ticket = StreamTicket::deserialize_ticket(&ticket_str)
        .map_err(|e| e.to_string())?;
    
    let (sender, mut receiver) = node.join(&ticket, name)
        .await
        .map_err(|e| e.to_string())?;
    
    // Store the sender
    {
        let mut sender_guard = get_sender_holder().lock().await;
        *sender_guard = Some(sender);
    }
    
    // Start a background task to collect events
    let event_queue = get_event_queue().clone();
    tokio::spawn(async move {
        tracing::info!("[Viewer] Event collection loop started");
        while let Some(result) = receiver.next().await {
            match result {
                Ok(event) => {
                    // Log event type for debugging
                    match &event {
                        StreamEvent::Signal { from, data, .. } => {
                            tracing::info!("[Viewer] RECEIVED SIGNAL from {} size={}", from, data.len());
                            // Try to decode as JSON
                            if let Ok(json_str) = std::str::from_utf8(data) {
                                tracing::info!("[Viewer] Signal content: {}", json_str);
                            }
                        }
                        StreamEvent::Presence { from, name, .. } => {
                            tracing::info!("[Viewer] RECEIVED PRESENCE from {} name={}", from, name);
                        }
                        StreamEvent::MediaChunk { from, sequence, .. } => {
                            tracing::info!("[Viewer] RECEIVED CHUNK from {} seq={}", from, sequence);
                        }
                        StreamEvent::NeighborUp { endpoint_id } => {
                            tracing::info!("[Viewer] NEIGHBOR UP: {}", endpoint_id);
                        }
                        StreamEvent::NeighborDown { endpoint_id } => {
                            tracing::info!("[Viewer] NEIGHBOR DOWN: {}", endpoint_id);
                        }
                        StreamEvent::Lagged => {
                            tracing::warn!("[Viewer] LAGGED");
                        }
                    }
                    let flutter_event: FlutterStreamEvent = event.into();
                    let mut queue = event_queue.lock().await;
                    queue.push(flutter_event);
                    tracing::info!("[Viewer] Event pushed to queue, queue size: {}", queue.len());
                }
                Err(e) => {
                    tracing::error!("[Viewer] Event error: {}", e);
                    let mut queue = event_queue.lock().await;
                    queue.push(FlutterStreamEvent::Error { message: e.to_string() });
                }
            }
        }
        tracing::info!("[Viewer] Event collection loop ended");
    });
    
    Ok(ticket_str)
}

/// Broadcast a media chunk (for broadcaster)
#[frb]
pub async fn broadcast_chunk(data: Vec<u8>, sequence: u64) -> Result<(), String> {
    let sender_guard = get_sender_holder().lock().await;
    
    let sender = sender_guard.as_ref()
        .ok_or_else(|| "Not connected to a stream".to_string())?;
    
    sender.broadcast_chunk(data, sequence)
        .await
        .map_err(|e| e.to_string())
}

/// Send a presence message
#[frb]
pub async fn send_presence() -> Result<(), String> {
    let sender_guard = get_sender_holder().lock().await;
    
    let sender = sender_guard.as_ref()
        .ok_or_else(|| "Not connected to a stream".to_string())?;
    
    sender.send_presence()
        .await
        .map_err(|e| e.to_string())
}

/// Send a signal message (for WebRTC signaling, etc.)
#[frb]
pub async fn send_signal(data: Vec<u8>) -> Result<(), String> {
    tracing::info!("[Flutter] send_signal called, data size: {} bytes", data.len());
    
    let sender_guard = get_sender_holder().lock().await;
    
    let sender = sender_guard.as_ref()
        .ok_or_else(|| {
            tracing::error!("[Flutter] send_signal failed: Not connected to a stream");
            "Not connected to a stream".to_string()
        })?;
    
    tracing::info!("[Flutter] Sending signal via gossip...");
    sender.send_signal(data)
        .await
        .map_err(|e| {
            tracing::error!("[Flutter] send_signal error: {}", e);
            e.to_string()
        })?;
    
    tracing::info!("[Flutter] Signal sent successfully");
    Ok(())
}

/// Poll for received events (returns all queued events)
#[frb]
pub async fn poll_events() -> Vec<FlutterStreamEvent> {
    let mut queue = get_event_queue().lock().await;
    std::mem::take(&mut *queue)
}

/// Get quality constraints for a preset
#[frb(sync)]
pub fn get_quality_constraints(quality: Quality) -> QualityConstraints {
    let q: StreamQuality = quality.into();
    let (width, height, framerate) = q.video_constraints();
    let audio_bitrate = q.audio_bitrate();
    
    QualityConstraints {
        width,
        height,
        framerate,
        audio_bitrate,
    }
}

/// Leave the current stream
#[frb]
pub async fn leave_stream() -> Result<(), String> {
    let mut sender_guard = get_sender_holder().lock().await;
    *sender_guard = None;
    
    // Clear event queue
    let mut queue = get_event_queue().lock().await;
    queue.clear();
    
    Ok(())
}

/// Shutdown the streaming node
#[frb]
pub async fn shutdown_streaming() -> Result<(), String> {
    // Leave current stream first
    leave_stream().await?;
    
    let holder = get_node_holder();
    let mut guard = holder.lock().await;
    
    if let Some(node) = guard.take() {
        node.shutdown().await;
    }
    
    Ok(())
}

/// Check if streaming node is initialized
#[frb(sync)]
pub fn is_streaming_initialized() -> bool {
    if let Some(holder) = STREAMING_NODE.get() {
        if let Ok(guard) = holder.try_lock() {
            return guard.is_some();
        }
    }
    false
}

/// Check if connected to a stream
#[frb(sync)]
pub fn is_connected_to_stream() -> bool {
    if let Some(holder) = STREAM_SENDER.get() {
        if let Ok(guard) = holder.try_lock() {
            return guard.is_some();
        }
    }
    false
}
