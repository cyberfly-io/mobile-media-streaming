//! Flutter-Rust bridge API for FFmpeg encoding/decoding
//!
//! This provides access to:
//! - Video encoding (H.264, HEVC, VP8/VP9)
//! - Audio encoding (Opus, AAC)
//! - Hardware acceleration (VideoToolbox, MediaCodec)
//! - Quality ladder transcoding
//!
//! Enable FFmpeg with: `cargo build --features ffmpeg`

use std::sync::Arc;
use tokio::sync::Mutex;
use flutter_rust_bridge::frb;

use super::ffmpeg::{
    VideoCodec, AudioCodec, HardwareAccel, PixelFormat,
    VideoEncoderConfig, AudioEncoderConfig, EncoderPreset, EncoderTune,
    VideoEncoder, VideoDecoder, AudioEncoder, AudioDecoder,
    QualityLadder, EncodedVideoFrame, EncodedAudioFrame,
    DecodedVideoFrame, DecodedAudioFrame,
};
use super::live_streaming::VideoQuality;

// ============================================================================
// GLOBAL STATE
// ============================================================================

static VIDEO_ENCODER: once_cell::sync::OnceCell<Arc<Mutex<Option<VideoEncoder>>>> = 
    once_cell::sync::OnceCell::new();

static VIDEO_DECODER: once_cell::sync::OnceCell<Arc<Mutex<Option<VideoDecoder>>>> = 
    once_cell::sync::OnceCell::new();

static AUDIO_ENCODER: once_cell::sync::OnceCell<Arc<Mutex<Option<AudioEncoder>>>> = 
    once_cell::sync::OnceCell::new();

static AUDIO_DECODER: once_cell::sync::OnceCell<Arc<Mutex<Option<AudioDecoder>>>> = 
    once_cell::sync::OnceCell::new();

static QUALITY_LADDER: once_cell::sync::OnceCell<Arc<Mutex<Option<QualityLadder>>>> = 
    once_cell::sync::OnceCell::new();

fn get_video_encoder() -> &'static Arc<Mutex<Option<VideoEncoder>>> {
    VIDEO_ENCODER.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_video_decoder() -> &'static Arc<Mutex<Option<VideoDecoder>>> {
    VIDEO_DECODER.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_audio_encoder() -> &'static Arc<Mutex<Option<AudioEncoder>>> {
    AUDIO_ENCODER.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_audio_decoder() -> &'static Arc<Mutex<Option<AudioDecoder>>> {
    AUDIO_DECODER.get_or_init(|| Arc::new(Mutex::new(None)))
}

fn get_quality_ladder() -> &'static Arc<Mutex<Option<QualityLadder>>> {
    QUALITY_LADDER.get_or_init(|| Arc::new(Mutex::new(None)))
}

// ============================================================================
// FLUTTER TYPES - CODECS
// ============================================================================

/// Video codec for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterVideoCodec {
    H264,
    H265,
    VP8,
    VP9,
    AV1,
}

impl From<FlutterVideoCodec> for VideoCodec {
    fn from(c: FlutterVideoCodec) -> Self {
        match c {
            FlutterVideoCodec::H264 => VideoCodec::H264,
            FlutterVideoCodec::H265 => VideoCodec::H265,
            FlutterVideoCodec::VP8 => VideoCodec::VP8,
            FlutterVideoCodec::VP9 => VideoCodec::VP9,
            FlutterVideoCodec::AV1 => VideoCodec::AV1,
        }
    }
}

impl From<VideoCodec> for FlutterVideoCodec {
    fn from(c: VideoCodec) -> Self {
        match c {
            VideoCodec::H264 => FlutterVideoCodec::H264,
            VideoCodec::H265 => FlutterVideoCodec::H265,
            VideoCodec::VP8 => FlutterVideoCodec::VP8,
            VideoCodec::VP9 => FlutterVideoCodec::VP9,
            VideoCodec::AV1 => FlutterVideoCodec::AV1,
        }
    }
}

