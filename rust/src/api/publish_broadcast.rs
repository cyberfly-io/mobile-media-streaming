//! Broadcast publishing for live streaming
//!
//! This module provides:
//! - VideoRenditions: Multi-quality video tracks
//! - AudioRenditions: Multi-quality audio tracks  
//! - PublishBroadcast: Orchestrates media encoding and MoQ transmission

use std::time::Instant;

use anyhow::Result;
use moq_lite::{BroadcastProducer, Broadcast, Track, TrackProducer, GroupProducer};
use tokio::sync::mpsc;
use tracing::{debug, info};
use bytes::Bytes;

/// Video quality level
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoQuality {
    /// Low quality (480p, 1 Mbps)
    Low,
    /// Medium quality (720p, 2.5 Mbps)
    Medium,
    /// High quality (1080p, 5 Mbps)
    High,
}

impl VideoQuality {
    /// Get the height for this quality level
    pub fn height(&self) -> u32 {
        match self {
            VideoQuality::Low => 480,
            VideoQuality::Medium => 720,
            VideoQuality::High => 1080,
        }
    }

    /// Get the bitrate for this quality level (bps)
    pub fn bitrate(&self) -> u32 {
        match self {
            VideoQuality::Low => 1_000_000,
            VideoQuality::Medium => 2_500_000,
            VideoQuality::High => 5_000_000,
        }
    }

    /// Get the track name suffix
    pub fn suffix(&self) -> &'static str {
        match self {
            VideoQuality::Low => "low",
            VideoQuality::Medium => "med",
            VideoQuality::High => "high",
        }
    }
}

/// Audio quality level
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioQuality {
    /// Low quality (32 kbps)
    Low,
    /// Medium quality (64 kbps)
    Medium,
    /// High quality (128 kbps)
    High,
}

impl AudioQuality {
    /// Get the bitrate for this quality level (bps)
    pub fn bitrate(&self) -> u32 {
        match self {
            AudioQuality::Low => 32_000,
            AudioQuality::Medium => 64_000,
            AudioQuality::High => 128_000,
        }
    }

    /// Get the track name suffix
    pub fn suffix(&self) -> &'static str {
        match self {
            AudioQuality::Low => "low",
            AudioQuality::Medium => "med",
            AudioQuality::High => "high",
        }
    }
}

/// Encoded video frame ready for transmission
#[derive(Debug, Clone)]
pub struct EncodedVideoFrame {
    /// H.264/AVC NAL units
    pub data: Bytes,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Whether this is a keyframe (IDR)
    pub is_keyframe: bool,
    /// Quality level
    pub quality: VideoQuality,
}

/// Encoded audio frame ready for transmission
#[derive(Debug, Clone)]
pub struct EncodedAudioFrame {
    /// Opus encoded audio
    pub data: Bytes,
    /// Presentation timestamp in microseconds
    pub pts_us: i64,
    /// Quality level
    pub quality: AudioQuality,
}

/// Video track producer wrapping MoQ track
pub struct VideoTrackWriter {
    producer: TrackProducer,
    current_group: Option<GroupProducer>,
    quality: VideoQuality,
    frames_written: u64,
    bytes_written: u64,
}

impl VideoTrackWriter {
    /// Create a new video track writer
    pub fn new(producer: TrackProducer, quality: VideoQuality) -> Self {
        Self {
            producer,
            current_group: None,
            quality,
            frames_written: 0,
            bytes_written: 0,
        }
    }

    /// Write an encoded frame to the track
    pub fn write_frame(&mut self, frame: &EncodedVideoFrame) {
        // For MoQ, each group starts with a keyframe
        // We create a new group for each keyframe
        if frame.is_keyframe {
            debug!(
                quality = ?self.quality,
                pts = frame.pts_us,
                size = frame.data.len(),
                "writing keyframe - starting new group"
            );
            // Start a new group for keyframe
            self.current_group = Some(self.producer.append_group());
        }

        // Get or create current group
        let group = match &mut self.current_group {
            Some(g) => g,
            None => {
                // No group yet, create one
                self.current_group = Some(self.producer.append_group());
                self.current_group.as_mut().unwrap()
            }
        };

        // Write frame to the group
        group.write_frame(frame.data.clone());
        
        self.frames_written += 1;
        self.bytes_written += frame.data.len() as u64;
    }

    /// Get statistics
    pub fn stats(&self) -> (u64, u64) {
        (self.frames_written, self.bytes_written)
    }
}

/// Audio track producer wrapping MoQ track
pub struct AudioTrackWriter {
    producer: TrackProducer,
    current_group: Option<GroupProducer>,
    quality: AudioQuality,
    frames_written: u64,
    bytes_written: u64,
}

impl AudioTrackWriter {
    /// Create a new audio track writer
    pub fn new(producer: TrackProducer, quality: AudioQuality) -> Self {
        Self {
            producer,
            current_group: None,
            quality,
            frames_written: 0,
            bytes_written: 0,
        }
    }

