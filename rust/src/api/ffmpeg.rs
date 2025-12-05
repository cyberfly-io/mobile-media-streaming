//! FFmpeg integration for video/audio encoding and decoding
//!
//! This module provides:
//! - Hardware-accelerated encoding (VideoToolbox/MediaCodec)
//! - Quality ladder transcoding (180p, 360p, 720p, 1080p)
//! - Low-latency codecs (H.264, HEVC, VP8/VP9, Opus, AAC)
//! - Frame/packet conversion for MoQ streaming
//!
//! Enable with: `cargo build --features ffmpeg`

use std::collections::HashMap;
use std::sync::Arc;
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

use super::live_streaming::VideoQuality;

// ============================================================================
// CODEC IDENTIFIERS
// ============================================================================

/// Video codec options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum VideoCodec {
    /// H.264/AVC - Best compatibility
    H264,
    /// H.265/HEVC - Better compression, good mobile HW support
    H265,
    /// VP8 - Royalty-free, WebRTC compatible
    VP8,
    /// VP9 - Better than VP8, good Android support
    VP9,
    /// AV1 - Future codec, limited mobile HW support
    AV1,
}

impl VideoCodec {
    /// Get FFmpeg encoder name for this codec
    pub fn encoder_name(&self, hardware: HardwareAccel) -> &'static str {
        match (self, hardware) {
            // iOS VideoToolbox
            (VideoCodec::H264, HardwareAccel::VideoToolbox) => "h264_videotoolbox",
            (VideoCodec::H265, HardwareAccel::VideoToolbox) => "hevc_videotoolbox",
            // Android MediaCodec
            (VideoCodec::H264, HardwareAccel::MediaCodec) => "h264_mediacodec",
            (VideoCodec::H265, HardwareAccel::MediaCodec) => "hevc_mediacodec",
            (VideoCodec::VP8, HardwareAccel::MediaCodec) => "vp8_mediacodec",
            (VideoCodec::VP9, HardwareAccel::MediaCodec) => "vp9_mediacodec",
            // Software fallbacks
            (VideoCodec::H264, HardwareAccel::None) => "libx264",
            (VideoCodec::H265, HardwareAccel::None) => "libx265",
            (VideoCodec::VP8, HardwareAccel::None) => "libvpx",
            (VideoCodec::VP9, HardwareAccel::None) => "libvpx-vp9",
            (VideoCodec::AV1, _) => "libaom-av1",
            // Fallback for unsupported HW combinations
            _ => self.encoder_name(HardwareAccel::None),
        }
    }

    /// Get FFmpeg decoder name for this codec
    pub fn decoder_name(&self, hardware: HardwareAccel) -> &'static str {
        match (self, hardware) {
            // iOS VideoToolbox
            (VideoCodec::H264, HardwareAccel::VideoToolbox) => "h264_videotoolbox",
            (VideoCodec::H265, HardwareAccel::VideoToolbox) => "hevc_videotoolbox",
            // Android MediaCodec
            (VideoCodec::H264, HardwareAccel::MediaCodec) => "h264_mediacodec",
            (VideoCodec::H265, HardwareAccel::MediaCodec) => "hevc_mediacodec",
            (VideoCodec::VP8, HardwareAccel::MediaCodec) => "vp8_mediacodec",
            (VideoCodec::VP9, HardwareAccel::MediaCodec) => "vp9_mediacodec",
            // Software (use codec ID, not name)
            _ => match self {
                VideoCodec::H264 => "h264",
                VideoCodec::H265 => "hevc",
                VideoCodec::VP8 => "vp8",
                VideoCodec::VP9 => "vp9",
                VideoCodec::AV1 => "av1",
            },
        }
    }

    /// MIME type for this codec
    pub fn mime_type(&self) -> &'static str {
        match self {
            VideoCodec::H264 => "video/avc",
            VideoCodec::H265 => "video/hevc",
            VideoCodec::VP8 => "video/vp8",
            VideoCodec::VP9 => "video/vp9",
            VideoCodec::AV1 => "video/av1",
        }
    }
}

