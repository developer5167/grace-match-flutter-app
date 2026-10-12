import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as ck;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/notifications/push_center.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import 'call_kit.dart';
import 'call_notifications.dart';
import 'call_session.dart';

/// The one live call, and everything that rings.
///
/// The call belongs here rather than to the call screen, which is what makes
/// it behave like a phone call: the member can leave the screen, read their
/// chats, lock the phone, and the call carries on — with a bar at the top of
/// the app to come back to it.
///
/// Calls arrive three ways, and all three land in [onIncoming]: the socket
/// while the app is open, a push while it is in the background, and a push
/// that wakes it from closed (handled in a background isolate by [CallKit]).
class CallManager {
  CallManager._();
  static final instance = CallManager._();

  late SocketService _socket;
  bool _started = false;

  final active = ValueNotifier<CallSession?>(null);

  /// Whether the full call screen is showing. When it is not and a call is
  /// live, the app shows the ongoing-call bar instead.
  final screenOpen = ValueNotifier<bool>(false);

  final Map<String, IncomingCallData> _ringing = {};
  String? _sheetCallId;
  StreamSubscription<CallEvent>? _socketSub;
  StreamSubscription<ck.CallEvent?>? _kitSub;

  bool get inCall => active.value?.isLive == true;

  void start(SocketService socket) {
    if (_started) return;
    _started = true;
    _socket = socket;
    socket.activeCallId = () {
      final s = active.value;
      return s != null && s.isLive ? s.callId : null;
    };
    _socketSub = socket.callStream.listen(_onSocketEvent);
    _kitSub = FlutterCallkitIncoming.onEvent.listen(_onKitEvent, onError: (_) {});
    PushCenter.extraResponseHandler = _onLocalNotification;
    CallNotifications.hide();
  }

  bool _onLocalNotification(NotificationResponse response) {
    final data = PushCenter.decode(response.payload);
    if (data?['kind']?.toString() != 'ongoing_call') return false;
    if (response.actionId == 'call_hangup') {
      active.value?.hangUp();
    } else {
      openScreen();
    }
    return true;
  }

  // ── Incoming ─────────────────────────────────────────────────────────

  void _onSocketEvent(CallEvent event) {
    switch (event.name) {
      case 'call:incoming':
        onIncoming({...event.data, 'kind': 'incoming_call'});
        break;
      case 'call:cancelled':
      case 'call:ended':
        final id = event.callId;
        if (id != null && active.value?.callId != id) onCancelled(id);
        break;
    }
  }

