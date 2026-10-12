import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/socket_service.dart';
import 'call_kit.dart';

enum CallPhase { idle, dialling, ringing, connecting, connected, ended }

/// One call, from dial to hang up.
///
/// Signalling matches the working Masthi Chat flow: both sides open a peer
/// connection and attach local media first; the caller only creates the SDP
/// offer *after* the callee has answered. Sending the offer earlier drops it —
/// the callee has no peer connection yet, and a broadcast stream does not
/// buffer `call:signal`.
///
/// Owned by [CallManager], not by a screen: the member can leave the call
/// screen and keep talking while they use the rest of the app.
///
/// Media never touches the API. Audio and video go phone-to-phone.
class CallSession extends ChangeNotifier {
  final SocketService socket;
  final String conversationId;
  final String peerName;
  final String peerPhoto;
  final bool isVideo;
  final bool isCaller;

  CallSession({
    required this.socket,
    required this.conversationId,
    required this.peerName,
    this.peerPhoto = '',
    required this.isVideo,
    required this.isCaller,
  });

  RTCPeerConnection? _pc;
  MediaStream? _local;
  StreamSubscription<CallEvent>? _sub;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool _disposed = false;

  CallPhase phase = CallPhase.idle;
  String? callId;
  bool micOn = true;
  bool cameraOn = true;
  bool speakerOn = true;
  bool reconnecting = false;
  bool hasRemoteVideo = false;

  /// Why the call ended, when it was not a normal hang-up.
  String? error;

  /// A failure the member can fix by upgrading.
  bool needsPlan = false;
  DateTime? connectedAt;

  final List<RTCIceCandidate> _pendingCandidates = [];
  final List<Map<String, dynamic>> _pendingSignals = [];
  bool _remoteReady = false;
  bool _offerWhenReady = false;
  bool _offerSent = false;
  bool _hangUpRequested = false;
  Timer? _phaseTimeout;
  Timer? _reconnectGrace;
  Timer? _iceRestartDelay;

  bool get isLive => phase != CallPhase.ended && phase != CallPhase.idle;

