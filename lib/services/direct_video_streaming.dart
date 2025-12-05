import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cyberfly_streaming/services/direct_streaming_service.dart';
import 'package:cyberfly_streaming/src/rust/api/direct_flutter_api.dart' as direct_api;

/// Video chunk size (64KB)
const int directVideoChunkSize = 64 * 1024;

/// Video metadata for direct streaming
class DirectVideoMetadata {
  final String fileName;
  final int fileSize;
  final String mimeType;
  final int totalChunks;
  final double? duration;

  DirectVideoMetadata({
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.totalChunks,
    this.duration,
  });
}

/// Video file broadcaster using direct connections
class DirectVideoFileBroadcaster {
  final DirectStreamingService _streamingService;
  final File _file;
  final String _myEndpointId;
  
  late DirectVideoMetadata _metadata;
  List<Uint8List> _chunks = [];
  bool _isStreaming = false;
  int _currentChunkIndex = 0;
  Timer? _presenceTimer;
  
  Function(int sent, int total)? onProgress;
  Function(String peerId, int chunkIndex)? onPeerRequest;
  Function(String peerId)? onPeerConnected;
  
  StreamSubscription<direct_api.FlutterDirectEvent>? _eventSubscription;

  DirectVideoFileBroadcaster({
    required DirectStreamingService streamingService,
    required File file,
    required String myEndpointId,
  }) : _streamingService = streamingService,
       _file = file,
       _myEndpointId = myEndpointId;

  DirectVideoMetadata get metadata => _metadata;
  bool get isStreaming => _isStreaming;
  int get currentChunk => _currentChunkIndex;
  int get totalChunks => _chunks.length;

  /// Prepare the video file by reading it into chunks
  Future<DirectVideoMetadata> prepare() async {
    debugPrint('[DirectVideo] Preparing file: ${_file.path}');
    
    final fileSize = await _file.length();
    final fileName = _file.path.split('/').last;
    final mimeType = _getMimeType(fileName);
    
    // Read file into chunks
    final bytes = await _file.readAsBytes();
    _chunks = [];
    
    for (int i = 0; i < bytes.length; i += directVideoChunkSize) {
      final end = (i + directVideoChunkSize < bytes.length) 
          ? i + directVideoChunkSize 
          : bytes.length;
      _chunks.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    
    _metadata = DirectVideoMetadata(
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      totalChunks: _chunks.length,
    );
    
    debugPrint('[DirectVideo] Prepared ${_chunks.length} chunks, size: $fileSize');
    return _metadata;
  }

  /// Start broadcasting the video file
  Future<void> startBroadcast({int chunkIntervalMs = 100}) async {
    if (_isStreaming) return;
    if (_chunks.isEmpty) {
      await prepare();
    }
    
    _isStreaming = true;
    debugPrint('[DirectVideo] Starting broadcast...');
    
    // Listen for events (metadata requests, chunk requests, peer connections)
    _eventSubscription = _streamingService.eventStream.listen(_handleEvent);
    
    // Start periodic presence
    _startPresenceTimer();
    
    // Don't auto-broadcast chunks - wait for viewers to connect and request
    debugPrint('[DirectVideo] Waiting for viewers to connect...');
  }

  void _startPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isStreaming) {
        await _streamingService.sendPresence('broadcaster');
      }
    });
  }

  /// Stop broadcasting
  void stopBroadcast() {
    _isStreaming = false;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    debugPrint('[DirectVideo] Broadcast stopped');
  }

  /// Handle incoming events
  void _handleEvent(direct_api.FlutterDirectEvent event) {
    if (event is direct_api.FlutterDirectEvent_PeerConnected) {
      debugPrint('[DirectVideo Broadcaster] Peer connected: ${event.endpointId.substring(0, 16)}...');
      onPeerConnected?.call(event.endpointId);
      // Auto-send metadata to new peer
      _sendMetadataAsync();
    } else if (event is direct_api.FlutterDirectEvent_RequestMetadata) {
      debugPrint('[DirectVideo Broadcaster] Metadata request from: ${event.from.substring(0, 16)}...');
      _sendMetadataAsync();
    } else if (event is direct_api.FlutterDirectEvent_RequestChunk) {
      debugPrint('[DirectVideo Broadcaster] Chunk ${event.index} request from: ${event.from.substring(0, 16)}...');
      _sendChunkAsync(event.index, event.from);
    }
  }

  void _sendMetadataAsync() {
    // Fire and forget
    _streamingService.sendMetadata(
      fileName: _metadata.fileName,
      fileSize: _metadata.fileSize,
      mimeType: _metadata.mimeType,
      totalChunks: _metadata.totalChunks,
      duration: _metadata.duration,
    ).then((_) {
      debugPrint('[DirectVideo Broadcaster] Metadata sent');
    }).catchError((e) {
      debugPrint('[DirectVideo Broadcaster] Failed to send metadata: $e');
    });
  }

  void _sendChunkAsync(int index, String peerId) {
    if (index < 0 || index >= _chunks.length) {
      debugPrint('[DirectVideo Broadcaster] Invalid chunk index: $index');
      return;
    }
    
    onPeerRequest?.call(peerId, index);
    
    _streamingService.sendChunk(index, _chunks[index]).then((_) {
      debugPrint('[DirectVideo Broadcaster] Sent chunk $index');
    }).catchError((e) {
      debugPrint('[DirectVideo Broadcaster] Failed to send chunk $index: $e');
    });
  }

  /// Broadcast all chunks (for push-based streaming)
  Future<void> broadcastAllChunks({int chunkIntervalMs = 100}) async {
    debugPrint('[DirectVideo Broadcaster] Broadcasting all ${_chunks.length} chunks...');
    
    // First send metadata
    await _streamingService.sendMetadata(
      fileName: _metadata.fileName,
      fileSize: _metadata.fileSize,
      mimeType: _metadata.mimeType,
      totalChunks: _metadata.totalChunks,
      duration: _metadata.duration,
    );
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Then send all chunks
    for (int i = 0; i < _chunks.length && _isStreaming; i++) {
      await _streamingService.sendChunk(i, _chunks[i]);
      _currentChunkIndex = i + 1;
      onProgress?.call(_currentChunkIndex, _chunks.length);
      
      if (chunkIntervalMs > 0) {
        await Future.delayed(Duration(milliseconds: chunkIntervalMs));
      }
    }
    
    debugPrint('[DirectVideo Broadcaster] Finished broadcasting all chunks');
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'video/mp4';
    }
  }
}

