import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cyberfly_streaming/services/streaming_service.dart';
import 'package:cyberfly_streaming/services/video_file_streaming.dart';

/// Video file streaming screen (compatible with web dashboard)
/// Uses gossip protocol to distribute video file chunks
class VideoStreamingScreen extends StatefulWidget {
  const VideoStreamingScreen({super.key});

  @override
  State<VideoStreamingScreen> createState() => _VideoStreamingScreenState();
}

class _VideoStreamingScreenState extends State<VideoStreamingScreen> {
  final StreamingService _streamingService = StreamingService();
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
  
  // Video file related
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  VideoPlayerController? _localVideoController;
  VideoPlayerController? _remoteVideoController;
  bool _isLocalVideoInitialized = false;
  bool _isRemoteVideoInitialized = false;
  
  // Broadcast/receive objects (web-compatible protocol)
  VideoFileBroadcaster? _broadcaster;
  VideoFileViewer? _viewer;
  
  // Progress
  double _broadcastProgress = 0.0;
  int _chunksSent = 0;
  int _totalChunks = 0;
  double _receiveProgress = 0.0;
  int _chunksReceived = 0;
  int _totalChunksToReceive = 0;
  
  // Received video metadata
  VideoMetadata? _receivedMetadata;

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
      // Create gossip channel
      final ticket = await _streamingService.createStream(
        name: _nameController.text,
      );
      
