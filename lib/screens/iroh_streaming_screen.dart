import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:cyberfly_streaming/src/rust/api/iroh_live_flutter_api.dart';

/// Main streaming screen using the new iroh-live inspired API
class IrohStreamingScreen extends StatefulWidget {
  const IrohStreamingScreen({super.key});

  @override
  State<IrohStreamingScreen> createState() => _IrohStreamingScreenState();
}

class _IrohStreamingScreenState extends State<IrohStreamingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // State
  bool _isInitialized = false;
  String? _error;
  
  // Capture state
  List<FlutterCaptureDevice> _captureDevices = [];
  String? _activeDevice;
  ui.Image? _previewImage;
  Timer? _previewTimer;
  int _frameWidth = 0;
  int _frameHeight = 0;
  
  // Real camera state
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraPreview = false;
  
  // Publisher state
  final Map<String, FlutterPublisherStatus> _publishers = {};
  
  // Subscriber state
  final Map<String, FlutterSubscriberStatus> _subscribers = {};
  Timer? _subscriberUpdateTimer;
  
  // Settings
  String _selectedVideoPreset = 'P720';
  String _selectedAudioPreset = 'opus_hq';
  List<FlutterVideoRendition> _videoPresets = [];
  List<FlutterAudioRendition> _audioPresets = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initialize();
  }
  
  @override
  void dispose() {
    _previewTimer?.cancel();
    _cameraController?.dispose();
    _subscriberUpdateTimer?.cancel();
    _tabController.dispose();
    // Shutdown iroh-live node
    irohNodeShutdown().catchError((e) {
      debugPrint('Error shutting down iroh node: $e');
    });
    super.dispose();
  }
  
  Future<void> _initialize() async {
    try {
      // Initialize the iroh-live node first
      String? endpointId;
      try {
        endpointId = await irohNodeInit();
        debugPrint('Iroh-live node initialized: $endpointId');
      } catch (e) {
        debugPrint('Failed to initialize iroh-live node: $e');
        // Continue with mock mode
      }
      
      // Initialize capture system
      final success = irohCaptureInit();
      if (!success) {
        throw Exception('Failed to initialize capture system');
      }
      
      // Get available cameras
      _cameras = await availableCameras();
      
      // Load devices
      _captureDevices = irohCaptureListDevices();
      
      // Load presets
      _videoPresets = irohGetVideoPresets();
      _audioPresets = irohGetAudioPresets();
      
      setState(() {
        _isInitialized = true;
        if (endpointId != null) {
          // Could store endpoint ID if needed
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Iroh Live Streaming'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.videocam), text: 'Capture'),
            Tab(icon: Icon(Icons.upload), text: 'Publish'),
            Tab(icon: Icon(Icons.download), text: 'Subscribe'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F0F1A), Color(0xFF1E1E2E)],
          ),
        ),
        child: _error != null
            ? _buildErrorView()
            : !_isInitialized
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCaptureTab(),
                      _buildPublishTab(),
                      _buildSubscribeTab(),
                      _buildSettingsTab(),
                    ],
                  ),
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _error = null;
                  _isInitialized = false;
                });
                _initialize();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================================
  // Capture Tab
  // ============================================================================
  
  Widget _buildCaptureTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview area
          _buildPreviewCard(),
          const SizedBox(height: 16),
          
          // Device selector
          _buildDeviceSelectorCard(),
          const SizedBox(height: 16),
          
          // Capture controls
          _buildCaptureControlsCard(),
        ],
      ),
    );
  }
  
  Widget _buildPreviewCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Column(
        children: [
          Container(
            height: 240,
            width: double.infinity,
            color: Colors.black,
            child: _buildPreviewContent(),
          ),
          _buildPreviewInfo(),
        ],
      ),
    );
  }
  
  Widget _buildPreviewContent() {
    // Show real camera preview if camera is active
    if (_isCameraPreview && _cameraController != null && _cameraController!.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 240,
            height: _cameraController!.value.previewSize?.width ?? 320,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }
    
    // Show test pattern preview
    if (_previewImage != null) {
      return RawImage(
        image: _previewImage,
        fit: BoxFit.contain,
      );
    }
    
    // No preview
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'Select a device to preview',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreviewInfo() {
    if (_isCameraPreview && _cameraController != null && _cameraController!.value.isInitialized) {
      final size = _cameraController!.value.previewSize;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: Colors.black54,
        child: Text(
          '${size?.width.toInt() ?? 0}x${size?.height.toInt() ?? 0} | Camera | Live',
          style: const TextStyle(color: Colors.white, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    if (_previewImage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: Colors.black54,
        child: Text(
          '${_frameWidth}x$_frameHeight | Test Pattern | Live',
          style: const TextStyle(color: Colors.white, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
  
  Widget _buildDeviceSelectorCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                const Text(
                  'Capture Devices',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_captureDevices.isEmpty)
              const Text('No devices found', style: TextStyle(color: Colors.white70))
            else
              ..._captureDevices.map((device) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: device.id == _activeDevice 
                      ? const Color(0xFF6366F1).withValues(alpha: 0.2) 
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: device.id == _activeDevice 
                        ? const Color(0xFF6366F1) 
                        : Colors.transparent,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    _getDeviceIcon(device.deviceType),
                    color: device.id == _activeDevice ? const Color(0xFF6366F1) : Colors.white70,
                  ),
                  title: Text(
                    device.name,
                    style: TextStyle(
                      color: device.id == _activeDevice ? Colors.white : Colors.white70,
                      fontWeight: device.id == _activeDevice ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    device.deviceType,
                    style: TextStyle(
                      color: device.id == _activeDevice ? Colors.white70 : Colors.white38,
                    ),
                  ),
                  trailing: device.id == _activeDevice
                      ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
                      : device.isDefault
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Default', style: TextStyle(fontSize: 10, color: Colors.white70)),
                            )
                          : null,
                  selected: device.id == _activeDevice,
                  onTap: () => _selectDevice(device.id),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )),
          ],
        ),
      ),
    );
  }
  
  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType) {
      case 'camera':
        return Icons.camera_alt;
      case 'screen':
        return Icons.desktop_windows;
      case 'test_pattern':
        return Icons.pattern;
      default:
        return Icons.devices;
    }
  }
  
  Widget _buildCaptureControlsCard() {
    final isCapturing = _activeDevice != null && (_previewTimer != null || _isCameraPreview);
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_input_component, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                const Text(
                  'Capture Controls',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _activeDevice != null
                        ? (isCapturing ? _stopCapture : _startCapture)
                        : null,
                    icon: Icon(isCapturing ? Icons.stop : Icons.play_arrow),
                    label: Text(isCapturing ? 'Stop Capture' : 'Start Capture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCapturing ? Colors.red : const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Status: ${isCapturing ? "Capturing from $_activeDevice" : "Idle"}',
              style: TextStyle(
                color: isCapturing ? const Color(0xFF22C55E) : Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _selectDevice(String deviceId) async {
    // Stop any existing capture first
    await _stopCapture();
    
    final success = irohCaptureStart(deviceId: deviceId);
    if (success) {
      setState(() {
        _activeDevice = deviceId;
      });
      // Automatically start preview when device is selected
      await _startCapture();
    }
  }
  
  Future<void> _startCapture() async {
    if (_activeDevice == null) return;
    
    // Check if this is a real camera device
    if (_activeDevice!.contains('camera_front') || _activeDevice!.contains('camera_back')) {
      await _startRealCamera();
      return;
    }
    
    // For test patterns, use simulated frames
    _startTestPatternCapture();
  }
  
  Future<void> _startRealCamera() async {
    if (_cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cameras available on this device')),
        );
      }
      return;
    }
    
    try {
      // Find the appropriate camera
      CameraDescription? selectedCamera;
      
      if (_activeDevice!.contains('front')) {
        selectedCamera = _cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        selectedCamera = _cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
      }
      
      // Dispose old controller if exists
      await _cameraController?.dispose();
      
      // Create new camera controller
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraPreview = true;
          _previewImage = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start camera: $e')),
        );
      }
      // Fall back to test pattern
      _startTestPatternCapture();
    }
  }
  
  void _startTestPatternCapture() {
    // Determine pattern from device ID
    String pattern = 'color_bars';
    if (_activeDevice!.contains('gradient')) {
      pattern = 'gradient';
    } else if (_activeDevice!.contains('moving_box')) {
      pattern = 'moving_box';
    } else if (_activeDevice!.contains('screen')) {
      pattern = 'gradient';
    }
    
    setState(() {
      _isCameraPreview = false;
    });
    
    // Start preview timer - REDUCED RATE to 100ms (10fps) to prevent lag
    _previewTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      try {
        final frame = irohCaptureGetTestFrame(
          width: 320, // Reduced resolution for preview
          height: 180,
          pattern: pattern,
        );
        
        // Convert raw bytes to ui.Image for efficient rendering
        ui.decodeImageFromPixels(
          frame.data,
          frame.width,
          frame.height,
          ui.PixelFormat.rgba8888,
          (image) {
            if (mounted) {
              setState(() {
                _previewImage = image;
                _frameWidth = frame.width;
                _frameHeight = frame.height;
              });
            }
          },
        );
      } catch (e) {
        debugPrint('Error getting frame: $e');
      }
    });
  }
  
  Future<void> _stopCapture() async {
    // Stop test pattern timer
    _previewTimer?.cancel();
    _previewTimer = null;
    
    // Stop real camera
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    
    irohCaptureStop();
    
    setState(() {
      _previewImage = null;
      _isCameraPreview = false;
    });
  }
  
  // ============================================================================
  // Publish Tab
  // ============================================================================
  
  Widget _buildPublishTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Create publisher card
          _buildCreatePublisherCard(),
          const SizedBox(height: 16),
          
          // Active publishers
          _buildActivePublishersCard(),
        ],
      ),
    );
  }
  
  Widget _buildCreatePublisherCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_circle, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                const Text(
                  'Create Publisher',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Video Quality',
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedVideoPreset,
                  dropdownColor: const Color(0xFF2E2E3E),
                  style: const TextStyle(color: Colors.white),
                  isDense: true,
                  items: _videoPresets.map((preset) {
                    return DropdownMenuItem(
                      value: preset.name,
                      child: Text('${preset.name} (${preset.width}x${preset.height} @ ${preset.fps}fps)'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVideoPreset = value!;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Audio Quality',
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedAudioPreset,
                  dropdownColor: const Color(0xFF2E2E3E),
                  style: const TextStyle(color: Colors.white),
                  isDense: true,
                  items: _audioPresets.map((preset) {
                    return DropdownMenuItem(
                      value: preset.name,
                      child: Text('${preset.name} (${preset.sampleRate}Hz, ${preset.channels}ch)'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedAudioPreset = value!;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createPublisher,
                icon: const Icon(Icons.add),
                label: const Text('Create Publisher'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _createPublisher() async {
    final publisherId = 'publisher_${DateTime.now().millisecondsSinceEpoch}';
    final broadcastName = 'broadcast_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // Try to use the async version with real iroh-live backend
      final ticket = await irohPublishCreateAsync(
        publisherId: publisherId,
        broadcastName: broadcastName,
      );
      
      // Start publishing
      await irohPublishStartAsync(publisherId: publisherId);
      
      // Update UI
      _refreshPublisherStatus(publisherId);
      
      if (mounted) {
        // Show ticket for sharing
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Broadcast Created!', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share this ticket with subscribers:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    ticket,
                    style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF22C55E), fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ticket));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ticket copied to clipboard!')),
                  );
                },
                child: const Text('Copy & Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Publisher creation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create publisher: $e')),
        );
      }
    }
  }
  
  void _refreshPublisherStatus(String publisherId) {
    final status = irohPublishGetStatus(publisherId: publisherId);
    if (status != null) {
      setState(() {
        _publishers[publisherId] = status;
      });
    }
  }
  
  Widget _buildActivePublishersCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.live_tv, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(
                  'Active Publishers (${_publishers.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_publishers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No active publishers', style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              ..._publishers.entries.map((entry) => _buildPublisherTile(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPublisherTile(String publisherId, FlutterPublisherStatus status) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: status.isActive 
            ? const Color(0xFF22C55E).withValues(alpha: 0.1) 
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status.isActive ? const Color(0xFF22C55E) : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: Icon(
          status.isActive ? Icons.broadcast_on_personal : Icons.broadcast_on_home,
          color: status.isActive ? const Color(0xFF22C55E) : Colors.grey,
        ),
        title: Text(
          publisherId.length > 20 ? '${publisherId.substring(0, 20)}...' : publisherId,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'ID: $publisherId',
              style: const TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              'Frames: ${status.framesPublished} | Bytes: ${_formatBytes(status.bytesSent)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              'Bitrate: ${_formatBitrate(status.currentBitrate)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              'Renditions: ${status.videoRenditions.join(", ")}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white70),
              tooltip: 'Copy Broadcast ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: publisherId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Broadcast ID copied: ${publisherId.length > 30 ? '${publisherId.substring(0, 30)}...' : publisherId}'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF22C55E),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(status.isActive ? Icons.stop : Icons.play_arrow),
              color: status.isActive ? Colors.red : const Color(0xFF22C55E),
              onPressed: () async {
                if (status.isActive) {
                  await irohPublishStopAsync(publisherId: publisherId);
                } else {
                  await irohPublishStartAsync(publisherId: publisherId);
                }
                _refreshPublisherStatus(publisherId);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                irohPublishRemove(publisherId: publisherId);
                setState(() {
                  _publishers.remove(publisherId);
                });
              },
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
  
  // ============================================================================
  // Subscribe Tab
  // ============================================================================
  
  Widget _buildSubscribeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Join broadcast card
          _buildJoinBroadcastCard(),
          const SizedBox(height: 16),
          
          // Active subscriptions
          _buildActiveSubscriptionsCard(),
        ],
      ),
    );
  }
  
  Widget _buildJoinBroadcastCard() {
    final TextEditingController broadcastIdController = TextEditingController();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_link, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                const Text(
                  'Join Broadcast',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: broadcastIdController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Broadcast ID',
                hintText: 'Enter broadcast ID to subscribe',
                labelStyle: const TextStyle(color: Colors.white70),
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _createSubscriber(broadcastIdController.text),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Subscribe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _createSubscriber(String broadcastId) async {
    if (broadcastId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a broadcast ID')),
      );
      return;
    }
    
    final subscriberId = 'subscriber_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // Parse the ticket to get broadcast name and endpoint (sync function)
      final ticketInfo = irohTicketParse(ticketString: broadcastId);
      debugPrint('Parsed ticket: broadcast=${ticketInfo?.broadcastName}, endpoint=${ticketInfo?.endpointId}');
      
      // Create subscriber
      await irohSubscribeCreateAsync(
        subscriberId: subscriberId,
        broadcastId: broadcastId,
      );
      
      // Connect to the publisher with ticket
      await irohSubscribeConnectAsync(
        subscriberId: subscriberId,
        ticketString: broadcastId,
      );
      _refreshSubscriberStatus(subscriberId);
      _startSubscriberUpdateTimer();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to: ${ticketInfo?.broadcastName ?? broadcastId}')),
        );
      }
    } catch (e) {
      debugPrint('Error subscribing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to subscribe: $e')),
        );
      }
    }
  }
  
  void _startSubscriberUpdateTimer() {
    _subscriberUpdateTimer?.cancel();
    _subscriberUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_subscribers.isEmpty) {
        timer.cancel();
        return;
      }
      
      // Simulate frame reception for connected subscribers
      for (final entry in _subscribers.entries) {
        if (entry.value.isConnected) {
          // Simulate receiving ~30fps video at ~200KB per frame
          irohSubscribeSimulateVideoReceive(
            subscriberId: entry.key,
            frameSize: BigInt.from(200000),
          );
        }
      }
      
      // Refresh all subscriber statuses
      if (mounted) {
        setState(() {
          for (final subscriberId in _subscribers.keys.toList()) {
            final status = irohSubscribeGetStatus(subscriberId: subscriberId);
            if (status != null) {
              _subscribers[subscriberId] = status;
            }
          }
        });
      }
    });
  }
  
  void _refreshSubscriberStatus(String subscriberId) {
    final status = irohSubscribeGetStatus(subscriberId: subscriberId);
    if (status != null) {
      setState(() {
        _subscribers[subscriberId] = status;
      });
    }
  }
  
  Widget _buildActiveSubscriptionsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.subscriptions, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(
                  'Active Subscriptions (${_subscribers.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_subscribers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No active subscriptions', style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              ..._subscribers.entries.map((entry) => _buildSubscriberTile(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSubscriberTile(String subscriberId, FlutterSubscriberStatus status) {
    // Check if this is a local broadcast (from our own publishers)
    final isLocalBroadcast = _publishers.keys.any((pid) => pid == status.broadcastId);
    final hasVideoPreview = isLocalBroadcast && _isCameraPreview && _cameraController != null && _cameraController!.value.isInitialized;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: status.isConnected 
            ? const Color(0xFF3B82F6).withValues(alpha: 0.1) 
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status.isConnected ? const Color(0xFF3B82F6) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video preview area
          if (status.isConnected)
            Container(
              height: 200,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: hasVideoPreview
                  ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      child: CameraPreview(_cameraController!),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isLocalBroadcast ? Icons.videocam_off : Icons.cloud_download,
                            size: 48,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isLocalBroadcast 
                                ? 'Camera not active on publisher' 
                                : 'Connecting to remote stream...',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          if (!isLocalBroadcast) ...[
                            const SizedBox(height: 8),
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          
          // Info and controls
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Broadcast ID with copy button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Broadcast: ${status.broadcastId}',
                        style: const TextStyle(
                          fontFamily: 'monospace', 
                          fontSize: 11, 
                          color: Color(0xFF3B82F6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLocalBroadcast)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LOCAL',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Stats row
                Row(
                  children: [
                    _buildStatChip(Icons.movie, '${status.framesReceived}', 'frames'),
                    const SizedBox(width: 8),
                    _buildStatChip(Icons.data_usage, _formatBytes(status.bytesReceived), 'received'),
                    const SizedBox(width: 8),
                    _buildStatChip(Icons.high_quality, status.currentQuality, 'quality'),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Buffer health indicator
                Row(
                  children: [
                    const Text('Buffer: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: status.bufferHealth,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          status.bufferHealth > 0.5 ? const Color(0xFF22C55E) : Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(status.bufferHealth * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Connection status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: status.isConnected 
                            ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status.isConnected ? Icons.wifi : Icons.wifi_off,
                            size: 12,
                            color: status.isConnected ? const Color(0xFF22C55E) : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status.isConnected ? 'Connected' : 'Disconnected',
                            style: TextStyle(
                              fontSize: 10,
                              color: status.isConnected ? const Color(0xFF22C55E) : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    
                    // Pause/Play button
                    IconButton(
                      icon: Icon(status.isConnected ? Icons.pause_circle : Icons.play_circle),
                      iconSize: 32,
                      color: status.isConnected ? Colors.orange : const Color(0xFF22C55E),
                      onPressed: () async {
                        if (status.isConnected) {
                          await irohSubscribeDisconnectAsync(subscriberId: subscriberId);
                        } else {
                          // Use the broadcastId (ticket) stored in status to reconnect
                          await irohSubscribeConnectAsync(
                            subscriberId: subscriberId,
                            ticketString: status.broadcastId,
                          );
                        }
                        _refreshSubscriberStatus(subscriberId);
                      },
                    ),
                    
                    // Delete button
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 28,
                      color: Colors.red,
                      onPressed: () {
                        irohSubscribeRemove(subscriberId: subscriberId);
                        setState(() {
                          _subscribers.remove(subscriberId);
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // Settings Tab
  // ============================================================================
  
  Widget _buildSettingsTab() {
    final version = irohGetVersion();
    final features = irohGetFeatures();
    final videoCodecs = irohGetSupportedVideoCodecs();
    final audioCodecs = irohGetSupportedAudioCodecs();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Library info
          _buildInfoCard('Library Info', [
            _buildInfoRow('Version', version),
            _buildInfoRow('Video Codecs', videoCodecs.join(', ')),
            _buildInfoRow('Audio Codecs', audioCodecs.join(', ')),
          ]),
          const SizedBox(height: 16),
          
          // Features
          _buildFeaturesCard(features),
          const SizedBox(height: 16),
          
          // Video presets
          _buildPresetsCard('Video Presets', _videoPresets.map((p) => 
            '${p.name}: ${p.width}x${p.height} @ ${p.fps}fps, ${_formatBitrate(p.bitrate)}'
          ).toList()),
          const SizedBox(height: 16),
          
          // Audio presets
          _buildPresetsCard('Audio Presets', _audioPresets.map((p) => 
            '${p.name}: ${p.sampleRate}Hz, ${p.channels}ch, ${_formatBitrate(p.bitrate)}'
          ).toList()),
          const SizedBox(height: 16),
          
          // Codec HW acceleration
          _buildCodecAccelerationCard(videoCodecs),
        ],
      ),
    );
  }
  
  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
  
  Widget _buildFeaturesCard(Map<String, bool> features) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Features', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: features.entries.map((entry) {
                return Chip(
                  avatar: Icon(
                    entry.value ? Icons.check_circle : Icons.cancel,
                    color: entry.value ? const Color(0xFF22C55E) : Colors.red,
                    size: 18,
                  ),
                  label: Text(entry.key, style: TextStyle(color: entry.value ? const Color(0xFF22C55E) : Colors.red)),
                  backgroundColor: entry.value ? const Color(0xFF22C55E).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPresetsCard(String title, List<String> presets) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            ...presets.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $p', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70)),
            )),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCodecAccelerationCard(List<String> codecs) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Codec Hardware Acceleration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            ...codecs.map((codec) {
              final isHwAccelerated = irohIsCodecHwAccelerated(codec: codec);
              return ListTile(
                dense: true,
                leading: Icon(
                  isHwAccelerated ? Icons.bolt : Icons.memory,
                  color: isHwAccelerated ? Colors.amber : Colors.grey,
                ),
                title: Text(codec.toUpperCase(), style: const TextStyle(color: Colors.white)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHwAccelerated ? Colors.amber.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isHwAccelerated ? 'HW' : 'SW',
                    style: TextStyle(
                      color: isHwAccelerated ? Colors.amber : Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
  
  // ============================================================================
  // Helpers
  // ============================================================================
  
  String _formatBytes(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  String _formatBitrate(int bps) {
    if (bps < 1000) return '$bps bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)} Kbps';
    return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  }
}
