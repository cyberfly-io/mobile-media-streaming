//! Audio/Video traits and types inspired by iroh-live/av.rs
//!
//! This module provides the core abstractions for:
//! - Video/Audio formats and frames
//! - Encoder/Decoder traits
//! - Quality presets
//! - Catalog configurations

use std::time::Duration;
use std::sync::Arc;
use anyhow::Result;
use serde::{Deserialize, Serialize};

// ============================================================================
// PIXEL FORMATS
// ============================================================================

/// Pixel format for video frames
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum PixelFormat {
    #[default]
    Rgba,
    Bgra,
    Rgb,
    Yuv420p,
    Nv12,
    Nv21,
}

impl PixelFormat {
    /// Bytes per pixel for this format
    pub fn bytes_per_pixel(&self) -> usize {
        match self {
            Self::Rgba | Self::Bgra => 4,
            Self::Rgb => 3,
            Self::Yuv420p | Self::Nv12 | Self::Nv21 => 0, // Planar format
        }
    }

    /// Check if format is planar (YUV-based)
    pub fn is_planar(&self) -> bool {
        matches!(self, Self::Yuv420p | Self::Nv12 | Self::Nv21)
    }
}

// ============================================================================
// VIDEO TYPES
// ============================================================================

/// Video format descriptor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoFormat {
    pub pixel_format: PixelFormat,
    pub width: u32,
    pub height: u32,
}

impl VideoFormat {
    pub fn new(width: u32, height: u32, pixel_format: PixelFormat) -> Self {
        Self { pixel_format, width, height }
    }

    pub fn rgba(width: u32, height: u32) -> Self {
        Self::new(width, height, PixelFormat::Rgba)
    }

    /// Calculate expected buffer size
    pub fn buffer_size(&self) -> usize {
        match self.pixel_format {
            PixelFormat::Rgba | PixelFormat::Bgra => {
                (self.width * self.height * 4) as usize
            }
            PixelFormat::Rgb => {
                (self.width * self.height * 3) as usize
            }
            PixelFormat::Yuv420p => {
                // Y plane + U plane (1/4) + V plane (1/4) = 1.5 * width * height
                (self.width * self.height * 3 / 2) as usize
            }
            PixelFormat::Nv12 | PixelFormat::Nv21 => {
                // Y plane + interleaved UV plane = 1.5 * width * height
                (self.width * self.height * 3 / 2) as usize
            }
        }
    }
}

/// A raw video frame
#[derive(Debug, Clone)]
pub struct VideoFrame {
    pub format: VideoFormat,
    pub data: Vec<u8>,
    pub timestamp: Duration,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
}

impl VideoFrame {
    pub fn new(format: VideoFormat, data: Vec<u8>, timestamp: Duration) -> Self {
        Self {
            pts_us: timestamp.as_micros() as i64,
            format,
            data,
            timestamp,
        }
    }

    pub fn width(&self) -> u32 {
        self.format.width
    }

    pub fn height(&self) -> u32 {
        self.format.height
    }
}

/// A decoded video frame ready for display
#[derive(Debug, Clone)]
pub struct DecodedFrame {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub pixel_format: PixelFormat,
    pub timestamp: Duration,
}

impl DecodedFrame {
    pub fn to_rgba(&self) -> Vec<u8> {
        if self.pixel_format == PixelFormat::Rgba {
            return self.data.clone();
        }
        // Simple conversion for BGRA -> RGBA
        if self.pixel_format == PixelFormat::Bgra {
            let mut rgba = self.data.clone();
            for chunk in rgba.chunks_exact_mut(4) {
                chunk.swap(0, 2); // Swap R and B
            }
            return rgba;
        }
        // For other formats, return as-is (decoder should handle conversion)
        self.data.clone()
    }
}

// ============================================================================
// AUDIO TYPES
// ============================================================================

/// Audio format descriptor
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct AudioFormat {
    pub sample_rate: u32,
    pub channel_count: u32,
}

impl AudioFormat {
    pub fn new(sample_rate: u32, channel_count: u32) -> Self {
        Self { sample_rate, channel_count }
    }

    /// Standard 48kHz stereo format (common for Opus)
    pub fn stereo_48khz() -> Self {
        Self::new(48000, 2)
    }

    /// Mono 16kHz (common for voice)
    pub fn mono_16khz() -> Self {
        Self::new(16000, 1)
    }

    /// Samples per 20ms frame (Opus standard frame size)
    pub fn samples_per_20ms(&self) -> u32 {
        self.sample_rate / 50 // 20ms = 1/50 second
    }
}

/// An audio frame (PCM samples)
#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub format: AudioFormat,
    /// Interleaved f32 samples
    pub samples: Vec<f32>,
    pub timestamp: Duration,
}

impl AudioFrame {
    pub fn new(format: AudioFormat, samples: Vec<f32>, timestamp: Duration) -> Self {
        Self { format, samples, timestamp }
    }