  IncomingCallData get identity => IncomingCallData(
        callId: callId ?? '',
        conversationId: conversationId,
        callerName: peerName,
        callerPhoto: peerPhoto,
        isVideo: isVideo,
        outgoing: isCaller,
        shownAt: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _initRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  /// Place a call. Returns null on success, or a reason to show the member.
  Future<String?> dial() async {
    _set(CallPhase.dialling);
    _listen();

    final ack = await socket.startCall(conversationId: conversationId, isVideo: isVideo);
    if (ack['ok'] != true) {
      needsPlan = ack['code'] == 'PLAN_REQUIRED';
      return _fail(ack['error']?.toString() ?? 'Could not start the call');
    }

    callId = ack['call_id']?.toString();
    // The member pressed end while the server was still setting up.
    if (_hangUpRequested || phase == CallPhase.ended) {
      final id = callId;
      if (id != null) await _endOnServer(id);
      return null;
    }

    try {
      await _prepare(_iceFrom(ack['ice_servers']));
    } catch (e) {
      debugPrint('call media failed: $e');
      await hangUp(reason: _mediaError);
      return error;
    }
    if (phase == CallPhase.dialling) _set(CallPhase.ringing);
    return null;
  }

  /// Accept an incoming call.
  Future<String?> accept(String incomingCallId) async {
    callId = incomingCallId;
    _set(CallPhase.connecting);

    // Masthi Chat opens the peer connection on the incoming screen *before*
    // accept is emitted. Same here: media first, then tell the caller to offer.
    _listen();
    try {
      await _prepare(await _loadIce());
    } catch (e) {
      debugPrint('call media failed: $e');
      await hangUp(reason: _mediaError);
      return error;
    }
    if (phase == CallPhase.ended) return error;

    // A cold start from the lock screen is still connecting its socket.
    final ack = await socket.answerCall(incomingCallId);
    if (phase == CallPhase.ended) return error;
    if (ack['ok'] != true) {
      final why = ack['code'] == 'CALL_OVER'
          ? 'This call has already ended'
          : ack['error']?.toString() ?? 'Could not answer';
      await _teardown();
      error = why;
      _set(CallPhase.ended);
      return why;
    }
    return null;
  }

  String get _mediaError => isVideo
      ? 'Could not start the camera or microphone'
      : 'Could not start the microphone';

  Future<String?> _fail(String message) async {
    error = message;
    await _teardown();
    _set(CallPhase.ended);
    return message;
  }

  /// Copied from masthiChatFlutter/lib/CallScreen.dart.
  /// That app never fetched ICE from the server; the phones used this list.
  static const _masthiIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': 'turn:relay.metered.ca:80',
      'username': 'openai',
      'credential': 'openai123',
    },
  ];

  List<Map<String, dynamic>> _iceFrom(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return List<Map<String, dynamic>>.from(_masthiIceServers);
  }

  Future<List<Map<String, dynamic>>> _loadIce() async {
    try {
      final dio = DioClient.instance;
      final resp = await dio.get(ApiEndpoints.iceServers);
      final data = resp.data;
      dynamic list;
      if (data is Map) {
        final inner = data['data'];
        if (inner is Map) {
          list = inner['ice_servers'];
        }
      }
      final parsed = _iceFrom(list);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {}
    return List<Map<String, dynamic>>.from(_masthiIceServers);
  }

  Future<void> _prepare([List<Map<String, dynamic>>? iceServers]) async {
    await _initRenderers();

    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            }
          : false,
    });
    if (phase == CallPhase.ended) {
      await _teardown();
      return;
    }
    localRenderer.srcObject = _local;

    speakerOn = isVideo;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}

    _pc = await createPeerConnection({
      'iceServers': iceServers ?? _masthiIceServers,
      'sdpSemantics': 'unified-plan',
    }, {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': isVideo,
      },
      'optional': [],
    });

    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onIceCandidate = (candidate) {
      if (callId == null || candidate.candidate == null) return;
      socket.sendSignal(callId!, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      if (event.track.kind == 'video') hasRemoteVideo = true;
      _markConnected();
    };

    _pc!.onIceConnectionState = _onIceState;

    _safeNotify();

    if (_offerWhenReady) {
      _offerWhenReady = false;
      await _sendOffer();
    }
    await _flushPendingSignals();
  }

  void _markConnected() {
    if (phase == CallPhase.ended) return;
    if (phase != CallPhase.connected) {
      connectedAt ??= DateTime.now();
      _set(CallPhase.connected);
      final id = callId;
      if (id != null) CallKit.markConnected(id);
    } else {
      _safeNotify();
    }
  }

  /// Networks change mid-call — Wi-Fi to mobile data, a lift, a tunnel. The
  /// call survives that if it is given a moment and a fresh route, so a
  /// dropped path is "reconnecting", not "ended".
  void _onIceState(RTCIceConnectionState state) {
    if (phase == CallPhase.ended) return;
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _iceRestartDelay?.cancel();
        _reconnectGrace?.cancel();
        _reconnectGrace = null;
        if (reconnecting) {
          reconnecting = false;
          _safeNotify();
        }
        _markConnected();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _startReconnecting(restartAfter: const Duration(seconds: 3));
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _startReconnecting(restartAfter: Duration.zero);
        break;
      default:
        break;
    }
  }

  void _startReconnecting({required Duration restartAfter}) {
    // Before the first connection the phase timeout is in charge.
    if (phase != CallPhase.connected) return;
    if (!reconnecting) {
      reconnecting = true;
      _safeNotify();
    }
    _reconnectGrace ??= Timer(const Duration(seconds: 20), () {
      if (reconnecting && phase != CallPhase.ended) {
        hangUp(reason: 'The call was disconnected');
      }
    });
    // Only the caller renegotiates, so the two sides never offer at once.
    if (!isCaller) return;
    _iceRestartDelay?.cancel();
    _iceRestartDelay = Timer(restartAfter, () async {
      if (!reconnecting || phase == CallPhase.ended) return;
      try {
        await socket.ensureConnected();
        await _sendOffer(iceRestart: true);
      } catch (e) {
        debugPrint('ice restart failed: $e');
      }
    });
  }

  Future<void> _sendOffer({bool iceRestart = false}) async {
    final pc = _pc;
    final id = callId;
    if (pc == null || id == null) return;
    if (!iceRestart) {
      if (_offerSent) return;
      _offerSent = true;
    }
    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
        if (iceRestart) 'iceRestart': true,
      });
      await pc.setLocalDescription(offer);
      socket.sendSignal(id, {'type': 'offer', 'sdp': offer.sdp});
    } catch (e) {
      if (!iceRestart) _offerSent = false;
      debugPrint('offer failed: $e');
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = socket.callStream.listen((event) async {
      if (phase == CallPhase.ended) return;
      if (event.callId == null || callId == null || event.callId != callId) return;

      switch (event.name) {
        case 'call:answered':
          if (!isCaller) break;
          if (phase == CallPhase.ringing || phase == CallPhase.dialling) {
            _set(CallPhase.connecting);
          }
          if (_pc != null) {
            await _sendOffer();
          } else {
            _offerWhenReady = true;
          }
          break;

        case 'call:cancelled':
          // Sent to this member's other phones when this one picks up.
          if (event.data['reason'] == 'answered_elsewhere') break;
          await _endedRemotely(event.data['reason']?.toString());
          break;

        case 'call:ended':
          await _endedRemotely(event.data['reason']?.toString());
          break;

        case 'call:signal':
          final raw = event.data['signal'];
          if (raw is Map) {
            await _onSignal(Map<String, dynamic>.from(raw));
          }
          break;
      }
    });
  }

  Future<void> _endedRemotely(String? reason) async {
    switch (reason) {
      case 'rejected':
        error = '$peerName declined';
        break;
      case 'missed':
        error = 'No answer';
        break;
      case 'disconnected':
        error = 'The call was disconnected';
        break;
    }
    await _teardown();
    _set(CallPhase.ended);
  }

  Future<void> _onSignal(Map<String, dynamic> signal) async {
    if (_pc == null) {
      _pendingSignals.add(signal);
      return;
    }
    await _applySignal(signal);
  }

  Future<void> _flushPendingSignals() async {
    final pending = List<Map<String, dynamic>>.from(_pendingSignals);
    _pendingSignals.clear();
    for (final s in pending) {
      await _applySignal(s);
    }
  }

  Future<void> _applySignal(Map<String, dynamic> signal) async {
    final pc = _pc;
    if (pc == null) return;

    // One malformed or out-of-order message must not take the call down.
    try {
      switch (signal['type']) {
        case 'offer':
          await pc.setRemoteDescription(
            RTCSessionDescription(signal['sdp']?.toString(), 'offer'),
          );
          _remoteReady = true;
          await _drainCandidates();

          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          if (callId != null) {
            socket.sendSignal(callId!, {'type': 'answer', 'sdp': answer.sdp});
          }
          break;

        case 'answer':
          final state = await pc.getSignalingState();
          if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) break;
          await pc.setRemoteDescription(
            RTCSessionDescription(signal['sdp']?.toString(), 'answer'),
          );
          _remoteReady = true;
          await _drainCandidates();
          break;

        case 'candidate':
          final candidate = RTCIceCandidate(
            signal['candidate']?.toString(),
            signal['sdpMid']?.toString(),
            (signal['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_remoteReady) {
            await pc.addCandidate(candidate);
          } else {
            _pendingCandidates.add(candidate);
          }
          break;
      }
    } catch (e) {
      debugPrint('signal ${signal['type']} failed: $e');
    }
  }

  Future<void> _drainCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in pending) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> toggleMic() async {
    micOn = !micOn;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    _safeNotify();
  }

  Future<void> toggleCamera() async {
    cameraOn = !cameraOn;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = cameraOn;
    }
    _safeNotify();
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}
    _safeNotify();
  }

  /// End the call from this side. Safe to call more than once, and from any
  /// state — including before the server has handed out a call id.
  Future<void> hangUp({String? reason}) async {
    if (phase == CallPhase.ended) return;
    if (reason != null) error ??= reason;
    final id = callId;
    if (id == null && phase == CallPhase.dialling) {
      // dial() finishes the job once the server replies with an id.
      _hangUpRequested = true;
    }
    await _teardown();
    _set(CallPhase.ended);
    if (id != null) await _endOnServer(id);
  }

  Future<void> _endOnServer(String id) async {
    final ack = await socket.endCall(id);
    if (ack['ok'] != true) {
      // No socket right now. Over HTTP instead, or the other phone keeps
      // ringing — or keeps showing a frozen call — until it times out.
      await CallKit.endOverHttp(id);
    }
  }

  Future<void> _teardown() async {
    _phaseTimeout?.cancel();
    _phaseTimeout = null;
    _reconnectGrace?.cancel();
    _reconnectGrace = null;
    _iceRestartDelay?.cancel();
    _iceRestartDelay = null;
    reconnecting = false;
    await _sub?.cancel();
    _sub = null;
    final local = _local;
    _local = null;
    for (final t in local?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await local?.dispose();
    } catch (_) {}
    final pc = _pc;
    _pc = null;
    try {
      await pc?.close();
    } catch (_) {}
    _pendingCandidates.clear();
    _pendingSignals.clear();
    _remoteReady = false;
    _offerWhenReady = false;
    if (_renderersReady && !_disposed) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _set(CallPhase next) {
    if (phase == CallPhase.ended) return;
    phase = next;
    _phaseTimeout?.cancel();
    _phaseTimeout = null;
    // Backstops only: the server rings out at 45 seconds and says so.
    if (next == CallPhase.ringing || next == CallPhase.dialling) {
      _phaseTimeout = Timer(const Duration(seconds: 55), () {
        if (phase == CallPhase.ringing || phase == CallPhase.dialling) {
          hangUp(reason: 'No answer');
        }
      });
    } else if (next == CallPhase.connecting) {
      _phaseTimeout = Timer(const Duration(seconds: 35), () {
        if (phase == CallPhase.connecting) hangUp(reason: 'Could not connect');
      });
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
    if (_renderersReady) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}
