//! Flutter-Rust bridge API for direct streaming functionality

use std::sync::Arc;
use tokio::sync::Mutex;
use flutter_rust_bridge::frb;

use super::direct_streaming::{
    DirectStreamingEndpoint, DirectStreamEvent, DirectMessage, DirectStreamTicket,
};

/// Global direct streaming endpoint instance
static DIRECT_ENDPOINT: once_cell::sync::OnceCell<Arc<Mutex<Option<DirectStreamingEndpoint>>>> = 
    once_cell::sync::OnceCell::new();

/// Global event queue for direct streaming
static DIRECT_EVENT_QUEUE: once_cell::sync::OnceCell<Arc<Mutex<Vec<FlutterDirectEvent>>>> = 
    once_cell::sync::OnceCell::new();

fn get_direct_endpoint_holder() -> &'static Arc<Mutex<Option<DirectStreamingEndpoint>>> {
    DIRECT_ENDPOINT.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_direct_event_queue() -> &'static Arc<Mutex<Vec<FlutterDirectEvent>>> {
    DIRECT_EVENT_QUEUE.get_or_init(|| Arc::new(Mutex::new(Vec::new())))
}

/// Event types for Flutter
#[derive(Debug, Clone)]
pub enum FlutterDirectEvent {
    PeerConnected { endpoint_id: String },
    PeerDisconnected { endpoint_id: String },
    RequestMetadata { from: String, timestamp: u64 },
    Metadata { 
        from: String, 
        file_name: String, 
        file_size: u64, 
        mime_type: String, 
        total_chunks: u32,
        duration: Option<f64>,
        timestamp: u64,
    },
    RequestChunk { from: String, index: u32, timestamp: u64 },
    Chunk { from: String, index: u32, data: Vec<u8>, timestamp: u64 },
    Presence { from: String, name: String, timestamp: u64 },
    Signal { from: String, data: Vec<u8>, timestamp: u64 },
    Error { message: String },
}

impl From<DirectStreamEvent> for FlutterDirectEvent {
    fn from(event: DirectStreamEvent) -> Self {
        match event {
            DirectStreamEvent::PeerConnected { endpoint_id } => {
                FlutterDirectEvent::PeerConnected { endpoint_id }
            }
            DirectStreamEvent::PeerDisconnected { endpoint_id } => {
                FlutterDirectEvent::PeerDisconnected { endpoint_id }
            }
            DirectStreamEvent::Message { from, message, timestamp } => {
                match message {
                    DirectMessage::RequestMetadata => {
                        FlutterDirectEvent::RequestMetadata { from, timestamp }
                    }
                    DirectMessage::Metadata { file_name, file_size, mime_type, total_chunks, duration } => {
                        FlutterDirectEvent::Metadata { 
                            from, file_name, file_size, mime_type, total_chunks, duration, timestamp 
                        }
                    }
                    DirectMessage::RequestChunk { index } => {
                        FlutterDirectEvent::RequestChunk { from, index, timestamp }
                    }
                    DirectMessage::Chunk { index, data } => {
                        FlutterDirectEvent::Chunk { from, index, data, timestamp }
                    }
                    DirectMessage::Presence { name } => {
                        FlutterDirectEvent::Presence { from, name, timestamp }
                    }
                    DirectMessage::Signal { data } => {
                        FlutterDirectEvent::Signal { from, data, timestamp }
                    }
                }
            }
            DirectStreamEvent::Error { message } => {
                FlutterDirectEvent::Error { message }
            }
        }
    }
}

/// Initialize the direct streaming endpoint
#[frb]
pub async fn init_direct_streaming() -> Result<String, String> {
    let holder = get_direct_endpoint_holder();
    let mut guard = holder.lock().await;
    
    if guard.is_some() {
        if let Some(ep) = guard.as_ref() {
            return Ok(ep.endpoint_id().to_string());
        }
    }
    
    let endpoint = DirectStreamingEndpoint::new(None)
        .await
        .map_err(|e| e.to_string())?;
    
    let endpoint_id = endpoint.endpoint_id().to_string();
    *guard = Some(endpoint);
    
    tracing::info!("[Direct] Initialized with endpoint: {}", endpoint_id);
    Ok(endpoint_id)
}

/// Get our endpoint ID for direct streaming
#[frb]
pub async fn get_direct_endpoint_id() -> Result<String, String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(ep) => Ok(ep.endpoint_id().to_string()),
        None => Err("Direct streaming not initialized".to_string()),
    }
}