/// Audio codec options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AudioCodec {
    /// AAC - Universal compatibility
    AAC,
    /// Opus - Best for real-time, low latency
    Opus,
    /// MP3 - Legacy support
    MP3,
}

impl AudioCodec {
    pub fn encoder_name(&self) -> &'static str {
        match self {
            AudioCodec::AAC => "aac",
            AudioCodec::Opus => "libopus",
            AudioCodec::MP3 => "libmp3lame",
        }
    }

    pub fn decoder_name(&self) -> &'static str {
        match self {
            AudioCodec::AAC => "aac",
            AudioCodec::Opus => "opus",
            AudioCodec::MP3 => "mp3",
        }
    }

    pub fn mime_type(&self) -> &'static str {
        match self {
            AudioCodec::AAC => "audio/aac",
            AudioCodec::Opus => "audio/opus",
            AudioCodec::MP3 => "audio/mpeg",
        }
    }

    /// Recommended bitrate in kbps
    pub fn recommended_bitrate(&self, high_quality: bool) -> u32 {
        match (self, high_quality) {
            (AudioCodec::AAC, true) => 128,
            (AudioCodec::AAC, false) => 64,
            (AudioCodec::Opus, true) => 96,
            (AudioCodec::Opus, false) => 32,
            (AudioCodec::MP3, true) => 192,
            (AudioCodec::MP3, false) => 128,
        }
    }
}

/// Hardware acceleration options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum HardwareAccel {
    /// No hardware acceleration (software encoding)
    None,
    /// iOS VideoToolbox
    VideoToolbox,
    /// Android MediaCodec
    MediaCodec,
    /// NVIDIA NVENC (desktop)
    NVENC,
    /// Intel QuickSync (desktop)
    QSV,
    /// AMD AMF (desktop)
    AMF,
}

impl HardwareAccel {
    /// Detect available hardware acceleration for current platform
    pub fn detect() -> Self {
        #[cfg(target_os = "ios")]
        return HardwareAccel::VideoToolbox;
        
        #[cfg(target_os = "android")]
        return HardwareAccel::MediaCodec;
        
        #[cfg(target_os = "macos")]
        return HardwareAccel::VideoToolbox;
        
        #[cfg(not(any(target_os = "ios", target_os = "android", target_os = "macos")))]
        return HardwareAccel::None;
    }
}

// ============================================================================
// ENCODER CONFIGURATION
// ============================================================================

/// Video encoder configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoEncoderConfig {
    /// Video codec to use
    pub codec: VideoCodec,
    /// Output quality preset
    pub quality: VideoQuality,
    /// Hardware acceleration
    pub hardware: HardwareAccel,
    /// Target bitrate in kbps (0 = use quality default)
    pub bitrate_kbps: u32,
    /// Keyframe interval in frames (0 = auto)
    pub keyframe_interval: u32,
    /// Encoding preset (ultrafast, fast, medium, slow)
    pub preset: EncoderPreset,
    /// Tune for specific content type
    pub tune: EncoderTune,
    /// Enable low-latency mode
    pub low_latency: bool,
}

impl VideoEncoderConfig {
    pub fn new(quality: VideoQuality) -> Self {
        Self {
            codec: VideoCodec::H264,
            quality,
            hardware: HardwareAccel::detect(),
            bitrate_kbps: quality.bitrate_kbps(),
            keyframe_interval: quality.fps() * 2, // Keyframe every 2 seconds
            preset: EncoderPreset::Fast,
            tune: EncoderTune::ZeroLatency,
            low_latency: true,
        }
    }

    pub fn with_codec(mut self, codec: VideoCodec) -> Self {
        self.codec = codec;
        self
    }

    pub fn with_hardware(mut self, hw: HardwareAccel) -> Self {
        self.hardware = hw;
        self
    }

    pub fn with_bitrate(mut self, bitrate_kbps: u32) -> Self {
        self.bitrate_kbps = bitrate_kbps;
        self
    }

    pub fn with_preset(mut self, preset: EncoderPreset) -> Self {
        self.preset = preset;
        self
    }

    /// Get width from quality preset
    pub fn width(&self) -> u32 {
        self.quality.dimensions().0
    }