/// Video file viewer using direct connections
class DirectVideoFileViewer {
  final DirectStreamingService _streamingService;
  final String _myEndpointId;
  
  DirectVideoMetadata? _metadata;
  final Map<int, Uint8List> _chunks = {};
  final Set<int> _receivedChunks = {};
  final Set<int> _pendingRequests = {};
  
  Function(DirectVideoMetadata metadata)? onMetadata;
  Function(int received, int total)? onProgress;
  Function()? onReady;
  Function(String error)? onError;
  Function(Uint8List videoData)? onVideoComplete;
  Function()? onConnected;
  
  StreamSubscription<direct_api.FlutterDirectEvent>? _eventSubscription;
  Timer? _requestTimer;
  bool _isConnected = false;
  
  DirectVideoFileViewer({
    required DirectStreamingService streamingService,
    required String myEndpointId,
  }) : _streamingService = streamingService,
       _myEndpointId = myEndpointId;

  DirectVideoMetadata? get metadata => _metadata;
  int get receivedChunks => _receivedChunks.length;
  int get totalChunks => _metadata?.totalChunks ?? 0;
  double get progress => totalChunks > 0 ? receivedChunks / totalChunks : 0;
  bool get isComplete => _metadata != null && _receivedChunks.length >= _metadata!.totalChunks;
  bool get isConnected => _isConnected;

  /// Start listening for video data
  void startListening() {
    _eventSubscription = _streamingService.eventStream.listen(_handleEvent);
    debugPrint('[DirectVideo Viewer] Started listening for events');
  }

  /// Request metadata from broadcaster
  Future<void> requestMetadata() async {
    debugPrint('[DirectVideo Viewer] Requesting metadata...');
    await _streamingService.requestMetadata();
  }

  /// Request a specific chunk
  Future<void> requestChunk(int chunkIndex) async {
    if (_pendingRequests.contains(chunkIndex)) return;
    if (_receivedChunks.contains(chunkIndex)) return;
    
    debugPrint('[DirectVideo Viewer] Requesting chunk $chunkIndex');
    _pendingRequests.add(chunkIndex);
    
    await _streamingService.requestChunk(chunkIndex);
  }

