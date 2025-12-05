import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC signaling message types (compatible with web dashboard)
enum WebRTCSignalType {
  offer('webrtc-offer'),
  answer('webrtc-answer'),
  iceCandidate('webrtc-ice-candidate'),
  requestOffer('webrtc-request-offer');

  final String value;
  const WebRTCSignalType(this.value);

  static WebRTCSignalType? fromString(String value) {
    return WebRTCSignalType.values.cast<WebRTCSignalType?>().firstWhere(
          (e) => e?.value == value,
          orElse: () => null,
        );
  }
}

/// WebRTC signal message (matches web dashboard format)
class WebRTCSignal {
  final WebRTCSignalType type;
  final String from;
  final String? to;
  final String? sdp;
  final Map<String, dynamic>? candidate;

  WebRTCSignal({
    required this.type,
    required this.from,
    this.to,
    this.sdp,
    this.candidate,
  });

  factory WebRTCSignal.fromJson(Map<String, dynamic> json) {
    return WebRTCSignal(
      type: WebRTCSignalType.fromString(json['type'] as String) ??
          WebRTCSignalType.requestOffer,
      from: json['from'] as String,
      to: json['to'] as String?,
      sdp: json['sdp'] as String?,
      candidate: json['candidate'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'from': from,
      if (to != null) 'to': to,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
    };
  }

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  static WebRTCSignal? fromBytes(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type != null && type.startsWith('webrtc-')) {
        return WebRTCSignal.fromJson(json);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

/// Peer connection info
class PeerConnectionInfo {
  final RTCPeerConnection pc;
  final String peerId;
  DateTime lastActivity;

  PeerConnectionInfo({
    required this.pc,
    required this.peerId,
  }) : lastActivity = DateTime.now();
}

/// WebRTC configuration (STUN + TURN servers for NAT traversal)
/// Includes free TURN servers for symmetric NAT scenarios
final Map<String, dynamic> _rtcConfiguration = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},
    // Free TURN servers from Open Relay Project
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ],
  'iceCandidatePoolSize': 10,
  'iceTransportPolicy': 'all', // Try all candidates including relay
};

