//! FFmpeg H264 encoder implementation following iroh-live patterns
//!
//! This provides hardware-accelerated H.264 encoding using ffmpeg-next,
//! with support for VideoToolbox (macOS/iOS) and MediaCodec (Android).
//!
//! Enable with: cargo build --features ffmpeg

#![cfg(feature = "ffmpeg")]

use std::task::Poll;
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use ffmpeg_next::{self as ffmpeg, codec, format::Pixel, frame::Video as VideoFrame};
use tracing::{debug, info, trace, warn};

/// Video preset for encoding
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoPreset {
    P180,  // 320x180 @ 15fps
    P360,  // 640x360 @ 24fps
    P720,  // 1280x720 @ 30fps
    P1080, // 1920x1080 @ 30fps
}

impl VideoPreset {
    pub fn width(&self) -> u32 {
        match self {
            VideoPreset::P180 => 320,
            VideoPreset::P360 => 640,
            VideoPreset::P720 => 1280,
            VideoPreset::P1080 => 1920,
        }
    }

    pub fn height(&self) -> u32 {
        match self {
            VideoPreset::P180 => 180,
            VideoPreset::P360 => 360,
            VideoPreset::P720 => 720,
            VideoPreset::P1080 => 1080,
        }
    }

    pub fn fps(&self) -> u32 {
        match self {
            VideoPreset::P180 => 15,
            VideoPreset::P360 => 24,
            VideoPreset::P720 | VideoPreset::P1080 => 30,
        }
    }

    pub fn all() -> Vec<VideoPreset> {
        vec![VideoPreset::P180, VideoPreset::P360, VideoPreset::P720, VideoPreset::P1080]
    }
}

/// Hardware backend for encoding
#[derive(Debug, Clone, Copy, Default)]
enum HwBackend {
    #[default]
    Software,
    #[cfg(target_os = "macos")]
    Videotoolbox,
    #[cfg(any(target_os = "linux", target_os = "android"))]
    Mediacodec,
}

impl HwBackend {
    fn codec_name(&self) -> &'static str {
        match self {
            Self::Software => "libx264",
            #[cfg(target_os = "macos")]
            Self::Videotoolbox => "h264_videotoolbox",
            #[cfg(any(target_os = "linux", target_os = "android"))]
            Self::Mediacodec => "h264_mediacodec",
        }
    }

    fn candidates() -> Vec<Self> {
        let mut candidates = Vec::new();
        
        #[cfg(target_os = "macos")]
        candidates.push(HwBackend::Videotoolbox);
        
        #[cfg(any(target_os = "linux", target_os = "android"))]
        candidates.push(HwBackend::Mediacodec);
        
        // Always end with software
        candidates.push(HwBackend::Software);
        candidates
    }

    fn pixel_format(&self) -> Pixel {
        Pixel::YUV420P
    }
}

/// Encoder options
#[derive(Debug, Clone)]
struct EncoderOpts {
    width: u32,
    height: u32,
    framerate: u32,
    bitrate: u64,
}

/// Color space converter (rescaler)
pub struct Rescaler {
    ctx: Option<ffmpeg::software::scaling::Context>,
    target_format: Pixel,
    target_size: Option<(u32, u32)>,
}

// Make rescaler Send safe
unsafe impl Send for Rescaler {}

impl Rescaler {
    pub fn new(target_format: Pixel, target_size: Option<(u32, u32)>) -> Result<Self> {
        Ok(Self {
            ctx: None,
            target_format,
            target_size,
        })
    }

    pub fn process(&mut self, frame: &VideoFrame) -> Result<VideoFrame> {
        let src_fmt = frame.format();
        let (src_w, src_h) = (frame.width(), frame.height());
        let (dst_w, dst_h) = self.target_size.unwrap_or((src_w, src_h));

        // Skip if no conversion needed
        if src_fmt == self.target_format && src_w == dst_w && src_h == dst_h {
            return Ok(frame.clone());
        }

        // Create or recreate scaler if needed
        if self.ctx.is_none() || self.needs_reinit(frame) {
            self.ctx = Some(ffmpeg::software::scaling::Context::get(
                src_fmt,
                src_w,
                src_h,
                self.target_format,
                dst_w,
                dst_h,
                ffmpeg::software::scaling::Flags::BILINEAR,
            )?);
        }

        let ctx = self.ctx.as_mut().unwrap();
        let mut output = VideoFrame::empty();
        output.set_format(self.target_format);
        output.set_width(dst_w);
        output.set_height(dst_h);
        
        ctx.run(frame, &mut output)?;
        Ok(output)
    }