    /// Write an encoded audio frame to the track
    pub fn write_frame(&mut self, frame: &EncodedAudioFrame) {
        // Audio frames typically start new groups periodically (e.g., every ~20 frames)
        // For simplicity, we create a new group every 20 frames
        let start_new_group = self.current_group.is_none() || (self.frames_written % 20 == 0);
        
        if start_new_group {
            self.current_group = Some(self.producer.append_group());
        }
        
        if let Some(ref mut group) = self.current_group {
            group.write_frame(frame.data.clone());
        }
        
        self.frames_written += 1;
        self.bytes_written += frame.data.len() as u64;
    }

    /// Get statistics
    pub fn stats(&self) -> (u64, u64) {
        (self.frames_written, self.bytes_written)
    }
}

/// Collection of video renditions (multiple quality levels)
pub struct VideoRenditions {
    tracks: Vec<(VideoQuality, VideoTrackWriter)>,
}

impl VideoRenditions {
    /// Create video renditions from a broadcast producer
    pub fn new(broadcast: &mut BroadcastProducer, qualities: &[VideoQuality]) -> Self {
        let mut tracks = Vec::new();
        
        for quality in qualities {
            let track_name = format!("video.{}", quality.suffix());
            let track = Track {
                name: track_name.clone(),
                priority: match quality {
                    VideoQuality::High => 0,
                    VideoQuality::Medium => 1,
                    VideoQuality::Low => 2,
                },
            };
            
            let producer = broadcast.create_track(track);
            tracks.push((*quality, VideoTrackWriter::new(producer, *quality)));
            
            info!("created video track: {track_name}");
        }
        
        Self { tracks }
    }

    /// Write a frame to the appropriate quality track
    pub fn write_frame(&mut self, frame: &EncodedVideoFrame) {
        for (quality, writer) in &mut self.tracks {
            if *quality == frame.quality {
                writer.write_frame(frame);
                return;
            }
        }
        
        // If no matching quality, write to all (for single-quality mode)
        if self.tracks.len() == 1 {
            self.tracks[0].1.write_frame(frame);
        }
    }

    /// Get the primary (highest quality) writer
    pub fn primary(&mut self) -> Option<&mut VideoTrackWriter> {
        self.tracks.first_mut().map(|(_, w)| w)
    }
}

/// Collection of audio renditions (multiple quality levels)
pub struct AudioRenditions {
    tracks: Vec<(AudioQuality, AudioTrackWriter)>,
}

impl AudioRenditions {
    /// Create audio renditions from a broadcast producer
    pub fn new(broadcast: &mut BroadcastProducer, qualities: &[AudioQuality]) -> Self {
        let mut tracks = Vec::new();
        
        for quality in qualities {
            let track_name = format!("audio.{}", quality.suffix());
            let track = Track {
                name: track_name.clone(),
                priority: match quality {
                    AudioQuality::High => 0,
                    AudioQuality::Medium => 1,
                    AudioQuality::Low => 2,
                },
            };
            
            let producer = broadcast.create_track(track);
            tracks.push((*quality, AudioTrackWriter::new(producer, *quality)));
            
            info!("created audio track: {track_name}");
        }
        
        Self { tracks }
    }

    /// Write a frame to the appropriate quality track
    pub fn write_frame(&mut self, frame: &EncodedAudioFrame) {
        for (quality, writer) in &mut self.tracks {
            if *quality == frame.quality {
                writer.write_frame(frame);
                return;
            }
        }
        
        // If no matching quality, write to all (for single-quality mode)
        if self.tracks.len() == 1 {
            self.tracks[0].1.write_frame(frame);
        }
    }

    /// Get the primary (highest quality) writer
    pub fn primary(&mut self) -> Option<&mut AudioTrackWriter> {
        self.tracks.first_mut().map(|(_, w)| w)
    }
}

/// Messages for the broadcast publisher
pub enum PublishCommand {
    /// Push an encoded video frame
    PushVideo(EncodedVideoFrame),
    /// Push an encoded audio frame
    PushAudio(EncodedAudioFrame),
    /// Stop publishing
    Stop,
}

/// Handle for sending frames to a broadcast
#[derive(Clone)]
pub struct PublishHandle {
    tx: mpsc::Sender<PublishCommand>,
}

impl PublishHandle {
    /// Push an encoded video frame
    pub async fn push_video(&self, frame: EncodedVideoFrame) -> Result<()> {
        self.tx.send(PublishCommand::PushVideo(frame)).await
            .map_err(|_| anyhow::anyhow!("broadcast closed"))?;
        Ok(())
    }

    /// Push an encoded audio frame
    pub async fn push_audio(&self, frame: EncodedAudioFrame) -> Result<()> {
        self.tx.send(PublishCommand::PushAudio(frame)).await
            .map_err(|_| anyhow::anyhow!("broadcast closed"))?;
        Ok(())
    }