      // Create broadcaster with web-compatible protocol
      _broadcaster = VideoFileBroadcaster(
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
        debugPrint('[VideoFile] Peer ${peerId.substring(0, 8)} requested chunk $chunkIndex');
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
      
      // Send initial presence
      await _streamingService.sendPresence();
      
      // Start broadcasting with web-compatible protocol
      await _broadcaster!.startBroadcast(chunkIntervalMs: 50);
      
    } catch (e) {
      setState(() {
        _error = 'Failed to start broadcast: $e';
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
      // Join gossip channel
      await _streamingService.joinStream(
        ticket: ticket,
        name: _nameController.text,
      );
      
      // Create viewer with web-compatible protocol
      _viewer = VideoFileViewer(
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
      
      _viewer!.onReady = () {
        debugPrint('[VideoFile] Viewer ready');
      };
      
      _viewer!.onError = (error) {
        setState(() {
          _error = error;
        });
      };
      
      _viewer!.onVideoComplete = (videoData) async {
        debugPrint('[VideoFile] Video complete! ${videoData.length} bytes');
        await _saveAndPlayReceivedVideo(videoData);
      };
      
      setState(() {
        _isWatching = true;
      });
      
      // Start listening for gossip events
      _viewer!.startListening();
      
      // Send presence
      await _streamingService.sendPresence();
      
      // Request metadata with retry
      _requestMetadataWithRetry();
      
    } catch (e) {
      setState(() {
        _error = 'Failed to join stream: $e';
      });
    }
  }

  Future<void> _requestMetadataWithRetry() async {
    const maxAttempts = 10;
    const delayMs = 1000;
    
    for (int i = 0; i < maxAttempts; i++) {
      if (!_isWatching || _viewer == null) return;
      
      // Check if we already have metadata
      if (_viewer!.metadata != null) {
        debugPrint('[VideoFile] Already have metadata, stopping requests');
        return;
      }
      
      debugPrint('[VideoFile] Requesting metadata (attempt ${i + 1}/$maxAttempts)...');
      await _viewer!.requestMetadata();
      
      await Future.delayed(const Duration(milliseconds: delayMs));
    }
    
    debugPrint('[VideoFile] Metadata request attempts exhausted');
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
      
      debugPrint('[VideoFile] Saved video to: $filePath');
      
      // Initialize video player
      await _initializeRemoteVideoPlayer(file);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video received: $fileName')),
        );
      }
    } catch (e) {
      debugPrint('[VideoFile] Error saving video: $e');
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
        title: const Text('P2P Video File Streaming'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                const Icon(Icons.video_library, color: Colors.purple),
                const SizedBox(width: 8),
                Text('Broadcast Video File', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_isBroadcasting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('SHARING', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // File selection buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBroadcasting ? null : _selectVideoFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select File'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isBroadcasting ? null : _recordVideo,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Record'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Selected file info
            if (_selectedFile != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_file, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFileName ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatFileSize(_selectedFileSize ?? 0),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!_isBroadcasting)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: _clearSelectedFile,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Video preview
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 200,
                width: double.infinity,
                color: Colors.black,
                child: _buildVideoPreview(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Progress indicator
            if (_isBroadcasting) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Progress: $_chunksSent / $_totalChunks chunks'),
                  Text('${(_broadcastProgress * 100).toStringAsFixed(1)}%'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _broadcastProgress, color: Colors.purple),
              const SizedBox(height: 16),
            ],
            
            // Stream ticket display
            if (_streamTicket != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
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
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: _copyTicket,
                      tooltip: 'Copy',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Broadcast controls
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitialized && !_isWatching && _selectedFile != null
                    ? (_isBroadcasting ? _stopBroadcast : _startBroadcast)
                    : null,
                icon: Icon(_isBroadcasting ? Icons.stop : Icons.cloud_upload),
                label: Text(_isBroadcasting ? 'Stop Sharing' : 'Start Broadcast'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBroadcasting ? Colors.red : Colors.purple,
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

  Widget _buildVideoPreview() {
    if (_selectedFile == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_file, color: Colors.grey, size: 48),
            SizedBox(height: 8),
            Text('Select or record a video', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (!_isLocalVideoInitialized || _localVideoController == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _localVideoController!.value.aspectRatio,
          child: VideoPlayer(_localVideoController!),
        ),
        // Play/Pause overlay
        if (!_isBroadcasting)
          Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(30),
            ),
            child: IconButton(
              icon: Icon(
                _localVideoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () {
                setState(() {
                  if (_localVideoController!.value.isPlaying) {
                    _localVideoController!.pause();
                  } else {
                    _localVideoController!.play();
                  }
                });
              },
            ),
          ),
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
                const Icon(Icons.download, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Receive Video', style: Theme.of(context).textTheme.titleMedium),
                if (_isWatching && _receivedMetadata != null) ...[
                  const Spacer(),
                  Text(
                    '${(_receiveProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                ],
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
            
            // Received metadata info
            if (_receivedMetadata != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_file, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _receivedMetadata!.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_formatFileSize(_receivedMetadata!.fileSize)} • ${_receivedMetadata!.totalChunks} chunks',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Receiving: $_chunksReceived / $_totalChunksToReceive'),
                  Text('${(_receiveProgress * 100).toStringAsFixed(1)}%'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _receiveProgress, color: Colors.blue),
              const SizedBox(height: 16),
            ],
            
            // Video player
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 200,
                width: double.infinity,
                color: Colors.black,
                child: _buildRemoteVideoPlayer(),
              ),
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitialized && !_isBroadcasting
                    ? (_isWatching ? _stopWatching : _joinStream)
                    : null,
                icon: Icon(_isWatching ? Icons.stop : Icons.download),
                label: Text(_isWatching ? 'Stop Receiving' : 'Start Receiving'),
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

  Widget _buildRemoteVideoPlayer() {
    if (!_isWatching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download, color: Colors.grey, size: 48),
            SizedBox(height: 8),
            Text('Enter ticket to receive', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    if (_isRemoteVideoInitialized && _remoteVideoController != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _remoteVideoController!.value.aspectRatio,
            child: VideoPlayer(_remoteVideoController!),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(30),
            ),
            child: IconButton(
              icon: Icon(
                _remoteVideoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () {
                setState(() {
                  if (_remoteVideoController!.value.isPlaying) {
                    _remoteVideoController!.pause();
                  } else {
                    _remoteVideoController!.play();
                  }
                });
              },
            ),
          ),
        ],
      );
    }
    
    if (_receivedMetadata == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 8),
            Text('Waiting for metadata...', style: TextStyle(color: Colors.blue)),
          ],
        ),
      );
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 8),
          Text(
            'Downloading: ${(_receiveProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.blue),
          ),
          Text(
            '$_chunksReceived / $_totalChunksToReceive chunks',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
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
              '1. Select Video',
              'Choose a video file or record one. The file will be split into 64KB chunks.',
            ),
            _buildInfoTile(
              '2. Broadcast',
              'Start sharing to create a gossip channel. Share the ticket with receivers.',
            ),
            _buildInfoTile(
              '3. Receive',
              'Paste the ticket to join. Video chunks are downloaded and assembled for playback.',
            ),
            _buildInfoTile(
              '4. P2P Relay',
              'Receivers can relay chunks to other peers, enabling distributed delivery.',
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