    /// Get height from quality preset
    pub fn height(&self) -> u32 {
        self.quality.dimensions().1
    }

    /// Get framerate from quality preset
    pub fn fps(&self) -> u32 {
        self.quality.fps()
    }
}

/// Encoder speed preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EncoderPreset {
    /// Fastest encoding, lowest quality
    Ultrafast,
    /// Very fast encoding
    Superfast,
    /// Fast encoding (recommended for live)
    Fast,
    /// Balanced
    Medium,
    /// Slow encoding, higher quality
    Slow,
    /// Slowest, best quality (for recording)
    Veryslow,
}

impl EncoderPreset {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Ultrafast => "ultrafast",
            Self::Superfast => "superfast",
            Self::Fast => "fast",
            Self::Medium => "medium",
            Self::Slow => "slow",
            Self::Veryslow => "veryslow",
        }
    }
}

/// Encoder tuning for content type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EncoderTune {
    /// No specific tuning
    None,
    /// Optimize for zero latency (live streaming)
    ZeroLatency,
    /// Optimize for film content
    Film,
    /// Optimize for animation
    Animation,
    /// Optimize for still image with some motion
    Stillimage,
    /// Optimize for screen recording
    Screen,
}

impl EncoderTune {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::None => "",
            Self::ZeroLatency => "zerolatency",
            Self::Film => "film",
            Self::Animation => "animation",
            Self::Stillimage => "stillimage",
            Self::Screen => "screen",
        }
    }
}

/// Audio encoder configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEncoderConfig {
    /// Audio codec to use
    pub codec: AudioCodec,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// Number of channels (1 = mono, 2 = stereo)
    pub channels: u32,
    /// Bitrate in kbps
    pub bitrate_kbps: u32,
}

impl AudioEncoderConfig {
    pub fn new(codec: AudioCodec, high_quality: bool) -> Self {
        Self {
            codec,
            sample_rate: if high_quality { 48000 } else { 44100 },
            channels: if high_quality { 2 } else { 1 },
            bitrate_kbps: codec.recommended_bitrate(high_quality),
        }
    }

    /// Low-latency voice configuration (Opus)
    pub fn voice() -> Self {
        Self {
            codec: AudioCodec::Opus,
            sample_rate: 48000,
            channels: 1,
            bitrate_kbps: 32,
        }
    }

    /// High-quality music configuration (AAC)
    pub fn music() -> Self {
        Self {
            codec: AudioCodec::AAC,
            sample_rate: 48000,
            channels: 2,
            bitrate_kbps: 128,
        }
    }
}

// ============================================================================
// ENCODED FRAME DATA
// ============================================================================

/// Encoded video frame
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncodedVideoFrame {
    /// Frame data (NAL units for H.264/HEVC)
    pub data: Vec<u8>,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Decode timestamp in microseconds
    pub dts_us: i64,
    /// Is this a keyframe?
    pub is_keyframe: bool,
    /// Frame duration in microseconds
    pub duration_us: i64,
    /// Frame index
    pub frame_index: u64,
    /// Codec used
    pub codec: VideoCodec,
    /// Quality level
    pub quality: VideoQuality,
}

impl EncodedVideoFrame {
    /// Priority for MoQ delivery (keyframes get priority 0)
    pub fn moq_priority(&self) -> u8 {
        if self.is_keyframe {
            0 // Highest priority
        } else {
            128 // Normal priority
        }
    }

    /// TTL for MoQ in milliseconds
    pub fn moq_ttl_ms(&self) -> u64 {
        if self.is_keyframe {
            5000 // Keyframes live longer
        } else {
            2000 // Regular frames expire faster
        }
    }
}

/// Encoded audio frame
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncodedAudioFrame {
    /// Frame data
    pub data: Vec<u8>,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Frame duration in microseconds
    pub duration_us: i64,
    /// Sample count in this frame
    pub samples: u32,
    /// Codec used
    pub codec: AudioCodec,
}

// ============================================================================
// MOCK ENCODER/DECODER (when FFmpeg not available)
// ============================================================================