/// WebRTC service for P2P video streaming
/// Compatible with cyberfly-node-web-dashboard WebRTC implementation
class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  String _myEndpointId = '';
  MediaStream? _localStream;
  final Map<String, PeerConnectionInfo> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingIceCandidates = {};

  // Callbacks
  Function(WebRTCSignal signal)? onSignalToSend;
  Function(MediaStream stream)? onRemoteStream;
  Function(String state)? onConnectionStateChange;

  // Renderers for video display
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isInitialized = false;
  bool _isBroadcasting = false;
  bool _isWatching = false;

  bool get isInitialized => _isInitialized;
  bool get isBroadcasting => _isBroadcasting;
  bool get isWatching => _isWatching;
  MediaStream? get localStream => _localStream;
  int get peerCount => _peerConnections.length;

  /// Initialize the WebRTC service
  Future<void> initialize(String endpointId) async {
    if (_isInitialized) return;

    _myEndpointId = endpointId;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _isInitialized = true;
    debugPrint('[WebRTC] Initialized with endpoint: ${_myEndpointId.substring(0, 16)}...');
  }

  /// Start broadcasting with camera/microphone
  Future<void> startBroadcast({
    bool useCamera = true,
    bool useAudio = true,
    String quality = 'medium',
  }) async {
    if (!_isInitialized) throw Exception('WebRTC not initialized');
    if (_isBroadcasting) return;

    final constraints = _getMediaConstraints(quality, useCamera, useAudio);
    
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      localRenderer.srcObject = _localStream;
      _isBroadcasting = true;
      debugPrint('[WebRTC] Broadcasting started with ${_localStream!.getTracks().length} tracks');
    } catch (e) {
      debugPrint('[WebRTC] Failed to get media: $e');
      rethrow;
    }
  }

  /// Start screen sharing broadcast
  Future<void> startScreenShare({bool useAudio = true}) async {
    if (!_isInitialized) throw Exception('WebRTC not initialized');
    if (_isBroadcasting) return;

    try {
      _localStream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': useAudio,
      });
      localRenderer.srcObject = _localStream;
      _isBroadcasting = true;
      debugPrint('[WebRTC] Screen sharing started');
    } catch (e) {
      debugPrint('[WebRTC] Failed to get display media: $e');
      rethrow;
    }
  }

  /// Handle incoming WebRTC signal (from Iroh gossip)
  Future<void> handleSignal(WebRTCSignal signal) async {
    // Ignore messages from ourselves
    if (signal.from == _myEndpointId) return;

    // If message is targeted to someone else, ignore
    if (signal.to != null && signal.to != _myEndpointId) return;

    debugPrint('[WebRTC] Received signal: ${signal.type.value} from: ${signal.from.substring(0, 8)}');

    switch (signal.type) {
      case WebRTCSignalType.requestOffer:
        await _handleRequestOffer(signal);
        break;
      case WebRTCSignalType.offer:
        await _handleOffer(signal);
        break;
      case WebRTCSignalType.answer:
        await _handleAnswer(signal);
        break;
      case WebRTCSignalType.iceCandidate:
        await _handleIceCandidate(signal);
        break;
    }
  }

  /// Request an offer from broadcaster (as viewer)
  Future<void> requestOffer() async {
    if (!_isInitialized) {
      debugPrint('[WebRTC] requestOffer: Not initialized, skipping');
      return;
    }
    
    _isWatching = true;
    final signal = WebRTCSignal(
      type: WebRTCSignalType.requestOffer,
      from: _myEndpointId,
    );
    
    debugPrint('[WebRTC] requestOffer: Created signal, callback set: ${onSignalToSend != null}');
    if (onSignalToSend != null) {
      debugPrint('[WebRTC] requestOffer: Calling onSignalToSend callback...');
      onSignalToSend!(signal);
    } else {
      debugPrint('[WebRTC] requestOffer: ERROR - onSignalToSend callback is null!');
    }
    debugPrint('[WebRTC] Sent request-offer from ${_myEndpointId.substring(0, 16)}');
  }

  /// Handle request-offer from viewer (as broadcaster)
  Future<void> _handleRequestOffer(WebRTCSignal signal) async {
    if (_localStream == null) {
      debugPrint('[WebRTC] Not broadcasting, ignoring request-offer');
      return;
    }

    // Check if tracks are still active
    final activeTracks = _localStream!.getTracks().where((t) => t.enabled).toList();
    if (activeTracks.isEmpty) {
      debugPrint('[WebRTC] Media tracks ended, ignoring request-offer');
      return;
    }

    debugPrint('[WebRTC] Creating offer for peer: ${signal.from.substring(0, 8)}');

    // Create peer connection for this viewer
    final pc = await _createBroadcasterPeerConnection(signal.from);
    
    // Create and send offer
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    final offerSignal = WebRTCSignal(
      type: WebRTCSignalType.offer,
      from: _myEndpointId,
      to: signal.from,
      sdp: offer.sdp,
    );
    onSignalToSend?.call(offerSignal);
  }

  /// Handle offer from broadcaster (as viewer)
  Future<void> _handleOffer(WebRTCSignal signal) async {
    debugPrint('[WebRTC] Received offer from ${signal.from.substring(0, 8)}, creating answer');

    // Create peer connection for receiving
    final pc = await _createViewerPeerConnection(signal.from);

    // Set remote description (the offer)
    debugPrint('[WebRTC] Setting remote description (offer)...');
    await pc.setRemoteDescription(
      RTCSessionDescription(signal.sdp, 'offer'),
    );
    debugPrint('[WebRTC] Remote description set');

    // Apply any pending ICE candidates
    final pending = _pendingIceCandidates[signal.from] ?? [];
    if (pending.isNotEmpty) {
      debugPrint('[WebRTC] Applying ${pending.length} pending ICE candidates...');
      for (final candidate in pending) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          debugPrint('[WebRTC] Error adding pending candidate: $e');
        }
      }
      _pendingIceCandidates.remove(signal.from);
    }

    // Create and send answer
    debugPrint('[WebRTC] Creating answer...');
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    debugPrint('[WebRTC] Local description set (answer)');

    final answerSignal = WebRTCSignal(
      type: WebRTCSignalType.answer,
      from: _myEndpointId,
      to: signal.from,
      sdp: answer.sdp,
    );
    onSignalToSend?.call(answerSignal);
    debugPrint('[WebRTC] Answer sent');
  }

  /// Handle answer from viewer (as broadcaster)
  Future<void> _handleAnswer(WebRTCSignal signal) async {
    debugPrint('[WebRTC] Received answer from: ${signal.from.substring(0, 8)}');

    final peerInfo = _peerConnections[signal.from];
    if (peerInfo == null) {
      debugPrint('[WebRTC] No peer connection found for answer');
      return;
    }

    debugPrint('[WebRTC] Setting remote description (answer)...');
    await peerInfo.pc.setRemoteDescription(
      RTCSessionDescription(signal.sdp, 'answer'),
    );
    debugPrint('[WebRTC] Remote description set');

    // Apply any pending ICE candidates
    final pending = _pendingIceCandidates[signal.from] ?? [];
    if (pending.isNotEmpty) {
      debugPrint('[WebRTC] Applying ${pending.length} pending ICE candidates...');
      for (final candidate in pending) {
        try {
          await peerInfo.pc.addCandidate(candidate);
        } catch (e) {
          debugPrint('[WebRTC] Error adding pending candidate: $e');
        }
      }
      _pendingIceCandidates.remove(signal.from);
    }
  }

  /// Handle ICE candidate
  Future<void> _handleIceCandidate(WebRTCSignal signal) async {
    if (signal.candidate == null) {
      debugPrint('[WebRTC] Received empty ICE candidate (end of candidates)');
      return;
    }

    final candidateStr = signal.candidate!['candidate'] as String?;
    if (candidateStr == null || candidateStr.isEmpty) {
      debugPrint('[WebRTC] Received null/empty candidate string');
      return;
    }

    // Log candidate type for debugging
    final isRelay = candidateStr.contains('typ relay');
    final isHost = candidateStr.contains('typ host');
    final isSrflx = candidateStr.contains('typ srflx');
    debugPrint('[WebRTC] ICE candidate type: ${isRelay ? "RELAY/TURN" : isHost ? "HOST" : isSrflx ? "SRFLX/STUN" : "OTHER"}');

    final candidate = RTCIceCandidate(
      candidateStr,
      signal.candidate!['sdpMid'] as String?,
      signal.candidate!['sdpMLineIndex'] as int?,
    );

    final peerInfo = _peerConnections[signal.from];
    if (peerInfo == null) {
      debugPrint('[WebRTC] No peer connection for ${signal.from.substring(0, 8)}, queuing candidate');
      _pendingIceCandidates.putIfAbsent(signal.from, () => []).add(candidate);
      return;
    }

    // Check if remote description is set
    final remoteDesc = await peerInfo.pc.getRemoteDescription();
    if (remoteDesc != null) {
      debugPrint('[WebRTC] Adding ICE candidate from: ${signal.from.substring(0, 8)}');
      try {
        await peerInfo.pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('[WebRTC] Error adding ICE candidate: $e');
      }
    } else {
      // Queue the candidate for later
      debugPrint('[WebRTC] Remote description not set yet, queuing ICE candidate from: ${signal.from.substring(0, 8)}');
      _pendingIceCandidates.putIfAbsent(signal.from, () => []).add(candidate);
    }
  }

  /// Create peer connection for broadcasting (adding local tracks)
  Future<RTCPeerConnection> _createBroadcasterPeerConnection(String peerId) async {
    final pc = await createPeerConnection(_rtcConfiguration);

    // Add all tracks from the local stream
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        debugPrint('[WebRTC] Adding track to peer connection: ${track.kind}');
        await pc.addTrack(track, _localStream!);
      }
    }

    _setupPeerConnectionCallbacks(pc, peerId);
    _peerConnections[peerId] = PeerConnectionInfo(pc: pc, peerId: peerId);
    
    return pc;
  }

  /// Create peer connection for viewing (receiving remote tracks)
  Future<RTCPeerConnection> _createViewerPeerConnection(String peerId) async {
    final pc = await createPeerConnection(_rtcConfiguration);

    // Handle incoming tracks
    pc.onTrack = (RTCTrackEvent event) {
      debugPrint('[WebRTC] Received track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        onRemoteStream?.call(event.streams[0]);
      }
    };

    _setupPeerConnectionCallbacks(pc, peerId);
    _peerConnections[peerId] = PeerConnectionInfo(pc: pc, peerId: peerId);
    
    return pc;
  }

  /// Setup common peer connection callbacks
  void _setupPeerConnectionCallbacks(RTCPeerConnection pc, String peerId) {
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final candidateStr = candidate.candidate;
      if (candidateStr == null || candidateStr.isEmpty) {
        debugPrint('[WebRTC] ICE gathering complete (null candidate)');
        return;
      }
      
      // Log candidate type
      final isRelay = candidateStr.contains('typ relay');
      final isHost = candidateStr.contains('typ host');
      final isSrflx = candidateStr.contains('typ srflx');
      debugPrint('[WebRTC] Local ICE candidate (${isRelay ? "TURN" : isHost ? "HOST" : isSrflx ? "STUN" : "OTHER"}): ${candidateStr.substring(0, candidateStr.length.clamp(0, 60))}...');
      
      final signal = WebRTCSignal(
        type: WebRTCSignalType.iceCandidate,
        from: _myEndpointId,
        to: peerId,
        candidate: candidate.toMap(),
      );
      onSignalToSend?.call(signal);
    };

    pc.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('[WebRTC] ICE gathering state: $state');
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTC] Connection state: $state');
      onConnectionStateChange?.call(state.toString());
      
      // Clean up disconnected peers
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _removePeer(peerId);
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[WebRTC] ICE connection state: $state');
    };

    pc.onSignalingState = (RTCSignalingState state) {
      debugPrint('[WebRTC] Signaling state: $state');
    };
  }

  /// Remove a peer connection
  void _removePeer(String peerId) {
    final peerInfo = _peerConnections.remove(peerId);
    peerInfo?.pc.close();
    _pendingIceCandidates.remove(peerId);
    debugPrint('[WebRTC] Removed peer: ${peerId.substring(0, 8)}');
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream == null) return;

    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
      debugPrint('[WebRTC] Camera switched');
    }
  }

  /// Toggle microphone mute
  void toggleMicrophone() {
    if (_localStream == null) return;

    final audioTrack = _localStream!.getAudioTracks().firstOrNull;
    if (audioTrack != null) {
      audioTrack.enabled = !audioTrack.enabled;
      debugPrint('[WebRTC] Microphone ${audioTrack.enabled ? 'unmuted' : 'muted'}');
    }
  }

  /// Toggle video
  void toggleVideo() {
    if (_localStream == null) return;

    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      videoTrack.enabled = !videoTrack.enabled;
      debugPrint('[WebRTC] Video ${videoTrack.enabled ? 'enabled' : 'disabled'}');
    }
  }

  /// Stop broadcasting/watching
  Future<void> stop() async {
    // Close all peer connections
    for (final peerInfo in _peerConnections.values) {
      await peerInfo.pc.close();
    }
    _peerConnections.clear();
    _pendingIceCandidates.clear();

    // Stop local stream
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    _isBroadcasting = false;
    _isWatching = false;
    debugPrint('[WebRTC] Stopped');
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    _isInitialized = false;
    debugPrint('[WebRTC] Disposed');
  }

  /// Get media constraints for quality preset
  Map<String, dynamic> _getMediaConstraints(String quality, bool video, bool audio) {
    final Map<String, dynamic> videoConstraints;
    
    switch (quality) {
      case 'low':
        videoConstraints = {
          'width': {'ideal': 640},
          'height': {'ideal': 360},
          'frameRate': {'ideal': 15},
        };
        break;
      case 'high':
        videoConstraints = {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'frameRate': {'ideal': 30},
        };
        break;
      case 'ultra':
        videoConstraints = {
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
          'frameRate': {'ideal': 30},
        };
        break;
      case 'medium':
      default:
        videoConstraints = {
          'width': {'ideal': 854},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 24},
        };
        break;
    }

    // Audio constraints matching web dashboard
    final Map<String, dynamic> audioConstraints = {
      'sampleRate': 48000,
      'channelCount': 2,
      'echoCancellation': true,
      'noiseSuppression': true,
    };

    return {
      'audio': audio ? audioConstraints : false,
      'video': video ? videoConstraints : false,
    };
  }
}
