import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/network/socket_service.dart';

enum CallPhase { idle, dialling, ringing, connecting, connected, ended }

/// One call, from dial to hang up.
///
/// Owns the peer connection and the signalling exchange; knows nothing about
/// who is allowed to call whom, because that is the server's decision and
/// duplicating it here would mean two rules that drift apart.
///
/// Media never touches the API server. Audio and video go directly between the
/// two phones, relayed by TURN only when a direct path cannot be found.
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

  /// ICE candidates that arrive before the remote description is set.
  ///
  /// This ordering happens routinely — the callee's candidates can beat the
  /// caller's answer. Applying one early throws and the call silently fails to
  /// connect, so they are held and replayed.
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteReady = false;

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

    await _prepare(_iceFrom(ack));
    _set(CallPhase.ringing);

    // The caller makes the offer as soon as the call is created, so that when
    // the callee answers there is already something to answer.
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    socket.sendSignal(callId!, {'type': 'offer', 'sdp': offer.sdp});
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

    final ack = await socket.answerCall(incomingCallId);
    if (ack['ok'] != true) {
      error = ack['error']?.toString() ?? 'Could not answer';
      _set(CallPhase.ended);
      return error;
    }

    _listen();
    await _prepare(_iceFrom(ack));
    return null;
  }

  List<Map<String, dynamic>> _iceFrom(Map<String, dynamic> ack) {
    final raw = ack['ice_servers'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    // Falls back to public STUN. Works on most home wifi and fails on mobile
    // carriers, which is why the server logs loudly when TURN is missing.
    return [
      {'urls': 'stun:stun.l.google.com:19302'}
    ];
  }

  Future<void> _prepare(List<Map<String, dynamic>> iceServers) async {
    await _initRenderers();

    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    localRenderer.srcObject = _local;

    _pc = await createPeerConnection({
      'iceServers': iceServers,
      // Required by the spec's unified plan; without it the remote track
      // arrives on a path flutter_webrtc no longer reports.
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onIceCandidate = (candidate) {
      if (callId == null) return;
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

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'The connection dropped';
        hangUp();
      }
    };

    notifyListeners();
  }

  void _listen() {
    _sub?.cancel();
    _sub = socket.callStream.listen((event) async {
      if (event.callId != null && callId != null && event.callId != callId) return;

      switch (event.name) {
        case 'call:answered':
          if (phase == CallPhase.ringing) _set(CallPhase.connecting);
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
          await _onSignal(Map<String, dynamic>.from(event.data['signal'] as Map));
          break;
      }
    });
  }

  Future<void> _onSignal(Map<String, dynamic> signal) async {
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
        socket.sendSignal(callId!, {'type': 'answer', 'sdp': answer.sdp});
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
        // Holding these until the remote description exists is the difference
        // between a call that connects and one that rings forever.
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
    _remoteReady = false;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  void _set(CallPhase next) {
    phase = next;
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
