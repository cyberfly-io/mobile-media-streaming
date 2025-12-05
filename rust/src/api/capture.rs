//! Capture module inspired by iroh-live/capture.rs
//!
//! This module provides abstractions for:
//! - Screen capture (xcap-style)
//! - Camera capture (nokhwa-style)
//! - Platform-agnostic capture sources

use std::sync::Arc;
use std::time::{Duration, Instant};
use anyhow::{Result, Context};
use tokio::sync::mpsc;
use tracing::{info, debug, warn};

use super::av::{VideoFormat, VideoFrame, PixelFormat, VideoSource};

// ============================================================================
// CAPTURE DEVICE INFO
// ============================================================================

/// Information about an available capture device
#[derive(Debug, Clone)]
pub struct CaptureDeviceInfo {
    pub id: String,
    pub name: String,
    pub device_type: CaptureDeviceType,
    pub native_width: u32,
    pub native_height: u32,
}

/// Type of capture device
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureDeviceType {
    Camera,
    Screen,
    Window,
}

// ============================================================================
// CAPTURE SOURCE TRAIT
// ============================================================================

/// Generic capture source trait
pub trait CaptureSource: VideoSource {
    /// Device information
    fn device_info(&self) -> &CaptureDeviceInfo;
    
    /// Start capturing
    fn start(&mut self) -> Result<()>;
    
    /// Stop capturing
    fn stop(&mut self) -> Result<()>;
    
    /// Check if capturing
    fn is_capturing(&self) -> bool;
}

// ============================================================================
// SIMULATED CAMERA CAPTURER
// ============================================================================

/// Camera capturer (simulated for Flutter - actual capture done on Flutter side)
/// This provides a way to feed camera frames from Flutter into Rust
pub struct CameraCapturer {
    device_info: CaptureDeviceInfo,
    format: VideoFormat,
    frame_rx: mpsc::Receiver<VideoFrame>,
    capturing: bool,
    last_frame: Option<VideoFrame>,
}

impl CameraCapturer {
    /// Create a new camera capturer
    pub fn new(
        device_id: String,
        device_name: String,
        width: u32,
        height: u32,
    ) -> (Self, mpsc::Sender<VideoFrame>) {
        let (tx, rx) = mpsc::channel(4);
        
        let capturer = Self {
            device_info: CaptureDeviceInfo {
                id: device_id,
                name: device_name,
                device_type: CaptureDeviceType::Camera,
                native_width: width,
                native_height: height,
            },
            format: VideoFormat::rgba(width, height),
            frame_rx: rx,
            capturing: false,
            last_frame: None,
        };
        
        (capturer, tx)
    }

    /// Get the frame sender for pushing frames from Flutter
    pub fn frame_sender(&self) -> Option<mpsc::Sender<VideoFrame>> {
        // Note: In practice, you'd keep the sender around
        None
    }
}

impl VideoSource for CameraCapturer {
    fn format(&self) -> VideoFormat {
        self.format.clone()
    }

    fn pop_frame(&mut self) -> Result<Option<VideoFrame>> {
        if !self.capturing {
            return Ok(None);
        }
        
        // Try to get latest frame, return last frame if none available
        while let Ok(frame) = self.frame_rx.try_recv() {
            self.last_frame = Some(frame);
        }
        
        Ok(self.last_frame.clone())
    }
}

impl CaptureSource for CameraCapturer {
    fn device_info(&self) -> &CaptureDeviceInfo {
        &self.device_info
    }

    fn start(&mut self) -> Result<()> {
        info!("Starting camera capture: {}", self.device_info.name);
        self.capturing = true;
        Ok(())
    }

    fn stop(&mut self) -> Result<()> {
        info!("Stopping camera capture: {}", self.device_info.name);
        self.capturing = false;
        Ok(())
    }

    fn is_capturing(&self) -> bool {
        self.capturing
    }
}

// ============================================================================
// SIMULATED SCREEN CAPTURER
// ============================================================================

/// Screen capturer (simulated for Flutter - actual capture done on Flutter side)
pub struct ScreenCapturer {
    device_info: CaptureDeviceInfo,
    format: VideoFormat,
    frame_rx: mpsc::Receiver<VideoFrame>,
    capturing: bool,
    last_frame: Option<VideoFrame>,
}

impl ScreenCapturer {
    /// Create a new screen capturer
    pub fn new(
        screen_id: String,
        screen_name: String,
        width: u32,
        height: u32,
    ) -> (Self, mpsc::Sender<VideoFrame>) {
        let (tx, rx) = mpsc::channel(4);
        
        let capturer = Self {
            device_info: CaptureDeviceInfo {
                id: screen_id,
                name: screen_name,
                device_type: CaptureDeviceType::Screen,
                native_width: width,
                native_height: height,
            },
            format: VideoFormat::rgba(width, height),
            frame_rx: rx,
            capturing: false,
            last_frame: None,
        };
        
        (capturer, tx)
    }
}

impl VideoSource for ScreenCapturer {
    fn format(&self) -> VideoFormat {
        self.format.clone()
    }

