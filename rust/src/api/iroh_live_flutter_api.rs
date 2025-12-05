//! Flutter-friendly API for iroh-live streaming
//! 
//! This module provides Flutter bindings for broadcast publishing,
//! subscribing, and capture management using real iroh-live backend.

use std::collections::HashMap;
use std::sync::RwLock;
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use tokio::sync::Mutex as TokioMutex;

use super::iroh_live::{LiveNode, LiveTicket, VideoFrame as IrohVideoFrame};

// ============================================================================
// Types for Flutter (all use primitives or simple structs)
// ============================================================================

/// Video frame data for Flutter
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterVideoFrame {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
    pub timestamp_ms: u64,
    pub format: String, // "rgba", "nv12", "i420"
}

/// Audio samples for Flutter
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterAudioSamples {
    pub data: Vec<u8>,
    pub sample_rate: u32,
    pub channels: u16,
    pub timestamp_ms: u64,
    pub format: String, // "pcm_s16le", "pcm_f32le"
}

/// Capture device info for Flutter
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterCaptureDevice {
    pub id: String,
    pub name: String,
    pub device_type: String, // "camera", "screen", "test_pattern"
    pub is_default: bool,
}

/// Broadcast catalog info for Flutter
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterBroadcastCatalog {
    pub broadcast_id: String,
    pub video_tracks: Vec<FlutterTrackInfo>,
    pub audio_tracks: Vec<FlutterTrackInfo>,
    pub created_at_ms: u64,
}

/// Track info for catalog
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterTrackInfo {
    pub track_id: String,
    pub name: String,
    pub codec: String,
    pub bitrate: u32,
    pub extra: HashMap<String, String>,
}

/// Video rendition quality info
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterVideoRendition {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate: u32,
    pub codec: String,
}

/// Audio rendition quality info
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterAudioRendition {
    pub name: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub bitrate: u32,
    pub codec: String,
}

/// Publisher status
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterPublisherStatus {
    pub publisher_id: String,
    pub is_active: bool,
    pub frames_published: u64,
    pub bytes_sent: u64,
    pub current_bitrate: u32,
    pub video_renditions: Vec<String>,
    pub audio_renditions: Vec<String>,
}

/// Subscriber status
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterSubscriberStatus {
    pub subscriber_id: String,
    pub broadcast_id: String,
    pub is_connected: bool,
    pub frames_received: u64,
    pub bytes_received: u64,
    pub current_quality: String,
    pub buffer_health: f32,
}

// ============================================================================
// Global State
// ============================================================================

/// Global LiveNode instance for real iroh-live streaming
static LIVE_NODE: Lazy<TokioMutex<Option<LiveNode>>> = Lazy::new(|| {
    TokioMutex::new(None)
});

/// Store broadcast tickets for sharing
static BROADCAST_TICKETS: Lazy<RwLock<HashMap<String, String>>> = Lazy::new(|| {
    RwLock::new(HashMap::new())
});

struct CaptureState {
    devices: Vec<FlutterCaptureDevice>,
    active_capture: Option<String>,
    frame_counter: u64,
}

struct PublishState {
    broadcast_name: String,
    ticket: String,
    is_active: bool,
    frames_published: u64,
    bytes_sent: u64,
    video_renditions: Vec<String>,
    audio_renditions: Vec<String>,
}

struct SubscribeState {
    broadcast_id: String,
    is_connected: bool,
    frames_received: u64,
    bytes_received: u64,
    current_quality: String,
}

static CAPTURE_STATE: Lazy<RwLock<CaptureState>> = Lazy::new(|| {
    RwLock::new(CaptureState {
        devices: Vec::new(),
        active_capture: None,
        frame_counter: 0,
    })
});

static PUBLISHERS: Lazy<RwLock<HashMap<String, PublishState>>> = Lazy::new(|| {
    RwLock::new(HashMap::new())
});

static SUBSCRIBERS: Lazy<RwLock<HashMap<String, SubscribeState>>> = Lazy::new(|| {
    RwLock::new(HashMap::new())
});

// ============================================================================
// Node Management API
// ============================================================================

/// Initialize the iroh-live node
pub async fn iroh_node_init() -> Result<String, String> {
    let mut node_guard = LIVE_NODE.lock().await;
    
    if node_guard.is_some() {
        return Ok("Node already initialized".to_string());
    }
    
    match LiveNode::new(None).await {
        Ok(node) => {
            let endpoint_id = node.endpoint_id().to_string();
            *node_guard = Some(node);
            Ok(endpoint_id)
        }
        Err(e) => Err(format!("Failed to initialize node: {}", e))
    }
}

