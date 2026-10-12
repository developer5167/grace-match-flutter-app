import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/push_center.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/membership_sync.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/call_manager.dart';
import '../data/call_session.dart';

/// The call.
///
/// Full-bleed remote video with the local preview inset — the arrangement
/// everyone already knows, so nobody has to learn it during the one call that
/// matters. Voice calls show a name and a status line instead of a black
/// rectangle.
///
/// The screen only shows the call; [CallManager] owns it. Back or the
/// minimise button leaves the call running, as on any phone, and the bar at
/// the top of the app brings the member back here.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _manager = CallManager.instance;
  CallSession? _session;
  Timer? _ticker;
  bool _left = false;
  bool _endHandled = false;

  @override
  void initState() {
    super.initState();
    _session = _manager.active.value;
    _manager.screenOpen.value = true;
    _session?.addListener(_onChange);
    _manager.active.addListener(_onActiveChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _session?.phase == CallPhase.connected) setState(() {});
    });
    if (_session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
    }
  }

  /// A second call can replace the one on screen — answering while another
  /// was still winding down.
  void _onActiveChanged() {
    final next = _manager.active.value;
    if (next == null || next == _session) return;
    _session?.removeListener(_onChange);
    setState(() {
      _session = next;
      _endHandled = false;
    });
    next.addListener(_onChange);
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    // Opened from a killed app via the ringing screen: nothing sits under
    // this route. Discover is the home they expect — not the brand splash.
    PushCenter.finishStartupDiscarding();
    syncMembershipTheme();
    router.go('/discover');
  }

  void _minimise() {
    AppHaptics.light();
    _leave();
  }

  void _onChange() {
    final session = _session;
    if (!mounted || session == null) return;
    if (session.phase == CallPhase.ended && !_endHandled) {
      _endHandled = true;
      final why = session.error;
      if (session.needsPlan && why != null) {
        _showPlanDialog(why);
      } else {
        Future.delayed(Duration(milliseconds: why == null ? 700 : 1600), _leave);
      }
    }
    setState(() {});
  }

  void _showPlanDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Upgrade to call', style: AppTextStyles.headlineMedium),
        content: Text(message, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _leave();
            },
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _leave();
              AppRouter.router.push('/subscription');
            },
            child: const Text('See plans'),
          ),
        ],
      ),
    );
  }

  String get _status {
    final s = _session;
    if (s == null) return '';
    if (s.phase == CallPhase.ended) return s.error ?? 'Call ended';
    if (s.reconnecting) return 'Reconnecting…';
    switch (s.phase) {
      case CallPhase.idle:
      case CallPhase.dialling:   return 'Calling…';
      case CallPhase.ringing:    return 'Ringing…';
      case CallPhase.connecting: return 'Connecting…';
      case CallPhase.connected:  return _elapsed;
      case CallPhase.ended:      return 'Call ended';
    }
  }

  String get _elapsed {
    final start = _session?.connectedAt;
    if (start == null) return '00:00';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _session?.removeListener(_onChange);
    _manager.active.removeListener(_onActiveChanged);
    _manager.screenOpen.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final connected = session.phase == CallPhase.connected;
    final ended = session.phase == CallPhase.ended;
    final showRemote = session.isVideo && connected && session.remoteRenderer.srcObject != null;
    final showLocal = session.isVideo && session.cameraOn && !ended &&
        session.localRenderer.srcObject != null;
    final top = MediaQuery.of(context).padding.top;

    return PopScope(
      // Back leaves the call running, like every phone does. Hanging up is
      // the red button, and nothing else.
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (showRemote)
              RTCVideoView(
                session.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _placeholder(session),

            if (showLocal)
              Positioned(
                top: top + 72,
                right: 16,
                width: 108,
                height: 152,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: AppColors.surface,
                    child: RTCVideoView(
                      session.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // Minimise, name and status
            Positioned(
              top: top + 8,
              left: 8,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to the app',
                    onPressed: _minimise,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.headlineSmall.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _status,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: session.reconnecting ? AppColors.gold : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (!ended) _controls(session),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(CallSession session) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CallAvatar(name: session.peerName, photo: session.peerPhoto, size: 112),
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: session.reconnecting ? AppColors.gold : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(CallSession session) {
    return Positioned(
      left: 0, right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _round(
            icon: session.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: !session.micOn,
            onTap: () { AppHaptics.light(); session.toggleMic(); },
          ),
          if (session.isVideo) ...[
            const SizedBox(width: 16),
            _round(
              icon: session.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              active: !session.cameraOn,
              onTap: () { AppHaptics.light(); session.toggleCamera(); },
            ),
            const SizedBox(width: 16),
            _round(
              icon: Icons.cameraswitch_rounded,
              onTap: () { AppHaptics.light(); session.switchCamera(); },
            ),
          ],
          const SizedBox(width: 16),
          _round(
            icon: session.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            active: session.speakerOn,
            onTap: () { AppHaptics.light(); session.toggleSpeaker(); },
          ),
          const SizedBox(width: 16),
          _round(
            icon: Icons.call_end_rounded,
            background: AppColors.error,
            iconColor: Colors.white,
            onTap: () {
              AppHaptics.heavy();
              session.hangUp();
            },
          ),
        ],
      ),
    );
  }

  Widget _round({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? background,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: background ?? (active ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor ?? (active ? Colors.black : Colors.white),
          size: 24,
        ),
      ),
    );
  }
}
