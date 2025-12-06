//! Broadcast subscription for live streaming
//!
//! This module provides:
//! - SubscribeBroadcast: Receives and decodes media from a remote broadcast
//! - WatchTrack: Video track receiver with quality selection
//! - AudioTrack: Audio track receiver

use std::time::Instant;

use anyhow::Result;
use bytes::Bytes;
use moq_lite::{BroadcastConsumer, Track, TrackConsumer};
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use tracing::{debug, info, instrument, warn};

/// Received video frame
#[derive(Debug, Clone)]
pub struct ReceivedVideoFrame {
    /// H.264/AVC NAL units
    pub data: Bytes,
    /// Track name this frame came from
    pub track: String,
    /// Frame sequence number
    pub sequence: u64,
}

/// Received audio frame
#[derive(Debug, Clone)]
pub struct ReceivedAudioFrame {
    /// Opus encoded audio
    pub data: Bytes,
    /// Track name this frame came from
    pub track: String,
    /// Frame sequence number
    pub sequence: u64,
}

/// Video track receiver
pub struct WatchTrack {
    /// Track name
    name: String,
    /// Track consumer from MoQ
    consumer: TrackConsumer,
    /// Frame counter
    frame_count: u64,
    /// Output channel
    output_tx: mpsc::Sender<ReceivedVideoFrame>,
}

impl WatchTrack {
    /// Create a new video track receiver
    pub fn new(
        name: String,
        consumer: TrackConsumer,
        output_tx: mpsc::Sender<ReceivedVideoFrame>,
    ) -> Self {
        Self {
            name,
            consumer,
            frame_count: 0,
            output_tx,
        }
    }

    /// Run the track receiver
    pub async fn run(mut self, cancel: CancellationToken) {
        info!("watching video track: {}", self.name);
        let start = Instant::now();

        loop {
            tokio::select! {
                _ = cancel.cancelled() => {
                    debug!("video track cancelled: {}", self.name);
                    break;
                }
                result = self.consumer.next_group() => {
                    match result {
                        Ok(Some(mut group)) => {
                            // Read all frames from this group
                            while let Ok(Some(data)) = group.read_frame().await {
                                self.frame_count += 1;
                                
                                let frame = ReceivedVideoFrame {
                                    data,
                                    track: self.name.clone(),
                                    sequence: self.frame_count,
                                };
                                
                                if self.output_tx.send(frame).await.is_err() {
                                    debug!("video output closed");
                                    return;
                                }
                                
                                if self.frame_count % 300 == 0 {
                                    let elapsed = start.elapsed().as_secs_f64();
                                    let fps = self.frame_count as f64 / elapsed;
                                    debug!(
                                        track = %self.name,
                                        frames = self.frame_count,
                                        fps = fps,
                                        "video progress"
                                    );
                                }
                            }
                        }
                        Ok(None) => {
                            debug!("video track ended: {}", self.name);
                            break;
                        }
                        Err(e) => {
                            warn!("video track error: {e}");
                            break;
                        }
                    }
                }
            }
        }

        let elapsed = start.elapsed();
        info!(
            "video track finished: {} - {} frames in {:.1}s",
            self.name,
            self.frame_count,
            elapsed.as_secs_f64()
        );
    }
}

/// Audio track receiver
pub struct AudioTrack {
    /// Track name
    name: String,
    /// Track consumer from MoQ
    consumer: TrackConsumer,
    /// Frame counter
    frame_count: u64,
    /// Output channel
    output_tx: mpsc::Sender<ReceivedAudioFrame>,
}

impl AudioTrack {
    /// Create a new audio track receiver
    pub fn new(
        name: String,
        consumer: TrackConsumer,
        output_tx: mpsc::Sender<ReceivedAudioFrame>,
    ) -> Self {
        Self {
            name,
            consumer,
            frame_count: 0,
            output_tx,
        }
    }

    /// Run the track receiver
    pub async fn run(mut self, cancel: CancellationToken) {
        info!("watching audio track: {}", self.name);

        loop {
            tokio::select! {
                _ = cancel.cancelled() => {
                    debug!("audio track cancelled: {}", self.name);
                    break;
                }
                result = self.consumer.next_group() => {
                    match result {
                        Ok(Some(mut group)) => {
                            // Read all frames from this group
                            while let Ok(Some(data)) = group.read_frame().await {
                                self.frame_count += 1;
                                
                                let frame = ReceivedAudioFrame {
                                    data,
                                    track: self.name.clone(),
                                    sequence: self.frame_count,
                                };
                                
                                if self.output_tx.send(frame).await.is_err() {
                                    debug!("audio output closed");
                                    return;
                                }
                            }
                        }
                        Ok(None) => {
                            debug!("audio track ended: {}", self.name);
                            break;
                        }
                        Err(e) => {
                            warn!("audio track error: {e}");
                            break;
                        }
                    }
                }
            }
        }

        info!(
            "audio track finished: {} - {} frames",
            self.name,
            self.frame_count
        );
    }
}

/// Handle for receiving frames from a subscription
pub struct SubscribeHandle {
    /// Video frame receiver
    pub video_rx: mpsc::Receiver<ReceivedVideoFrame>,
    /// Audio frame receiver
    pub audio_rx: mpsc::Receiver<ReceivedAudioFrame>,
    /// Cancellation token to stop subscription
    cancel: CancellationToken,
}

