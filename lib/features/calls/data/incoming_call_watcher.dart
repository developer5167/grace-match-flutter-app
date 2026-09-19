import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';

/// Listens for incoming calls anywhere in the app.
///
/// Without this a call only arrives if the member happens to already be on the
/// call screen, which is nowhere. It is started once at app level and lives
/// for the session.
///
/// Presents a full-screen answer/decline sheet rather than a snackbar: a
/// ringing phone is the most interruptive thing this app does, and it should
/// look like it.
class IncomingCallWatcher {
  final SocketService socket;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<CallEvent>? _sub;
  String? _showingCallId;

  IncomingCallWatcher({required this.socket, required this.navigatorKey});

  void start() {
    _sub?.cancel();
    _sub = socket.callStream.listen(_onEvent);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onEvent(CallEvent event) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // The caller gave up, or the call was answered on another device.
    if (event.name == 'call:cancelled' || event.name == 'call:ended') {
      if (_showingCallId != null && event.callId == _showingCallId) {
        _showingCallId = null;
        nav.popUntil((route) => route.settings.name != _routeName);
      }
      return;
    }

    if (event.name != 'call:incoming') return;

    final callId = event.callId;
    if (callId == null || callId == _showingCallId) return;
    _showingCallId = callId;

    AppHaptics.heavy();

    final data = event.data;
    await nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _routeName),
        fullscreenDialog: true,
        builder: (_) => _IncomingCallSheet(
          socket: socket,
          callId: callId,
          conversationId: data['conversation_id']?.toString() ?? '',
          callerName: data['caller_name']?.toString() ?? 'Someone',
          isVideo: data['is_video'] != false,
        ),
      ),
    );
    _showingCallId = null;
  }

  static const _routeName = 'incoming-call';
}

class _IncomingCallSheet extends StatelessWidget {
  final SocketService socket;
  final String callId;
  final String conversationId;
  final String callerName;
  final bool isVideo;

  const _IncomingCallSheet({
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
                    await socket.rejectCall(callId);
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
                    // Answering happens inside the call screen so there is one
                    // place that owns the peer connection.
                    nav.push(MaterialPageRoute(
                      builder: (_) => _deferredCallScreen(),
                    ));
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

  Widget _deferredCallScreen() {
    // Imported lazily to keep this file free of a cycle with the call screen.
    return CallScreenFactory.build(
      socket: socket,
      conversationId: conversationId,
      peerName: callerName,
      isVideo: isVideo,
      incomingCallId: callId,
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
