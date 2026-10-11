import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/socket_service.dart';

enum CallPhase { idle, dialling, ringing, connecting, connected, ended }

/// One call, from dial to hang up.
///
/// Signalling matches the working Masthi Chat flow: both sides open a peer
/// connection and attach local media first; the caller only creates the SDP
/// offer *after* the callee has answered. Sending the offer earlier drops it —
/// the callee has no peer connection yet, and a broadcast stream does not
/// buffer `call:signal`.
///
/// Media never touches the API. Audio and video go phone-to-phone.
class CallSession extends ChangeNotifier {
  final SocketService socket;

  CallSession(this.socket);

  RTCPeerConnection? _pc;
  MediaStream? _local;
  StreamSubscription<CallEvent>? _sub;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  CallPhase phase = CallPhase.idle;
  String? callId;
  String? peerName;
  bool isVideo = true;
  bool isCaller = false;
  bool micOn = true;
  bool cameraOn = true;
  bool speakerOn = true;
  String? error;
  DateTime? connectedAt;

  final List<RTCIceCandidate> _pendingCandidates = [];
  final List<Map<String, dynamic>> _pendingSignals = [];
  bool _remoteReady = false;
  bool _offerWhenReady = false;
  Timer? _connectTimeout;

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  /// Place a call. Returns null on success, or a reason to show the member.
  Future<String?> dial({
    required String conversationId,
    required String peerDisplayName,
    bool video = true,
  }) async {
    isCaller = true;
    isVideo = video;
    peerName = peerDisplayName;
    _set(CallPhase.dialling);

    final ack = await socket.startCall(conversationId: conversationId, isVideo: video);
    if (ack['ok'] != true) {
      error = ack['error']?.toString() ?? 'Could not start the call';
      _set(CallPhase.ended);
      return error;
    }

    callId = ack['call_id']?.toString();
    _listen();
    await _prepare(_iceFrom(ack['ice_servers']));
    _set(CallPhase.ringing);
    return null;
  }

  /// Accept an incoming call.
  Future<String?> accept({
    required String incomingCallId,
    required String peerDisplayName,
    bool video = true,
  }) async {
    isCaller = false;
    isVideo = video;
    callId = incomingCallId;
    peerName = peerDisplayName;
    _set(CallPhase.connecting);

    // Masthi Chat opens the peer connection on the incoming screen *before*
    // accept is emitted. Same here: media first, then tell the caller to offer.
    _listen();
    await _prepare(await _loadIce());

    final ack = await socket.answerCall(incomingCallId);
    if (ack['ok'] != true) {
      error = ack['error']?.toString() ?? 'Could not answer';
      _set(CallPhase.ended);
      return error;
    }
    return null;
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
    localRenderer.srcObject = _local;

    speakerOn = isVideo;
    await Helper.setSpeakerphoneOn(speakerOn);

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
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        if (phase != CallPhase.connected) {
          connectedAt = DateTime.now();
          _set(CallPhase.connected);
        } else {
          notifyListeners();
        }
      }
    };

    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (phase != CallPhase.connected) {
          connectedAt = DateTime.now();
          _set(CallPhase.connected);
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        error = 'The connection dropped';
        hangUp();
      }
    };

    notifyListeners();

    if (_offerWhenReady) {
      _offerWhenReady = false;
      await _sendOffer();
    }
    await _flushPendingSignals();
  }

  Future<void> _sendOffer() async {
    final pc = _pc;
    final id = callId;
    if (pc == null || id == null) return;
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo,
    });
    await pc.setLocalDescription(offer);
    socket.sendSignal(id, {'type': 'offer', 'sdp': offer.sdp});
  }

  void _listen() {
    _sub?.cancel();
    _sub = socket.callStream.listen((event) async {
      if (event.callId != null && callId != null && event.callId != callId) return;

      switch (event.name) {
        case 'call:answered':
          if (!isCaller) break;
          if (phase == CallPhase.ringing) _set(CallPhase.connecting);
          if (_pc != null) {
            await _sendOffer();
          } else {
            _offerWhenReady = true;
          }
          break;

        case 'call:ended':
        case 'call:cancelled':
          final reason = event.data['reason']?.toString();
          if (reason == 'rejected') error = '${peerName ?? 'They'} declined';
          if (reason == 'missed') error = 'No answer';
          await _teardown();
          _set(CallPhase.ended);
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
  }

  Future<void> _drainCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  Future<void> toggleMic() async {
    micOn = !micOn;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraOn = !cameraOn;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = cameraOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  Future<void> hangUp() async {
    final id = callId;
    await _teardown();
    _set(CallPhase.ended);
    if (id != null) await socket.endCall(id);
  }

  Future<void> decline(String incomingCallId) async {
    await socket.rejectCall(incomingCallId);
    await _teardown();
    _set(CallPhase.ended);
  }

  Future<void> _teardown() async {
    _connectTimeout?.cancel();
    _connectTimeout = null;
    await _sub?.cancel();
    _sub = null;
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    await _pc?.close();
    _pc = null;
    _pendingCandidates.clear();
    _pendingSignals.clear();
    _remoteReady = false;
    _offerWhenReady = false;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  void _set(CallPhase next) {
    phase = next;
    if (next == CallPhase.connecting || next == CallPhase.ringing) {
      _connectTimeout?.cancel();
      _connectTimeout = Timer(const Duration(seconds: 40), () {
        if (phase == CallPhase.connecting || phase == CallPhase.ringing) {
          error = phase == CallPhase.ringing ? 'No answer' : 'Could not connect';
          hangUp();
        }
      });
    } else {
      _connectTimeout?.cancel();
      _connectTimeout = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _teardown();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