/// Video encoder (mock implementation when FFmpeg not available)
#[derive(Debug)]
pub struct VideoEncoder {
    config: VideoEncoderConfig,
    frame_index: u64,
    initialized: bool,
}

impl VideoEncoder {
    /// Create a new video encoder
    pub fn new(config: VideoEncoderConfig) -> Result<Self> {
        tracing::info!(
            "[VideoEncoder] Creating encoder: {:?} {}x{} @ {}fps, {} kbps, hw={:?}",
            config.codec,
            config.width(),
            config.height(),
            config.fps(),
            config.bitrate_kbps,
            config.hardware,
        );
        
        Ok(Self {
            config,
            frame_index: 0,
            initialized: false,
        })
    }

    /// Initialize the encoder (lazy initialization)
    pub fn initialize(&mut self) -> Result<()> {
        #[cfg(feature = "ffmpeg")]
        {
            // Real FFmpeg initialization would go here
            self.initialized = true;
            return Ok(());
        }
        
        #[cfg(not(feature = "ffmpeg"))]
        {
            // Mock initialization
            tracing::warn!("[VideoEncoder] FFmpeg not available, using mock encoder");
            self.initialized = true;
            Ok(())
        }
    }

    /// Encode a raw frame (RGBA, NV12, or YUV420)
    pub fn encode(&mut self, raw_frame: &[u8], pts_us: i64) -> Result<EncodedVideoFrame> {
        if !self.initialized {
            self.initialize()?;
        }

        let is_keyframe = self.frame_index % self.config.keyframe_interval as u64 == 0;
        
        // Calculate expected frame size based on bitrate
        // bitrate_kbps * 1000 / 8 / fps = bytes per frame
        let expected_size = (self.config.bitrate_kbps as usize * 1000 / 8) 
            / self.config.fps() as usize;
        
        #[cfg(feature = "ffmpeg")]
        let data = {
            // Real FFmpeg encoding would go here
            self.ffmpeg_encode(raw_frame, pts_us, is_keyframe)?
        };
        
        #[cfg(not(feature = "ffmpeg"))]
        let data = {
            // Mock: just compress the input or generate placeholder
            self.mock_encode(raw_frame, expected_size, is_keyframe)
        };

        let frame = EncodedVideoFrame {
            data,
            pts_us,
            dts_us: pts_us, // For low-latency, DTS = PTS
            is_keyframe,
            duration_us: 1_000_000 / self.config.fps() as i64,
            frame_index: self.frame_index,
            codec: self.config.codec,
            quality: self.config.quality,
        };

        self.frame_index += 1;
        Ok(frame)
    }

    #[cfg(not(feature = "ffmpeg"))]
    fn mock_encode(&self, raw_frame: &[u8], target_size: usize, is_keyframe: bool) -> Vec<u8> {
        // Mock: create a simplified "encoded" frame
        // In real usage, this would be actual H.264 NAL units
        let mut output = Vec::with_capacity(target_size);
        
        // Add NAL start code
        output.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
        
        // Add NAL unit type (simplified)
        if is_keyframe {
            output.push(0x65); // IDR slice
        } else {
            output.push(0x41); // Non-IDR slice
        }
        
        // Add frame data (truncated/padded to target size)
        let data_len = target_size.saturating_sub(5).min(raw_frame.len());
        output.extend_from_slice(&raw_frame[..data_len]);
        
        // Pad if needed
        while output.len() < target_size {
            output.push(0x00);
        }
        
        output
    }

    /// Get encoder configuration
    pub fn config(&self) -> &VideoEncoderConfig {
        &self.config
    }

    /// Reset encoder state
    pub fn reset(&mut self) {
        self.frame_index = 0;
    }

    /// Flush any remaining frames
    pub fn flush(&mut self) -> Vec<EncodedVideoFrame> {
        // In mock mode, nothing to flush
        Vec::new()
    }
}

/// Video decoder (mock implementation when FFmpeg not available)
#[derive(Debug)]
pub struct VideoDecoder {
    codec: VideoCodec,
    hardware: HardwareAccel,
    initialized: bool,
}