/// Create a direct stream as broadcaster and return the ticket
#[frb]
pub async fn create_direct_stream(name: String) -> Result<String, String> {
    let holder = get_direct_endpoint_holder();
    let mut guard = holder.lock().await;
    
    let endpoint = guard.as_mut()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    // Start accepting connections
    endpoint.start_accepting()
        .await
        .map_err(|e| e.to_string())?;
    
    // Create ticket from our address
    let addr = endpoint.endpoint_addr();
    let ticket = DirectStreamTicket::new(addr);
    
    // Start event polling task
    let event_queue = get_direct_event_queue().clone();
    let endpoint_holder = get_direct_endpoint_holder().clone();
    
    tokio::spawn(async move {
        tracing::info!("[Direct Broadcaster] Event polling started");
        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            
            let guard = endpoint_holder.lock().await;
            if let Some(ep) = guard.as_ref() {
                let events = ep.poll_events().await;
                if !events.is_empty() {
                    let mut queue = event_queue.lock().await;
                    for event in events {
                        tracing::info!("[Direct Broadcaster] Event: {:?}", std::mem::discriminant(&event));
                        queue.push(event.into());
                    }
                }
            } else {
                break;
            }
        }
        tracing::info!("[Direct Broadcaster] Event polling ended");
    });
    
    tracing::info!("[Direct] Created stream, ticket ready");
    Ok(ticket.serialize())
}

/// Join a direct stream as viewer
#[frb]
pub async fn join_direct_stream(ticket_str: String, _name: String) -> Result<String, String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    // Parse ticket
    let ticket = DirectStreamTicket::deserialize(&ticket_str)
        .map_err(|e| format!("Invalid ticket: {}", e))?;
    
    tracing::info!("[Direct Viewer] Connecting to broadcaster: {}", ticket.endpoint_id);
    
    // Connect to broadcaster
    let peer_addr = ticket.to_endpoint_addr();
    endpoint.connect_to_peer(peer_addr)
        .await
        .map_err(|e| format!("Failed to connect: {}", e))?;
    
    // Start event polling task
    let event_queue = get_direct_event_queue().clone();
    let endpoint_holder = get_direct_endpoint_holder().clone();
    
    tokio::spawn(async move {
        tracing::info!("[Direct Viewer] Event polling started");
        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            
            let guard = endpoint_holder.lock().await;
            if let Some(ep) = guard.as_ref() {
                let events = ep.poll_events().await;
                if !events.is_empty() {
                    let mut queue = event_queue.lock().await;
                    for event in events {
                        tracing::info!("[Direct Viewer] Event: {:?}", std::mem::discriminant(&event));
                        queue.push(event.into());
                    }
                }
            } else {
                break;
            }
        }
        tracing::info!("[Direct Viewer] Event polling ended");
    });
    
    tracing::info!("[Direct] Joined stream");
    Ok(ticket_str)
}

/// Send metadata (for broadcaster)
#[frb]
pub async fn direct_send_metadata(
    file_name: String,
    file_size: u64,
    mime_type: String,
    total_chunks: u32,
    duration: Option<f64>,
) -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::Metadata {
        file_name,
        file_size,
        mime_type,
        total_chunks,
        duration,
    };
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    tracing::info!("[Direct] Broadcasted metadata");
    Ok(())
}

/// Send a chunk (for broadcaster)
#[frb]
pub async fn direct_send_chunk(index: u32, data: Vec<u8>) -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::Chunk { index, data };
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    Ok(())
}

/// Request metadata (for viewer)
#[frb]
pub async fn direct_request_metadata() -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::RequestMetadata;
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    tracing::info!("[Direct] Requested metadata");
    Ok(())
}

/// Request a specific chunk (for viewer)
#[frb]
pub async fn direct_request_chunk(index: u32) -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::RequestChunk { index };
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    Ok(())
}

/// Send presence (for keepalive)
#[frb]
pub async fn direct_send_presence(name: String) -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::Presence { name };
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    Ok(())
}

/// Send arbitrary signal data
#[frb]
pub async fn direct_send_signal(data: Vec<u8>) -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    let endpoint = guard.as_ref()
        .ok_or_else(|| "Direct streaming not initialized".to_string())?;
    
    let message = DirectMessage::Signal { data };
    
    endpoint.broadcast(&message)
        .await
        .map_err(|e| e.to_string())?;
    
    Ok(())
}

/// Poll for direct stream events
#[frb]
pub async fn poll_direct_events() -> Vec<FlutterDirectEvent> {
    let mut queue = get_direct_event_queue().lock().await;
    std::mem::take(&mut *queue)
}

/// Get number of connected peers
#[frb]
pub async fn get_direct_peer_count() -> u32 {
    let holder = get_direct_endpoint_holder();
    let guard = holder.lock().await;
    
    match guard.as_ref() {
        Some(ep) => ep.peer_count().await as u32,
        None => 0,
    }
}

/// Leave the direct stream
#[frb]
pub async fn leave_direct_stream() -> Result<(), String> {
    let holder = get_direct_endpoint_holder();
    let mut guard = holder.lock().await;
    
    if let Some(ep) = guard.as_ref() {
        ep.shutdown().await;
    }
    *guard = None;
    
    // Clear event queue
    let mut queue = get_direct_event_queue().lock().await;
    queue.clear();
    
    tracing::info!("[Direct] Left stream");
    Ok(())
}

/// Shutdown direct streaming
#[frb]
pub async fn shutdown_direct_streaming() -> Result<(), String> {
    leave_direct_stream().await
}

/// Check if direct streaming is initialized
#[frb(sync)]
pub fn is_direct_streaming_initialized() -> bool {
    if let Some(holder) = DIRECT_ENDPOINT.get() {
        if let Ok(guard) = holder.try_lock() {
            return guard.is_some();
        }
    }
    false
}