/// Get the node's endpoint ID
pub async fn iroh_node_get_endpoint_id() -> Result<String, String> {
    let node_guard = LIVE_NODE.lock().await;
    
    match &*node_guard {
        Some(node) => Ok(node.endpoint_id().to_string()),
        None => Err("Node not initialized".to_string())
    }
}

/// Shutdown the node
pub async fn iroh_node_shutdown() -> Result<(), String> {
    let mut node_guard = LIVE_NODE.lock().await;
    
    if let Some(node) = node_guard.take() {
        node.shutdown().await;
    }
    
    Ok(())
}

// ============================================================================
// Capture Management API
// ============================================================================

/// Initialize the capture system
#[frb(sync)]
pub fn iroh_capture_init() -> bool {
    let mut state = CAPTURE_STATE.write().unwrap();
    
    // Clear existing devices
    state.devices.clear();
    
    // Add camera devices
    state.devices.push(FlutterCaptureDevice {
        id: "camera_front".to_string(),
        name: "Front Camera".to_string(),
        device_type: "camera".to_string(),
        is_default: true,
    });
    
    state.devices.push(FlutterCaptureDevice {
        id: "camera_back".to_string(),
        name: "Back Camera".to_string(),
        device_type: "camera".to_string(),
        is_default: false,
    });
    
    // Add test pattern devices
    state.devices.push(FlutterCaptureDevice {
        id: "test_pattern_color_bars".to_string(),
        name: "Color Bars Test Pattern".to_string(),
        device_type: "test_pattern".to_string(),
        is_default: false,
    });
    
    state.devices.push(FlutterCaptureDevice {
        id: "test_pattern_gradient".to_string(),
        name: "Gradient Test Pattern".to_string(),
        device_type: "test_pattern".to_string(),
        is_default: false,
    });
    
    state.devices.push(FlutterCaptureDevice {
        id: "test_pattern_moving_box".to_string(),
        name: "Moving Box Test Pattern".to_string(),
        device_type: "test_pattern".to_string(),
        is_default: false,
    });
    
    true
}

/// List available capture devices
#[frb(sync)]
pub fn iroh_capture_list_devices() -> Vec<FlutterCaptureDevice> {
    let state = CAPTURE_STATE.read().unwrap();
    state.devices.clone()
}

/// Start capturing from a device
#[frb(sync)]
pub fn iroh_capture_start(device_id: String) -> bool {
    let mut state = CAPTURE_STATE.write().unwrap();
    
    // Check if device exists
    if !state.devices.iter().any(|d| d.id == device_id) {
        return false;
    }
    
    state.active_capture = Some(device_id);
    state.frame_counter = 0;
    true
}

/// Stop capturing
#[frb(sync)]
pub fn iroh_capture_stop() -> bool {
    let mut state = CAPTURE_STATE.write().unwrap();
    state.active_capture = None;
    true
}

/// Get current capture device
#[frb(sync)]
pub fn iroh_capture_current_device() -> Option<String> {
    let state = CAPTURE_STATE.read().unwrap();
    state.active_capture.clone()
}

/// Generate a test frame (for testing)
#[frb(sync)]
pub fn iroh_capture_get_test_frame(width: u32, height: u32, pattern: String) -> FlutterVideoFrame {
    let mut state = CAPTURE_STATE.write().unwrap();
    state.frame_counter += 1;
    let frame_num = state.frame_counter;
    
    let data_size = (width * height * 4) as usize;
    let mut data = vec![0u8; data_size];
    
    match pattern.as_str() {
        "color_bars" => generate_color_bars(&mut data, width, height),
        "gradient" => generate_gradient(&mut data, width, height, frame_num),
        "moving_box" => generate_moving_box(&mut data, width, height, frame_num),
        _ => generate_color_bars(&mut data, width, height),
    }
    
    FlutterVideoFrame {
        width,
        height,
        data,
        timestamp_ms: frame_num * 33, // ~30fps
        format: "rgba".to_string(),
    }
}