/// Audio codec for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterAudioCodec {
    AAC,
    Opus,
    MP3,
}

impl From<FlutterAudioCodec> for AudioCodec {
    fn from(c: FlutterAudioCodec) -> Self {
        match c {
            FlutterAudioCodec::AAC => AudioCodec::AAC,
            FlutterAudioCodec::Opus => AudioCodec::Opus,
            FlutterAudioCodec::MP3 => AudioCodec::MP3,
        }
    }
}

impl From<AudioCodec> for FlutterAudioCodec {
    fn from(c: AudioCodec) -> Self {
        match c {
            AudioCodec::AAC => FlutterAudioCodec::AAC,
            AudioCodec::Opus => FlutterAudioCodec::Opus,
            AudioCodec::MP3 => FlutterAudioCodec::MP3,
        }
    }
}

/// Hardware acceleration for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterHardwareAccel {
    None,
    VideoToolbox,
    MediaCodec,
    NVENC,
    QSV,
    AMF,
}

impl From<FlutterHardwareAccel> for HardwareAccel {
    fn from(h: FlutterHardwareAccel) -> Self {
        match h {
            FlutterHardwareAccel::None => HardwareAccel::None,
            FlutterHardwareAccel::VideoToolbox => HardwareAccel::VideoToolbox,
            FlutterHardwareAccel::MediaCodec => HardwareAccel::MediaCodec,
            FlutterHardwareAccel::NVENC => HardwareAccel::NVENC,
            FlutterHardwareAccel::QSV => HardwareAccel::QSV,
            FlutterHardwareAccel::AMF => HardwareAccel::AMF,
        }
    }
}

impl From<HardwareAccel> for FlutterHardwareAccel {
    fn from(h: HardwareAccel) -> Self {
        match h {
            HardwareAccel::None => FlutterHardwareAccel::None,
            HardwareAccel::VideoToolbox => FlutterHardwareAccel::VideoToolbox,
            HardwareAccel::MediaCodec => FlutterHardwareAccel::MediaCodec,
            HardwareAccel::NVENC => FlutterHardwareAccel::NVENC,
            HardwareAccel::QSV => FlutterHardwareAccel::QSV,
            HardwareAccel::AMF => FlutterHardwareAccel::AMF,
        }
    }
}

/// Encoder preset for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterEncoderPreset {
    Ultrafast,
    Superfast,
    Fast,
    Medium,
    Slow,
    Veryslow,
}

impl From<FlutterEncoderPreset> for EncoderPreset {
    fn from(p: FlutterEncoderPreset) -> Self {
        match p {
            FlutterEncoderPreset::Ultrafast => EncoderPreset::Ultrafast,
            FlutterEncoderPreset::Superfast => EncoderPreset::Superfast,
            FlutterEncoderPreset::Fast => EncoderPreset::Fast,
            FlutterEncoderPreset::Medium => EncoderPreset::Medium,
            FlutterEncoderPreset::Slow => EncoderPreset::Slow,
            FlutterEncoderPreset::Veryslow => EncoderPreset::Veryslow,
        }
    }
}

// ============================================================================
// FLUTTER TYPES - FRAMES
// ============================================================================

/// Encoded video frame for Flutter
#[derive(Debug, Clone)]
pub struct FlutterEncodedVideoFrame {
    pub data: Vec<u8>,
    pub pts_us: i64,
    pub dts_us: i64,
    pub is_keyframe: bool,
    pub duration_us: i64,
    pub frame_index: u64,
    pub codec: FlutterVideoCodec,
    /// MoQ priority (0-255, lower = higher priority)
    pub moq_priority: u8,
    /// MoQ TTL in milliseconds
    pub moq_ttl_ms: u64,
}