  /// Start requesting missing chunks
  void startRequestingChunks() {
    if (_metadata == null) return;
    
    debugPrint('[DirectVideo Viewer] Starting to request chunks, total: ${_metadata!.totalChunks}');
    
    _requestTimer?.cancel();
    _requestTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (_metadata == null) return;
      
      // Find next chunks to request (limit to 3 concurrent)
      int requested = 0;
      for (int i = 0; i < _metadata!.totalChunks && requested < 3; i++) {
        if (!_receivedChunks.contains(i) && !_pendingRequests.contains(i)) {
          await requestChunk(i);
          requested++;
        }
      }
      
      // Check if complete
      if (_receivedChunks.length >= _metadata!.totalChunks) {
        debugPrint('[DirectVideo Viewer] All chunks received!');
        _requestTimer?.cancel();
        _assembleVideo();
      }
      
      // Clear stale pending requests after timeout
      if (requested == 0 && _pendingRequests.isNotEmpty) {
        debugPrint('[DirectVideo Viewer] Clearing stale pending requests');
        _pendingRequests.clear();
      }
    });
  }

  /// Handle incoming events
  void _handleEvent(direct_api.FlutterDirectEvent event) {
    if (event is direct_api.FlutterDirectEvent_PeerConnected) {
      _isConnected = true;
      debugPrint('[DirectVideo Viewer] Connected to broadcaster');
      onConnected?.call();
      // Request metadata after connecting
      Future.delayed(const Duration(milliseconds: 100), () {
        requestMetadata();
      });
    } else if (event is direct_api.FlutterDirectEvent_PeerDisconnected) {
      _isConnected = false;
      debugPrint('[DirectVideo Viewer] Disconnected from broadcaster');
    } else if (event is direct_api.FlutterDirectEvent_Metadata) {
      _handleMetadata(event);
    } else if (event is direct_api.FlutterDirectEvent_Chunk) {
      _handleChunk(event);
    }
  }

  void _handleMetadata(direct_api.FlutterDirectEvent_Metadata event) {
    if (_metadata != null) return; // Already have metadata
    
    _metadata = DirectVideoMetadata(
      fileName: event.fileName,
      fileSize: event.fileSize.toInt(),
      mimeType: event.mimeType,
      totalChunks: event.totalChunks,
      duration: event.duration,
    );
    
    debugPrint('[DirectVideo Viewer] Received metadata: ${_metadata!.fileName}, ${_metadata!.totalChunks} chunks');
    onMetadata?.call(_metadata!);
    onReady?.call();
    
    // Start requesting chunks
    startRequestingChunks();
  }

  void _handleChunk(direct_api.FlutterDirectEvent_Chunk event) {
    final index = event.index;
    
    // Skip if we already have this chunk
    if (_receivedChunks.contains(index)) return;
    
    _chunks[index] = Uint8List.fromList(event.data);
    _receivedChunks.add(index);
    _pendingRequests.remove(index);
    
    debugPrint('[DirectVideo Viewer] Received chunk $index');
    
    // Update progress
    if (_metadata != null) {
      onProgress?.call(_receivedChunks.length, _metadata!.totalChunks);
      
      // Check if complete
      if (_receivedChunks.length >= _metadata!.totalChunks) {
        debugPrint('[DirectVideo Viewer] All chunks received, assembling video...');
        _requestTimer?.cancel();
        _assembleVideo();
      }
    }
  }

  void _assembleVideo() {
    if (_metadata == null) return;
    
    debugPrint('[DirectVideo Viewer] Assembling ${_chunks.length} chunks...');
    
    // Assemble chunks in order
    final List<int> allBytes = [];
    for (int i = 0; i < _metadata!.totalChunks; i++) {
      final chunk = _chunks[i];
      if (chunk != null) {
        allBytes.addAll(chunk);
      } else {
        debugPrint('[DirectVideo Viewer] Missing chunk $i');
        onError?.call('Missing chunk $i');
        return;
      }
    }
    
    debugPrint('[DirectVideo Viewer] Assembled video: ${allBytes.length} bytes');
    onVideoComplete?.call(Uint8List.fromList(allBytes));
  }

  /// Stop listening and clean up
  void destroy() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _requestTimer?.cancel();
    _requestTimer = null;
    _chunks.clear();
    _receivedChunks.clear();
    _pendingRequests.clear();
    _metadata = null;
    _isConnected = false;
  }
}