    fn pop_frame(&mut self) -> Result<Option<VideoFrame>> {
        if !self.capturing {
            return Ok(None);
        }
        
        while let Ok(frame) = self.frame_rx.try_recv() {
            self.last_frame = Some(frame);
        }
        
        Ok(self.last_frame.clone())
    }
}

impl CaptureSource for ScreenCapturer {
    fn device_info(&self) -> &CaptureDeviceInfo {
        &self.device_info
    }

    fn start(&mut self) -> Result<()> {
        info!("Starting screen capture: {}", self.device_info.name);
        self.capturing = true;
        Ok(())
    }

    fn stop(&mut self) -> Result<()> {
        info!("Stopping screen capture: {}", self.device_info.name);
        self.capturing = false;
        Ok(())
    }

    fn is_capturing(&self) -> bool {
        self.capturing
    }
}

// ============================================================================
// TEST PATTERN GENERATOR
// ============================================================================

/// Test pattern video source for debugging
pub struct TestPatternSource {
    format: VideoFormat,
    frame_count: u64,
    start_time: Instant,
    fps: u32,
    pattern: TestPattern,
}

/// Available test patterns
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TestPattern {
    ColorBars,
    Gradient,
    MovingBox,
    Noise,
}

impl TestPatternSource {
    pub fn new(width: u32, height: u32, fps: u32, pattern: TestPattern) -> Self {
        Self {
            format: VideoFormat::rgba(width, height),
            frame_count: 0,
            start_time: Instant::now(),
            fps,
            pattern,
        }
    }

    fn generate_color_bars(&self) -> Vec<u8> {
        let width = self.format.width as usize;
        let height = self.format.height as usize;
        let mut data = vec![0u8; width * height * 4];
        
        // 8 color bars: white, yellow, cyan, green, magenta, red, blue, black
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
                let bar_idx = (x / bar_width).min(7);
                let color = colors[bar_idx];
                let pixel_idx = (y * width + x) * 4;
                data[pixel_idx] = color.0;     // R
                data[pixel_idx + 1] = color.1; // G
                data[pixel_idx + 2] = color.2; // B
                data[pixel_idx + 3] = 255;     // A
            }
        }
        
        data
    }

    fn generate_gradient(&self) -> Vec<u8> {
        let width = self.format.width as usize;
        let height = self.format.height as usize;
        let mut data = vec![0u8; width * height * 4];
        
        for y in 0..height {
            for x in 0..width {
                let pixel_idx = (y * width + x) * 4;
                data[pixel_idx] = (x * 255 / width) as u8;     // R
                data[pixel_idx + 1] = (y * 255 / height) as u8; // G
                data[pixel_idx + 2] = 128;                      // B
                data[pixel_idx + 3] = 255;                      // A
            }
        }
        
        data
    }

    fn generate_moving_box(&self) -> Vec<u8> {
        let width = self.format.width as usize;
        let height = self.format.height as usize;
        let mut data = vec![0u8; width * height * 4];
        
        // Calculate box position based on frame count
        let box_size = 50;
        let box_x = ((self.frame_count as usize * 3) % (width - box_size)) as i32;
        let box_y = ((self.frame_count as usize * 2) % (height - box_size)) as i32;
        let box_size_i32 = box_size as i32;
        
        for y in 0..height {
            for x in 0..width {
                let pixel_idx = (y * width + x) * 4;
                let xi = x as i32;
                let yi = y as i32;
                let in_box = xi >= box_x 
                    && xi < (box_x + box_size_i32)
                    && yi >= box_y 
                    && yi < (box_y + box_size_i32);
                
                if in_box {
                    data[pixel_idx] = 255;     // R
                    data[pixel_idx + 1] = 0;   // G
                    data[pixel_idx + 2] = 0;   // B
                } else {
                    data[pixel_idx] = 32;      // R
                    data[pixel_idx + 1] = 32;  // G
                    data[pixel_idx + 2] = 64;  // B
                }
                data[pixel_idx + 3] = 255;     // A
            }
        }
        
        data
    }

    fn generate_noise(&self) -> Vec<u8> {
        let width = self.format.width as usize;
        let height = self.format.height as usize;
        let mut data = vec![0u8; width * height * 4];
        
        // Simple pseudo-random noise based on frame count and position
        let seed = self.frame_count;
        for y in 0..height {
            for x in 0..width {
                let pixel_idx = (y * width + x) * 4;
                let noise = ((seed.wrapping_mul(31337) ^ (x as u64 * 7919) ^ (y as u64 * 104729)) % 256) as u8;
                data[pixel_idx] = noise;
                data[pixel_idx + 1] = noise;
                data[pixel_idx + 2] = noise;
                data[pixel_idx + 3] = 255;
            }
        }
        
        data
    }
}

impl VideoSource for TestPatternSource {
    fn format(&self) -> VideoFormat {
        self.format.clone()
    }