  Future<void> onIncoming(Map<String, dynamic> raw) async {
    final call = CallKit.parse(raw);
    if (call == null) return;
    if (active.value?.callId == call.callId) return;
    // The server refuses a second call to someone already on one; this only
    // guards the instant between their call starting and the server knowing.
    if (inCall) return;
    _ringing[call.callId] = call;

    await CallKit.ring(call);

    // App already in the member's hand: answer here, not from the shade.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _showSheet(call);
    }
  }

  /// Phone unlocked onto the app while a call is still ringing.
  void onAppResumed() {
    if (inCall || _ringing.isEmpty) return;
    _showSheet(_ringing.values.last);
  }

  void onCancelled(String callId) {
    if (active.value?.callId == callId) return;
    final wasRinging = _ringing.remove(callId) != null;
    if (wasRinging) AppHaptics.light();
    CallKit.dismissIfRinging(callId);
    _closeSheet(callId);
  }

  void _onKitEvent(ck.CallEvent? event) {
    if (event == null) return;
    switch (event) {
      case ck.CallEventActionCallAccept(:final callKitParams):
        final data = _dataFrom(callKitParams);
        if (data != null) acceptIncoming(data, fromCallKit: true);
        break;
      case ck.CallEventActionCallDecline(:final callKitParams):
        decline(callKitParams.id, fromCallKit: true);
        break;
      case ck.CallEventActionCallEnded(:final callKitParams):
        // "Hang up" on the ongoing-call notification.
        final session = active.value;
        if (session != null && session.callId == callKitParams.id && session.isLive) {
          session.hangUp();
        }
        break;
      case ck.CallEventActionCallTimeout(:final id):
        _ringing.remove(id);
        _closeSheet(id);
        break;
      default:
        break;
    }
  }

  IncomingCallData? _dataFrom(ck.CallKitParams p) {
    final extra = p.extra;
    if (extra != null) {
      final parsed = CallKit.parse(Map<String, dynamic>.from(extra));
      if (parsed != null) return parsed;
    }
    return _ringing[p.id];
  }

  /// Answer. From the lock screen, the ringing notification, or the in-app
  /// sheet — all end up here, and none of them go through the splash screen.
  Future<void> acceptIncoming(
    IncomingCallData call, {
    bool fromCallKit = false,
    bool navigate = true,
  }) async {
    final current = active.value;
    if (current != null && current.callId == call.callId) {
      if (navigate) openScreen();
      return;
    }
    if (current != null && current.isLive) {
      await current.hangUp();
    }
    _ringing.remove(call.callId);
    _closeSheet(call.callId);
    // Always take the ringing notification down. Answering from inside the
    // app used to leave it sitting in the shade. CallKit's own Accept
    // already converted it to the ongoing-call notification, so skip that
    // path — hideCallkitIncoming would pull that down too.
    if (!fromCallKit) await CallKit.dismiss(call.callId);

    final session = CallSession(
      socket: _socket,
      conversationId: call.conversationId,
      peerName: call.callerName,
      peerPhoto: call.callerPhoto,
      isVideo: call.isVideo,
      isCaller: false,
    )..callId = call.callId;
    _adopt(session);
    if (navigate) openScreen();

    if (!await _permissions(call.isVideo)) {
      await session.hangUp(reason: _permissionMessage(call.isVideo));
      return;
    }
    final failure = await session.accept(call.callId);
    if (failure == null && session.isLive) {
      // Restarts the plugin's foreground service now that the microphone and
      // camera are granted, so they keep working with the screen off.
      await CallKit.markOngoing(session.identity, outgoing: false);
      if (session.phase == CallPhase.connected) await CallKit.markConnected(call.callId);
    }
  }

  Future<void> decline(String callId, {bool fromCallKit = false}) async {
    _ringing.remove(callId);
    _closeSheet(callId);
    if (!fromCallKit) await CallKit.dismiss(callId);
    if (active.value?.callId == callId) return;
    final ack = await _socket.rejectCall(callId);
    if (ack['ok'] != true) await CallKit.rejectOverHttp(callId);
  }

  // ── Outgoing ─────────────────────────────────────────────────────────

  /// Place a call. Returns a message when the call could not begin.
  Future<String?> startOutgoing({
    required String conversationId,
    required String peerName,
    String peerPhoto = '',
    required bool video,
  }) async {
    if (inCall) {
      openScreen();
      return null;
    }
    if (!await _permissions(video)) return _permissionMessage(video);

    final session = CallSession(
      socket: _socket,
      conversationId: conversationId,
      peerName: peerName,
      peerPhoto: peerPhoto,
      isVideo: video,
      isCaller: true,
    );
    _adopt(session);
    openScreen();

    final failure = await session.dial();
    final id = session.callId;
    if (failure == null && session.isLive && id != null) {
      // Permissions were already granted. Restart the foreground service now
      // that the microphone (and camera) are in use, so it survives minimise.
      await CallKit.markOngoing(session.identity, outgoing: true);
      if (session.phase == CallPhase.connected) await CallKit.markConnected(id);
    }
    return failure;
  }

  // ── Session lifecycle ────────────────────────────────────────────────

  void _adopt(CallSession session) {
    final previous = active.value;
    active.value = session;
    if (previous != null && previous != session) _retire(previous);

    var kitOngoing = false;
    var kitConnected = false;

    void onChange() {
      if (session.phase == CallPhase.ended) {
        session.removeListener(onChange);
        CallNotifications.hide();
        final id = session.callId;
        if (id != null) CallKit.end(id);
        // Give the call screen a moment to show why the call ended before the
        // session and its video renderers go away.
        Future.delayed(const Duration(seconds: 4), () {
          if (active.value == session) active.value = null;
          _retire(session);
        });
        return;
      }

      // Incoming already has CallKit's tray item from the ring. Outgoing
      // never did — this is the "Calling Priya" notification they expect
      // after leaving the call screen.
      if (session.isCaller) CallNotifications.show(session);

      final id = session.callId;
      if (id != null && id.isNotEmpty && !kitOngoing) {
        kitOngoing = true;
        CallKit.markOngoing(session.identity, outgoing: session.isCaller);
      }
      if (id != null && session.phase == CallPhase.connected && !kitConnected) {
        kitConnected = true;
        CallKit.markConnected(id);
      }
    }

    session.addListener(onChange);
    onChange();
  }

  void _retire(CallSession session) {
    if (session.isLive) session.hangUp();
    Future.delayed(const Duration(seconds: 1), session.dispose);
  }

  void openScreen() {
    if (screenOpen.value) return;
    AppRouter.router.push('/call');
  }

  Future<bool> _permissions(bool video) async {
    final needed = video ? [Permission.microphone, Permission.camera] : [Permission.microphone];
    final statuses = await needed.request();
    return statuses.values.every((s) => s.isGranted);
  }

  String _permissionMessage(bool video) => video
      ? 'Camera and microphone access are needed for video calls.'
      : 'Microphone access is needed for calls.';

  /// Android 14 treats the full-screen ringing screen as a permission. Without
  /// it the call shows as a banner that collapses after a few seconds, with
  /// no Accept or Decline on it. Asked once, with the reason.
  Future<void> ensureRingingPermission(BuildContext context) async {
    if (AppStorage.wasCallScreenPermissionAsked()) return;
    bool allowed;
    try {
      allowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
    } catch (_) {
      return;
    }
    if (allowed) return;
    AppStorage.markCallScreenPermissionAsked();
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Show incoming calls', style: AppTextStyles.headlineMedium),
        content: Text(
          'Allow GraceMatch to show calls on your lock screen, so you can answer '
          'when your match calls.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Allow')),
        ],
      ),
    );
    if (go == true) {
      try {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      } catch (_) {}
    }
  }

  // ── Plan ─────────────────────────────────────────────────────────────

  CallEntitlements? _entitlements;
  DateTime? _entitlementsAt;

  CallEntitlements? get cachedEntitlements => _entitlements;

  /// Which call buttons this member's plan allows. Cached briefly so opening
  /// chats does not refetch it each time, and short enough that an upgrade
  /// shows up on the next chat.
  Future<CallEntitlements> entitlements({bool refresh = false}) async {
    final at = _entitlementsAt;
    final cached = _entitlements;
    if (!refresh && cached != null && at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 2)) {
      return cached;
    }
    try {
      final resp = await DioClient.instance.get(ApiEndpoints.entitlements);
      final data = resp.data is Map ? resp.data['data'] : null;
      final features = data is Map ? data['features'] : null;
      final next = CallEntitlements(
        voice: features is Map && features['voice_calls'] == true,
        video: features is Map && features['video_calls'] == true,
      );
      _entitlements = next;
      _entitlementsAt = DateTime.now();
      return next;
    } catch (_) {
      return cached ?? const CallEntitlements(voice: false, video: false);
    }
  }

  // ── In-app ringing (no notification permission) ──────────────────────

  void _showSheet(IncomingCallData call) {
    final nav = AppRouter.rootNavigatorKey.currentState;
    if (nav == null || _sheetCallId != null) return;
    _sheetCallId = call.callId;
    AppHaptics.heavy();
    nav
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: _sheetRoute),
          fullscreenDialog: true,
          builder: (_) => IncomingCallSheet(call: call),
        ))
        .whenComplete(() {
      if (_sheetCallId == call.callId) _sheetCallId = null;
    });
  }

  void _closeSheet(String callId) {
    if (_sheetCallId != callId) return;
    _sheetCallId = null;
    AppRouter.rootNavigatorKey.currentState
        ?.popUntil((route) => route.settings.name != _sheetRoute);
  }

  static const _sheetRoute = 'incoming-call';

  void stop() {
    _socketSub?.cancel();
    _kitSub?.cancel();
    if (PushCenter.extraResponseHandler == _onLocalNotification) {
      PushCenter.extraResponseHandler = null;
    }
    _started = false;
  }
}

