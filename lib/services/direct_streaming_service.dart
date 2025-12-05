import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cyberfly_streaming/src/rust/api/direct_flutter_api.dart' as direct_api;

/// Direct streaming service using iroh direct connections (not gossip)
/// This provides more reliable bidirectional communication
class DirectStreamingService {
  static final DirectStreamingService _instance = DirectStreamingService._internal();
  factory DirectStreamingService() => _instance;
  DirectStreamingService._internal();

  String? _endpointId;
  bool _isInitialized = false;
  Timer? _eventPollTimer;
  final StreamController<direct_api.FlutterDirectEvent> _eventController =
      StreamController<direct_api.FlutterDirectEvent>.broadcast();

  String? get endpointId => _endpointId;
  bool get isInitialized => _isInitialized;
  
  /// Stream of events from the P2P network
  Stream<direct_api.FlutterDirectEvent> get eventStream => _eventController.stream;

  /// Initialize the direct streaming endpoint
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _endpointId = await direct_api.initDirectStreaming();
      _isInitialized = true;
      debugPrint('[DirectStreaming] Initialized with endpoint: $_endpointId');
    } catch (e) {
      debugPrint('[DirectStreaming] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Get the endpoint ID
  Future<String> getEndpointId() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _endpointId ?? await direct_api.getDirectEndpointId();
  }

  /// Create a new direct stream as broadcaster
  Future<String> createStream({required String name}) async {
    if (!_isInitialized) {
      await initialize();
    }
    final ticket = await direct_api.createDirectStream(name: name);
    _startEventPolling();
    debugPrint('[DirectStreaming] Created stream, ticket: ${ticket.substring(0, 50)}...');
    return ticket;
  }

  /// Join an existing direct stream as viewer
  Future<String> joinStream({
    required String ticket,
    required String name,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    final result = await direct_api.joinDirectStream(ticketStr: ticket, name: name);
    _startEventPolling();
    debugPrint('[DirectStreaming] Joined stream');
    return result;
  }

  /// Send metadata (for broadcaster)
  Future<void> sendMetadata({
    required String fileName,
    required int fileSize,
    required String mimeType,
    required int totalChunks,
    double? duration,
  }) async {
    await direct_api.directSendMetadata(
      fileName: fileName,
      fileSize: BigInt.from(fileSize),
      mimeType: mimeType,
      totalChunks: totalChunks,
      duration: duration,
    );
    debugPrint('[DirectStreaming] Sent metadata: $fileName, $totalChunks chunks');
  }

  /// Send a chunk (for broadcaster)
  Future<void> sendChunk(int index, Uint8List data) async {
    await direct_api.directSendChunk(index: index, data: data);
  }

  /// Request metadata from broadcaster (for viewer)
  Future<void> requestMetadata() async {
    debugPrint('[DirectStreaming] Requesting metadata...');
    await direct_api.directRequestMetadata();
  }

  /// Request a specific chunk (for viewer)
  Future<void> requestChunk(int index) async {
    await direct_api.directRequestChunk(index: index);
  }

  /// Send presence (keepalive)
  Future<void> sendPresence(String name) async {
    await direct_api.directSendPresence(name: name);
  }

  /// Send arbitrary signal data
  Future<void> sendSignal(Uint8List data) async {
    await direct_api.directSendSignal(data: data);
  }

  /// Get number of connected peers
  Future<int> getPeerCount() async {
    return await direct_api.getDirectPeerCount();
  }

  /// Leave the current stream
  Future<void> leaveStream() async {
    _stopEventPolling();
    await direct_api.leaveDirectStream();
    debugPrint('[DirectStreaming] Left stream');
  }

  /// Check if direct streaming is initialized
  bool isStreamingInitialized() {
    return direct_api.isDirectStreamingInitialized();
  }

  /// Start polling for events
  void _startEventPolling() {
    _stopEventPolling();
    _eventPollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _pollEvents(),
    );
  }

  /// Stop polling for events
  void _stopEventPolling() {
    _eventPollTimer?.cancel();
    _eventPollTimer = null;
  }

  /// Poll for events and emit them
  Future<void> _pollEvents() async {
    try {
      final events = await direct_api.pollDirectEvents();
      if (events.isNotEmpty) {
        debugPrint('[DirectStreaming] ========== POLL EVENTS ==========');
        debugPrint('[DirectStreaming] Received ${events.length} events');
      }
      for (final event in events) {
        _logEvent(event);
        _eventController.add(event);
      }
    } catch (e) {
      debugPrint('[DirectStreaming] Error polling events: $e');
    }
  }

  void _logEvent(direct_api.FlutterDirectEvent event) {
    if (event is direct_api.FlutterDirectEvent_PeerConnected) {
      debugPrint('[DirectStreaming] >>> PEER CONNECTED: ${event.endpointId.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_PeerDisconnected) {
      debugPrint('[DirectStreaming] >>> PEER DISCONNECTED: ${event.endpointId.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_RequestMetadata) {
      debugPrint('[DirectStreaming] >>> METADATA REQUEST from ${event.from.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_Metadata) {
      debugPrint('[DirectStreaming] >>> METADATA: ${event.fileName}, ${event.totalChunks} chunks');
    } else if (event is direct_api.FlutterDirectEvent_RequestChunk) {
      debugPrint('[DirectStreaming] >>> CHUNK REQUEST: index=${event.index} from ${event.from.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_Chunk) {
      debugPrint('[DirectStreaming] >>> CHUNK: index=${event.index}, ${event.data.length} bytes');
    } else if (event is direct_api.FlutterDirectEvent_Presence) {
      debugPrint('[DirectStreaming] >>> PRESENCE: ${event.name} from ${event.from.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_Signal) {
      debugPrint('[DirectStreaming] >>> SIGNAL: ${event.data.length} bytes from ${event.from.substring(0, 16)}...');
    } else if (event is direct_api.FlutterDirectEvent_Error) {
      debugPrint('[DirectStreaming] >>> ERROR: ${event.message}');
    }
  }

  /// Shutdown the streaming endpoint
  Future<void> shutdown() async {
    if (!_isInitialized) return;
    
    _stopEventPolling();
    await direct_api.shutdownDirectStreaming();
    _isInitialized = false;
    _endpointId = null;
    debugPrint('[DirectStreaming] Shutdown complete');
  }

  /// Dispose resources
  void dispose() {
    _stopEventPolling();
    _eventController.close();
  }
}