    fn pop_frame(&mut self) -> Result<Option<VideoFrame>> {
        let elapsed = self.start_time.elapsed();
        let expected_frame = (elapsed.as_secs_f64() * self.fps as f64) as u64;
        
        if self.frame_count >= expected_frame {
            return Ok(None); // Not time for next frame yet
        }
        
        let data = match self.pattern {
            TestPattern::ColorBars => self.generate_color_bars(),
            TestPattern::Gradient => self.generate_gradient(),
            TestPattern::MovingBox => self.generate_moving_box(),
            TestPattern::Noise => self.generate_noise(),
        };
        
        let timestamp = Duration::from_secs_f64(self.frame_count as f64 / self.fps as f64);
        self.frame_count += 1;
        
        Ok(Some(VideoFrame::new(self.format.clone(), data, timestamp)))
    }
}

// ============================================================================
// SHARED VIDEO SOURCE (like iroh-live SharedVideoSource)
// ============================================================================

/// Shared video source that can be cloned and used across multiple consumers
#[derive(Clone)]
pub struct SharedVideoSource {
    format: VideoFormat,
    frame_rx: Arc<tokio::sync::watch::Receiver<Option<VideoFrame>>>,
}

impl SharedVideoSource {
    /// Create a shared video source from any VideoSource
    pub fn new<S: VideoSource>(mut source: S) -> (Self, SharedVideoSourceTask) {
        let format = source.format();
        let (tx, rx) = tokio::sync::watch::channel(None);
        
        let shared = Self {
            format,
            frame_rx: Arc::new(rx),
        };
        
        let task = SharedVideoSourceTask {
            source: Box::new(source),
            tx,
        };
        
        (shared, task)
    }
}

impl VideoSource for SharedVideoSource {
    fn format(&self) -> VideoFormat {
        self.format.clone()
    }

    fn pop_frame(&mut self) -> Result<Option<VideoFrame>> {
        Ok(self.frame_rx.borrow().clone())
    }
}

/// Background task that feeds frames to SharedVideoSource
pub struct SharedVideoSourceTask {
    source: Box<dyn VideoSource>,
    tx: tokio::sync::watch::Sender<Option<VideoFrame>>,
}

impl SharedVideoSourceTask {
    /// Run the task, feeding frames from source to shared sink
    pub fn run_blocking(mut self, interval_ms: u64) {
        let interval = Duration::from_millis(interval_ms);
        loop {
            match self.source.pop_frame() {
                Ok(Some(frame)) => {
                    if self.tx.send(Some(frame)).is_err() {
                        break; // All receivers dropped
                    }
                }
                Ok(None) => {
                    std::thread::sleep(interval);
                }
                Err(e) => {
                    warn!("Video source error: {}", e);
                    break;
                }
            }
        }
    }
}

// ============================================================================
// CAPTURE MANAGER
// ============================================================================

/// Manager for capture devices
pub struct CaptureManager {
    cameras: Vec<CaptureDeviceInfo>,
    screens: Vec<CaptureDeviceInfo>,
}

impl CaptureManager {
    pub fn new() -> Self {
        Self {
            cameras: Vec::new(),
            screens: Vec::new(),
        }
    }

    /// Register a camera device (called from Flutter)
    pub fn register_camera(
        &mut self,
        id: String,
        name: String,
        width: u32,
        height: u32,
    ) {
        self.cameras.push(CaptureDeviceInfo {
            id,
            name,
            device_type: CaptureDeviceType::Camera,
            native_width: width,
            native_height: height,
        });
    }

    /// Register a screen/display (called from Flutter)
    pub fn register_screen(
        &mut self,
        id: String,
        name: String,
        width: u32,
        height: u32,
    ) {
        self.screens.push(CaptureDeviceInfo {
            id,
            name,
            device_type: CaptureDeviceType::Screen,
            native_width: width,
            native_height: height,
        });
    }

    /// List available cameras
    pub fn cameras(&self) -> &[CaptureDeviceInfo] {
        &self.cameras
    }

    /// List available screens
    pub fn screens(&self) -> &[CaptureDeviceInfo] {
        &self.screens
    }

    /// Create a camera capturer
    pub fn create_camera_capturer(
        &self,
        device_id: &str,
    ) -> Option<(CameraCapturer, mpsc::Sender<VideoFrame>)> {
        let device = self.cameras.iter().find(|d| d.id == device_id)?;
        Some(CameraCapturer::new(
            device.id.clone(),
            device.name.clone(),
            device.native_width,
            device.native_height,
        ))
    }

    /// Create a screen capturer
    pub fn create_screen_capturer(
        &self,
        screen_id: &str,
    ) -> Option<(ScreenCapturer, mpsc::Sender<VideoFrame>)> {
        let device = self.screens.iter().find(|d| d.id == screen_id)?;
        Some(ScreenCapturer::new(
            device.id.clone(),
            device.name.clone(),
            device.native_width,
            device.native_height,
        ))
    }

    /// Create a test pattern source
    pub fn create_test_source(
        &self,
        width: u32,
        height: u32,
        fps: u32,
        pattern: TestPattern,
    ) -> TestPatternSource {
        TestPatternSource::new(width, height, fps, pattern)
    }
}

impl Default for CaptureManager {
    fn default() -> Self {
        Self::new()
    }
}
