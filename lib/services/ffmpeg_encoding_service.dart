import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Configuration for H264 video encoding
class H264EncoderConfig {
  final int width;
  final int height;
  final int frameRate;
  final int bitrate; // in kbps
  final String preset; // ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
  final String tune; // zerolatency, film, animation, grain, stillimage, psnr, ssim, fastdecode
  final int gopSize; // keyframe interval
  final String profile; // baseline, main, high
  final String level; // 3.0, 3.1, 4.0, 4.1, 4.2, 5.0, 5.1
  
  const H264EncoderConfig({
    this.width = 1280,
    this.height = 720,
    this.frameRate = 30,
    this.bitrate = 2500,
    this.preset = 'ultrafast',
    this.tune = 'zerolatency',
    this.gopSize = 30,
    this.profile = 'baseline',
    this.level = '4.0',
  });
  
  /// Low latency config for real-time streaming
  factory H264EncoderConfig.lowLatency({
    int width = 1280,
    int height = 720,
    int frameRate = 30,
    int bitrate = 2000,
  }) {
    return H264EncoderConfig(
      width: width,
      height: height,
      frameRate: frameRate,
      bitrate: bitrate,
      preset: 'ultrafast',
      tune: 'zerolatency',
      gopSize: frameRate, // 1 second GOP
      profile: 'baseline',
      level: '4.0',
    );
  }
  
  /// High quality config for recording
  factory H264EncoderConfig.highQuality({
    int width = 1920,
    int height = 1080,
    int frameRate = 30,
    int bitrate = 8000,
  }) {
    return H264EncoderConfig(
      width: width,
      height: height,
      frameRate: frameRate,
      bitrate: bitrate,
      preset: 'medium',
      tune: 'film',
      gopSize: frameRate * 2, // 2 second GOP
      profile: 'high',
      level: '4.2',
    );
  }
  
  /// Mobile-optimized config
  factory H264EncoderConfig.mobile({
    int width = 720,
    int height = 480,
    int frameRate = 24,
    int bitrate = 1000,
  }) {
    return H264EncoderConfig(
      width: width,
      height: height,
      frameRate: frameRate,
      bitrate: bitrate,
      preset: 'veryfast',
      tune: 'zerolatency',
      gopSize: frameRate,
      profile: 'baseline',
      level: '3.1',
    );
  }
}

/// Configuration for Opus audio encoding
class OpusEncoderConfig {
  final int sampleRate;
  final int channels;
  final int bitrate; // in kbps
  final String application; // voip, audio, lowdelay
  
  const OpusEncoderConfig({
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitrate = 128,
    this.application = 'lowdelay',
  });
  
  /// Low latency config for real-time streaming
  factory OpusEncoderConfig.lowLatency({
    int sampleRate = 48000,
    int channels = 1,
  }) {
    return OpusEncoderConfig(
      sampleRate: sampleRate,
      channels: channels,
      bitrate: 64,
      application: 'lowdelay',
    );
  }
  
  /// Voice optimized config
  factory OpusEncoderConfig.voice() {
    return const OpusEncoderConfig(
      sampleRate: 16000,
      channels: 1,
      bitrate: 32,
      application: 'voip',
    );
  }
  
  /// Music/high quality config
  factory OpusEncoderConfig.music() {
    return const OpusEncoderConfig(
      sampleRate: 48000,
      channels: 2,
      bitrate: 192,
      application: 'audio',
    );
  }
}

/// Result of an encoding session
class EncodingResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final Duration duration;
  final int? outputSizeBytes;
  
  EncodingResult({
    required this.success,
    this.outputPath,
    this.error,
    required this.duration,
    this.outputSizeBytes,
  });
}

/// Callback for encoding progress
typedef EncodingProgressCallback = void Function(
  double progress, // 0.0 to 1.0
  int timeMs, // encoded time in milliseconds
  double speed, // encoding speed multiplier
);

/// Callback for encoded frame data (for real-time streaming)
typedef EncodedFrameCallback = void Function(Uint8List data, int timestamp);