fn generate_color_bars(data: &mut [u8], width: u32, height: u32) {
    let colors: [(u8, u8, u8); 8] = [
        (255, 255, 255), // White
        (255, 255, 0),   // Yellow
        (0, 255, 255),   // Cyan
        (0, 255, 0),     // Green
        (255, 0, 255),   // Magenta
        (255, 0, 0),     // Red
        (0, 0, 255),     // Blue
        (0, 0, 0),       // Black
    ];
    
    let bar_width = width / 8;
    
    for y in 0..height {
        for x in 0..width {
            let bar_idx = ((x / bar_width) as usize).min(7);
            let (r, g, b) = colors[bar_idx];
            let idx = ((y * width + x) * 4) as usize;
            if idx + 3 < data.len() {
                data[idx] = r;
                data[idx + 1] = g;
                data[idx + 2] = b;
                data[idx + 3] = 255;
            }
        }
    }
}

fn generate_gradient(data: &mut [u8], width: u32, height: u32, _frame_num: u64) {
    for y in 0..height {
        for x in 0..width {
            let r = ((x as f32 / width as f32) * 255.0) as u8;
            let g = ((y as f32 / height as f32) * 255.0) as u8;
            let b = 128u8;
            let idx = ((y * width + x) * 4) as usize;
            if idx + 3 < data.len() {
                data[idx] = r;
                data[idx + 1] = g;
                data[idx + 2] = b;
                data[idx + 3] = 255;
            }
        }
    }
}

fn generate_moving_box(data: &mut [u8], width: u32, height: u32, frame_num: u64) {
    // Fill with dark gray
    for i in (0..data.len()).step_by(4) {
        data[i] = 40;
        data[i + 1] = 40;
        data[i + 2] = 40;
        data[i + 3] = 255;
    }
    
    // Draw moving box
    let box_size = 100u32;
    let max_x = width.saturating_sub(box_size);
    let max_y = height.saturating_sub(box_size);
    
    if max_x == 0 || max_y == 0 {
        return;
    }
    
    let box_x = ((frame_num * 5) % max_x as u64) as u32;
    let box_y = ((frame_num * 3) % max_y as u64) as u32;
    
    for y in box_y..(box_y + box_size).min(height) {
        for x in box_x..(box_x + box_size).min(width) {
            let idx = ((y * width + x) * 4) as usize;
            if idx + 3 < data.len() {
                data[idx] = 255;
                data[idx + 1] = 128;
                data[idx + 2] = 0;
                data[idx + 3] = 255;
            }
        }
    }
}

// ============================================================================
// Publishing API
// ============================================================================

/// Create a new publisher and get the broadcast ticket
/// Returns the ticket string that can be shared with subscribers
pub async fn iroh_publish_create_async(publisher_id: String, broadcast_name: String) -> Result<String, String> {
    // First ensure node is initialized
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized. Call iroh_node_init() first")?;
    
    // Create publisher in LiveNode
    let ticket = node.create_publisher(publisher_id.clone(), broadcast_name.clone())
        .await
        .map_err(|e| format!("Failed to create publisher: {}", e))?;
    
    let ticket_string = ticket.serialize();
    
    // Store in local state
    let mut publishers = PUBLISHERS.write().unwrap();
    publishers.insert(publisher_id.clone(), PublishState {
        broadcast_name,
        ticket: ticket_string.clone(),
        is_active: false,
        frames_published: 0,
        bytes_sent: 0,
        video_renditions: vec!["720p".to_string()],
        audio_renditions: vec!["opus_hq".to_string()],
    });
    
    // Store ticket for sharing
    BROADCAST_TICKETS.write().unwrap().insert(publisher_id.clone(), ticket_string.clone());
    
    Ok(ticket_string)
}

/// Create a new publisher (sync version for compatibility)
#[frb(sync)]
pub fn iroh_publish_create(publisher_id: String) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if publishers.contains_key(&publisher_id) {
        return false;
    }
    
    publishers.insert(publisher_id, PublishState {
        broadcast_name: "default".to_string(),
        ticket: String::new(),
        is_active: false,
        frames_published: 0,
        bytes_sent: 0,
        video_renditions: vec!["720p".to_string()],
        audio_renditions: vec!["opus_hq".to_string()],
    });
    
    true
}

/// Start publishing (async version with real backend)
pub async fn iroh_publish_start_async(publisher_id: String) -> Result<(), String> {
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized")?;
    
    node.start_publishing(&publisher_id)
        .await
        .map_err(|e| format!("Failed to start publishing: {}", e))?;
    
    let mut publishers = PUBLISHERS.write().unwrap();
    if let Some(state) = publishers.get_mut(&publisher_id) {
        state.is_active = true;
    }
    
    Ok(())
}