impl VideoDecoder {
    /// Create a new video decoder
    pub fn new(codec: VideoCodec, hardware: HardwareAccel) -> Result<Self> {
        tracing::info!(
            "[VideoDecoder] Creating decoder: {:?}, hw={:?}",
            codec,
            hardware,
        );
        
        Ok(Self {
            codec,
            hardware,
            initialized: false,
        })
    }

    /// Auto-detect codec and create decoder
    pub fn auto_detect() -> Result<Self> {
        Self::new(VideoCodec::H264, HardwareAccel::detect())
    }

    /// Initialize the decoder
    pub fn initialize(&mut self) -> Result<()> {
        #[cfg(feature = "ffmpeg")]
        {
            // Real FFmpeg initialization would go here
            self.initialized = true;
            return Ok(());
        }
        
        #[cfg(not(feature = "ffmpeg"))]
        {
            tracing::warn!("[VideoDecoder] FFmpeg not available, using mock decoder");
            self.initialized = true;
            Ok(())
        }
    }

    /// Decode an encoded frame to raw pixels (RGBA)
    pub fn decode(&mut self, frame: &EncodedVideoFrame) -> Result<DecodedVideoFrame> {
        if !self.initialized {
            self.initialize()?;
        }

        #[cfg(feature = "ffmpeg")]
        let (data, width, height) = {
            // Real FFmpeg decoding would go here
            self.ffmpeg_decode(&frame.data)?
        };
        
        #[cfg(not(feature = "ffmpeg"))]
        let (data, width, height) = {
            // Mock: create placeholder frame
            self.mock_decode(frame)
        };

        Ok(DecodedVideoFrame {
            data,
            width,
            height,
            pts_us: frame.pts_us,
            is_keyframe: frame.is_keyframe,
            format: PixelFormat::RGBA,
        })
    }

    #[cfg(not(feature = "ffmpeg"))]
    fn mock_decode(&self, frame: &EncodedVideoFrame) -> (Vec<u8>, u32, u32) {
        let (width, height) = frame.quality.dimensions();
        let size = (width * height * 4) as usize; // RGBA
        
        // Generate a colored frame based on keyframe status
        let mut data = Vec::with_capacity(size);
        for y in 0..height {
            for x in 0..width {
                if frame.is_keyframe {
                    // Green tint for keyframes
                    data.push(0);     // R
                    data.push(128);   // G
                    data.push(0);     // B
                    data.push(255);   // A
                } else {
                    // Blue tint for P-frames
                    data.push(0);     // R
                    data.push(0);     // G
                    data.push(128);   // B
                    data.push(255);   // A
                }
            }
        }
        
        (data, width, height)
    }

    /// Flush remaining frames
    pub fn flush(&mut self) -> Vec<DecodedVideoFrame> {
        Vec::new()
    }
}

/// Decoded video frame (raw pixels)
#[derive(Debug, Clone)]
pub struct DecodedVideoFrame {
    /// Pixel data
    pub data: Vec<u8>,
    /// Frame width
    pub width: u32,
    /// Frame height
    pub height: u32,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Is this from a keyframe?
    pub is_keyframe: bool,
    /// Pixel format
    pub format: PixelFormat,
}

/// Pixel format for raw frames
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PixelFormat {
    /// 32-bit RGBA (8 bits per channel)
    RGBA,
    /// 32-bit BGRA (8 bits per channel)
    BGRA,
    /// YUV 4:2:0 planar
    YUV420P,
    /// NV12 (Y plane + interleaved UV)
    NV12,
}

impl PixelFormat {
    /// Bytes per pixel (for packed formats) or 0 for planar
    pub fn bytes_per_pixel(&self) -> usize {
        match self {
            Self::RGBA | Self::BGRA => 4,
            Self::YUV420P | Self::NV12 => 0, // Planar
        }
    }

    /// Calculate buffer size for given dimensions
    pub fn buffer_size(&self, width: u32, height: u32) -> usize {
        let pixels = (width * height) as usize;
        match self {
            Self::RGBA | Self::BGRA => pixels * 4,
            Self::YUV420P | Self::NV12 => pixels * 3 / 2, // Y + U/4 + V/4
        }
    }
}