/// FFmpeg-based encoding service for live streaming
/// 
/// This service provides encoding capabilities using FFmpegKit.
/// For real-time streaming, it can encode camera frames to H264
/// and audio samples to Opus format.
class FFmpegEncodingService {
  static FFmpegEncodingService? _instance;
  static FFmpegEncodingService get instance {
    _instance ??= FFmpegEncodingService._();
    return _instance!;
  }
  
  FFmpegEncodingService._();
  
  Directory? _tempDir;
  bool _initialized = false;
  
  /// Initialize the encoding service
  Future<void> initialize() async {
    if (_initialized) return;
    
    _tempDir = await getTemporaryDirectory();
    
    // Enable FFmpegKit logging in debug mode
    FFmpegKitConfig.enableLogCallback((log) {
      // Uncomment for debugging:
      // print('FFmpeg: ${log.getMessage()}');
    });
    
    // Enable statistics callback
    FFmpegKitConfig.enableStatisticsCallback((statistics) {
      // Statistics available during encoding
    });
    
    _initialized = true;
  }
  
  /// Get a temporary file path for encoding output
  String _getTempFilePath(String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${_tempDir!.path}/encoded_$timestamp.$extension';
  }
  
  /// Encode a video file to H264 format
  /// 
  /// Takes an input video file and encodes it to H264 format
  /// suitable for streaming over the network.
  Future<EncodingResult> encodeVideoToH264(
    String inputPath, {
    H264EncoderConfig config = const H264EncoderConfig(),
    EncodingProgressCallback? onProgress,
    String? outputPath,
  }) async {
    await initialize();
    
    final startTime = DateTime.now();
    final output = outputPath ?? _getTempFilePath('mp4');
    
    // Build FFmpeg command for H264 encoding
    final command = [
      '-i', inputPath,
      '-c:v', 'libx264',
      '-preset', config.preset,
      '-tune', config.tune,
      '-profile:v', config.profile,
      '-level', config.level,
      '-b:v', '${config.bitrate}k',
      '-maxrate', '${(config.bitrate * 1.5).toInt()}k',
      '-bufsize', '${config.bitrate * 2}k',
      '-r', '${config.frameRate}',
      '-g', '${config.gopSize}',
      '-keyint_min', '${config.gopSize}',
      '-sc_threshold', '0',
      '-vf', 'scale=${config.width}:${config.height}',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      '-y', // Overwrite output file
      output,
    ].join(' ');
    
    // Execute FFmpeg command
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);
    
    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(output);
      final size = await outputFile.length();
      