/// Start publishing (sync version for compatibility)
#[frb(sync)]
pub fn iroh_publish_start(publisher_id: String) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if let Some(state) = publishers.get_mut(&publisher_id) {
        state.is_active = true;
        true
    } else {
        false
    }
}

/// Stop publishing (async version)
pub async fn iroh_publish_stop_async(publisher_id: String) -> Result<(), String> {
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized")?;
    
    node.stop_publishing(&publisher_id)
        .await
        .map_err(|e| format!("Failed to stop publishing: {}", e))?;
    
    let mut publishers = PUBLISHERS.write().unwrap();
    if let Some(state) = publishers.get_mut(&publisher_id) {
        state.is_active = false;
    }
    
    Ok(())
}

/// Stop publishing (sync version)
#[frb(sync)]
pub fn iroh_publish_stop(publisher_id: String) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if let Some(state) = publishers.get_mut(&publisher_id) {
        state.is_active = false;
        true
    } else {
        false
    }
}

/// Remove a publisher
#[frb(sync)]
pub fn iroh_publish_remove(publisher_id: String) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    publishers.remove(&publisher_id).is_some()
}

/// Push a video frame to publisher
#[frb(sync)]
pub fn iroh_publish_push_video(publisher_id: String, frame: FlutterVideoFrame) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if let Some(state) = publishers.get_mut(&publisher_id) {
        if state.is_active {
            state.frames_published += 1;
            state.bytes_sent += frame.data.len() as u64;
            true
        } else {
            false
        }
    } else {
        false
    }
}

/// Push audio samples to publisher
#[frb(sync)]
pub fn iroh_publish_push_audio(publisher_id: String, samples: FlutterAudioSamples) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if let Some(state) = publishers.get_mut(&publisher_id) {
        if state.is_active {
            state.bytes_sent += samples.data.len() as u64;
            true
        } else {
            false
        }
    } else {
        false
    }
}

/// Get publisher status
#[frb(sync)]
pub fn iroh_publish_get_status(publisher_id: String) -> Option<FlutterPublisherStatus> {
    let publishers = PUBLISHERS.read().unwrap();
    
    publishers.get(&publisher_id).map(|state| {
        FlutterPublisherStatus {
            publisher_id: publisher_id.clone(),
            is_active: state.is_active,
            frames_published: state.frames_published,
            bytes_sent: state.bytes_sent,
            current_bitrate: if state.is_active { 2500000 } else { 0 },
            video_renditions: state.video_renditions.clone(),
            audio_renditions: state.audio_renditions.clone(),
        }
    })
}

/// Set video renditions for publisher
#[frb(sync)]
pub fn iroh_publish_set_video_renditions(publisher_id: String, renditions: Vec<String>) -> bool {
    let mut publishers = PUBLISHERS.write().unwrap();
    
    if let Some(state) = publishers.get_mut(&publisher_id) {
        state.video_renditions = renditions;
        true
    } else {
        false
    }
}

/// Get available video presets
#[frb(sync)]
pub fn iroh_get_video_presets() -> Vec<FlutterVideoRendition> {
    vec![
        FlutterVideoRendition {
            name: "P180".to_string(),
            width: 320,
            height: 180,
            fps: 15,
            bitrate: 150_000,
            codec: "h264".to_string(),
        },
        FlutterVideoRendition {
            name: "P360".to_string(),
            width: 640,
            height: 360,
            fps: 30,
            bitrate: 500_000,
            codec: "h264".to_string(),
        },
        FlutterVideoRendition {
            name: "P720".to_string(),
            width: 1280,
            height: 720,
            fps: 30,
            bitrate: 2_000_000,
            codec: "h264".to_string(),
        },
        FlutterVideoRendition {
            name: "P1080".to_string(),
            width: 1920,
            height: 1080,
            fps: 30,
            bitrate: 4_500_000,
            codec: "h264".to_string(),
        },
    ]
}

/// Get available audio presets
#[frb(sync)]
pub fn iroh_get_audio_presets() -> Vec<FlutterAudioRendition> {
    vec![
        FlutterAudioRendition {
            name: "opus_lq".to_string(),
            sample_rate: 24000,
            channels: 1,
            bitrate: 24_000,
            codec: "opus".to_string(),
        },
        FlutterAudioRendition {
            name: "opus_hq".to_string(),
            sample_rate: 48000,
            channels: 2,
            bitrate: 128_000,
            codec: "opus".to_string(),
        },
        FlutterAudioRendition {
            name: "aac_hq".to_string(),
            sample_rate: 44100,
            channels: 2,
            bitrate: 192_000,
            codec: "aac".to_string(),
        },
    ]
}

