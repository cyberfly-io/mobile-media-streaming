//! Subscribe module inspired by iroh-live/subscribe.rs
//!
//! This module provides:
//! - SubscribeBroadcast for receiving video/audio streams
//! - Quality-based rendition selection
//! - Decoder thread management
//! - Frame delivery to Flutter

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Result, Context};
use tokio::sync::{mpsc, oneshot, watch};
use tracing::{info, debug, warn, error};

use super::av::{
    VideoFormat, VideoFrame, DecodedFrame, VideoPreset, VideoCodec,
    AudioFormat, AudioFrame, AudioPreset, AudioCodec,
    EncodedPacket, TrackKind, Quality, PlaybackConfig,
    VideoCatalogConfig, AudioCatalogConfig, PixelFormat,
};
use super::publish::{BroadcastCatalog, VideoInfo, AudioInfo};

// ============================================================================
// SUBSCRIBE BROADCAST
// ============================================================================

/// Subscribing broadcast (like iroh-live SubscribeBroadcast)
pub struct SubscribeBroadcast {
    catalog: Arc<Mutex<BroadcastCatalog>>,
    catalog_watch: watch::Receiver<BroadcastCatalog>,
    
    /// Channel to receive encoded packets
    packet_tx: mpsc::Sender<EncodedPacket>,
    packet_rx: Option<mpsc::Receiver<EncodedPacket>>,
    
    active_video_decoder: Option<DecoderHandle>,
    active_audio_decoder: Option<AudioDecoderHandle>,
    
    playback_config: PlaybackConfig,
}

impl SubscribeBroadcast {
    pub fn new() -> (Self, mpsc::Sender<EncodedPacket>, watch::Sender<BroadcastCatalog>) {
        let (packet_tx, packet_rx) = mpsc::channel(64);
        let (catalog_tx, catalog_rx) = watch::channel(BroadcastCatalog::default());
        
        let subscriber = Self {
            catalog: Arc::new(Mutex::new(BroadcastCatalog::default())),
            catalog_watch: catalog_rx,
            packet_tx: packet_tx.clone(),
            packet_rx: Some(packet_rx),
            active_video_decoder: None,
            active_audio_decoder: None,
            playback_config: PlaybackConfig::default(),
        };
        
        (subscriber, packet_tx, catalog_tx)
    }

    /// Update catalog from received data
    pub fn update_catalog(&mut self, catalog: BroadcastCatalog) {
        *self.catalog.lock().expect("poisoned") = catalog;
    }

    /// Get current catalog
    pub fn catalog(&self) -> BroadcastCatalog {
        self.catalog.lock().expect("poisoned").clone()
    }

    /// Take the packet receiver (for feeding packets)
    pub fn take_packet_rx(&mut self) -> Option<mpsc::Receiver<EncodedPacket>> {
        self.packet_rx.take()
    }

    /// Set playback configuration
    pub fn set_playback_config(&mut self, config: PlaybackConfig) {
        self.playback_config = config;
    }

    /// Get available video renditions
    pub fn video_renditions(&self) -> Vec<String> {
        self.catalog
            .lock()
            .expect("poisoned")
            .video
            .as_ref()
            .map(|v| v.renditions.keys().cloned().collect())
            .unwrap_or_default()
    }

    /// Get available audio renditions
    pub fn audio_renditions(&self) -> Vec<String> {
        self.catalog
            .lock()
            .expect("poisoned")
            .audio
            .as_ref()
            .map(|a| a.renditions.keys().cloned().collect())
            .unwrap_or_default()
    }

    /// Watch video with quality preference
    pub fn watch(&mut self, quality: Quality) -> Result<WatchTrack> {
        let catalog = self.catalog.lock().expect("poisoned");
        let video_info = catalog.video.as_ref().context("No video published")?;
        
        // Select best rendition based on quality
        let available: Vec<VideoPreset> = video_info
            .renditions
            .keys()
            .filter_map(|name| VideoPreset::from_name(name))
            .collect();
        
        let preset = quality
            .select_video(&available)
            .context("No suitable video rendition")?;
        
        let track_name = preset.track_name();
        let config = video_info
            .renditions
            .get(&track_name)
            .context("Rendition config not found")?
            .clone();
        
        drop(catalog);
        
        self.watch_rendition(&track_name, &config)
    }