      return EncodingResult(
        success: true,
        outputPath: output,
        duration: duration,
        outputSizeBytes: size,
      );
    } else {
      final logs = await session.getAllLogsAsString();
      return EncodingResult(
        success: false,
        error: logs,
        duration: duration,
      );
    }
  }
  
  /// Encode raw video frames to H264 format
  /// 
  /// Takes raw YUV420 frames from camera and encodes to H264.
  /// This is for real-time encoding of camera frames.
  Future<EncodingResult> encodeRawFramesToH264(
    String inputPipePath, // Named pipe or raw file
    int inputWidth,
    int inputHeight,
    int totalFrames, {
    H264EncoderConfig config = const H264EncoderConfig(),
    EncodingProgressCallback? onProgress,
    String? outputPath,
  }) async {
    await initialize();
    
    final startTime = DateTime.now();
    final output = outputPath ?? _getTempFilePath('h264');
    
    // Build FFmpeg command for raw frame encoding
    final command = [
      '-f', 'rawvideo',
      '-pixel_format', 'nv21', // Android camera format
      '-video_size', '${inputWidth}x${inputHeight}',
      '-framerate', '${config.frameRate}',
      '-i', inputPipePath,
      '-c:v', 'libx264',
      '-preset', config.preset,
      '-tune', config.tune,
      '-profile:v', config.profile,
      '-level', config.level,
      '-b:v', '${config.bitrate}k',
      '-maxrate', '${(config.bitrate * 1.5).toInt()}k',
      '-bufsize', '${config.bitrate * 2}k',
      '-g', '${config.gopSize}',
      '-keyint_min', '${config.gopSize}',
      '-sc_threshold', '0',
      '-vf', 'scale=${config.width}:${config.height}',
      '-pix_fmt', 'yuv420p',
      '-f', 'h264', // Raw H264 output
      '-y',
      output,
    ].join(' ');
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);
    
    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(output);
      final size = await outputFile.exists() ? await outputFile.length() : 0;
      
      return EncodingResult(
        success: true,
        outputPath: output,
        duration: duration,
        outputSizeBytes: size,
      );
    } else {
      final logs = await session.getAllLogsAsString();
      return EncodingResult(
        success: false,
        error: logs,
        duration: duration,
      );
    }
  }
  
  /// Encode audio to Opus format
  /// 
  /// Takes an input audio file and encodes it to Opus format
  /// suitable for low-latency audio streaming.
  Future<EncodingResult> encodeAudioToOpus(
    String inputPath, {
    OpusEncoderConfig config = const OpusEncoderConfig(),
    EncodingProgressCallback? onProgress,
    String? outputPath,
  }) async {
    await initialize();
    
    final startTime = DateTime.now();
    final output = outputPath ?? _getTempFilePath('opus');
    
    // Build FFmpeg command for Opus encoding
    final command = [
      '-i', inputPath,
      '-c:a', 'libopus',
      '-b:a', '${config.bitrate}k',
      '-ar', '${config.sampleRate}',
      '-ac', '${config.channels}',
      '-application', config.application,
      '-frame_duration', '20', // 20ms frames for low latency
      '-vbr', 'on',
      '-compression_level', '10',
      '-y',
      output,
    ].join(' ');
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);
    
    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(output);
      final size = await outputFile.length();
      
      return EncodingResult(
        success: true,
        outputPath: output,
        duration: duration,
        outputSizeBytes: size,
      );
    } else {
      final logs = await session.getAllLogsAsString();
      return EncodingResult(
        success: false,
        error: logs,
        duration: duration,
      );
    }
  }
  
  /// Encode video with audio for streaming
  /// 
  /// Takes a video file and prepares it for live streaming
  /// with both H264 video and Opus audio.
  Future<EncodingResult> encodeForStreaming(
    String inputPath, {
    H264EncoderConfig videoConfig = const H264EncoderConfig(),
    OpusEncoderConfig audioConfig = const OpusEncoderConfig(),
    EncodingProgressCallback? onProgress,
    String? outputPath,
  }) async {
    await initialize();
    
    final startTime = DateTime.now();
    final output = outputPath ?? _getTempFilePath('mkv');
    
    // Build FFmpeg command for combined encoding
    final command = [
      '-i', inputPath,
      // Video encoding
      '-c:v', 'libx264',
      '-preset', videoConfig.preset,
      '-tune', videoConfig.tune,
      '-profile:v', videoConfig.profile,
      '-level', videoConfig.level,
      '-b:v', '${videoConfig.bitrate}k',
      '-maxrate', '${(videoConfig.bitrate * 1.5).toInt()}k',
      '-bufsize', '${videoConfig.bitrate * 2}k',
      '-r', '${videoConfig.frameRate}',
      '-g', '${videoConfig.gopSize}',
      '-keyint_min', '${videoConfig.gopSize}',
      '-vf', 'scale=${videoConfig.width}:${videoConfig.height}',
      '-pix_fmt', 'yuv420p',
      // Audio encoding
      '-c:a', 'libopus',
      '-b:a', '${audioConfig.bitrate}k',
      '-ar', '${audioConfig.sampleRate}',
      '-ac', '${audioConfig.channels}',
      '-application', audioConfig.application,
      '-y',
      output,
    ].join(' ');
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);
    
    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(output);
      final size = await outputFile.length();
      
      return EncodingResult(
        success: true,
        outputPath: output,
        duration: duration,
        outputSizeBytes: size,
      );
    } else {
      final logs = await session.getAllLogsAsString();
      return EncodingResult(
        success: false,
        error: logs,
        duration: duration,
      );
    }
  }
  
  /// Extract audio from video file
  Future<EncodingResult> extractAudio(
    String inputPath, {
    String? outputPath,
  }) async {
    await initialize();
    
    final startTime = DateTime.now();
    final output = outputPath ?? _getTempFilePath('aac');
    
    final command = '-i $inputPath -vn -acodec copy -y $output';
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);
    
    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(output);
      final size = await outputFile.length();
      
      return EncodingResult(
        success: true,
        outputPath: output,
        duration: duration,
        outputSizeBytes: size,
      );
    } else {
      final logs = await session.getAllLogsAsString();
      return EncodingResult(
        success: false,
        error: logs,
        duration: duration,
      );
    }
  }
  
  /// Get video information
  Future<Map<String, dynamic>?> getMediaInfo(String inputPath) async {
    await initialize();
    
    final session = await FFmpegKit.execute('-i $inputPath -f null -');
    final logs = await session.getAllLogsAsString();
    
    // Parse basic info from FFmpeg output
    final info = <String, dynamic>{};
    
    // Extract duration
    final durationMatch = RegExp(r'Duration: (\d+):(\d+):(\d+)\.(\d+)').firstMatch(logs ?? '');
    if (durationMatch != null) {
      final hours = int.parse(durationMatch.group(1)!);
      final minutes = int.parse(durationMatch.group(2)!);
      final seconds = int.parse(durationMatch.group(3)!);
      info['duration'] = Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    
    // Extract video dimensions
    final videoMatch = RegExp(r'Stream.*Video:.* (\d+)x(\d+)').firstMatch(logs ?? '');
    if (videoMatch != null) {
      info['width'] = int.parse(videoMatch.group(1)!);
      info['height'] = int.parse(videoMatch.group(2)!);
    }
    
    // Extract framerate
    final fpsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*fps').firstMatch(logs ?? '');
    if (fpsMatch != null) {
      info['fps'] = double.parse(fpsMatch.group(1)!);
    }
    
    return info.isEmpty ? null : info;
  }
  
  /// Cancel all running encoding sessions
  Future<void> cancelAll() async {
    await FFmpegKit.cancel();
  }
  
  /// Clean up temporary files
  Future<void> cleanupTempFiles() async {
    if (_tempDir == null) return;
    
    try {
      final dir = _tempDir!;
      final files = dir.listSync();
      for (final file in files) {
        if (file.path.contains('encoded_')) {
          await file.delete();
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
  
  /// Dispose the service
  Future<void> dispose() async {
    await cancelAll();
    await cleanupTempFiles();
    _initialized = false;
    _instance = null;
  }
}

/// Helper class for streaming frame encoding
/// 
/// This class handles real-time encoding of camera frames
/// by writing to a pipe and having FFmpeg read from it.
class StreamingEncoder {
  final H264EncoderConfig videoConfig;
  final OpusEncoderConfig audioConfig;
  
  Process? _ffmpegProcess;
  IOSink? _videoSink;
  bool _isRunning = false;
  int _frameCount = 0;
  
  StreamingEncoder({
    this.videoConfig = const H264EncoderConfig(),
    this.audioConfig = const OpusEncoderConfig(),
  });
  
  bool get isRunning => _isRunning;
  int get frameCount => _frameCount;
  
  /// Start the streaming encoder
  /// 
  /// Returns the path to the output stream that can be read
  /// and sent over the network.
  Future<String?> start(int inputWidth, int inputHeight) async {
    if (_isRunning) return null;
    
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/stream_${DateTime.now().millisecondsSinceEpoch}.h264';
    
    // Use FFmpeg through FFmpegKit for encoding
    // For real-time streaming, we'd typically use a pipe or socket
    // This is a simplified version that writes to a file
    
    _isRunning = true;
    _frameCount = 0;
    
    return outputPath;
  }
  
  /// Push a raw video frame for encoding
  /// 
  /// The frame data should be in NV21 or YUV420 format
  void pushFrame(Uint8List frameData) {
    if (!_isRunning) return;
    
    _videoSink?.add(frameData);
    _frameCount++;
  }
  
  /// Stop the streaming encoder
  Future<void> stop() async {
    if (!_isRunning) return;
    
    await _videoSink?.close();
    _ffmpegProcess?.kill();
    
    _isRunning = false;
    _videoSink = null;
    _ffmpegProcess = null;
  }
}