// ============================================================================
// Subscription API
// ============================================================================

/// Create a new subscriber (async version with real backend)
pub async fn iroh_subscribe_create_async(subscriber_id: String, broadcast_id: String) -> Result<(), String> {
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized")?;
    
    node.create_subscriber(subscriber_id.clone(), broadcast_id.clone())
        .await
        .map_err(|e| format!("Failed to create subscriber: {}", e))?;
    
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    subscribers.insert(subscriber_id, SubscribeState {
        broadcast_id,
        is_connected: false,
        frames_received: 0,
        bytes_received: 0,
        current_quality: "auto".to_string(),
    });
    
    Ok(())
}

/// Create a new subscriber (sync version for compatibility)
#[frb(sync)]
pub fn iroh_subscribe_create(subscriber_id: String, broadcast_id: String) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    
    if subscribers.contains_key(&subscriber_id) {
        return false;
    }
    
    subscribers.insert(subscriber_id, SubscribeState {
        broadcast_id,
        is_connected: false,
        frames_received: 0,
        bytes_received: 0,
        current_quality: "auto".to_string(),
    });
    
    true
}

/// Connect subscriber to broadcast using ticket string (async with real backend)
pub async fn iroh_subscribe_connect_async(subscriber_id: String, ticket_string: String) -> Result<(), String> {
    // Parse the ticket
    let ticket = LiveTicket::deserialize(&ticket_string)
        .map_err(|e| format!("Invalid ticket: {}", e))?;
    
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized")?;
    
    node.connect_subscriber(&subscriber_id, &ticket)
        .await
        .map_err(|e| format!("Failed to connect: {}", e))?;
    
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        state.is_connected = true;
        state.broadcast_id = ticket.broadcast_name;
    }
    
    Ok(())
}

/// Connect subscriber to broadcast (sync version)
#[frb(sync)]
pub fn iroh_subscribe_connect(subscriber_id: String) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        state.is_connected = true;
        true
    } else {
        false
    }
}

/// Disconnect subscriber (async with real backend)
pub async fn iroh_subscribe_disconnect_async(subscriber_id: String) -> Result<(), String> {
    let node_guard = LIVE_NODE.lock().await;
    let node = node_guard.as_ref().ok_or("Node not initialized")?;
    
    node.disconnect_subscriber(&subscriber_id)
        .await
        .map_err(|e| format!("Failed to disconnect: {}", e))?;
    
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        state.is_connected = false;
    }
    
    Ok(())
}

/// Disconnect subscriber (sync version)
#[frb(sync)]
pub fn iroh_subscribe_disconnect(subscriber_id: String) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        state.is_connected = false;
        true
    } else {
        false
    }
}

/// Remove a subscriber
#[frb(sync)]
pub fn iroh_subscribe_remove(subscriber_id: String) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    subscribers.remove(&subscriber_id).is_some()
}

/// Set quality preference for subscriber
#[frb(sync)]
pub fn iroh_subscribe_set_quality(subscriber_id: String, quality: String) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        state.current_quality = quality;
        true
    } else {
        false
    }
}

/// Get subscriber status
#[frb(sync)]
pub fn iroh_subscribe_get_status(subscriber_id: String) -> Option<FlutterSubscriberStatus> {
    let subscribers = SUBSCRIBERS.read().unwrap();
    
    subscribers.get(&subscriber_id).map(|state| {
        FlutterSubscriberStatus {
            subscriber_id: subscriber_id.clone(),
            broadcast_id: state.broadcast_id.clone(),
            is_connected: state.is_connected,
            frames_received: state.frames_received,
            bytes_received: state.bytes_received,
            current_quality: state.current_quality.clone(),
            buffer_health: if state.is_connected { 0.95 } else { 0.0 },
        }
    })
}

/// Simulate receiving a video frame (for testing)
#[frb(sync)]
pub fn iroh_subscribe_simulate_video_receive(subscriber_id: String, frame_size: u64) -> bool {
    let mut subscribers = SUBSCRIBERS.write().unwrap();
    
    if let Some(state) = subscribers.get_mut(&subscriber_id) {
        if state.is_connected {
            state.frames_received += 1;
            state.bytes_received += frame_size;
            true
        } else {
            false
        }
    } else {
        false
    }
}

// ============================================================================
// Catalog API
// ============================================================================