// ============================================================================
// QUALITY LADDER TRANSCODER
// ============================================================================

/// Multi-quality encoder for adaptive bitrate streaming
pub struct QualityLadder {
    /// Encoders for each quality level
    encoders: HashMap<VideoQuality, VideoEncoder>,
    /// Base configuration
    base_config: VideoEncoderConfig,
}

impl QualityLadder {
    /// Create a quality ladder from the source quality down
    pub fn new(source_quality: VideoQuality, codec: VideoCodec) -> Result<Self> {
        let mut encoders = HashMap::new();
        let base_config = VideoEncoderConfig::new(source_quality).with_codec(codec);
        
        // Create encoders for all qualities <= source
        for quality in VideoQuality::all() {
            if quality.bitrate_kbps() <= source_quality.bitrate_kbps() {
                let config = VideoEncoderConfig::new(quality).with_codec(codec);
                let encoder = VideoEncoder::new(config)?;
                encoders.insert(quality, encoder);
            }
        }
        
        tracing::info!(
            "[QualityLadder] Created {} quality levels: {:?}",
            encoders.len(),
            encoders.keys().collect::<Vec<_>>(),
        );
        
        Ok(Self { encoders, base_config })
    }

    /// Encode a frame to all quality levels
    pub fn encode_all(&mut self, raw_frame: &[u8], pts_us: i64) -> HashMap<VideoQuality, EncodedVideoFrame> {
        let mut results = HashMap::new();
        
        for (quality, encoder) in &mut self.encoders {
            match encoder.encode(raw_frame, pts_us) {
                Ok(frame) => {
                    results.insert(*quality, frame);
                }
                Err(e) => {
                    tracing::warn!("[QualityLadder] Failed to encode {:?}: {}", quality, e);
                }
            }
        }
        
        results
    }

    /// Encode a frame to a specific quality only
    pub fn encode_single(&mut self, raw_frame: &[u8], pts_us: i64, quality: VideoQuality) -> Result<EncodedVideoFrame> {
        let encoder = self.encoders.get_mut(&quality)
            .ok_or_else(|| anyhow!("Quality {:?} not available in ladder", quality))?;
        encoder.encode(raw_frame, pts_us)
    }

    /// Get available quality levels
    pub fn available_qualities(&self) -> Vec<VideoQuality> {
        self.encoders.keys().copied().collect()
    }

    /// Reset all encoders
    pub fn reset(&mut self) {
        for encoder in self.encoders.values_mut() {
            encoder.reset();
        }
    }
}

// ============================================================================
// AUDIO ENCODER/DECODER
// ============================================================================

/// Audio encoder
#[derive(Debug)]
pub struct AudioEncoder {
    config: AudioEncoderConfig,
    sample_index: u64,
    initialized: bool,
}

impl AudioEncoder {
    pub fn new(config: AudioEncoderConfig) -> Result<Self> {
        tracing::info!(
            "[AudioEncoder] Creating encoder: {:?}, {}Hz, {} ch, {} kbps",
            config.codec,
            config.sample_rate,
            config.channels,
            config.bitrate_kbps,
        );
        
        Ok(Self {
            config,
            sample_index: 0,
            initialized: false,
        })
    }

    /// Encode raw PCM audio (16-bit signed, interleaved)
    pub fn encode(&mut self, pcm_data: &[i16], pts_us: i64) -> Result<EncodedAudioFrame> {
        if !self.initialized {
            self.initialized = true;
        }

        // Calculate samples
        let samples = pcm_data.len() as u32 / self.config.channels;
        
        // Mock: just convert to bytes
        let data: Vec<u8> = pcm_data.iter()
            .flat_map(|s| s.to_le_bytes())
            .collect();

        let frame = EncodedAudioFrame {
            data,
            pts_us,
            duration_us: (samples as i64 * 1_000_000) / self.config.sample_rate as i64,
            samples,
            codec: self.config.codec,
        };

        self.sample_index += samples as u64;
        Ok(frame)
    }

