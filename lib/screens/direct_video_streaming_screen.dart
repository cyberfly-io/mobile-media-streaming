import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyberfly_streaming/services/direct_streaming_service.dart';
import 'package:cyberfly_streaming/services/direct_video_streaming.dart';

/// Video file streaming screen using DIRECT iroh connections
/// This solves the one-way gossip connectivity issue by establishing
/// bidirectional QUIC streams between broadcaster and viewer
class DirectVideoStreamingScreen extends StatefulWidget {
  const DirectVideoStreamingScreen({super.key});

  @override
  State<DirectVideoStreamingScreen> createState() => _DirectVideoStreamingScreenState();
}

class _DirectVideoStreamingScreenState extends State<DirectVideoStreamingScreen> {
  final DirectStreamingService _streamingService = DirectStreamingService();
  final TextEditingController _nameController = TextEditingController(text: 'Flutter User');
  final TextEditingController _ticketController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isBroadcasting = false;
  bool _isWatching = false;
  String? _endpointId;
  String? _streamTicket;
  String? _error;
  int _peerCount = 0;
  
  // Video file related
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  VideoPlayerController? _localVideoController;
  VideoPlayerController? _remoteVideoController;
  bool _isLocalVideoInitialized = false;
  bool _isRemoteVideoInitialized = false;
  
  // Broadcast/receive objects (direct connection protocol)
  DirectVideoFileBroadcaster? _broadcaster;
  DirectVideoFileViewer? _viewer;
  
  // Progress
  double _broadcastProgress = 0.0;
  int _chunksSent = 0;
  int _totalChunks = 0;
  double _receiveProgress = 0.0;
  int _chunksReceived = 0;
  int _totalChunksToReceive = 0;
  
  // Received video metadata
  DirectVideoMetadata? _receivedMetadata;

  @override
  void initState() {
    super.initState();
    _initializeNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ticketController.dispose();
    _localVideoController?.dispose();
    _remoteVideoController?.dispose();
    _broadcaster?.stopBroadcast();
    _viewer?.destroy();
    super.dispose();
  }

  Future<void> _initializeNode() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      await _streamingService.initialize();
      final endpointId = await _streamingService.getEndpointId();
      setState(() {
        _endpointId = endpointId;
        _isInitialized = true;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _selectVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        await _initializeLocalVideoPlayer(file);
        
        setState(() {
          _selectedFile = file;
          _selectedFileName = result.files.first.name;
          _selectedFileSize = result.files.first.size;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to select file: $e';
      });
    }
  }