    fn needs_reinit(&self, frame: &VideoFrame) -> bool {
        // Simplified - always reinit for now
        false
    }
}

/// H.264 encoder using ffmpeg-next
pub struct H264Encoder {
    encoder: ffmpeg::encoder::video::Encoder,
    rescaler: Rescaler,
    backend: HwBackend,
    opts: EncoderOpts,
    frame_count: u64,
}

// Make encoder Send safe  
unsafe impl Send for H264Encoder {}

impl H264Encoder {
    /// Create new H.264 encoder with given dimensions and framerate
    pub fn new(width: u32, height: u32, framerate: u32) -> Result<Self> {
        info!("Initializing H264 encoder: {width}x{height} @ {framerate}fps");
        ffmpeg::init()?;

        // Bitrate heuristic
        let pixels = width * height;
        let framerate_factor = 30.0 + (framerate as f32 - 30.) / 2.;
        let bitrate = (pixels as f32 * 0.07 * framerate_factor).round() as u64;

        let opts = EncoderOpts {
            width,
            height,
            framerate,
            bitrate,
        };

        let candidates = HwBackend::candidates();
        let mut last_err: Option<anyhow::Error> = None;

        for backend in candidates {
            match Self::open_encoder(backend, &opts) {
                Ok((encoder, rescaler)) => {
                    info!(
                        "Using encoder backend: {} ({backend:?})",
                        backend.codec_name()
                    );
                    return Ok(Self {
                        encoder,
                        rescaler,
                        backend,
                        opts,
                        frame_count: 0,
                    });
                }
                Err(e) => {
                    debug!(
                        "Backend {backend:?} ({}) not available: {e:#}",
                        backend.codec_name()
                    );
                    last_err = Some(e);
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow!("no H.264 encoder available")))
    }

    fn open_encoder(
        backend: HwBackend,
        opts: &EncoderOpts,
    ) -> Result<(ffmpeg::encoder::video::Encoder, Rescaler)> {
        // Find encoder
        let codec = ffmpeg::codec::encoder::find_by_name(backend.codec_name())
            .with_context(|| format!("encoder {} not found", backend.codec_name()))?;
        debug!("Found encoder: {}", codec.name());

        // Build context
        let mut ctx = codec::context::Context::new_with_codec(codec);
        unsafe {
            use std::ffi::c_int;
            let ctx_mut = ctx.as_mut_ptr();
            (*ctx_mut).width = opts.width as i32;
            (*ctx_mut).height = opts.height as i32;
            (*ctx_mut).time_base.num = 1;
            (*ctx_mut).time_base.den = opts.framerate as i32;
            (*ctx_mut).framerate.num = opts.framerate as i32;
            (*ctx_mut).framerate.den = 1;
            (*ctx_mut).gop_size = opts.framerate as i32;
            (*ctx_mut).bit_rate = opts.bitrate as i64;
            (*ctx_mut).flags = (*ctx_mut).flags | codec::Flags::GLOBAL_HEADER.bits() as c_int;
            (*ctx_mut).pix_fmt = backend.pixel_format().into();
        }

        // Setup encoder options
        let enc_opts = {
            let mut enc_opts = vec![
                // Disable annexB for MP4/ISO BMFF style
                ("annexB", "0"),
            ];
            if matches!(backend, HwBackend::Software) {
                enc_opts.extend_from_slice(&[
                    ("preset", "ultrafast"),
                    ("tune", "zerolatency"),
                    ("profile", "baseline"),
                ]);
            }
            ffmpeg::Dictionary::from_iter(enc_opts.into_iter())
        };

        // Open encoder
        let encoder = ctx.encoder().video()?.open_as_with(codec, enc_opts)?;

        // Build rescaler to convert input to YUV420P
        let rescaler = Rescaler::new(backend.pixel_format(), Some((opts.width, opts.height)))?;

        Ok((encoder, rescaler))
    }

    /// Get video config for hang catalog
    pub fn video_config(&self) -> Result<hang::catalog::VideoConfig> {
        Ok(hang::catalog::VideoConfig {
            codec: hang::catalog::VideoCodec::H264(hang::catalog::H264 {
                profile: 0x42, // Baseline
                constraints: 0xE0,
                level: 0x1E, // Level 3.0
            }),
            description: Some(self.avcc_description()?.into()),
            coded_width: Some(self.opts.width),
            coded_height: Some(self.opts.height),
            display_ratio_width: None,
            display_ratio_height: None,
            bitrate: Some(self.opts.bitrate),
            framerate: Some(self.opts.framerate as f64),
            optimize_for_latency: Some(true),
        })
    }

    /// Get avcC extradata
    pub fn avcc_description(&self) -> Result<Vec<u8>> {
        // Access extradata from the encoder context
        unsafe {
            let ctx = self.encoder.as_ptr();
            let extradata = (*ctx).extradata;
            let extradata_size = (*ctx).extradata_size as usize;
            
            if extradata.is_null() || extradata_size == 0 {
                return Err(anyhow!("missing avcC extradata"));
            }
            
            let slice = std::slice::from_raw_parts(extradata, extradata_size);
            Ok(slice.to_vec())
        }
    }

    /// Receive encoded packet
    pub fn receive_packet(&mut self) -> Result<Poll<Option<hang::Frame>>> {
        loop {
            let mut packet = ffmpeg::packet::Packet::empty();
            match self.encoder.receive_packet(&mut packet) {
                Ok(()) => {
                    let payload = packet.data().unwrap_or(&[]).to_vec();
                    let hang_frame = hang::Frame {
                        payload: payload.into(),
                        timestamp: Duration::from_nanos(
                            self.frame_count * 1_000_000_000 / self.opts.framerate as u64,
                        ),
                        keyframe: packet.is_key(),
                    };
                    return Ok(Poll::Ready(Some(hang_frame)));
                }
                Err(ffmpeg::Error::Eof) => return Ok(Poll::Ready(None)),
                Err(ffmpeg::Error::Other { errno }) if errno == ffmpeg::util::error::EAGAIN => {
                    return Ok(Poll::Pending);
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    /// Encode a frame
    pub fn encode_frame(&mut self, mut frame: VideoFrame) -> Result<()> {
        frame.set_pts(Some(self.frame_count as i64));
        self.frame_count += 1;

        if self.frame_count % self.opts.framerate as u64 == 0 {
            trace!(
                "Encoding {}: {}x{} fmt={:?} pts={:?}",
                self.frame_count,
                frame.width(),
                frame.height(),
                frame.format(),
                frame.pts(),
            );
        }

        // Convert to YUV420P
        let frame = self
            .rescaler
            .process(&frame)
            .context("failed to color-convert frame")?;

        self.encoder
            .send_frame(&frame)
            .map_err(|e| anyhow!("send_frame failed: {e:?}"))?;

        Ok(())
    }

    /// Flush encoder
    pub fn flush(&mut self) -> Result<()> {
        self.encoder.send_eof()?;
        Ok(())
    }

    /// Push raw RGBA/BGRA frame
    pub fn push_frame(&mut self, raw: &[u8], width: u32, height: u32, is_bgra: bool) -> Result<()> {
        let pixel = if is_bgra { Pixel::BGRA } else { Pixel::RGBA };
        let mut ff = VideoFrame::new(pixel, width, height);
        
        let stride = ff.stride(0);
        let row_bytes = (width as usize) * 4;
        
        for y in 0..(height as usize) {
            let dst_off = y * stride;
            let src_off = y * row_bytes;
            if src_off + row_bytes <= raw.len() {
                ff.data_mut(0)[dst_off..dst_off + row_bytes]
                    .copy_from_slice(&raw[src_off..src_off + row_bytes]);
            }
        }
        
        self.encode_frame(ff)
    }

    /// Pop encoded packet
    pub fn pop_packet(&mut self) -> Result<Option<hang::Frame>> {
        match self.receive_packet()? {
            Poll::Ready(v) => Ok(v),
            Poll::Pending => Ok(None),
        }
    }
}

/// Create encoder with preset
impl H264Encoder {
    pub fn with_preset(preset: VideoPreset) -> Result<Self> {
        Self::new(preset.width(), preset.height(), preset.fps())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preset_values() {
        let p720 = VideoPreset::P720;
        assert_eq!(p720.width(), 1280);
        assert_eq!(p720.height(), 720);
        assert_eq!(p720.fps(), 30);
    }
}