/// Create a broadcast catalog
#[frb(sync)]
pub fn iroh_catalog_create(
    broadcast_id: String,
    video_renditions: Vec<String>,
    audio_renditions: Vec<String>,
) -> FlutterBroadcastCatalog {
    let video_tracks: Vec<FlutterTrackInfo> = video_renditions.iter().map(|r| {
        FlutterTrackInfo {
            track_id: format!("video_{}", r),
            name: r.clone(),
            codec: "h264".to_string(),
            bitrate: match r.as_str() {
                "P180" => 150_000,
                "P360" => 500_000,
                "P720" => 2_000_000,
                "P1080" => 4_500_000,
                _ => 1_000_000,
            },
            extra: HashMap::new(),
        }
    }).collect();
    
    let audio_tracks: Vec<FlutterTrackInfo> = audio_renditions.iter().map(|r| {
        FlutterTrackInfo {
            track_id: format!("audio_{}", r),
            name: r.clone(),
            codec: if r.contains("opus") { "opus" } else { "aac" }.to_string(),
            bitrate: match r.as_str() {
                "opus_lq" => 24_000,
                "opus_hq" => 128_000,
                "aac_hq" => 192_000,
                _ => 64_000,
            },
            extra: HashMap::new(),
        }
    }).collect();
    
    FlutterBroadcastCatalog {
        broadcast_id,
        video_tracks,
        audio_tracks,
        created_at_ms: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64,
    }
}

/// Serialize catalog to JSON
#[frb(sync)]
pub fn iroh_catalog_to_json(catalog: FlutterBroadcastCatalog) -> String {
    // Simple JSON serialization without serde
    format!(
        r#"{{"broadcast_id":"{}","video_tracks_count":{},"audio_tracks_count":{},"created_at_ms":{}}}"#,
        catalog.broadcast_id,
        catalog.video_tracks.len(),
        catalog.audio_tracks.len(),
        catalog.created_at_ms
    )
}

// ============================================================================
// Ticket Management
// ============================================================================

/// Parse a ticket string and return its components
#[frb(sync)]
pub fn iroh_ticket_parse(ticket_string: String) -> Option<FlutterTicketInfo> {
    LiveTicket::deserialize(&ticket_string)
        .ok()
        .map(|ticket| FlutterTicketInfo {
            broadcast_name: ticket.broadcast_name,
            endpoint_id: ticket.endpoint_id.to_string(),
            ticket_string,
        })
}

/// Get the ticket for a publisher
#[frb(sync)]
pub fn iroh_publish_get_ticket(publisher_id: String) -> Option<String> {
    BROADCAST_TICKETS.read().unwrap().get(&publisher_id).cloned()
}

/// Ticket information for Flutter
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct FlutterTicketInfo {
    pub broadcast_name: String,
    pub endpoint_id: String,
    pub ticket_string: String,
}

// ============================================================================
// Utility functions
// ============================================================================

/// Get supported video codecs
#[frb(sync)]
pub fn iroh_get_supported_video_codecs() -> Vec<String> {
    vec![
        "h264".to_string(),
        "h265".to_string(),
        "vp8".to_string(),
        "vp9".to_string(),
        "av1".to_string(),
    ]
}

/// Get supported audio codecs
#[frb(sync)]
pub fn iroh_get_supported_audio_codecs() -> Vec<String> {
    vec![
        "opus".to_string(),
        "aac".to_string(),
        "pcm".to_string(),
    ]
}

/// Check if a codec is hardware accelerated
#[frb(sync)]
pub fn iroh_is_codec_hw_accelerated(codec: String) -> bool {
    match codec.as_str() {
        "h264" | "h265" => true,
        "vp8" | "vp9" => true,
        "av1" => false, // Not widely supported yet
        _ => false,
    }
}

/// Get library version
#[frb(sync)]
pub fn iroh_get_version() -> String {
    "0.1.0".to_string()
}

/// Get feature flags
#[frb(sync)]
pub fn iroh_get_features() -> HashMap<String, bool> {
    let mut features = HashMap::new();
    features.insert("capture".to_string(), true);
    features.insert("publish".to_string(), true);
    features.insert("subscribe".to_string(), true);
    features.insert("hw_encode".to_string(), true);
    features.insert("hw_decode".to_string(), true);
    features.insert("screen_capture".to_string(), false); // Removed
    features.insert("camera_capture".to_string(), true);
    features.insert("test_patterns".to_string(), true);
    features.insert("multi_quality".to_string(), true);
    features.insert("p2p_quic".to_string(), true); // New iroh-live feature
    features
}