  Future<void> _recordVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 10),
      );

      if (video != null) {
        final file = File(video.path);
        await _initializeLocalVideoPlayer(file);
        
        final fileSize = await file.length();
        setState(() {
          _selectedFile = file;
          _selectedFileName = video.name;
          _selectedFileSize = fileSize;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to record video: $e';
      });
    }
  }

  Future<void> _initializeLocalVideoPlayer(File file) async {
    _localVideoController?.dispose();
    
    _localVideoController = VideoPlayerController.file(file);
    await _localVideoController!.initialize();
    
    setState(() {
      _isLocalVideoInitialized = true;
    });
  }

  Future<void> _initializeRemoteVideoPlayer(File file) async {
    _remoteVideoController?.dispose();
    
    _remoteVideoController = VideoPlayerController.file(file);
    await _remoteVideoController!.initialize();
    
    setState(() {
      _isRemoteVideoInitialized = true;
    });
    
    // Auto-play received video
    _remoteVideoController!.play();
  }

  Future<void> _startBroadcast() async {
    if (!_isInitialized || _selectedFile == null || _endpointId == null) return;

    setState(() {
      _error = null;
    });

    try {
      // Create direct stream (starts accepting connections)
      final ticket = await _streamingService.createStream(
        name: _nameController.text,
      );
      
      // Create broadcaster with direct connection protocol
      _broadcaster = DirectVideoFileBroadcaster(
        streamingService: _streamingService,
        file: _selectedFile!,
        myEndpointId: _endpointId!,
      );
      
      // Set progress callback
      _broadcaster!.onProgress = (sent, total) {
        setState(() {
          _chunksSent = sent;
          _totalChunks = total;
          _broadcastProgress = total > 0 ? sent / total : 0;
        });
      };
      
      _broadcaster!.onPeerRequest = (peerId, chunkIndex) {
        debugPrint('[DirectVideo] Peer ${peerId.substring(0, 8)} requested chunk $chunkIndex');
      };
      
      _broadcaster!.onPeerConnected = (peerId) {
        debugPrint('[DirectVideo] Peer connected: ${peerId.substring(0, 8)}');
        _updatePeerCount();
      };
      
      // Prepare file (split into chunks)
      final metadata = await _broadcaster!.prepare();
      
      setState(() {
        _streamTicket = ticket;
        _isBroadcasting = true;
        _totalChunks = metadata.totalChunks;
        _broadcastProgress = 0.0;
        _chunksSent = 0;
      });
      
      // Start broadcasting (waits for viewers to connect and request)
      await _broadcaster!.startBroadcast(chunkIntervalMs: 50);
      
      // Start peer count polling
      _startPeerCountPolling();
      
    } catch (e) {
      setState(() {
        _error = 'Failed to start broadcast: $e';
      });
    }
  }

  void _startPeerCountPolling() {
    Future.doWhile(() async {
      if (!_isBroadcasting) return false;
      await _updatePeerCount();
      await Future.delayed(const Duration(seconds: 2));
      return _isBroadcasting;
    });
  }

  Future<void> _updatePeerCount() async {
    final count = await _streamingService.getPeerCount();
    if (mounted) {
      setState(() {
        _peerCount = count;
      });
    }
  }

  Future<void> _stopBroadcast() async {
    _broadcaster?.stopBroadcast();
    _broadcaster = null;
    await _streamingService.leaveStream();
    
    setState(() {
      _isBroadcasting = false;
      _streamTicket = null;
      _broadcastProgress = 0.0;
      _peerCount = 0;
    });
  }

  Future<void> _joinStream() async {
    if (!_isInitialized || _endpointId == null) return;
    final ticket = _ticketController.text.trim();
    if (ticket.isEmpty) {
      setState(() {
        _error = 'Please enter a stream ticket';
      });
      return;
    }

    setState(() {
      _error = null;
      _receivedMetadata = null;
      _isRemoteVideoInitialized = false;
      _chunksReceived = 0;
      _totalChunksToReceive = 0;
      _receiveProgress = 0.0;
    });

    try {
      // Join direct stream (connects to broadcaster)
      await _streamingService.joinStream(
        ticket: ticket,
        name: _nameController.text,
      );
      
      // Create viewer with direct connection protocol
      _viewer = DirectVideoFileViewer(
        streamingService: _streamingService,
        myEndpointId: _endpointId!,
      );
      
      // Set callbacks
      _viewer!.onMetadata = (metadata) {
        setState(() {
          _receivedMetadata = metadata;
          _totalChunksToReceive = metadata.totalChunks;
        });
      };
      
      _viewer!.onProgress = (received, total) {
        setState(() {
          _chunksReceived = received;
          _totalChunksToReceive = total;
          _receiveProgress = total > 0 ? received / total : 0;
        });
      };
      
      _viewer!.onConnected = () {
        debugPrint('[DirectVideo] Connected to broadcaster!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connected to broadcaster!')),
          );
        }
      };
      
      _viewer!.onReady = () {
        debugPrint('[DirectVideo] Viewer ready, starting to receive chunks');
      };
      
      _viewer!.onError = (error) {
        setState(() {
          _error = error;
        });
      };
      
      _viewer!.onVideoComplete = (videoData) async {
        debugPrint('[DirectVideo] Video complete! ${videoData.length} bytes');
        await _saveAndPlayReceivedVideo(videoData);
      };
      
      setState(() {
        _isWatching = true;
      });
      
      // Start listening for direct events
      _viewer!.startListening();
      
    } catch (e) {
      setState(() {
        _error = 'Failed to join stream: $e';
      });
    }
  }

  Future<void> _saveAndPlayReceivedVideo(Uint8List videoData) async {
    try {
      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final fileName = _receivedMetadata?.fileName ?? 'received_video.mp4';
      final filePath = '${tempDir.path}/$fileName';
      
      // Save video to file
      final file = File(filePath);
      await file.writeAsBytes(videoData);
      
      debugPrint('[DirectVideo] Saved video to: $filePath');
      
      // Initialize video player
      await _initializeRemoteVideoPlayer(file);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video received: $fileName')),
        );
      }
    } catch (e) {
      debugPrint('[DirectVideo] Error saving video: $e');
      setState(() {
        _error = 'Failed to save received video: $e';
      });
    }
  }

  Future<void> _stopWatching() async {
    _viewer?.destroy();
    _viewer = null;
    await _streamingService.leaveStream();
    
    setState(() {
      _isWatching = false;
      _receivedMetadata = null;
      _receiveProgress = 0.0;
    });
  }

  void _copyTicket() {
    if (_streamTicket != null) {
      Clipboard.setData(ClipboardData(text: _streamTicket!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket copied to clipboard')),
      );
    }
  }

  void _clearSelectedFile() {
    _localVideoController?.dispose();
    setState(() {
      _selectedFile = null;
      _selectedFileName = null;
      _selectedFileSize = null;
      _localVideoController = null;
      _isLocalVideoInitialized = false;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct P2P Video Streaming'),
        backgroundColor: Colors.deepPurple.shade100,
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
      color: Colors.deepPurple.shade50,
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
                Text('Direct Connection Status', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (_isInitializing)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Initializing direct endpoint...'),
                ],
              )
            else if (_isInitialized)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.link, size: 16, color: Colors.deepPurple),
                      const SizedBox(width: 4),
                      const Text('Direct QUIC connection ready'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Endpoint: ${_endpointId?.substring(0, 16) ?? ''}...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                  if (_isBroadcasting && _peerCount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people, size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text('$_peerCount viewer(s) connected'),
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
                const Icon(Icons.video_library, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text('Broadcast Video (Direct)', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isBroadcasting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_tethering, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text('LIVE ($_peerCount)', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // File selection
            if (_selectedFile == null && !_isBroadcasting)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isInitialized && !_isWatching ? _selectVideoFile : null,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select Video'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isInitialized && !_isWatching ? _recordVideo : null,
                      icon: const Icon(Icons.videocam),
                      label: const Text('Record'),
                    ),
                  ),
                ],
              )
            else if (_selectedFile != null) ...[
              // Selected file info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.movie, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedFileName ?? 'video',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!_isBroadcasting)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _clearSelectedFile,
                          ),
                      ],
                    ),
                    Text(
                      'Size: ${_formatFileSize(_selectedFileSize ?? 0)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Video preview
              if (_isLocalVideoInitialized && _localVideoController != null) ...[
                AspectRatio(
                  aspectRatio: _localVideoController!.value.aspectRatio,
                  child: VideoPlayer(_localVideoController!),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(_localVideoController!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        setState(() {
                          _localVideoController!.value.isPlaying
                              ? _localVideoController!.pause()
                              : _localVideoController!.play();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              
              // Broadcast controls
              if (!_isBroadcasting)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized && !_isWatching ? _startBroadcast : null,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Start Direct Broadcast'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                )
              else ...[
                // Broadcasting status
                if (_streamTicket != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stream Ticket:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_streamTicket!.substring(0, 30)}...',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: _copyTicket,
                              tooltip: 'Copy ticket',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Progress
                if (_totalChunks > 0) ...[
                  LinearProgressIndicator(
                    value: _broadcastProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Progress: $_chunksSent / $_totalChunks chunks (${(_broadcastProgress * 100).toStringAsFixed(1)}%)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Stop button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _stopBroadcast,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Broadcast'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
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
                const Icon(Icons.live_tv, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Watch Stream (Direct)', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isWatching)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_viewer?.isConnected == true ? Icons.link : Icons.link_off, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(_viewer?.isConnected == true ? 'CONNECTED' : 'CONNECTING', 
                             style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (!_isWatching) ...[
              TextField(
                controller: _ticketController,
                decoration: const InputDecoration(
                  labelText: 'Stream Ticket',
                  hintText: 'Paste ticket from broadcaster',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.confirmation_number),
                ),
                enabled: !_isBroadcasting,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isInitialized && !_isBroadcasting ? _joinStream : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Connect & Watch'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else ...[
              // Receiving status
              if (_receivedMetadata != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.movie, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _receivedMetadata!.fileName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Size: ${_formatFileSize(_receivedMetadata!.fileSize)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Progress
                LinearProgressIndicator(
                  value: _receiveProgress,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 4),
                Text(
                  'Receiving: $_chunksReceived / $_totalChunksToReceive chunks (${(_receiveProgress * 100).toStringAsFixed(1)}%)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ] else ...[
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Waiting for metadata from broadcaster...'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Received video player
              if (_isRemoteVideoInitialized && _remoteVideoController != null) ...[
                const SizedBox(height: 12),
                AspectRatio(
                  aspectRatio: _remoteVideoController!.value.aspectRatio,
                  child: VideoPlayer(_remoteVideoController!),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(_remoteVideoController!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        setState(() {
                          _remoteVideoController!.value.isPlaying
                              ? _remoteVideoController!.pause()
                              : _remoteVideoController!.play();
                        });
                      },
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stopWatching,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Watching'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Direct Connection Mode', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '🔗 This uses direct QUIC connections (not gossip relay)\n'
              '✅ Bidirectional communication guaranteed\n'
              '🚀 More reliable for NAT traversal\n'
              '📡 Messages flow directly between peers\n\n'
              'The broadcaster creates a ticket that viewers use to connect directly.',
              style: TextStyle(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
