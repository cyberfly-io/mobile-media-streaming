import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cyberfly_streaming/services/streaming_service.dart';
import 'package:cyberfly_streaming/src/rust/api/flutter_api.dart' as rust_api;

/// Video chunk size (64KB to match web dashboard)
const int videoChunkSize = 64 * 1024;

/// Video stream message types (compatible with web dashboard)
class VideoStreamMessage {
  final String type;
  final String from;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? totalChunks;
  final double? duration;
  final int? chunkIndex;
  final List<int>? chunkData;
  final List<int>? availableChunks;

  VideoStreamMessage({
    required this.type,
    required this.from,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.totalChunks,
    this.duration,
    this.chunkIndex,
    this.chunkData,
    this.availableChunks,
  });

  factory VideoStreamMessage.fromJson(Map<String, dynamic> json) {
    return VideoStreamMessage(
      type: json['type'] as String,
      from: json['from'] as String,
      fileName: json['fileName'] as String?,
      fileSize: json['fileSize'] as int?,
      mimeType: json['mimeType'] as String?,
      totalChunks: json['totalChunks'] as int?,
      duration: (json['duration'] as num?)?.toDouble(),
      chunkIndex: json['chunkIndex'] as int?,
      chunkData: (json['chunkData'] as List<dynamic>?)?.cast<int>(),
      availableChunks: (json['availableChunks'] as List<dynamic>?)?.cast<int>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'from': from,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (mimeType != null) 'mimeType': mimeType,
      if (totalChunks != null) 'totalChunks': totalChunks,
      if (duration != null) 'duration': duration,
      if (chunkIndex != null) 'chunkIndex': chunkIndex,
      if (chunkData != null) 'chunkData': chunkData,
      if (availableChunks != null) 'availableChunks': availableChunks,
    };
  }

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  static VideoStreamMessage? fromBytes(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type != null && type.startsWith('video-')) {
        return VideoStreamMessage.fromJson(json);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// Video metadata
class VideoMetadata {
  final String fileName;
  final int fileSize;
  final String mimeType;
  final int totalChunks;
  final double? duration;

  VideoMetadata({
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.totalChunks,
    this.duration,
  });
}

/// Video file broadcaster (compatible with web dashboard)
class VideoFileBroadcaster {
  final StreamingService _streamingService;
  final File _file;
  final String _myEndpointId;
  
  late VideoMetadata _metadata;
  List<Uint8List> _chunks = [];
  bool _isStreaming = false;
  int _currentChunkIndex = 0;
  Timer? _presenceTimer;
  
  Function(int sent, int total)? onProgress;
  Function(String peerId, int chunkIndex)? onPeerRequest;
  
  StreamSubscription<rust_api.FlutterStreamEvent>? _eventSubscription;

  VideoFileBroadcaster({
    required StreamingService streamingService,
    required File file,
    required String myEndpointId,
  }) : _streamingService = streamingService,
       _file = file,
       _myEndpointId = myEndpointId;

  VideoMetadata get metadata => _metadata;
  bool get isStreaming => _isStreaming;
  int get currentChunk => _currentChunkIndex;
  int get totalChunks => _chunks.length;

  /// Prepare the video file by reading it into chunks
  Future<VideoMetadata> prepare() async {
    debugPrint('[VideoFile] Preparing file: ${_file.path}');
    
    final fileSize = await _file.length();
    final fileName = _file.path.split('/').last;
    final mimeType = _getMimeType(fileName);
    
    // Read file into chunks
    final bytes = await _file.readAsBytes();
    _chunks = [];
    
    for (int i = 0; i < bytes.length; i += videoChunkSize) {
      final end = (i + videoChunkSize < bytes.length) ? i + videoChunkSize : bytes.length;
      _chunks.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    
    _metadata = VideoMetadata(
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      totalChunks: _chunks.length,
    );
    
    debugPrint('[VideoFile] Prepared ${_chunks.length} chunks, size: $fileSize');
    return _metadata;
  }

  /// Start broadcasting the video file
  Future<void> startBroadcast({int chunkIntervalMs = 100}) async {
    if (_isStreaming) return;
    if (_chunks.isEmpty) {
      await prepare();
    }
    
    _isStreaming = true;
    debugPrint('[VideoFile] Starting broadcast...');
    
    // Listen for events (metadata requests, chunk requests)
    _eventSubscription = _streamingService.eventStream.listen(_handleEvent);
    
    // Start periodic presence to keep NAT pinhole open
    _startPresenceTimer();
    
    // Broadcast metadata first (multiple times for reliability)
    await _broadcastMetadata();
    await Future.delayed(const Duration(milliseconds: 200));
    await _broadcastMetadata();
    
    // Broadcast chunks with interval
    _currentChunkIndex = 0;
    _broadcastChunks(chunkIntervalMs);
  }
  
  void _startPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isStreaming) {
        await _streamingService.sendPresence();
      }
    });
  }

  Future<void> _broadcastChunks(int intervalMs) async {
    while (_isStreaming && _currentChunkIndex < _chunks.length) {
      await _broadcastChunk(_currentChunkIndex);
      _currentChunkIndex++;
      onProgress?.call(_currentChunkIndex, _chunks.length);
      
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
    
    if (_isStreaming) {
      debugPrint('[VideoFile] Broadcast complete');
      // Keep listening for chunk requests from late joiners
    }
  }

  /// Stop broadcasting
  void stopBroadcast() {
    _isStreaming = false;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    debugPrint('[VideoFile] Broadcast stopped');
  }

  /// Broadcast video metadata
  /// Uses MediaChunk with special sequence number for reliable delivery
  Future<void> _broadcastMetadata() async {
    final message = VideoStreamMessage(
      type: 'video-metadata',
      from: _myEndpointId,
      fileName: _metadata.fileName,
      fileSize: _metadata.fileSize,
      mimeType: _metadata.mimeType,
      totalChunks: _metadata.totalChunks,
      duration: _metadata.duration,
    );
    
    debugPrint('[VideoFile] Broadcasting metadata: ${_metadata.fileName}');
    // Use MediaChunk with sequence 999999999 for metadata (more reliable than Signal)
    // This matches web dashboard's broadcastSignal behavior
    await _streamingService.broadcastChunk(message.toBytes(), 999999999);
    // Also send via signal for backwards compatibility
    await _streamingService.sendSignal(message.toBytes());
  }

  /// Broadcast a specific chunk
  Future<void> _broadcastChunk(int index) async {
    if (index < 0 || index >= _chunks.length) return;
    
    final chunk = _chunks[index];
    final message = VideoStreamMessage(
      type: 'video-chunk',
      from: _myEndpointId,
      chunkIndex: index,
      chunkData: chunk.toList(),
    );
    
    // Use broadcastChunk for media data (handles large messages)
    await _streamingService.broadcastChunk(message.toBytes(), index);
  }

  /// Handle incoming events
  void _handleEvent(rust_api.FlutterStreamEvent event) {
    debugPrint('[VideoFile Broadcaster] Received event: ${event.runtimeType}');
    if (event is rust_api.FlutterStreamEvent_Signal) {
      debugPrint('[VideoFile Broadcaster] Signal from: ${event.from.substring(0, 16)}, ${event.data.length} bytes');
      _handleSignalEvent(event.data, event.from);
    } else if (event is rust_api.FlutterStreamEvent_MediaChunk) {
      debugPrint('[VideoFile Broadcaster] MediaChunk from: ${event.from.substring(0, 16)}, ${event.data.length} bytes');
      _handleSignalEvent(event.data, event.from);
    }
  }

  void _handleSignalEvent(Uint8List data, String fromEndpoint) {
    debugPrint('[VideoFile Broadcaster] Raw signal data: ${String.fromCharCodes(data.take(200))}');
    
    final message = VideoStreamMessage.fromBytes(data);
    if (message == null) {
      debugPrint('[VideoFile Broadcaster] Failed to parse message as VideoStreamMessage');
      return;
    }
    
    debugPrint('[VideoFile Broadcaster] Parsed message type: ${message.type}, from: ${message.from}');
    
    if (message.from == _myEndpointId) {
      debugPrint('[VideoFile Broadcaster] Ignoring our own message');
      return;
    }
    
    _handleVideoMessage(message);
  }

  Future<void> _handleVideoMessage(VideoStreamMessage message) async {
    debugPrint('[VideoFile Broadcaster] Handling message type: ${message.type}');
    
    switch (message.type) {
      case 'video-request-metadata':
        debugPrint('[VideoFile Broadcaster] >>> Received metadata request from ${message.from.substring(0, 8)}');
        debugPrint('[VideoFile Broadcaster] >>> Sending metadata response...');
        await _broadcastMetadata();
        debugPrint('[VideoFile Broadcaster] >>> Metadata sent!');
        break;
        
      case 'video-request-chunk':
        if (message.chunkIndex != null) {
          await _handleChunkRequest(message.from, message.chunkIndex!);
        }
        break;
    }
  }

  Future<void> _handleChunkRequest(String peerId, int chunkIndex) async {
    onPeerRequest?.call(peerId, chunkIndex);
    
    if (chunkIndex >= 0 && chunkIndex < _chunks.length) {
      debugPrint('[VideoFile] Sending requested chunk $chunkIndex to ${peerId.substring(0, 8)}');
      await _broadcastChunk(chunkIndex);
    }
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

/// Video file viewer (compatible with web dashboard)
class VideoFileViewer {
  final StreamingService _streamingService;
  final String _myEndpointId;
  
  VideoMetadata? _metadata;
  final Map<int, Uint8List> _chunks = {};
  final Set<int> _receivedChunks = {};
  final Set<int> _pendingRequests = {};
  
  Function(VideoMetadata metadata)? onMetadata;
  Function(int received, int total)? onProgress;
  Function()? onReady;
  Function(String error)? onError;
  Function(Uint8List videoData)? onVideoComplete;
  
  StreamSubscription<rust_api.FlutterStreamEvent>? _eventSubscription;
  Timer? _requestTimer;
  
  VideoFileViewer({
    required StreamingService streamingService,
    required String myEndpointId,
  }) : _streamingService = streamingService,
       _myEndpointId = myEndpointId;

  VideoMetadata? get metadata => _metadata;
  int get receivedChunks => _receivedChunks.length;
  int get totalChunks => _metadata?.totalChunks ?? 0;
  double get progress => totalChunks > 0 ? receivedChunks / totalChunks : 0;
  bool get isComplete => _metadata != null && _receivedChunks.length >= _metadata!.totalChunks;

  /// Start listening for video data
  void startListening() {
    _eventSubscription = _streamingService.eventStream.listen(_handleEvent);
    debugPrint('[VideoFile Viewer] Started listening for events');
  }

  /// Request metadata from broadcaster
  /// Uses MediaChunk with special sequence for reliable delivery
  Future<void> requestMetadata() async {
    debugPrint('[VideoFile Viewer] Requesting metadata from broadcaster...');
    final message = VideoStreamMessage(
      type: 'video-request-metadata',
      from: _myEndpointId,
    );
    // Use MediaChunk for reliable delivery
    await _streamingService.broadcastChunk(message.toBytes(), 999999998);
    // Also send via signal
    await _streamingService.sendSignal(message.toBytes());
  }

  /// Request a specific chunk
  Future<void> requestChunk(int chunkIndex) async {
    if (_pendingRequests.contains(chunkIndex)) return;
    if (_receivedChunks.contains(chunkIndex)) return;
    
    debugPrint('[VideoFile Viewer] Requesting chunk $chunkIndex');
    _pendingRequests.add(chunkIndex);
    
    final message = VideoStreamMessage(
      type: 'video-request-chunk',
      from: _myEndpointId,
      chunkIndex: chunkIndex,
    );
    await _streamingService.sendSignal(message.toBytes());
  }

  /// Start requesting missing chunks
  void startRequestingChunks() {
    if (_metadata == null) return;
    
    debugPrint('[VideoFile Viewer] Starting to request chunks, total: ${_metadata!.totalChunks}');
    
    _requestTimer?.cancel();
    _requestTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_metadata == null) return;
      
      // Find next chunks to request (limit to 5 concurrent)
      int requested = 0;
      for (int i = 0; i < _metadata!.totalChunks && requested < 5; i++) {
        if (!_receivedChunks.contains(i) && !_pendingRequests.contains(i)) {
          await requestChunk(i);
          requested++;
        }
      }
      
      // Check if complete
      if (_receivedChunks.length >= _metadata!.totalChunks) {
        debugPrint('[VideoFile Viewer] All chunks received!');
        _requestTimer?.cancel();
        _assembleVideo();
      }
      
      // Clear stale pending requests
      if (requested == 0 && _pendingRequests.isNotEmpty) {
        debugPrint('[VideoFile Viewer] Clearing stale pending requests');
        _pendingRequests.clear();
      }
    });
  }

  /// Handle incoming events
  void _handleEvent(rust_api.FlutterStreamEvent event) {
    if (event is rust_api.FlutterStreamEvent_Signal) {
      _handleSignalData(event.data);
    } else if (event is rust_api.FlutterStreamEvent_MediaChunk) {
      _handleSignalData(event.data);
    }
  }

  void _handleSignalData(Uint8List data) {
    final message = VideoStreamMessage.fromBytes(data);
    if (message == null) return;
    if (message.from == _myEndpointId) return; // Ignore our own messages
    
    _handleVideoMessage(message);
  }

  Future<void> _handleVideoMessage(VideoStreamMessage message) async {
    switch (message.type) {
      case 'video-metadata':
        await _handleMetadata(message);
        break;
        
      case 'video-chunk':
        await _handleChunk(message);
        break;
        
      case 'video-request-chunk':
        await _handleChunkRequest(message);
        break;
        
      case 'video-have-chunks':
        _handlePeerChunks(message);
        break;
    }
  }

  Future<void> _handleMetadata(VideoStreamMessage message) async {
    if (_metadata != null) return; // Already have metadata
    
    _metadata = VideoMetadata(
      fileName: message.fileName ?? 'video',
      fileSize: message.fileSize ?? 0,
      mimeType: message.mimeType ?? 'video/mp4',
      totalChunks: message.totalChunks ?? 0,
      duration: message.duration,
    );
    
    debugPrint('[VideoFile Viewer] Received metadata: ${_metadata!.fileName}, ${_metadata!.totalChunks} chunks');
    onMetadata?.call(_metadata!);
    onReady?.call();
    
    // Start requesting chunks
    startRequestingChunks();
  }

  Future<void> _handleChunk(VideoStreamMessage message) async {
    if (message.chunkIndex == null || message.chunkData == null) return;
    
    final index = message.chunkIndex!;
    
    // Skip if we already have this chunk
    if (_receivedChunks.contains(index)) return;
    
    final chunkData = Uint8List.fromList(message.chunkData!);
    _chunks[index] = chunkData;
    _receivedChunks.add(index);
    _pendingRequests.remove(index);
    
    debugPrint('[VideoFile Viewer] Received chunk $index from ${message.from.substring(0, 8)}');
    
    // Update progress
    if (_metadata != null) {
      onProgress?.call(_receivedChunks.length, _metadata!.totalChunks);
      
      // Check if complete
      if (_receivedChunks.length >= _metadata!.totalChunks) {
        debugPrint('[VideoFile Viewer] All chunks received, assembling video...');
        _requestTimer?.cancel();
        _assembleVideo();
      }
    }
    
    // Announce that we have this chunk (for peer-assisted delivery)
    await _announceChunks();
  }

  Future<void> _handleChunkRequest(VideoStreamMessage message) async {
    if (message.chunkIndex == null) return;
    
    final index = message.chunkIndex!;
    final chunk = _chunks[index];
    
    if (chunk != null) {
      debugPrint('[VideoFile Viewer] Relaying chunk $index to ${message.from.substring(0, 8)}');
      
      final response = VideoStreamMessage(
        type: 'video-chunk',
        from: _myEndpointId,
        chunkIndex: index,
        chunkData: chunk.toList(),
      );
      
      await _streamingService.broadcastChunk(response.toBytes(), index + 100000);
    }
  }

  void _handlePeerChunks(VideoStreamMessage message) {
    // Track which chunks peers have (for smart requesting)
    debugPrint('[VideoFile Viewer] Peer ${message.from.substring(0, 8)} has ${message.availableChunks?.length ?? 0} chunks');
  }

  Future<void> _announceChunks() async {
    // Throttle announcements
    if (_receivedChunks.length % 10 != 0) return;
    
    final message = VideoStreamMessage(
      type: 'video-have-chunks',
      from: _myEndpointId,
      availableChunks: _receivedChunks.toList(),
    );
    
    await _streamingService.sendSignal(message.toBytes());
  }

  void _assembleVideo() {
    if (_metadata == null) return;
    
    debugPrint('[VideoFile Viewer] Assembling ${_chunks.length} chunks...');
    
    // Assemble chunks in order
    final List<int> allBytes = [];
    for (int i = 0; i < _metadata!.totalChunks; i++) {
      final chunk = _chunks[i];
      if (chunk != null) {
        allBytes.addAll(chunk);
      } else {
        debugPrint('[VideoFile Viewer] Missing chunk $i');
        break;
      }
    }
    
    debugPrint('[VideoFile Viewer] Assembled video: ${allBytes.length} bytes');
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
  }
}