impl From<EncodedVideoFrame> for FlutterEncodedVideoFrame {
    fn from(f: EncodedVideoFrame) -> Self {
        // Calculate MoQ values before consuming data
        let moq_priority = f.moq_priority();
        let moq_ttl_ms = f.moq_ttl_ms();
        
        Self {
            data: f.data,
            pts_us: f.pts_us,
            dts_us: f.dts_us,
            is_keyframe: f.is_keyframe,
            duration_us: f.duration_us,
            frame_index: f.frame_index,
            codec: f.codec.into(),
            moq_priority,
            moq_ttl_ms,
        }
    }
}

/// Decoded video frame for Flutter
#[derive(Debug, Clone)]
pub struct FlutterDecodedVideoFrame {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub pts_us: i64,
    pub is_keyframe: bool,
}

impl From<DecodedVideoFrame> for FlutterDecodedVideoFrame {
    fn from(f: DecodedVideoFrame) -> Self {
        Self {
            data: f.data,
            width: f.width,
            height: f.height,
            pts_us: f.pts_us,
            is_keyframe: f.is_keyframe,
        }
    }
}

/// Encoded audio frame for Flutter
#[derive(Debug, Clone)]
pub struct FlutterEncodedAudioFrame {
    pub data: Vec<u8>,
    pub pts_us: i64,
    pub duration_us: i64,
    pub samples: u32,
    pub codec: FlutterAudioCodec,
}

impl From<EncodedAudioFrame> for FlutterEncodedAudioFrame {
    fn from(f: EncodedAudioFrame) -> Self {
        Self {
            data: f.data,
            pts_us: f.pts_us,
            duration_us: f.duration_us,
            samples: f.samples,
            codec: f.codec.into(),
        }
    }
}

/// Decoded audio frame for Flutter
#[derive(Debug, Clone)]
pub struct FlutterDecodedAudioFrame {
    pub samples: Vec<i16>,
    pub pts_us: i64,
    pub sample_rate: u32,
    pub channels: u32,
}

impl From<DecodedAudioFrame> for FlutterDecodedAudioFrame {
    fn from(f: DecodedAudioFrame) -> Self {
        Self {
            samples: f.samples,
            pts_us: f.pts_us,
            sample_rate: f.sample_rate,
            channels: f.channels,
        }
    }
}

// ============================================================================
// VIDEO ENCODER API
// ============================================================================

/// Video quality for Flutter (reusing live_flutter_api enum)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlutterVideoQualityFfmpeg {
    P180,
    P360,
    P720,
    P1080,
}

impl From<FlutterVideoQualityFfmpeg> for VideoQuality {
    fn from(q: FlutterVideoQualityFfmpeg) -> Self {
        match q {
            FlutterVideoQualityFfmpeg::P180 => VideoQuality::P180,
            FlutterVideoQualityFfmpeg::P360 => VideoQuality::P360,
            FlutterVideoQualityFfmpeg::P720 => VideoQuality::P720,
            FlutterVideoQualityFfmpeg::P1080 => VideoQuality::P1080,
        }
    }
}

/// Create a video encoder
#[frb]
pub async fn ffmpeg_create_video_encoder(
    quality: FlutterVideoQualityFfmpeg,
    codec: FlutterVideoCodec,
    hardware: FlutterHardwareAccel,
    preset: FlutterEncoderPreset,
    bitrate_kbps: Option<u32>,
    low_latency: bool,
) -> Result<(), String> {
    let mut config = VideoEncoderConfig::new(quality.into())
        .with_codec(codec.into())
        .with_hardware(hardware.into())
        .with_preset(preset.into());
    
    if let Some(br) = bitrate_kbps {
        config = config.with_bitrate(br);
    }
    config.low_latency = low_latency;

    let encoder = VideoEncoder::new(config).map_err(|e| e.to_string())?;
    
    let holder = get_video_encoder();
    let mut guard = holder.lock().await;
    *guard = Some(encoder);
    
    tracing::info!("[FFmpeg] Video encoder created");
    Ok(())
}