    /// Watch specific video rendition
    pub fn watch_rendition(
        &mut self,
        track_name: &str,
        config: &VideoCatalogConfig,
    ) -> Result<WatchTrack> {
        // Stop any existing decoder
        self.active_video_decoder.take();
        
        info!("Starting video watch for {}", track_name);
        
        let (frame_tx, frame_rx) = mpsc::channel(4);
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (viewport_tx, viewport_rx) = watch::channel((
            config.coded_width,
            config.coded_height,
        ));
        
        let handle = DecoderHandle {
            track_name: track_name.to_string(),
            shutdown_tx,
        };
        
        self.active_video_decoder = Some(handle);
        
        Ok(WatchTrack {
            rendition: track_name.to_string(),
            frame_rx,
            viewport_tx,
            config: config.clone(),
        })
    }

    /// Listen to audio with quality preference
    pub fn listen(&mut self, quality: Quality) -> Result<AudioTrack> {
        let catalog = self.catalog.lock().expect("poisoned");
        let audio_info = catalog.audio.as_ref().context("No audio published")?;
        
        // Select best rendition based on quality
        let available: Vec<AudioPreset> = audio_info
            .renditions
            .keys()
            .filter_map(|name| {
                if name.contains("hq") { Some(AudioPreset::Hq) }
                else if name.contains("lq") { Some(AudioPreset::Lq) }
                else { None }
            })
            .collect();
        
        let preset = quality
            .select_audio(&available)
            .context("No suitable audio rendition")?;
        
        let track_name = preset.track_name();
        let config = audio_info
            .renditions
            .get(&track_name)
            .context("Rendition config not found")?
            .clone();
        
        drop(catalog);
        
        self.listen_rendition(&track_name, &config)
    }

    /// Listen to specific audio rendition
    pub fn listen_rendition(
        &mut self,
        track_name: &str,
        config: &AudioCatalogConfig,
    ) -> Result<AudioTrack> {
        // Stop any existing decoder
        self.active_audio_decoder.take();
        
        info!("Starting audio listen for {}", track_name);
        
        let (sample_tx, sample_rx) = mpsc::channel(32);
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        
        let handle = AudioDecoderHandle {
            track_name: track_name.to_string(),
            shutdown_tx,
        };
        
        self.active_audio_decoder = Some(handle);
        
        Ok(AudioTrack {
            rendition: track_name.to_string(),
            sample_rx,
            config: config.clone(),
        })
    }

    /// Stop watching video
    pub fn stop_watch(&mut self) {
        if let Some(handle) = self.active_video_decoder.take() {
            info!("Stopping video watch: {}", handle.track_name);
            let _ = handle.shutdown_tx.send(());
        }
    }

    /// Stop listening to audio
    pub fn stop_listen(&mut self) {
        if let Some(handle) = self.active_audio_decoder.take() {
            info!("Stopping audio listen: {}", handle.track_name);
            let _ = handle.shutdown_tx.send(());
        }
    }

    /// Get current video track name
    pub fn current_video_track(&self) -> Option<String> {
        self.active_video_decoder.as_ref().map(|h| h.track_name.clone())
    }

    /// Get current audio track name
    pub fn current_audio_track(&self) -> Option<String> {
        self.active_audio_decoder.as_ref().map(|h| h.track_name.clone())
    }
}

impl Default for SubscribeBroadcast {
    fn default() -> Self {
        let (s, _, _) = Self::new();
        s
    }
}

// ============================================================================
// DECODER HANDLES
// ============================================================================

struct DecoderHandle {
    track_name: String,
    shutdown_tx: oneshot::Sender<()>,
}

struct AudioDecoderHandle {
    track_name: String,
    shutdown_tx: oneshot::Sender<()>,
}

// ============================================================================
// WATCH TRACK
// ============================================================================

/// Handle for watching a video track
pub struct WatchTrack {
    pub rendition: String,
    pub frame_rx: mpsc::Receiver<DecodedFrame>,
    pub viewport_tx: watch::Sender<(u32, u32)>,
    pub config: VideoCatalogConfig,
}