impl SubscribeHandle {
    /// Receive the next video frame
    pub async fn recv_video(&mut self) -> Option<ReceivedVideoFrame> {
        self.video_rx.recv().await
    }

    /// Receive the next audio frame
    pub async fn recv_audio(&mut self) -> Option<ReceivedAudioFrame> {
        self.audio_rx.recv().await
    }

    /// Stop the subscription
    pub fn stop(&self) {
        self.cancel.cancel();
    }
}

/// Configuration for subscribe broadcast
#[derive(Debug, Clone)]
pub struct SubscribeConfig {
    /// Preferred video quality (track name suffix: "high", "med", "low")
    pub video_quality: Option<String>,
    /// Preferred audio quality (track name suffix: "high", "med", "low")
    pub audio_quality: Option<String>,
    /// Buffer size for received frames
    pub buffer_size: usize,
}

impl Default for SubscribeConfig {
    fn default() -> Self {
        Self {
            video_quality: Some("med".to_string()),
            audio_quality: Some("med".to_string()),
            buffer_size: 64,
        }
    }
}

/// Broadcast subscriber
///
/// Receives a MoQ broadcast and provides video/audio frame streams.
pub struct SubscribeBroadcast {
    /// Configuration
    config: SubscribeConfig,
    /// Broadcast consumer
    broadcast: BroadcastConsumer,
    /// Cancellation token
    cancel: CancellationToken,
}

impl SubscribeBroadcast {
    /// Create a new broadcast subscriber
    pub fn new(broadcast: BroadcastConsumer, config: SubscribeConfig) -> Self {
        Self {
            config,
            broadcast,
            cancel: CancellationToken::new(),
        }
    }

    /// Create with default config
    pub fn with_default(broadcast: BroadcastConsumer) -> Self {
        Self::new(broadcast, SubscribeConfig::default())
    }

    /// Start receiving and return a handle for consuming frames
    pub async fn start(self) -> Result<SubscribeHandle> {
        let (video_tx, video_rx) = mpsc::channel(self.config.buffer_size);
        let (audio_tx, audio_rx) = mpsc::channel(self.config.buffer_size);

        let cancel = self.cancel.clone();

        // Start the subscriber task
        tokio::spawn(self.run_subscriber(video_tx, audio_tx));

        Ok(SubscribeHandle {
            video_rx,
            audio_rx,
            cancel,
        })
    }

    /// Run the subscriber, receiving tracks from the catalog
    #[instrument(skip_all, name = "subscriber")]
    async fn run_subscriber(
        self,
        video_tx: mpsc::Sender<ReceivedVideoFrame>,
        audio_tx: mpsc::Sender<ReceivedAudioFrame>,
    ) {
        info!("starting broadcast subscription");

        // Find and subscribe to tracks
        let mut tasks = tokio::task::JoinSet::new();

        // Subscribe to video track
        let video_track_name = self
            .config
            .video_quality
            .clone()
            .map(|q| format!("video.{q}"))
            .unwrap_or_else(|| "video.med".to_string());
        
        let video_track = Track {
            name: video_track_name.clone(),
            priority: 0,
        };
        let video_consumer = self.broadcast.subscribe_track(&video_track);
        
        let watch = WatchTrack::new(video_track_name, video_consumer, video_tx);
        let cancel = self.cancel.child_token();
        tasks.spawn(async move {
            watch.run(cancel).await;
        });

        // Subscribe to audio track
        let audio_track_name = self
            .config
            .audio_quality
            .clone()
            .map(|q| format!("audio.{q}"))
            .unwrap_or_else(|| "audio.med".to_string());
        
        let audio_track = Track {
            name: audio_track_name.clone(),
            priority: 0,
        };
        let audio_consumer = self.broadcast.subscribe_track(&audio_track);
        
        let audio = AudioTrack::new(audio_track_name, audio_consumer, audio_tx);
        let cancel = self.cancel.child_token();
        tasks.spawn(async move {
            audio.run(cancel).await;
        });

        // Wait for all tracks to finish or cancellation
        loop {
            tokio::select! {
                _ = self.cancel.cancelled() => {
                    info!("subscription cancelled");
                    tasks.abort_all();
                    break;
                }
                result = tasks.join_next(), if !tasks.is_empty() => {
                    if result.is_none() {
                        debug!("all tracks finished");
                        break;
                    }
                }
            }
        }

        info!("subscription ended");
    }
}

/// Builder for SubscribeBroadcast
pub struct SubscribeBroadcastBuilder {
    broadcast: BroadcastConsumer,
    config: SubscribeConfig,
}

impl SubscribeBroadcastBuilder {
    /// Create a new builder
    pub fn new(broadcast: BroadcastConsumer) -> Self {
        Self {
            broadcast,
            config: SubscribeConfig::default(),
        }
    }

    /// Set preferred video quality
    pub fn video_quality(mut self, quality: impl ToString) -> Self {
        self.config.video_quality = Some(quality.to_string());
        self
    }

    /// Set preferred audio quality
    pub fn audio_quality(mut self, quality: impl ToString) -> Self {
        self.config.audio_quality = Some(quality.to_string());
        self
    }

    /// Set buffer size
    pub fn buffer_size(mut self, size: usize) -> Self {
        self.config.buffer_size = size;
        self
    }

    /// Build the subscriber
    pub fn build(self) -> SubscribeBroadcast {
        SubscribeBroadcast::new(self.broadcast, self.config)
    }
}