    pub fn sample_count(&self) -> usize {
        self.samples.len() / self.format.channel_count as usize
    }
}

// ============================================================================
// ENCODED PACKET
// ============================================================================

/// An encoded media packet (video or audio)
#[derive(Debug, Clone)]
pub struct EncodedPacket {
    pub data: Vec<u8>,
    pub timestamp: Duration,
    pub is_keyframe: bool,
    pub track_name: String,
}

impl EncodedPacket {
    pub fn video(data: Vec<u8>, timestamp: Duration, is_keyframe: bool, track: &str) -> Self {
        Self {
            data,
            timestamp,
            is_keyframe,
            track_name: track.to_string(),
        }
    }

    pub fn audio(data: Vec<u8>, timestamp: Duration, track: &str) -> Self {
        Self {
            data,
            timestamp,
            is_keyframe: true, // Audio packets are always "keyframes"
            track_name: track.to_string(),
        }
    }
}

// ============================================================================
// VIDEO PRESETS
// ============================================================================

/// Video quality preset (like iroh-live VideoPreset)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum VideoPreset {
    P180,
    P360,
    P720,
    P1080,
}

impl VideoPreset {
    pub fn all() -> [VideoPreset; 4] {
        [Self::P180, Self::P360, Self::P720, Self::P1080]
    }

    pub fn dimensions(&self) -> (u32, u32) {
        match self {
            Self::P180 => (320, 180),
            Self::P360 => (640, 360),
            Self::P720 => (1280, 720),
            Self::P1080 => (1920, 1080),
        }
    }

    pub fn width(&self) -> u32 {
        self.dimensions().0
    }

    pub fn height(&self) -> u32 {
        self.dimensions().1
    }

    pub fn fps(&self) -> u32 {
        30
    }

    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            Self::P180 => 300,
            Self::P360 => 800,
            Self::P720 => 2500,
            Self::P1080 => 5000,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::P180 => "180p",
            Self::P360 => "360p",
            Self::P720 => "720p",
            Self::P1080 => "1080p",
        }
    }

    pub fn track_name(&self) -> String {
        format!("video-{}", self.name())
    }

    pub fn from_name(name: &str) -> Option<Self> {
        if name.contains("180") { Some(Self::P180) }
        else if name.contains("360") { Some(Self::P360) }
        else if name.contains("720") { Some(Self::P720) }
        else if name.contains("1080") { Some(Self::P1080) }
        else { None }
    }
}

impl std::fmt::Display for VideoPreset {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

// ============================================================================
// AUDIO PRESETS
// ============================================================================

/// Audio quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AudioPreset {
    /// High quality: 48kHz stereo, 96kbps Opus
    Hq,
    /// Low quality: 48kHz mono, 32kbps Opus
    Lq,
}

impl AudioPreset {
    pub fn sample_rate(&self) -> u32 {
        48000
    }

    pub fn channel_count(&self) -> u32 {
        match self {
            Self::Hq => 2,
            Self::Lq => 1,
        }
    }

    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            Self::Hq => 96,
            Self::Lq => 32,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Hq => "hq",
            Self::Lq => "lq",
        }
    }

    pub fn track_name(&self) -> String {
        format!("audio-{}", self.name())
    }

    pub fn audio_format(&self) -> AudioFormat {
        AudioFormat::new(self.sample_rate(), self.channel_count())
    }
}

impl std::fmt::Display for AudioPreset {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

// ============================================================================
// QUALITY SELECTION
// ============================================================================

/// Quality selection preference
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum Quality {
    #[default]
    Highest,
    High,
    Mid,
    Low,
}

impl Quality {
    /// Select best video preset based on quality preference
    pub fn select_video(&self, available: &[VideoPreset]) -> Option<VideoPreset> {
        if available.is_empty() {
            return None;
        }
        
        let order = match self {
            Quality::Highest => [VideoPreset::P1080, VideoPreset::P720, VideoPreset::P360, VideoPreset::P180],
            Quality::High => [VideoPreset::P720, VideoPreset::P360, VideoPreset::P180, VideoPreset::P1080],
            Quality::Mid => [VideoPreset::P360, VideoPreset::P180, VideoPreset::P720, VideoPreset::P1080],
            Quality::Low => [VideoPreset::P180, VideoPreset::P360, VideoPreset::P720, VideoPreset::P1080],
        };

        for preset in order {
            if available.contains(&preset) {
                return Some(preset);
            }
        }
        available.first().copied()
    }

    /// Select best audio preset based on quality preference
    pub fn select_audio(&self, available: &[AudioPreset]) -> Option<AudioPreset> {
        if available.is_empty() {
            return None;
        }
        
        let order = match self {
            Quality::Highest | Quality::High => [AudioPreset::Hq, AudioPreset::Lq],
            Quality::Mid | Quality::Low => [AudioPreset::Lq, AudioPreset::Hq],
        };

        for preset in order {
            if available.contains(&preset) {
                return Some(preset);
            }
        }
        available.first().copied()
    }
}

// ============================================================================
// TRACK KIND
// ============================================================================

/// Track type identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrackKind {
    Video,
    Audio,
}