/// Encode a raw video frame (RGBA format)
#[frb]
pub async fn ffmpeg_encode_video_frame(
    raw_frame: Vec<u8>,
    pts_us: i64,
) -> Result<FlutterEncodedVideoFrame, String> {
    let holder = get_video_encoder();
    let mut guard = holder.lock().await;
    
    let encoder = guard.as_mut()
        .ok_or_else(|| "No video encoder created".to_string())?;
    
    let frame = encoder.encode(&raw_frame, pts_us).map_err(|e| e.to_string())?;
    Ok(frame.into())
}

/// Flush remaining video frames
#[frb]
pub async fn ffmpeg_flush_video_encoder() -> Result<Vec<FlutterEncodedVideoFrame>, String> {
    let holder = get_video_encoder();
    let mut guard = holder.lock().await;
    
    let encoder = guard.as_mut()
        .ok_or_else(|| "No video encoder created".to_string())?;
    
    let frames = encoder.flush();
    Ok(frames.into_iter().map(|f| f.into()).collect())
}

/// Reset video encoder
#[frb]
pub async fn ffmpeg_reset_video_encoder() -> Result<(), String> {
    let holder = get_video_encoder();
    let mut guard = holder.lock().await;
    
    if let Some(encoder) = guard.as_mut() {
        encoder.reset();
    }
    
    Ok(())
}

/// Destroy video encoder
#[frb]
pub async fn ffmpeg_destroy_video_encoder() -> Result<(), String> {
    let holder = get_video_encoder();
    let mut guard = holder.lock().await;
    *guard = None;
    
    tracing::info!("[FFmpeg] Video encoder destroyed");
    Ok(())
}

// ============================================================================
// VIDEO DECODER API
// ============================================================================

/// Create a video decoder
#[frb]
pub async fn ffmpeg_create_video_decoder(
    codec: FlutterVideoCodec,
    hardware: FlutterHardwareAccel,
) -> Result<(), String> {
    let decoder = VideoDecoder::new(codec.into(), hardware.into())
        .map_err(|e| e.to_string())?;
    
    let holder = get_video_decoder();
    let mut guard = holder.lock().await;
    *guard = Some(decoder);
    
    tracing::info!("[FFmpeg] Video decoder created");
    Ok(())
}

/// Decode a video frame
#[frb]
pub async fn ffmpeg_decode_video_frame(
    data: Vec<u8>,
    pts_us: i64,
    is_keyframe: bool,
    quality: FlutterVideoQualityFfmpeg,
) -> Result<FlutterDecodedVideoFrame, String> {
    let holder = get_video_decoder();
    let mut guard = holder.lock().await;
    
    let decoder = guard.as_mut()
        .ok_or_else(|| "No video decoder created".to_string())?;
    
    // Create encoded frame struct
    let encoded = EncodedVideoFrame {
        data,
        pts_us,
        dts_us: pts_us,
        is_keyframe,
        duration_us: 33333, // ~30fps
        frame_index: 0,
        codec: VideoCodec::H264, // Will be overridden
        quality: quality.into(),
    };
    
    let frame = decoder.decode(&encoded).map_err(|e| e.to_string())?;
    Ok(frame.into())
}

/// Destroy video decoder
#[frb]
pub async fn ffmpeg_destroy_video_decoder() -> Result<(), String> {
    let holder = get_video_decoder();
    let mut guard = holder.lock().await;
    *guard = None;
    
    tracing::info!("[FFmpeg] Video decoder destroyed");
    Ok(())
}

// ============================================================================
// AUDIO ENCODER API
// ============================================================================

/// Create an audio encoder
#[frb]
pub async fn ffmpeg_create_audio_encoder(
    codec: FlutterAudioCodec,
    sample_rate: u32,
    channels: u32,
    bitrate_kbps: u32,
) -> Result<(), String> {
    let config = AudioEncoderConfig {
        codec: codec.into(),
        sample_rate,
        channels,
        bitrate_kbps,
    };
    
    let encoder = AudioEncoder::new(config).map_err(|e| e.to_string())?;
    
    let holder = get_audio_encoder();
    let mut guard = holder.lock().await;
    *guard = Some(encoder);
    
    tracing::info!("[FFmpeg] Audio encoder created");
    Ok(())
}

