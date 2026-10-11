import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/network/dio_client.dart';
import 'incoming_call_notifications.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';

/// Listens for incoming calls anywhere in the app — socket while open,
/// and the same full-screen sheet when a call push wakes the process.
class IncomingCallWatcher {
  IncomingCallWatcher._({required this.socket, required this.navigatorKey});

  final SocketService socket;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<CallEvent>? _sub;
  String? _showingCallId;

  static IncomingCallWatcher? instance;
  static Map<String, dynamic>? _queued;

  static IncomingCallWatcher start({
    required SocketService socket,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    final watcher = IncomingCallWatcher._(socket: socket, navigatorKey: navigatorKey);
    instance = watcher;
    watcher._listen();
    final queued = _queued;
    _queued = null;
    if (queued != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        watcher.presentFromPush(queued);
      });
    }
    return watcher;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    if (instance == this) instance = null;
  }

  void _listen() {
    _sub?.cancel();
    _sub = socket.callStream.listen(_onEvent);
  }

  Future<void> _onEvent(CallEvent event) async {
    if (event.name == 'call:cancelled' || event.name == 'call:ended') {
      dismiss(event.callId);
      return;
    }
    if (event.name != 'call:incoming') return;
    presentFromPush({
      'call_id': event.callId,
      'conversation_id': event.data['conversation_id'],
      'caller_name': event.data['caller_name'],
      'is_video': event.data['is_video'],
    });
  }

  static void presentOrQueue(Map<String, dynamic> data) {
    final live = instance;
    if (live != null) {
      live.presentFromPush(data);
      return;
    }
    _queued = data;
  }

  Future<void> presentFromPush(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString();
    if (callId == null || callId.isEmpty) return;
    if (callId == _showingCallId) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      _queued = data;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final again = _queued;
        _queued = null;
        if (again != null) presentFromPush(again);
      });
      return;
    }

    _showingCallId = callId;
    AppHaptics.heavy();

    final isVideo = data['is_video']?.toString() != 'false' && data['is_video'] != false;
    await nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _routeName),
        fullscreenDialog: true,
        builder: (_) => IncomingCallSheet(
          socket: socket,
          callId: callId,
          conversationId: data['conversation_id']?.toString() ?? '',
          callerName: data['caller_name']?.toString().isNotEmpty == true
              ? data['caller_name'].toString()
              : 'Someone',
          isVideo: isVideo,
        ),
      ),
    );
    if (_showingCallId == callId) _showingCallId = null;
  }

  void dismiss(String? callId) {
    cancelIncomingCallNotification(FlutterLocalNotificationsPlugin(), callId);
    if (callId == null || _showingCallId == null) return;
    if (callId != _showingCallId) return;
    _showingCallId = null;
    final nav = navigatorKey.currentState;
    nav?.popUntil((route) => route.settings.name != _routeName);
  }

  Future<void> acceptFromNotification(Map<String, dynamic> data) async {
    dismiss(data['call_id']?.toString());
    final conv = data['conversation_id']?.toString() ?? '';
    final callId = data['call_id']?.toString() ?? '';
    if (conv.isEmpty || callId.isEmpty) return;
    final name = Uri.encodeComponent(data['caller_name']?.toString() ?? 'Member');
    final video = data['is_video']?.toString() != 'false';
    AppRouter.router.push('/call/$conv?call=$callId&name=$name&video=$video');
  }

  Future<void> declineFromNotification(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString();
    if (callId == null || callId.isEmpty) return;
    dismiss(callId);
    try {
      await socket.rejectCall(callId);
    } catch (_) {
      try {
        await DioClient.instance.post('/calls/$callId/reject');
      } catch (_) {}
    }
  }

  static const _routeName = 'incoming-call';
}

class IncomingCallSheet extends StatelessWidget {
  final SocketService socket;
  final String callId;
  final String conversationId;
  final String callerName;
  final bool isVideo;

  const IncomingCallSheet({
    super.key,
    required this.socket,
    required this.callId,
    required this.conversationId,
    required this.callerName,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.goldMild, width: 2),
              ),
              child: Center(
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                  style: AppTextStyles.displaySmall.copyWith(color: AppColors.gold),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(callerName, style: AppTextStyles.headlineSmall),
            const SizedBox(height: 6),
            Text(
              isVideo ? 'Incoming video call' : 'Incoming voice call',
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
                  onTap: () async {
                    AppHaptics.light();
                    final nav = Navigator.of(context);
                    try {
                      await socket.rejectCall(callId);
                    } catch (_) {
                      try {
                        await DioClient.instance.post('/calls/$callId/reject');
                      } catch (_) {}
                    }
                    nav.pop();
                  },
                ),
                _action(
                  icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  label: 'Answer',
                  colour: Colors.green,
                  onTap: () {
                    AppHaptics.medium();
                    final nav = Navigator.of(context);
                    nav.pop();
                    final name = Uri.encodeComponent(callerName);
                    AppRouter.router.push(
                      '/call/$conversationId?call=$callId&name=$name&video=$isVideo',
                    );
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

/// Indirection so the watcher does not import the call screen directly.
/// Set once at startup.
class CallScreenFactory {
  static Widget Function({
    required SocketService socket,
    required String conversationId,
    required String peerName,
    required bool isVideo,
    String? incomingCallId,
  })? builder;

  static Widget build({
    required SocketService socket,
    required String conversationId,
    required String peerName,
    required bool isVideo,
    String? incomingCallId,
  }) {
    final b = builder;
    if (b == null) return const SizedBox.shrink();
    return b(
      socket: socket,
      conversationId: conversationId,
      peerName: peerName,
      isVideo: isVideo,
      incomingCallId: incomingCallId,
    );
  }
}