impl TrackKind {
    pub fn from_name(name: &str) -> Option<Self> {
        if name.starts_with("audio-") {
            Some(Self::Audio)
        } else if name.starts_with("video-") {
            Some(Self::Video)
        } else {
            None
        }
    }
}

// ============================================================================
// CODEC TYPES
// ============================================================================

/// Video codec identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VideoCodec {
    H264,
    H265,
    Vp8,
    Vp9,
    Av1,
}

impl VideoCodec {
    pub fn name(&self) -> &'static str {
        match self {
            Self::H264 => "h264",
            Self::H265 => "h265",
            Self::Vp8 => "vp8",
            Self::Vp9 => "vp9",
            Self::Av1 => "av1",
        }
    }

    pub fn mime_type(&self) -> &'static str {
        match self {
            Self::H264 => "video/h264",
            Self::H265 => "video/h265",
            Self::Vp8 => "video/vp8",
            Self::Vp9 => "video/vp9",
            Self::Av1 => "video/av1",
        }
    }
}

/// Audio codec identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioCodec {
    Opus,
    Aac,
    Pcm,
}

impl AudioCodec {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Opus => "opus",
            Self::Aac => "aac",
            Self::Pcm => "pcm",
        }
    }

    pub fn mime_type(&self) -> &'static str {
        match self {
            Self::Opus => "audio/opus",
            Self::Aac => "audio/aac",
            Self::Pcm => "audio/pcm",
        }
    }
}

// ============================================================================
// ENCODER/DECODER TRAITS
// ============================================================================

/// Video source trait (like iroh-live VideoSource)
pub trait VideoSource: Send + 'static {
    fn format(&self) -> VideoFormat;
    fn pop_frame(&mut self) -> Result<Option<VideoFrame>>;
}

/// Audio source trait (like iroh-live AudioSource)
pub trait AudioSource: Send + 'static {
    fn format(&self) -> AudioFormat;
    fn pop_samples(&mut self, buf: &mut [f32]) -> Result<Option<usize>>;
    fn cloned_boxed(&self) -> Box<dyn AudioSource>;
}

/// Audio sink trait (like iroh-live AudioSink)
pub trait AudioSink: Send + 'static {
    fn format(&self) -> Result<AudioFormat>;
    fn push_samples(&mut self, samples: &[f32]) -> Result<()>;
}

/// Video encoder configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoEncoderConfig {
    pub codec: VideoCodec,
    pub preset: VideoPreset,
    pub keyframe_interval: u32,
    pub hardware_accel: bool,
}

impl Default for VideoEncoderConfig {
    fn default() -> Self {
        Self {
            codec: VideoCodec::H264,
            preset: VideoPreset::P720,
            keyframe_interval: 60,
            hardware_accel: true,
        }
    }
}

/// Audio encoder configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEncoderConfig {
    pub codec: AudioCodec,
    pub preset: AudioPreset,
}

impl Default for AudioEncoderConfig {
    fn default() -> Self {
        Self {
            codec: AudioCodec::Opus,
            preset: AudioPreset::Hq,
        }
    }
}

/// Playback configuration for decoders
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlaybackConfig {
    pub pixel_format: PixelFormat,
    /// Target viewport dimensions for scaling
    pub viewport: Option<(u32, u32)>,
}

// ============================================================================
// CATALOG CONFIGURATIONS (hang-compatible)
// ============================================================================

/// Video configuration for catalog
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoCatalogConfig {
    pub codec: VideoCodec,
    pub coded_width: u32,
    pub coded_height: u32,
    pub display_width: Option<u32>,
    pub display_height: Option<u32>,
    pub framerate: Option<f64>,
    pub bitrate: Option<u32>,
}

impl VideoCatalogConfig {
    pub fn from_preset(preset: VideoPreset, codec: VideoCodec) -> Self {
        let (w, h) = preset.dimensions();
        Self {
            codec,
            coded_width: w,
            coded_height: h,
            display_width: Some(w),
            display_height: Some(h),
            framerate: Some(preset.fps() as f64),
            bitrate: Some(preset.bitrate_kbps() * 1000),
        }
    }
}

/// Audio configuration for catalog
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioCatalogConfig {
    pub codec: AudioCodec,
    pub sample_rate: u32,
    pub channel_count: u32,
    pub bitrate: Option<u32>,
}

impl AudioCatalogConfig {
    pub fn from_preset(preset: AudioPreset, codec: AudioCodec) -> Self {
        Self {
            codec,
            sample_rate: preset.sample_rate(),
            channel_count: preset.channel_count(),
            bitrate: Some(preset.bitrate_kbps() * 1000),
        }
    }
}