impl WatchTrack {
    /// Get current rendition name
    pub fn rendition(&self) -> &str {
        &self.rendition
    }

    /// Set viewport size (for adaptive decoding)
    pub fn set_viewport(&self, width: u32, height: u32) {
        let _ = self.viewport_tx.send((width, height));
    }

    /// Get next decoded frame (non-blocking)
    pub fn try_recv_frame(&mut self) -> Option<DecodedFrame> {
        self.frame_rx.try_recv().ok()
    }

    /// Get next decoded frame (async)
    pub async fn recv_frame(&mut self) -> Option<DecodedFrame> {
        self.frame_rx.recv().await
    }

    /// Drain and get most recent frame
    pub fn current_frame(&mut self) -> Option<DecodedFrame> {
        let mut last = None;
        while let Ok(frame) = self.frame_rx.try_recv() {
            last = Some(frame);
        }
        last
    }
}

// ============================================================================
// AUDIO TRACK
// ============================================================================

/// Handle for listening to an audio track
pub struct AudioTrack {
    pub rendition: String,
    pub sample_rx: mpsc::Receiver<AudioSamples>,
    pub config: AudioCatalogConfig,
}

/// Decoded audio samples
#[derive(Debug, Clone)]
pub struct AudioSamples {
    pub samples: Vec<f32>,
    pub timestamp: Duration,
    pub sample_rate: u32,
    pub channel_count: u32,
}

impl AudioTrack {
    /// Get current rendition name
    pub fn rendition(&self) -> &str {
        &self.rendition
    }

    /// Get next audio samples (non-blocking)
    pub fn try_recv_samples(&mut self) -> Option<AudioSamples> {
        self.sample_rx.try_recv().ok()
    }

    /// Get next audio samples (async)
    pub async fn recv_samples(&mut self) -> Option<AudioSamples> {
        self.sample_rx.recv().await
    }
}

// ============================================================================
// SIMPLE VIDEO DECODER
// ============================================================================

/// Simple pass-through "decoder"
/// In production, this would use actual video decoding
pub struct SimpleVideoDecoder {
    config: VideoCatalogConfig,
    playback_config: PlaybackConfig,
    viewport: (u32, u32),
}

impl SimpleVideoDecoder {
    pub fn new(config: &VideoCatalogConfig, playback_config: &PlaybackConfig) -> Self {
        Self {
            config: config.clone(),
            playback_config: playback_config.clone(),
            viewport: (config.coded_width, config.coded_height),
        }
    }

    pub fn set_viewport(&mut self, width: u32, height: u32) {
        self.viewport = (width, height);
    }

    /// Decode a packet
    pub fn decode(&mut self, packet: &EncodedPacket) -> Result<Option<DecodedFrame>> {
        if packet.data.len() < 17 {
            return Ok(None);
        }

        // Parse simple header
        let width = u32::from_le_bytes([packet.data[0], packet.data[1], packet.data[2], packet.data[3]]);
        let height = u32::from_le_bytes([packet.data[4], packet.data[5], packet.data[6], packet.data[7]]);
        let pts_us = i64::from_le_bytes([
            packet.data[8], packet.data[9], packet.data[10], packet.data[11],
            packet.data[12], packet.data[13], packet.data[14], packet.data[15],
        ]);
        let _is_keyframe = packet.data[16] != 0;

        let data = packet.data[17..].to_vec();

        Ok(Some(DecodedFrame {
            data,
            width,
            height,
            pixel_format: self.playback_config.pixel_format,
            timestamp: Duration::from_micros(pts_us as u64),
        }))
    }
}

// ============================================================================
// SIMPLE AUDIO DECODER
// ============================================================================

/// Simple pass-through "decoder" for audio
pub struct SimpleAudioDecoder {
    config: AudioCatalogConfig,
}

impl SimpleAudioDecoder {
    pub fn new(config: &AudioCatalogConfig) -> Self {
        Self {
            config: config.clone(),
        }
    }

