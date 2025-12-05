//! Publish module inspired by iroh-live/publish.rs
//!
//! This module provides:
//! - PublishBroadcast for streaming video/audio
//! - Catalog management
//! - Multi-rendition support
//! - Encoder thread management

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Result, Context};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, oneshot};
use tracing::{info, debug, warn, error, trace};

use super::av::{
    VideoFormat, VideoFrame, VideoSource, VideoPreset, VideoCodec,
    AudioFormat, AudioFrame, AudioSource, AudioPreset, AudioCodec,
    EncodedPacket, TrackKind, VideoCatalogConfig, AudioCatalogConfig,
};
use super::capture::SharedVideoSource;

// ============================================================================
// BROADCAST CATALOG
// ============================================================================

/// Broadcast catalog (like hang Catalog)
/// Describes available tracks in a broadcast
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BroadcastCatalog {
    /// Available video renditions
    pub video: Option<VideoInfo>,
    /// Available audio renditions  
    pub audio: Option<AudioInfo>,
    /// Catalog version for change detection
    pub version: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoInfo {
    pub renditions: HashMap<String, VideoCatalogConfig>,
    pub priority: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioInfo {
    pub renditions: HashMap<String, AudioCatalogConfig>,
    pub priority: u8,
}

impl BroadcastCatalog {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_video(&mut self, video: Option<VideoInfo>) {
        self.video = video;
        self.version += 1;
    }

    pub fn set_audio(&mut self, audio: Option<AudioInfo>) {
        self.audio = audio;
        self.version += 1;
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>> {
        Ok(postcard::to_stdvec(self)?)
    }

    pub fn from_bytes(data: &[u8]) -> Result<Self> {
        Ok(postcard::from_bytes(data)?)
    }
}

// ============================================================================
// VIDEO RENDITIONS
// ============================================================================

/// Video renditions configuration
pub struct VideoRenditions {
    pub source: Box<dyn VideoSource>,
    pub presets: Vec<VideoPreset>,
    pub codec: VideoCodec,
    pub shared_source: Option<SharedVideoSource>,
}

impl VideoRenditions {
    pub fn new<S: VideoSource>(
        source: S,
        presets: impl IntoIterator<Item = VideoPreset>,
        codec: VideoCodec,
    ) -> Self {
        Self {
            source: Box::new(source),
            presets: presets.into_iter().collect(),
            codec,
            shared_source: None,
        }
    }

    /// Create catalog configs for all presets
    pub fn catalog_configs(&self) -> HashMap<String, VideoCatalogConfig> {
        self.presets
            .iter()
            .map(|preset| {
                let name = preset.track_name();
                let config = VideoCatalogConfig::from_preset(*preset, self.codec);
                (name, config)
            })
            .collect()
    }

    /// Get track names
    pub fn track_names(&self) -> Vec<String> {
        self.presets.iter().map(|p| p.track_name()).collect()
    }
}

// ============================================================================
// AUDIO RENDITIONS
// ============================================================================

/// Audio renditions configuration
pub struct AudioRenditions {
    pub source: Box<dyn AudioSource>,
    pub presets: Vec<AudioPreset>,
    pub codec: AudioCodec,
}

impl AudioRenditions {
    pub fn new<S: AudioSource>(
        source: S,
        presets: impl IntoIterator<Item = AudioPreset>,
        codec: AudioCodec,
    ) -> Self {
        Self {
            source: Box::new(source),
            presets: presets.into_iter().collect(),
            codec,
        }
    }

    /// Create catalog configs for all presets
    pub fn catalog_configs(&self) -> HashMap<String, AudioCatalogConfig> {
        self.presets
            .iter()
            .map(|preset| {
                let name = preset.track_name();
                let config = AudioCatalogConfig::from_preset(*preset, self.codec);
                (name, config)
            })
            .collect()
    }

    /// Get track names
    pub fn track_names(&self) -> Vec<String> {
        self.presets.iter().map(|p| p.track_name()).collect()
    }
}

// ============================================================================
// ENCODER HANDLE
// ============================================================================

/// Handle to a running encoder thread
pub struct EncoderHandle {
    pub track_name: String,
    pub kind: TrackKind,
    shutdown_tx: oneshot::Sender<()>,
    /// Channel to receive encoded packets
    pub packet_rx: mpsc::Receiver<EncodedPacket>,
}

impl EncoderHandle {
    /// Stop the encoder
    pub fn stop(self) {
        let _ = self.shutdown_tx.send(());
    }
}

// ============================================================================
// SIMPLE VIDEO ENCODER (no FFmpeg dependency)
// ============================================================================

/// Simple pass-through "encoder" that packages frames as-is
/// In production, this would use actual video encoding
pub struct SimpleVideoEncoder {
    preset: VideoPreset,
    codec: VideoCodec,
    frame_count: u64,
    keyframe_interval: u32,
}

impl SimpleVideoEncoder {
    pub fn new(preset: VideoPreset, codec: VideoCodec) -> Self {
        Self {
            preset,
            codec,
            frame_count: 0,
            keyframe_interval: 30,
        }
    }

    pub fn encode_frame(&mut self, frame: VideoFrame) -> Result<EncodedPacket> {
        let is_keyframe = self.frame_count % self.keyframe_interval as u64 == 0;
        self.frame_count += 1;

        // In production, this would actually encode the frame
        // For now, we just package the raw data with metadata header
        let mut data = Vec::with_capacity(16 + frame.data.len());
        
        // Simple header: [width:u32][height:u32][pts:i64][keyframe:u8]
        data.extend_from_slice(&frame.format.width.to_le_bytes());
        data.extend_from_slice(&frame.format.height.to_le_bytes());
        data.extend_from_slice(&frame.pts_us.to_le_bytes());
        data.push(if is_keyframe { 1 } else { 0 });
        data.extend_from_slice(&frame.data);

        Ok(EncodedPacket::video(
            data,
            frame.timestamp,
            is_keyframe,
            &self.preset.track_name(),
        ))
    }

    pub fn config(&self) -> VideoCatalogConfig {
        VideoCatalogConfig::from_preset(self.preset, self.codec)
    }
}

// ============================================================================
// SIMPLE AUDIO ENCODER
// ============================================================================

/// Simple pass-through "encoder" for audio
pub struct SimpleAudioEncoder {
    preset: AudioPreset,
    codec: AudioCodec,
    frame_count: u64,
}

impl SimpleAudioEncoder {
    pub fn new(preset: AudioPreset, codec: AudioCodec) -> Self {
        Self {
            preset,
            codec,
            frame_count: 0,
        }
    }

    pub fn encode_samples(&mut self, samples: &[f32], timestamp: Duration) -> Result<EncodedPacket> {
        self.frame_count += 1;

        // Simple encoding: convert f32 to i16 PCM
        let mut data = Vec::with_capacity(4 + samples.len() * 2);
        
        // Header: [sample_count:u32]
        data.extend_from_slice(&(samples.len() as u32).to_le_bytes());
        
        // Convert f32 samples to i16
        for &sample in samples {
            let clamped = sample.clamp(-1.0, 1.0);
            let i16_sample = (clamped * 32767.0) as i16;
            data.extend_from_slice(&i16_sample.to_le_bytes());
        }

        Ok(EncodedPacket::audio(
            data,
            timestamp,
            &self.preset.track_name(),
        ))
    }

    pub fn config(&self) -> AudioCatalogConfig {
        AudioCatalogConfig::from_preset(self.preset, self.codec)
    }
}

// ============================================================================
// PUBLISH BROADCAST
// ============================================================================

/// Publishing broadcast (like iroh-live PublishBroadcast)
pub struct PublishBroadcast {
    catalog: Arc<Mutex<BroadcastCatalog>>,
    catalog_tx: mpsc::Sender<BroadcastCatalog>,
    catalog_rx: mpsc::Receiver<BroadcastCatalog>,
    
    video_renditions: Option<VideoRenditions>,
    audio_renditions: Option<AudioRenditions>,
    
    active_video_encoders: HashMap<String, EncoderHandle>,
    active_audio_encoders: HashMap<String, EncoderHandle>,
    
    /// Channel for all encoded packets
    packet_tx: mpsc::Sender<EncodedPacket>,
    packet_rx: Option<mpsc::Receiver<EncodedPacket>>,
}

impl PublishBroadcast {
    pub fn new() -> Self {
        let (catalog_tx, catalog_rx) = mpsc::channel(8);
        let (packet_tx, packet_rx) = mpsc::channel(64);
        
        Self {
            catalog: Arc::new(Mutex::new(BroadcastCatalog::new())),
            catalog_tx,
            catalog_rx,
            video_renditions: None,
            audio_renditions: None,
            active_video_encoders: HashMap::new(),
            active_audio_encoders: HashMap::new(),
            packet_tx,
            packet_rx: Some(packet_rx),
        }
    }

    /// Get current catalog
    pub fn catalog(&self) -> BroadcastCatalog {
        self.catalog.lock().expect("poisoned").clone()
    }

    /// Take the packet receiver (can only be called once)
    pub fn take_packet_rx(&mut self) -> Option<mpsc::Receiver<EncodedPacket>> {
        self.packet_rx.take()
    }

    /// Set video source with renditions
    pub fn set_video(&mut self, renditions: Option<VideoRenditions>) -> Result<()> {
        // Stop any active encoders
        self.stop_video_encoders();
        
        match renditions {
            Some(renditions) => {
                let configs = renditions.catalog_configs();
                let video_info = VideoInfo {
                    renditions: configs,
                    priority: 1,
                };
                
                self.catalog.lock().expect("poisoned").set_video(Some(video_info));
                self.video_renditions = Some(renditions);
                self.publish_catalog()?;
                
                info!("Video renditions set: {:?}", self.video_renditions.as_ref().map(|r| r.track_names()));
            }
            None => {
                self.catalog.lock().expect("poisoned").set_video(None);
                self.video_renditions = None;
                self.publish_catalog()?;
            }
        }
        
        Ok(())
    }

    /// Set audio source with renditions
    pub fn set_audio(&mut self, renditions: Option<AudioRenditions>) -> Result<()> {
        // Stop any active encoders
        self.stop_audio_encoders();
        
        match renditions {
            Some(renditions) => {
                let configs = renditions.catalog_configs();
                let audio_info = AudioInfo {
                    renditions: configs,
                    priority: 2,
                };
                
                self.catalog.lock().expect("poisoned").set_audio(Some(audio_info));
                self.audio_renditions = Some(renditions);
                self.publish_catalog()?;
                
                info!("Audio renditions set: {:?}", self.audio_renditions.as_ref().map(|r| r.track_names()));
            }
            None => {
                self.catalog.lock().expect("poisoned").set_audio(None);
                self.audio_renditions = None;
                self.publish_catalog()?;
            }
        }
        
        Ok(())
    }

    /// Start encoding a specific video rendition
    pub fn start_video_encoder(&mut self, track_name: &str) -> Result<()> {
        let renditions = self.video_renditions.as_mut()
            .context("No video renditions configured")?;
        
        let preset = renditions.presets.iter()
            .find(|p| p.track_name() == track_name)
            .copied()
            .context("Rendition not found")?;

        if self.active_video_encoders.contains_key(track_name) {
            info!("Video encoder for {} already running", track_name);
            return Ok(());
        }

        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (packet_tx, packet_rx) = mpsc::channel(32);
        
        info!("Starting video encoder for {}", track_name);
        
        // Note: In a real implementation, we'd start encoding threads here
        // For now, we just create the handle
        let handle = EncoderHandle {
            track_name: track_name.to_string(),
            kind: TrackKind::Video,
            shutdown_tx,
            packet_rx,
        };
        
        self.active_video_encoders.insert(track_name.to_string(), handle);
        
        Ok(())
    }

    /// Start encoding a specific audio rendition
    pub fn start_audio_encoder(&mut self, track_name: &str) -> Result<()> {
        let renditions = self.audio_renditions.as_mut()
            .context("No audio renditions configured")?;
        
        let preset = renditions.presets.iter()
            .find(|p| p.track_name() == track_name)
            .copied()
            .context("Rendition not found")?;

        if self.active_audio_encoders.contains_key(track_name) {
            info!("Audio encoder for {} already running", track_name);
            return Ok(());
        }

        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (packet_tx, packet_rx) = mpsc::channel(32);
        
        info!("Starting audio encoder for {}", track_name);
        
        let handle = EncoderHandle {
            track_name: track_name.to_string(),
            kind: TrackKind::Audio,
            shutdown_tx,
            packet_rx,
        };
        
        self.active_audio_encoders.insert(track_name.to_string(), handle);
        
        Ok(())
    }

    /// Stop all video encoders
    fn stop_video_encoders(&mut self) {
        for (name, handle) in self.active_video_encoders.drain() {
            info!("Stopping video encoder: {}", name);
            handle.stop();
        }
    }

    /// Stop all audio encoders
    fn stop_audio_encoders(&mut self) {
        for (name, handle) in self.active_audio_encoders.drain() {
            info!("Stopping audio encoder: {}", name);
            handle.stop();
        }
    }

    /// Publish current catalog
    fn publish_catalog(&self) -> Result<()> {
        let catalog = self.catalog.lock().expect("poisoned").clone();
        self.catalog_tx.try_send(catalog).ok();
        Ok(())
    }

    /// Get list of available video renditions
    pub fn video_renditions(&self) -> Vec<String> {
        self.video_renditions
            .as_ref()
            .map(|r| r.track_names())
            .unwrap_or_default()
    }

    /// Get list of available audio renditions
    pub fn audio_renditions(&self) -> Vec<String> {
        self.audio_renditions
            .as_ref()
            .map(|r| r.track_names())
            .unwrap_or_default()
    }

    /// Get active video encoder names
    pub fn active_video_encoders(&self) -> Vec<String> {
        self.active_video_encoders.keys().cloned().collect()
    }

    /// Get active audio encoder names
    pub fn active_audio_encoders(&self) -> Vec<String> {
        self.active_audio_encoders.keys().cloned().collect()
    }
}

impl Drop for PublishBroadcast {
    fn drop(&mut self) {
        self.stop_video_encoders();
        self.stop_audio_encoders();
    }
}

impl Default for PublishBroadcast {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// FRAME PUSHER (for Flutter integration)
// ============================================================================

/// Frame pusher for feeding frames from Flutter
pub struct FramePusher {
    tx: mpsc::Sender<EncodedPacket>,
}

impl FramePusher {
    pub fn new(tx: mpsc::Sender<EncodedPacket>) -> Self {
        Self { tx }
    }

    /// Push a video frame (already encoded or raw)
    pub async fn push_video_frame(
        &self,
        data: Vec<u8>,
        timestamp_us: i64,
        is_keyframe: bool,
        track_name: String,
    ) -> Result<()> {
        let packet = EncodedPacket::video(
            data,
            Duration::from_micros(timestamp_us as u64),
            is_keyframe,
            &track_name,
        );
        self.tx.send(packet).await.context("Failed to send video packet")?;
        Ok(())
    }

    /// Push an audio frame (already encoded or raw)
    pub async fn push_audio_frame(
        &self,
        data: Vec<u8>,
        timestamp_us: i64,
        track_name: String,
    ) -> Result<()> {
        let packet = EncodedPacket::audio(
            data,
            Duration::from_micros(timestamp_us as u64),
            &track_name,
        );
        self.tx.send(packet).await.context("Failed to send audio packet")?;
        Ok(())
    }
}