class CallEntitlements {
  final bool voice;
  final bool video;
  const CallEntitlements({required this.voice, required this.video});
}

class IncomingCallSheet extends StatelessWidget {
  final IncomingCallData call;

  const IncomingCallSheet({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final name = call.callerName;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CallAvatar(name: name, photo: call.callerPhoto, size: 110),
            const SizedBox(height: 24),
            Text(name, style: AppTextStyles.headlineSmall),
            const SizedBox(height: 6),
            Text(
              call.isVideo ? 'Incoming video call' : 'Incoming voice call',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const Spacer(flex: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _action(
                  icon: Icons.call_end_rounded,
                  label: 'Decline',
                  colour: AppColors.error,
                  onTap: () {
                    AppHaptics.light();
                    CallManager.instance.decline(call.callId);
                  },
                ),
                _action(
                  icon: call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  label: 'Answer',
                  colour: Colors.green,
                  onTap: () {
                    AppHaptics.medium();
                    CallManager.instance.acceptIncoming(call);
                  },
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color colour,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68, height: 68,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

/// The other person's photo, or their initial when there is none.
class CallAvatar extends StatelessWidget {
  final String name;
  final String photo;
  final double size;

  const CallAvatar({super.key, required this.name, required this.photo, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: AppTextStyles.displaySmall.copyWith(color: AppColors.gold),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.goldMild, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo.startsWith('http')
          ? Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initial,
            )
          : initial,
    );
  }
}