    /// Stop the broadcast
    pub async fn stop(&self) -> Result<()> {
        self.tx.send(PublishCommand::Stop).await
            .map_err(|_| anyhow::anyhow!("broadcast closed"))?;
        Ok(())
    }
}

/// Broadcast publisher configuration
#[derive(Debug, Clone)]
pub struct PublishConfig {
    /// Broadcast name
    pub name: String,
    /// Video qualities to publish
    pub video_qualities: Vec<VideoQuality>,
    /// Audio qualities to publish
    pub audio_qualities: Vec<AudioQuality>,
}

impl Default for PublishConfig {
    fn default() -> Self {
        Self {
            name: "broadcast".to_string(),
            video_qualities: vec![VideoQuality::Medium],
            audio_qualities: vec![AudioQuality::Medium],
        }
    }
}

/// Broadcast publisher
/// 
/// Creates a MoQ broadcast with video and audio tracks,
/// and provides a handle for pushing encoded frames.
pub struct PublishBroadcast {
    /// Configuration
    config: PublishConfig,
    /// The MoQ broadcast producer
    broadcast: BroadcastProducer,
    /// Command receiver
    rx: mpsc::Receiver<PublishCommand>,
    /// Video renditions
    video: VideoRenditions,
    /// Audio renditions
    audio: AudioRenditions,
}

impl PublishBroadcast {
    /// Create a new broadcast publisher
    pub fn new(config: PublishConfig) -> (Self, PublishHandle) {
        let (tx, rx) = mpsc::channel(256);
        
        // Create broadcast producer
        let produce = Broadcast::produce();
        let mut broadcast = produce.producer;
        let _consumer = produce.consumer;
        
        // Create video renditions
        let video = VideoRenditions::new(&mut broadcast, &config.video_qualities);
        
        // Create audio renditions  
        let audio = AudioRenditions::new(&mut broadcast, &config.audio_qualities);
        
        info!("created broadcast: {}", config.name);
        
        let publisher = Self {
            config,
            broadcast,
            rx,
            video,
            audio,
        };
        
        let handle = PublishHandle { tx };
        
        (publisher, handle)
    }

    /// Get the broadcast producer for announcing to peers
    pub fn producer(&self) -> &BroadcastProducer {
        &self.broadcast
    }

    /// Run the publisher, processing incoming frames
    pub async fn run(mut self) {
        info!("starting broadcast: {}", self.config.name);
        
        let mut video_frames = 0u64;
        let mut audio_frames = 0u64;
        let start = Instant::now();
        
        while let Some(cmd) = self.rx.recv().await {
            match cmd {
                PublishCommand::PushVideo(frame) => {
                    self.video.write_frame(&frame);
                    video_frames += 1;
                    
                    if video_frames % 300 == 0 {
                        let elapsed = start.elapsed().as_secs_f64();
                        let fps = video_frames as f64 / elapsed;
                        debug!("video: {video_frames} frames, {fps:.1} fps");
                    }
                }
                PublishCommand::PushAudio(frame) => {
                    self.audio.write_frame(&frame);
                    audio_frames += 1;
                }
                PublishCommand::Stop => {
                    info!("stopping broadcast: {}", self.config.name);
                    break;
                }
            }
        }
        
        let elapsed = start.elapsed();
        info!(
            "broadcast ended: {} - {} video frames, {} audio frames in {:.1}s",
            self.config.name,
            video_frames,
            audio_frames,
            elapsed.as_secs_f64()
        );
    }
}

/// Builder for creating PublishBroadcast
pub struct PublishBroadcastBuilder {
    config: PublishConfig,
}

impl PublishBroadcastBuilder {
    /// Create a new builder
    pub fn new(name: impl ToString) -> Self {
        Self {
            config: PublishConfig {
                name: name.to_string(),
                ..Default::default()
            },
        }
    }

    /// Set video qualities
    pub fn video_qualities(mut self, qualities: Vec<VideoQuality>) -> Self {
        self.config.video_qualities = qualities;
        self
    }

    /// Set audio qualities
    pub fn audio_qualities(mut self, qualities: Vec<AudioQuality>) -> Self {
        self.config.audio_qualities = qualities;
        self
    }

    /// Build the publisher
    pub fn build(self) -> (PublishBroadcast, PublishHandle) {
        PublishBroadcast::new(self.config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_quality() {
        assert_eq!(VideoQuality::Low.height(), 480);
        assert_eq!(VideoQuality::Medium.height(), 720);
        assert_eq!(VideoQuality::High.height(), 1080);
    }

    #[test]
    fn test_audio_quality() {
        assert_eq!(AudioQuality::Low.bitrate(), 32_000);
        assert_eq!(AudioQuality::Medium.bitrate(), 64_000);
        assert_eq!(AudioQuality::High.bitrate(), 128_000);
    }
}