/// Create a voice-optimized audio encoder (Opus, low latency)
#[frb]
pub async fn ffmpeg_create_voice_encoder() -> Result<(), String> {
    let config = AudioEncoderConfig::voice();
    let encoder = AudioEncoder::new(config).map_err(|e| e.to_string())?;
    
    let holder = get_audio_encoder();
    let mut guard = holder.lock().await;
    *guard = Some(encoder);
    
    tracing::info!("[FFmpeg] Voice encoder created (Opus)");
    Ok(())
}

/// Create a music-optimized audio encoder (AAC, high quality)
#[frb]
pub async fn ffmpeg_create_music_encoder() -> Result<(), String> {
    let config = AudioEncoderConfig::music();
    let encoder = AudioEncoder::new(config).map_err(|e| e.to_string())?;
    
    let holder = get_audio_encoder();
    let mut guard = holder.lock().await;
    *guard = Some(encoder);
    
    tracing::info!("[FFmpeg] Music encoder created (AAC)");
    Ok(())
}

/// Encode PCM audio (16-bit signed, interleaved)
#[frb]
pub async fn ffmpeg_encode_audio_frame(
    pcm_samples: Vec<i16>,
    pts_us: i64,
) -> Result<FlutterEncodedAudioFrame, String> {
    let holder = get_audio_encoder();
    let mut guard = holder.lock().await;
    
    let encoder = guard.as_mut()
        .ok_or_else(|| "No audio encoder created".to_string())?;
    
    let frame = encoder.encode(&pcm_samples, pts_us).map_err(|e| e.to_string())?;
    Ok(frame.into())
}

/// Destroy audio encoder
#[frb]
pub async fn ffmpeg_destroy_audio_encoder() -> Result<(), String> {
    let holder = get_audio_encoder();
    let mut guard = holder.lock().await;
    *guard = None;
    
    tracing::info!("[FFmpeg] Audio encoder destroyed");
    Ok(())
}

// ============================================================================
// AUDIO DECODER API
// ============================================================================

/// Create an audio decoder
#[frb]
pub async fn ffmpeg_create_audio_decoder(codec: FlutterAudioCodec) -> Result<(), String> {
    let decoder = AudioDecoder::new(codec.into()).map_err(|e| e.to_string())?;
    
    let holder = get_audio_decoder();
    let mut guard = holder.lock().await;
    *guard = Some(decoder);
    
    tracing::info!("[FFmpeg] Audio decoder created");
    Ok(())
}

/// Decode audio frame to PCM
#[frb]
pub async fn ffmpeg_decode_audio_frame(
    data: Vec<u8>,
    pts_us: i64,
    codec: FlutterAudioCodec,
) -> Result<FlutterDecodedAudioFrame, String> {
    let holder = get_audio_decoder();
    let mut guard = holder.lock().await;
    
    let decoder = guard.as_mut()
        .ok_or_else(|| "No audio decoder created".to_string())?;
    
    let encoded = EncodedAudioFrame {
        data,
        pts_us,
        duration_us: 20000, // 20ms typical
        samples: 960, // 20ms at 48kHz
        codec: codec.into(),
    };
    
    let frame = decoder.decode(&encoded).map_err(|e| e.to_string())?;
    Ok(frame.into())
}

/// Destroy audio decoder
#[frb]
pub async fn ffmpeg_destroy_audio_decoder() -> Result<(), String> {
    let holder = get_audio_decoder();
    let mut guard = holder.lock().await;
    *guard = None;
    
    tracing::info!("[FFmpeg] Audio decoder destroyed");
    Ok(())
}

// ============================================================================
// QUALITY LADDER API
// ============================================================================