    /// Decode a packet
    pub fn decode(&mut self, packet: &EncodedPacket) -> Result<Option<AudioSamples>> {
        if packet.data.len() < 4 {
            return Ok(None);
        }

        // Parse header
        let sample_count = u32::from_le_bytes([
            packet.data[0], packet.data[1], packet.data[2], packet.data[3],
        ]) as usize;

        let expected_bytes = 4 + sample_count * 2;
        if packet.data.len() < expected_bytes {
            return Ok(None);
        }

        // Convert i16 back to f32
        let mut samples = Vec::with_capacity(sample_count);
        for chunk in packet.data[4..expected_bytes].chunks_exact(2) {
            let i16_sample = i16::from_le_bytes([chunk[0], chunk[1]]);
            samples.push(i16_sample as f32 / 32767.0);
        }

        Ok(Some(AudioSamples {
            samples,
            timestamp: packet.timestamp,
            sample_rate: self.config.sample_rate,
            channel_count: self.config.channel_count,
        }))
    }
}

// ============================================================================
// FRAME RECEIVER (for Flutter integration)
// ============================================================================

/// Frame receiver for delivering frames to Flutter
pub struct FrameReceiver {
    video_rx: mpsc::Receiver<DecodedFrame>,
    audio_rx: mpsc::Receiver<AudioSamples>,
}

impl FrameReceiver {
    pub fn new(
        video_rx: mpsc::Receiver<DecodedFrame>,
        audio_rx: mpsc::Receiver<AudioSamples>,
    ) -> Self {
        Self { video_rx, audio_rx }
    }

    /// Get next video frame
    pub fn try_recv_video(&mut self) -> Option<DecodedFrame> {
        self.video_rx.try_recv().ok()
    }

    /// Get next audio samples
    pub fn try_recv_audio(&mut self) -> Option<AudioSamples> {
        self.audio_rx.try_recv().ok()
    }

    /// Get latest video frame (drain queue)
    pub fn current_video_frame(&mut self) -> Option<DecodedFrame> {
        let mut last = None;
        while let Ok(frame) = self.video_rx.try_recv() {
            last = Some(frame);
        }
        last
    }
}

// ============================================================================
// QUALITY SELECTOR
// ============================================================================

/// Automatic quality selector based on network conditions
pub struct QualitySelector {
    current_quality: Quality,
    current_video_preset: Option<VideoPreset>,
    current_audio_preset: Option<AudioPreset>,
    
    /// Bandwidth estimate in kbps
    bandwidth_kbps: u32,
    /// Packet loss percentage (0-100)
    packet_loss: f32,
    /// Round trip time in ms
    rtt_ms: u32,
}

impl QualitySelector {
    pub fn new() -> Self {
        Self {
            current_quality: Quality::High,
            current_video_preset: None,
            current_audio_preset: None,
            bandwidth_kbps: 5000,
            packet_loss: 0.0,
            rtt_ms: 50,
        }
    }

    /// Update network stats
    pub fn update_stats(&mut self, bandwidth_kbps: u32, packet_loss: f32, rtt_ms: u32) {
        self.bandwidth_kbps = bandwidth_kbps;
        self.packet_loss = packet_loss;
        self.rtt_ms = rtt_ms;
        
        // Automatically adjust quality based on network conditions
        self.current_quality = if bandwidth_kbps >= 5000 && packet_loss < 1.0 && rtt_ms < 100 {
            Quality::Highest
        } else if bandwidth_kbps >= 2500 && packet_loss < 3.0 && rtt_ms < 200 {
            Quality::High
        } else if bandwidth_kbps >= 800 && packet_loss < 5.0 && rtt_ms < 300 {
            Quality::Mid
        } else {
            Quality::Low
        };
    }

    /// Get recommended video preset
    pub fn select_video(&self, available: &[VideoPreset]) -> Option<VideoPreset> {
        self.current_quality.select_video(available)
    }

    /// Get recommended audio preset
    pub fn select_audio(&self, available: &[AudioPreset]) -> Option<AudioPreset> {
        self.current_quality.select_audio(available)
    }

    /// Get current quality level
    pub fn quality(&self) -> Quality {
        self.current_quality
    }

    /// Force a specific quality
    pub fn set_quality(&mut self, quality: Quality) {
        self.current_quality = quality;
    }
}

impl Default for QualitySelector {
    fn default() -> Self {
        Self::new()
    }
}
