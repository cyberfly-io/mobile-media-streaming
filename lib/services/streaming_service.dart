import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cyberfly_streaming/src/rust/api/flutter_api.dart' as rust_api;

/// Streaming service that wraps the Rust implementation
class StreamingService {
  static final StreamingService _instance = StreamingService._internal();
  factory StreamingService() => _instance;
  StreamingService._internal();

  String? _endpointId;
  bool _isInitialized = false;
  Timer? _eventPollTimer;
  final StreamController<rust_api.FlutterStreamEvent> _eventController =
      StreamController<rust_api.FlutterStreamEvent>.broadcast();

  String? get endpointId => _endpointId;
  bool get isInitialized => _isInitialized;
  
  /// Stream of events from the P2P network
  Stream<rust_api.FlutterStreamEvent> get eventStream => _eventController.stream;

  /// Initialize the streaming node
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _endpointId = await rust_api.initStreamingNode();
      _isInitialized = true;
      debugPrint('[StreamingService] Initialized with endpoint: $_endpointId');
    } catch (e) {
      debugPrint('[StreamingService] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Get the endpoint ID
  Future<String> getEndpointId() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _endpointId ?? await rust_api.getEndpointId();
  }

  /// Create a new stream as broadcaster
  Future<String> createStream({required String name}) async {
    if (!_isInitialized) {
      await initialize();
    }
    final ticket = await rust_api.createStream(name: name);
    _startEventPolling();
    return ticket;
  }

  /// Join an existing stream as viewer
  Future<String> joinStream({
    required String ticket,
    required String name,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    final result = await rust_api.joinStream(ticketStr: ticket, name: name);
    _startEventPolling();
    return result;
  }

  /// Broadcast a media chunk (for broadcaster)
  Future<void> broadcastChunk(Uint8List data, int sequence) async {
    await rust_api.broadcastChunk(
      data: data,
      sequence: BigInt.from(sequence),
    );
  }

  /// Send a presence announcement
  Future<void> sendPresence() async {
    debugPrint('[StreamingService] sendPresence: connected=${isConnectedToStream()}');
    await rust_api.sendPresence();
    debugPrint('[StreamingService] sendPresence: sent');
  }

  /// Send a signal (e.g., for WebRTC signaling)
  Future<void> sendSignal(Uint8List data) async {
    // Note: Don't check isConnectedToStream() here as it uses try_lock which
    // can return false during concurrent operations. Let Rust handle the check.
    debugPrint('[StreamingService] sendSignal: sending ${data.length} bytes');
    try {
      await rust_api.sendSignal(data: data);
      debugPrint('[StreamingService] sendSignal: sent successfully');
    } catch (e) {
      debugPrint('[StreamingService] sendSignal: error - $e');
      rethrow;
    }
  }

  /// Leave the current stream
  Future<void> leaveStream() async {
    _stopEventPolling();
    await rust_api.leaveStream();
    debugPrint('[StreamingService] Left stream');
  }

  /// Check if connected to a stream
  bool isConnectedToStream() {
    return rust_api.isConnectedToStream();
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
      final events = await rust_api.pollEvents();
      if (events.isNotEmpty) {
        debugPrint('[StreamingService] ========== POLL EVENTS ==========');
        debugPrint('[StreamingService] Received ${events.length} events from Rust');
      }
      for (final event in events) {
        debugPrint('[StreamingService] Event type: ${event.runtimeType}');
        if (event is rust_api.FlutterStreamEvent_Signal) {
          debugPrint('[StreamingService] >>> SIGNAL EVENT <<<');
          debugPrint('[StreamingService]   From: ${event.from}');
          debugPrint('[StreamingService]   Data size: ${event.data.length} bytes');
          // Try to decode as JSON to see the content
          try {
            final jsonStr = String.fromCharCodes(event.data);
            debugPrint('[StreamingService]   Content: $jsonStr');
          } catch (e) {
            debugPrint('[StreamingService]   Content (hex): ${event.data.take(100).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          }
        } else if (event is rust_api.FlutterStreamEvent_MediaChunk) {
          debugPrint('[StreamingService] >>> MEDIA CHUNK EVENT <<<');
          debugPrint('[StreamingService]   From: ${event.from}');
          debugPrint('[StreamingService]   Sequence: ${event.sequence}');
          debugPrint('[StreamingService]   Data size: ${event.data.length} bytes');
        } else if (event is rust_api.FlutterStreamEvent_Presence) {
          debugPrint('[StreamingService] >>> PRESENCE EVENT <<<');
          debugPrint('[StreamingService]   From: ${event.from}');
          debugPrint('[StreamingService]   Name: ${event.name}');
        } else if (event is rust_api.FlutterStreamEvent_NeighborUp) {
          debugPrint('[StreamingService] >>> NEIGHBOR UP <<<');
          debugPrint('[StreamingService]   Endpoint: ${event.endpointId}');
        } else if (event is rust_api.FlutterStreamEvent_NeighborDown) {
          debugPrint('[StreamingService] >>> NEIGHBOR DOWN <<<');
          debugPrint('[StreamingService]   Endpoint: ${event.endpointId}');
        }
        _eventController.add(event);
      }
    } catch (e) {
      debugPrint('[StreamingService] Error polling events: $e');
    }
  }

  /// Get quality constraints for a preset
  rust_api.QualityConstraints getQualityConstraints(StreamQuality quality) {
    return rust_api.getQualityConstraints(quality: quality.toRustQuality());
  }

  /// Shutdown the streaming node
  Future<void> shutdown() async {
    if (!_isInitialized) return;
    
    _stopEventPolling();
    await rust_api.shutdownStreaming();
    _isInitialized = false;
    _endpointId = null;
    debugPrint('[StreamingService] Shutdown complete');
  }

  /// Dispose resources
  void dispose() {
    _stopEventPolling();
    _eventController.close();
  }
}

/// Stream quality presets
enum StreamQuality {
  low,
  medium,
  high,
  ultra;

  rust_api.Quality toRustQuality() {
    switch (this) {
      case StreamQuality.low:
        return rust_api.Quality.low;
      case StreamQuality.medium:
        return rust_api.Quality.medium;
      case StreamQuality.high:
        return rust_api.Quality.high;
      case StreamQuality.ultra:
        return rust_api.Quality.ultra;
    }
  }

  String get displayName {
    switch (this) {
      case StreamQuality.low:
        return 'Low (360p, 15fps)';
      case StreamQuality.medium:
        return 'Medium (480p, 24fps)';
      case StreamQuality.high:
        return 'High (720p, 30fps)';
      case StreamQuality.ultra:
        return 'Ultra (1080p, 30fps)';
    }
  }
}
