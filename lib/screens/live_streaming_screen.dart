import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cyberfly_streaming/services/streaming_service.dart';
import 'package:cyberfly_streaming/services/webrtc_service.dart';
import 'package:cyberfly_streaming/src/rust/api/flutter_api.dart' as rust_api;

/// Live streaming screen using WebRTC for video/audio
/// Compatible with cyberfly-node-web-dashboard
class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen>
    with WidgetsBindingObserver {
  final StreamingService _streamingService = StreamingService();
  final WebRTCService _webrtcService = WebRTCService();
  final TextEditingController _nameController =
      TextEditingController(text: 'Flutter User');
  final TextEditingController _ticketController = TextEditingController();

  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isBroadcasting = false;
  bool _isWatching = false;
  String? _endpointId;
  String? _streamTicket;
  String? _error;
  String _selectedQuality = 'medium';
  String _connectionState = '';
  int _neighborCount = 0;
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _useCamera = true; // true = camera, false = screen share
  
  StreamSubscription<rust_api.FlutterStreamEvent>? _eventSubscription;
  Timer? _presenceTimer;
  Timer? _offerRetryTimer;
  int _offerRetryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    _nameController.dispose();
    _ticketController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Optionally pause video when app is inactive
    } else if (state == AppLifecycleState.resumed) {
      // Resume video when app is active
    }
  }

  Future<void> _initializeAll() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      // Initialize streaming service (Iroh gossip)
      await _streamingService.initialize();
      final endpointId = await _streamingService.getEndpointId();
      
      // Initialize WebRTC service
      await _webrtcService.initialize(endpointId);
      
      // Setup WebRTC callbacks
      _webrtcService.onSignalToSend = _sendWebRTCSignal;
      _webrtcService.onRemoteStream = _onRemoteStream;
      _webrtcService.onConnectionStateChange = (state) {
        setState(() => _connectionState = state);
      };
      
      // Listen for gossip events
      _eventSubscription = _streamingService.eventStream.listen(_handleStreamEvent);

      setState(() {
        _endpointId = endpointId;
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// Handle stream events from Iroh gossip
  void _handleStreamEvent(rust_api.FlutterStreamEvent event) {
    debugPrint('[Stream] Event: ${event.runtimeType}');
    
    if (event is rust_api.FlutterStreamEvent_NeighborUp) {
      setState(() => _neighborCount++);
    } else if (event is rust_api.FlutterStreamEvent_NeighborDown) {
      setState(() => _neighborCount = (_neighborCount - 1).clamp(0, 999));
    } else if (event is rust_api.FlutterStreamEvent_Presence) {
      debugPrint('[Stream] Presence from: ${event.from.substring(0, 16)}, name: ${event.name}');
    } else if (event is rust_api.FlutterStreamEvent_Signal) {
      // WebRTC signaling message
      debugPrint('[Stream] RECEIVED Signal event from: ${event.from.substring(0, 16)}, data length: ${event.data.length}');
      _handleSignalEvent(event.data);
    }
  }

  /// Handle WebRTC signaling data from gossip
  void _handleSignalEvent(Uint8List data) {
    debugPrint('[Stream] Parsing signal data, length: ${data.length}');
    final signal = WebRTCSignal.fromBytes(data);
    if (signal != null) {
      debugPrint('[Stream] Parsed WebRTC signal: type=${signal.type.value}, from=${signal.from.substring(0, 16)}');
      _webrtcService.handleSignal(signal);
    } else {
      debugPrint('[Stream] Failed to parse signal data as WebRTC signal');
    }
  }

  /// Send WebRTC signal via Iroh gossip
  Future<void> _sendWebRTCSignal(WebRTCSignal signal) async {
    final signalJson = signal.toJson();
    debugPrint('[Stream] Sending WebRTC signal: ${signal.type.value} from=${signal.from.substring(0, 16)}');
    debugPrint('[Stream] Signal payload: $signalJson');
    
    try {
      final bytes = signal.toBytes();
      debugPrint('[Stream] Signal bytes length: ${bytes.length}');
      await _streamingService.sendSignal(bytes);
      debugPrint('[Stream] Signal sent successfully via gossip');
    } catch (e) {
      debugPrint('[Stream] ERROR sending signal: $e');
    }
  }

  /// Called when remote stream is received (viewer)
  void _onRemoteStream(MediaStream stream) {
    debugPrint('[WebRTC] Remote stream received');
    setState(() {}); // Refresh UI to show remote video
  }

  Future<void> _startBroadcast() async {
    if (!_isInitialized) return;

    setState(() {
      _error = null;
    });

    try {
      // Start WebRTC with camera or screen
      if (_useCamera) {
        await _webrtcService.startBroadcast(
          quality: _selectedQuality,
          useCamera: true,
          useAudio: true,
        );
      } else {
        await _webrtcService.startScreenShare(useAudio: true);
      }

      // Create gossip channel for signaling
      final ticket = await _streamingService.createStream(
        name: _nameController.text,
      );

      // Send initial presence
      await _streamingService.sendPresence();
      
      // Start presence timer (keep announcing presence) - matches web dashboard (5s)
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _streamingService.sendPresence(),
      );

      setState(() {
        _streamTicket = ticket;
        _isBroadcasting = true;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to start broadcast: $e';
      });
    }
  }

  Future<void> _stopBroadcast() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    
    await _webrtcService.stop();
    await _streamingService.leaveStream();

    setState(() {
      _isBroadcasting = false;
      _streamTicket = null;
      _neighborCount = 0;
      _connectionState = '';
    });
  }

  Future<void> _joinStream() async {
    if (!_isInitialized) return;
    final ticket = _ticketController.text.trim();
    if (ticket.isEmpty) {
      setState(() {
        _error = 'Please enter a stream ticket';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      // Join gossip channel
      await _streamingService.joinStream(
        ticket: ticket,
        name: _nameController.text,
      );

      // Send presence
      await _streamingService.sendPresence();
      
      // Start presence timer - matches web dashboard (5s)
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _streamingService.sendPresence(),
      );

      setState(() {
        _isWatching = true;
      });

      debugPrint('[Watch] State set to watching, now requesting WebRTC offer...');
      debugPrint('[Watch] WebRTC service initialized: ${_webrtcService.isInitialized}');
      debugPrint('[Watch] onSignalToSend callback set: ${_webrtcService.onSignalToSend != null}');
      
      // Request WebRTC offer from broadcaster with retry
      _offerRetryCount = 0;
      _requestOfferWithRetry();
      
    } catch (e) {
      setState(() {
        _error = 'Failed to join stream: $e';
      });
    }
  }

  void _requestOfferWithRetry() {
    const maxRetries = 10;
    
    debugPrint('[Watch] _requestOfferWithRetry called, isInitialized=${_webrtcService.isInitialized}');
    
    _offerRetryTimer?.cancel();
    _offerRetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _offerRetryCount++;
      
      // Check if we already have a connection
      if (_webrtcService.peerCount > 0) {
        debugPrint('[Watch] WebRTC connection established, stopping retries');
        _offerRetryTimer?.cancel();
        return;
      }
      
      if (_offerRetryCount > maxRetries) {
        debugPrint('[Watch] Max retries reached, stopping');
        _offerRetryTimer?.cancel();
        return;
      }
      
      debugPrint('[Watch] Requesting WebRTC offer (attempt $_offerRetryCount)...');
      _webrtcService.requestOffer();
    });
    
    // Initial request
    debugPrint('[Watch] Sending initial requestOffer...');
    _webrtcService.requestOffer();
  }

  Future<void> _stopWatching() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _offerRetryTimer?.cancel();
    _offerRetryTimer = null;
    
    await _webrtcService.stop();
    await _streamingService.leaveStream();
    
    setState(() {
      _isWatching = false;
      _neighborCount = 0;
      _connectionState = '';
    });
  }

  void _cleanup() {
    _eventSubscription?.cancel();
    _presenceTimer?.cancel();
    _offerRetryTimer?.cancel();
    _webrtcService.dispose();
  }

  void _copyTicket() {
    if (_streamTicket != null) {
      Clipboard.setData(ClipboardData(text: _streamTicket!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket copied to clipboard')),
      );
    }
  }

  void _toggleMute() {
    _webrtcService.toggleMicrophone();
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  void _toggleVideo() {
    _webrtcService.toggleVideo();
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
  }

  Future<void> _switchCamera() async {
    await _webrtcService.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Live Streaming'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isBroadcasting && _useCamera)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _switchCamera,
              tooltip: 'Switch Camera',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            if (_error != null) _buildErrorCard(),
            _buildNameInput(),
            const SizedBox(height: 16),
            _buildBroadcastSection(),
            const SizedBox(height: 16),
            _buildWatchSection(),
            const SizedBox(height: 16),
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isInitialized ? Icons.check_circle : Icons.pending,
                  color: _isInitialized ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text('Node Status', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_neighborCount > 0)
                  Chip(
                    label: Text('$_neighborCount peers'),
                    backgroundColor: Colors.blue.shade100,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isInitializing)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Initializing...'),
                ],
              )
            else if (_isInitialized)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done, size: 16, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Connected to Iroh network'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Endpoint: ${_endpointId?.substring(0, 16) ?? ''}...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                  if (_connectionState.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _connectionState.contains('connected') 
                              ? Icons.link 
                              : Icons.link_off,
                          size: 14,
                          color: _connectionState.contains('connected') 
                              ? Colors.green 
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text('WebRTC: $_connectionState',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              )
            else
              const Text('Not initialized'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _error = null)),
          ],
        ),
      ),
    );
  }

  Widget _buildNameInput() {
    return TextField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Your Name',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
      enabled: !_isBroadcasting && !_isWatching,
    );
  }

  Widget _buildBroadcastSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam, color: Colors.red),
                const SizedBox(width: 8),
                Text('Broadcast', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isBroadcasting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Quality selector
            DropdownButtonFormField<String>(
              value: _selectedQuality,
              decoration: const InputDecoration(labelText: 'Quality', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low (360p, 15fps)')),
                DropdownMenuItem(value: 'medium', child: Text('Medium (480p, 24fps)')),
                DropdownMenuItem(value: 'high', child: Text('High (720p, 30fps)')),
                DropdownMenuItem(value: 'ultra', child: Text('Ultra (1080p, 30fps)')),
              ],
              onChanged: _isBroadcasting ? null : (v) { if (v != null) setState(() => _selectedQuality = v); },
            ),
            const SizedBox(height: 12),
            
            // Source selector (Camera / Screen)
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Camera'), icon: Icon(Icons.camera_alt)),
                      ButtonSegment(value: false, label: Text('Screen'), icon: Icon(Icons.screen_share)),
                    ],
                    selected: {_useCamera},
                    onSelectionChanged: _isBroadcasting ? null : (v) => setState(() => _useCamera = v.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Video preview
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 240, 
                width: double.infinity, 
                color: Colors.black, 
                child: _isBroadcasting
                    ? RTCVideoView(
                        _webrtcService.localRenderer,
                        mirror: _useCamera,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off, color: Colors.grey, size: 48),
                            SizedBox(height: 8),
                            Text('Start broadcast to preview', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
              ),
            ),
            
            // Controls when broadcasting
            if (_isBroadcasting) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onPressed: _toggleMute,
                    color: _isMuted ? Colors.red : null,
                  ),
                  const SizedBox(width: 16),
                  _buildControlButton(
                    icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                    label: _isVideoOff ? 'Show Video' : 'Hide Video',
                    onPressed: _toggleVideo,
                    color: _isVideoOff ? Colors.red : null,
                  ),
                  if (_useCamera) ...[
                    const SizedBox(width: 16),
                    _buildControlButton(
                      icon: Icons.flip_camera_ios,
                      label: 'Flip',
                      onPressed: _switchCamera,
                    ),
                  ],
                ],
              ),
            ],
            
            const SizedBox(height: 12),
            
            // Ticket display
            if (_streamTicket != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _streamTicket!.length > 40 ? '${_streamTicket!.substring(0, 40)}...' : _streamTicket!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: _copyTicket, tooltip: 'Copy', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Start/Stop button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitialized && !_isWatching
                    ? (_isBroadcasting ? _stopBroadcast : _startBroadcast) : null,
                icon: Icon(_isBroadcasting ? Icons.stop : Icons.play_arrow),
                label: Text(_isBroadcasting ? 'Stop Broadcast' : 'Start Broadcast'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBroadcasting ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: color ?? Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: color != null ? Colors.white : Colors.black87),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildWatchSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Watch Stream', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ticketController,
              decoration: const InputDecoration(
                labelText: 'Stream Ticket',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number),
                hintText: 'Paste stream ticket here...',
              ),
              enabled: !_isWatching && !_isBroadcasting,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            
            // Remote video
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              child: _isWatching
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _webrtcService.peerCount > 0
                          ? RTCVideoView(
                              _webrtcService.remoteRenderer,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Colors.blue),
                                  SizedBox(height: 8),
                                  Text('Connecting to broadcaster...', 
                                      style: TextStyle(color: Colors.blue)),
                                ],
                              ),
                            ),
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.live_tv, color: Colors.grey, size: 48),
                          SizedBox(height: 8),
                          Text('Enter ticket to watch', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitialized && !_isBroadcasting ? (_isWatching ? _stopWatching : _joinStream) : null,
                icon: Icon(_isWatching ? Icons.stop : Icons.play_arrow),
                label: Text(_isWatching ? 'Stop Watching' : 'Join Stream'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isWatching ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 8),
                Text('How it works', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoTile(
              '1. Broadcast',
              'Start streaming your camera or screen. A gossip channel is created for peer discovery and WebRTC signaling.',
            ),
            _buildInfoTile(
              '2. Share Ticket',
              'Copy the stream ticket and share it with viewers. The ticket contains connection info.',
            ),
            _buildInfoTile(
              '3. Watch',
              'Viewers paste the ticket to join. WebRTC establishes direct P2P video connection.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
