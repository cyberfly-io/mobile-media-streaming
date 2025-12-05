import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera service for capturing video frames
class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _supportsImageStream = false;
  int _currentCameraIndex = 0;
  Timer? _frameTimer;
  
  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  bool get supportsImageStream => _supportsImageStream;
  List<CameraDescription> get cameras => _cameras;
  int get currentCameraIndex => _currentCameraIndex;
  
  /// Stream of camera frames (JPEG bytes)
  Stream<Uint8List> get frameStream => _frameController.stream;

  /// Request camera permissions
  Future<bool> requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    
    return cameraStatus.isGranted && micStatus.isGranted;
  }

  /// Check if permissions are granted
  Future<bool> hasPermissions() async {
    final camera = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    return camera && mic;
  }

  /// Initialize the camera service
  Future<void> initialize({
    ResolutionPreset resolution = ResolutionPreset.medium,
    bool enableAudio = true,
  }) async {
    if (_isInitialized) return;
    
    try {
      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('NoCameras', 'No cameras available on this device');
      }
      
      // Initialize with back camera by default, or front if back not available
      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_currentCameraIndex == -1) {
        _currentCameraIndex = 0;
      }
      
      await _initializeController(resolution, enableAudio);
      _isInitialized = true;
      debugPrint('[CameraService] Initialized with ${_cameras.length} cameras');
    } catch (e) {
      debugPrint('[CameraService] Failed to initialize: $e');
      rethrow;
    }
  }

  Future<void> _initializeController(
    ResolutionPreset resolution,
    bool enableAudio,
  ) async {
    _controller?.dispose();
    
    _controller = CameraController(
      _cameras[_currentCameraIndex],
      resolution,
      enableAudio: enableAudio,
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.nv21  // Better compatibility on Android
          : ImageFormatGroup.bgra8888,
    );
    
    await _controller!.initialize();
    
    // Check if image streaming is supported
    // CameraX on some devices doesn't support startImageStream
    _supportsImageStream = true; // Assume supported, will catch error if not
  }

  /// Switch between front and back cameras
  Future<void> switchCamera({
    ResolutionPreset resolution = ResolutionPreset.medium,
    bool enableAudio = true,
  }) async {
    if (_cameras.length < 2) return;
    
    final wasStreaming = _isStreaming;
    if (wasStreaming) {
      await stopImageStream();
    }
    
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initializeController(resolution, enableAudio);
    
    if (wasStreaming) {
      await startImageStream();
    }
    
    debugPrint('[CameraService] Switched to camera $_currentCameraIndex');
  }

  /// Get the current camera direction
  CameraLensDirection get currentLensDirection {
    if (!_isInitialized || _cameras.isEmpty) {
      return CameraLensDirection.back;
    }
    return _cameras[_currentCameraIndex].lensDirection;
  }

  /// Start streaming camera images
  /// Uses native image stream if supported, otherwise falls back to taking pictures
  Future<void> startImageStream() async {
    if (!_isInitialized || _controller == null) {
      throw CameraException('NotInitialized', 'Camera not initialized');
    }
    
    if (_isStreaming) return;
    
    // Try native image streaming first
    if (_supportsImageStream) {
      try {
        await _controller!.startImageStream((CameraImage image) async {
          if (!_frameController.isClosed) {
            // Convert CameraImage to bytes
            final bytes = _convertCameraImageToBytes(image);
            if (bytes != null) {
              _frameController.add(bytes);
            }
          }
        });
        _isStreaming = true;
        debugPrint('[CameraService] Started native image stream');
        return;
      } catch (e) {
        debugPrint('[CameraService] Native image stream not supported: $e');
        _supportsImageStream = false;
        // Fall through to picture-based streaming
      }
    }
    
    // Fallback: Take pictures at intervals for streaming
    debugPrint('[CameraService] Using picture-based streaming fallback');
    _isStreaming = true;
    _startPictureBasedStream();
  }
  
  /// Fallback streaming using rapid picture capture
  void _startPictureBasedStream() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_isStreaming || _controller == null || _frameController.isClosed) {
        _frameTimer?.cancel();
        return;
      }
      
      try {
        final file = await _controller!.takePicture();
        final bytes = await File(file.path).readAsBytes();
        if (!_frameController.isClosed) {
          _frameController.add(bytes);
        }
        // Clean up the temporary file
        try {
          await File(file.path).delete();
        } catch (_) {}
      } catch (e) {
        // Ignore errors during streaming, just skip this frame
        debugPrint('[CameraService] Frame capture error: $e');
      }
    });
  }
  
  /// Convert CameraImage to raw bytes
  Uint8List? _convertCameraImageToBytes(CameraImage image) {
    try {
      // Combine all planes into a single byte array
      int totalBytes = 0;
      for (final plane in image.planes) {
        totalBytes += plane.bytes.length;
      }
      
      final bytes = Uint8List(totalBytes);
      int offset = 0;
      for (final plane in image.planes) {
        bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }
      return bytes;
    } catch (e) {
      debugPrint('[CameraService] Error converting image: $e');
      return null;
    }
  }

  /// Stop streaming camera images
  Future<void> stopImageStream() async {
    if (!_isStreaming || _controller == null) return;
    
    // Cancel picture-based streaming timer
    _frameTimer?.cancel();
    _frameTimer = null;
    
    // Stop native image stream if it was used
    if (_supportsImageStream) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint('[CameraService] Error stopping native stream: $e');
      }
    }
    
    _isStreaming = false;
    debugPrint('[CameraService] Stopped image stream');
  }

  /// Take a picture
  Future<XFile?> takePicture() async {
    if (!_isInitialized || _controller == null) return null;
    
    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint('[CameraService] Failed to take picture: $e');
      return null;
    }
  }

  /// Start video recording
  Future<void> startVideoRecording() async {
    if (!_isInitialized || _controller == null) return;
    
    try {
      await _controller!.startVideoRecording();
      debugPrint('[CameraService] Started video recording');
    } catch (e) {
      debugPrint('[CameraService] Failed to start recording: $e');
      rethrow;
    }
  }

  /// Stop video recording and return the file
  Future<XFile?> stopVideoRecording() async {
    if (_controller == null) return null;
    
    try {
      final file = await _controller!.stopVideoRecording();
      debugPrint('[CameraService] Stopped video recording: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('[CameraService] Failed to stop recording: $e');
      return null;
    }
  }

  /// Set flash mode
  Future<void> setFlashMode(FlashMode mode) async {
    if (_controller == null) return;
    await _controller!.setFlashMode(mode);
  }

  /// Set zoom level (0.0 to 1.0 normalized)
  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null) return;
    final minZoom = await _controller!.getMinZoomLevel();
    final maxZoom = await _controller!.getMaxZoomLevel();
    final zoomLevel = minZoom + (maxZoom - minZoom) * zoom;
    await _controller!.setZoomLevel(zoomLevel);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stopImageStream();
    _frameTimer?.cancel();
    _frameTimer = null;
    if (!_frameController.isClosed) {
      _frameController.close();
    }
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    debugPrint('[CameraService] Disposed');
  }
}