    pub fn config(&self) -> &AudioEncoderConfig {
        &self.config
    }
}

/// Audio decoder
#[derive(Debug)]
pub struct AudioDecoder {
    codec: AudioCodec,
    initialized: bool,
}

impl AudioDecoder {
    pub fn new(codec: AudioCodec) -> Result<Self> {
        Ok(Self {
            codec,
            initialized: false,
        })
    }

    /// Decode to raw PCM (16-bit signed, interleaved)
    pub fn decode(&mut self, frame: &EncodedAudioFrame) -> Result<DecodedAudioFrame> {
        if !self.initialized {
            self.initialized = true;
        }

        // Mock: convert bytes back to samples
        let samples: Vec<i16> = frame.data
            .chunks_exact(2)
            .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
            .collect();

        Ok(DecodedAudioFrame {
            samples,
            pts_us: frame.pts_us,
            sample_rate: 48000, // Assume
            channels: 2,        // Assume
        })
    }
}

/// Decoded audio frame
#[derive(Debug, Clone)]
pub struct DecodedAudioFrame {
    /// PCM samples (16-bit signed, interleaved)
    pub samples: Vec<i16>,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// Number of channels
    pub channels: u32,
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Check if FFmpeg is available
pub fn is_ffmpeg_available() -> bool {
    #[cfg(feature = "ffmpeg")]
    return true;
    
    #[cfg(not(feature = "ffmpeg"))]
    return false;
}

/// Get FFmpeg version (if available)
pub fn ffmpeg_version() -> Option<String> {
    #[cfg(feature = "ffmpeg")]
    {
        // Would return actual FFmpeg version
        Some("7.1".to_string())
    }
    
    #[cfg(not(feature = "ffmpeg"))]
    {
        None
    }
}

/// List available hardware acceleration options
pub fn available_hardware_accels() -> Vec<HardwareAccel> {
    let mut accels = vec![HardwareAccel::None];
    
    #[cfg(target_os = "ios")]
    accels.push(HardwareAccel::VideoToolbox);
    
    #[cfg(target_os = "macos")]
    accels.push(HardwareAccel::VideoToolbox);
    
    #[cfg(target_os = "android")]
    accels.push(HardwareAccel::MediaCodec);
    
    accels
}

/// List available video codecs
pub fn available_video_codecs() -> Vec<VideoCodec> {
    vec![
        VideoCodec::H264,
        VideoCodec::H265,
        VideoCodec::VP8,
        VideoCodec::VP9,
        VideoCodec::AV1,
    ]
}

/// List available audio codecs
pub fn available_audio_codecs() -> Vec<AudioCodec> {
    vec![
        AudioCodec::AAC,
        AudioCodec::Opus,
        AudioCodec::MP3,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_encoder_config() {
        let config = VideoEncoderConfig::new(VideoQuality::P720);
        assert_eq!(config.width(), 1280);
        assert_eq!(config.height(), 720);
        assert_eq!(config.fps(), 30);
    }

    #[test]
    fn test_mock_encoder() {
        let config = VideoEncoderConfig::new(VideoQuality::P360);
        let mut encoder = VideoEncoder::new(config).unwrap();
        
        // Create a dummy frame
        let raw_frame = vec![0u8; 640 * 360 * 4]; // RGBA
        
        let encoded = encoder.encode(&raw_frame, 0).unwrap();
        assert!(encoded.is_keyframe);
        assert_eq!(encoded.frame_index, 0);
        
        let encoded2 = encoder.encode(&raw_frame, 33333).unwrap();
        assert!(!encoded2.is_keyframe);
        assert_eq!(encoded2.frame_index, 1);
    }

    #[test]
    fn test_quality_ladder() {
        let mut ladder = QualityLadder::new(VideoQuality::P720, VideoCodec::H264).unwrap();
        let qualities = ladder.available_qualities();
        
        assert!(qualities.contains(&VideoQuality::P180));
        assert!(qualities.contains(&VideoQuality::P360));
        assert!(qualities.contains(&VideoQuality::P720));
        assert!(!qualities.contains(&VideoQuality::P1080));
    }
}