/// Create a quality ladder for adaptive bitrate streaming
#[frb]
pub async fn ffmpeg_create_quality_ladder(
    source_quality: FlutterVideoQualityFfmpeg,
    codec: FlutterVideoCodec,
) -> Result<Vec<String>, String> {
    let ladder = QualityLadder::new(source_quality.into(), codec.into())
        .map_err(|e| e.to_string())?;
    
    let qualities: Vec<String> = ladder.available_qualities()
        .iter()
        .map(|q| q.name().to_string())
        .collect();
    
    let holder = get_quality_ladder();
    let mut guard = holder.lock().await;
    *guard = Some(ladder);
    
    tracing::info!("[FFmpeg] Quality ladder created with {} levels", qualities.len());
    Ok(qualities)
}

/// Encode a frame to all quality levels
#[frb]
pub async fn ffmpeg_encode_all_qualities(
    raw_frame: Vec<u8>,
    pts_us: i64,
) -> Result<Vec<FlutterEncodedVideoFrame>, String> {
    let holder = get_quality_ladder();
    let mut guard = holder.lock().await;
    
    let ladder = guard.as_mut()
        .ok_or_else(|| "No quality ladder created".to_string())?;
    
    let frames = ladder.encode_all(&raw_frame, pts_us);
    Ok(frames.into_values().map(|f| f.into()).collect())
}

/// Destroy quality ladder
#[frb]
pub async fn ffmpeg_destroy_quality_ladder() -> Result<(), String> {
    let holder = get_quality_ladder();
    let mut guard = holder.lock().await;
    *guard = None;
    
    tracing::info!("[FFmpeg] Quality ladder destroyed");
    Ok(())
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Check if FFmpeg is available
#[frb]
pub fn ffmpeg_is_available() -> bool {
    super::ffmpeg::is_ffmpeg_available()
}

/// Get FFmpeg version (if available)
#[frb]
pub fn ffmpeg_get_version() -> Option<String> {
    super::ffmpeg::ffmpeg_version()
}

/// Detect available hardware acceleration
#[frb]
pub fn ffmpeg_detect_hardware() -> FlutterHardwareAccel {
    HardwareAccel::detect().into()
}

/// List all available hardware accelerations
#[frb]
pub fn ffmpeg_list_hardware_accels() -> Vec<String> {
    super::ffmpeg::available_hardware_accels()
        .iter()
        .map(|h| format!("{:?}", h))
        .collect()
}

/// List all available video codecs
#[frb]
pub fn ffmpeg_list_video_codecs() -> Vec<String> {
    super::ffmpeg::available_video_codecs()
        .iter()
        .map(|c| format!("{:?}", c))
        .collect()
}

/// List all available audio codecs
#[frb]
pub fn ffmpeg_list_audio_codecs() -> Vec<String> {
    super::ffmpeg::available_audio_codecs()
        .iter()
        .map(|c| format!("{:?}", c))
        .collect()
}

/// Get codec MIME type
#[frb]
pub fn ffmpeg_get_video_mime_type(codec: FlutterVideoCodec) -> String {
    let c: VideoCodec = codec.into();
    c.mime_type().to_string()
}

/// Get audio codec MIME type
#[frb]
pub fn ffmpeg_get_audio_mime_type(codec: FlutterAudioCodec) -> String {
    let c: AudioCodec = codec.into();
    c.mime_type().to_string()
}

/// Get recommended bitrate for quality
#[frb]
pub fn ffmpeg_get_recommended_bitrate(quality: FlutterVideoQualityFfmpeg) -> u32 {
    let q: VideoQuality = quality.into();
    q.bitrate_kbps()
}

/// Get quality dimensions
#[frb]
pub fn ffmpeg_get_quality_dimensions(quality: FlutterVideoQualityFfmpeg) -> (u32, u32) {
    let q: VideoQuality = quality.into();
    q.dimensions()
}

/// Get recommended audio bitrate
#[frb]
pub fn ffmpeg_get_audio_bitrate(codec: FlutterAudioCodec, high_quality: bool) -> u32 {
    let c: AudioCodec = codec.into();
    c.recommended_bitrate(high_quality)
}
