import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:cyberfly_streaming/services/iroh_live_streaming_service.dart';

/// Modern streaming screen with integrated iroh-live + FFmpegKit
class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  
  // Service
  final _streamingService = IrohLiveStreamingService.instance;
  
  // State
  bool _isInitialized = false;
  String? _error;
  StreamingStatus _status = StreamingStatus.idle;
  StreamingStats _stats = const StreamingStats();
  
  // Broadcast state
  String? _broadcastTicket;
  String _broadcastName = 'my_stream';
  
  // Subscribe state
  final TextEditingController _ticketController = TextEditingController();
  IrohLiveSubscriptionService? _subscription;
  ui.Image? _receivedFrame;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
    
    // Set up service callbacks
    _streamingService.onStatusChanged = (status) {
      if (mounted) {
        setState(() => _status = status);
      }
    };
    
    _streamingService.onStatsUpdated = (stats) {
      if (mounted) {
        setState(() => _stats = stats);
      }
    };
    
    _streamingService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    };
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _ticketController.dispose();
    _subscription?.disconnect();
    super.dispose();
  }
  
  Future<void> _initialize() async {
    try {
      await _streamingService.initialize();
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('P2P Live Streaming'),
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
          tabs: const [
            Tab(icon: Icon(Icons.videocam), text: 'Broadcast'),
            Tab(icon: Icon(Icons.play_circle), text: 'Watch'),
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
                      _buildBroadcastTab(),
                      _buildWatchTab(),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================================
  // Broadcast Tab
  // ============================================================================
  
  Widget _buildBroadcastTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Camera Preview
          _buildCameraPreview(),
          const SizedBox(height: 16),
          
          // Status Card
          _buildStatusCard(),
          const SizedBox(height: 16),
          
          // Controls
          _buildBroadcastControls(),
          const SizedBox(height: 16),
          
          // Stats
          if (_status == StreamingStatus.streaming)
            _buildStatsCard(),
          
          // Share Ticket
          if (_broadcastTicket != null)
            _buildShareTicketCard(),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview() {
    final cameraController = _streamingService.cameraController;
    
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Column(
        children: [
          Container(
            height: 280,
            width: double.infinity,
            color: Colors.black,
            child: cameraController != null && cameraController.value.isInitialized
                ? ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: AspectRatio(
                      aspectRatio: cameraController.value.aspectRatio,
                      child: CameraPreview(cameraController),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off, size: 64, color: Colors.white24),
                        SizedBox(height: 8),
                        Text('Camera not started', style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
          ),
          // Live indicator
          if (_status == StreamingStatus.streaming)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                  SizedBox(width: 8),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getStatusColor(),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _getStatusText(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Spacer(),
            if (_status == StreamingStatus.streaming)
              Text(
                '${_stats.currentFps.toStringAsFixed(1)} fps',
                style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
  
  Color _getStatusColor() {
    switch (_status) {
      case StreamingStatus.idle:
        return Colors.grey;
      case StreamingStatus.initializing:
        return Colors.orange;
      case StreamingStatus.capturing:
        return Colors.blue;
      case StreamingStatus.encoding:
        return Colors.purple;
      case StreamingStatus.streaming:
        return const Color(0xFF22C55E);
      case StreamingStatus.error:
        return Colors.red;
    }
  }
  
  String _getStatusText() {
    switch (_status) {
      case StreamingStatus.idle:
        return 'Ready';
      case StreamingStatus.initializing:
        return 'Initializing...';
      case StreamingStatus.capturing:
        return 'Camera active';
      case StreamingStatus.encoding:
        return 'Starting stream...';
      case StreamingStatus.streaming:
        return 'Broadcasting';
      case StreamingStatus.error:
        return 'Error';
    }
  }
  
  Widget _buildBroadcastControls() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Broadcast name input
            TextField(
              decoration: InputDecoration(
                labelText: 'Stream Name',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: 'Enter a name for your stream',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.tag, color: Color(0xFF6366F1)),
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
              style: const TextStyle(color: Colors.white),
              onChanged: (value) => _broadcastName = value.isEmpty ? 'my_stream' : value,
            ),
            const SizedBox(height: 16),
            
            // Control buttons
            Row(
              children: [
                // Camera button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _status == StreamingStatus.streaming
                        ? null
                        : (_status == StreamingStatus.capturing
                            ? _stopCamera
                            : _startCamera),
                    icon: Icon(
                      _status == StreamingStatus.capturing
                          ? Icons.videocam_off
                          : Icons.videocam,
                    ),
                    label: Text(
                      _status == StreamingStatus.capturing ? 'Stop Camera' : 'Start Camera',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _status == StreamingStatus.capturing
                          ? Colors.orange
                          : const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Go Live button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _status == StreamingStatus.capturing
                        ? _startBroadcast
                        : (_status == StreamingStatus.streaming ? _stopBroadcast : null),
                    icon: Icon(
                      _status == StreamingStatus.streaming
                          ? Icons.stop
                          : Icons.broadcast_on_personal,
                    ),
                    label: Text(
                      _status == StreamingStatus.streaming ? 'Stop' : 'Go Live',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _status == StreamingStatus.streaming
                          ? Colors.red
                          : const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Color(0xFF6366F1)),
                SizedBox(width: 8),
                Text(
                  'Stream Statistics',
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
                _buildStatItem('Frames', '${_stats.framesSent}', Icons.image),
                _buildStatItem('Data', _stats.bytesFormatted, Icons.data_usage),
                _buildStatItem('FPS', _stats.currentFps.toStringAsFixed(1), Icons.speed),
                _buildStatItem('Latency', '${_stats.encodingLatencyMs}ms', Icons.timer),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Uptime: ${_formatDuration(_stats.uptime)}',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
  
  Widget _buildShareTicketCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.share, color: Color(0xFF22C55E)),
                SizedBox(width: 8),
                Text(
                  'Share Your Stream',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Share this ticket with viewers:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _broadcastTicket!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFF6366F1)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _broadcastTicket!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ticket copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================================
  // Watch Tab
  // ============================================================================
  
  Widget _buildWatchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video Player
          _buildVideoPlayer(),
          const SizedBox(height: 16),
          
          // Join Stream Controls
          _buildJoinControls(),
        ],
      ),
    );
  }
  
  Widget _buildVideoPlayer() {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Container(
        height: 280,
        width: double.infinity,
        color: Colors.black,
        child: _receivedFrame != null
            ? RawImage(image: _receivedFrame, fit: BoxFit.contain)
            : const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.live_tv, size: 64, color: Colors.white24),
                    SizedBox(height: 8),
                    Text('Enter a stream ticket to watch', style: TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
      ),
    );
  }
  
  Widget _buildJoinControls() {
    final isConnected = _subscription?.status == StreamingStatus.streaming;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link, color: Color(0xFF6366F1)),
                SizedBox(width: 8),
                Text(
                  'Join a Stream',
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
              controller: _ticketController,
              decoration: InputDecoration(
                labelText: 'Stream Ticket',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: 'Paste the broadcast ticket here',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.qr_code, color: Color(0xFF6366F1)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste, color: Color(0xFF6366F1)),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _ticketController.text = data!.text!;
                    }
                  },
                ),
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
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isConnected ? _leaveStream : _joinStream,
                icon: Icon(isConnected ? Icons.close : Icons.play_arrow),
                label: Text(isConnected ? 'Leave Stream' : 'Join Stream'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.red : const Color(0xFF22C55E),
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
  
  // ============================================================================
  // Actions
  // ============================================================================
  
  Future<void> _startCamera() async {
    await _streamingService.startCameraPreview();
    setState(() {});
  }
  
  Future<void> _stopCamera() async {
    await _streamingService.stopCameraPreview();
    setState(() {});
  }
  
  Future<void> _startBroadcast() async {
    final ticket = await _streamingService.startBroadcast(
      broadcastName: _broadcastName,
    );
    
    if (ticket != null) {
      setState(() => _broadcastTicket = ticket);
    }
  }
  
  Future<void> _stopBroadcast() async {
    await _streamingService.stopBroadcast();
    setState(() => _broadcastTicket = null);
  }
  
  Future<void> _joinStream() async {
    final ticket = _ticketController.text.trim();
    if (ticket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a stream ticket')),
      );
      return;
    }
    
    _subscription = IrohLiveSubscriptionService(
      subscriberId: 'sub_${DateTime.now().millisecondsSinceEpoch}',
      broadcastTicket: ticket,
    );
    
    _subscription!.onVideoFrame = (data, width, height) {
      // Convert to ui.Image for display
      ui.decodeImageFromPixels(
        data,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (image) {
          if (mounted) {
            setState(() => _receivedFrame = image);
          }
        },
      );
    };
    
    _subscription!.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    };
    
    final success = await _subscription!.connect();
    if (!success) {
      _subscription = null;
    }
    setState(() {});
  }
  
  Future<void> _leaveStream() async {
    await _subscription?.disconnect();
    _subscription = null;
    _receivedFrame = null;
    setState(() {});
  }
  
  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
