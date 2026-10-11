import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/call_session.dart';

/// The call.
///
/// Full-bleed remote video with the local preview inset — the arrangement
/// everyone already knows, so nobody has to learn it during the one call that
/// matters. Voice calls show a name and a status line instead of a black
/// rectangle.
class CallScreen extends StatefulWidget {
  final SocketService socket;
  final String conversationId;
  final String peerName;
  final bool isVideo;

  /// Set when answering: the call already exists and is ringing.
  final String? incomingCallId;

  const CallScreen({
    super.key,
    required this.socket,
    required this.conversationId,
    required this.peerName,
    this.isVideo = true,
    this.incomingCallId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallSession _session = CallSession(widget.socket);
  Timer? _ticker;
  bool _starting = true;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onChange);
    _begin();
  }

  Future<void> _begin() async {
    // Asked here rather than at app start: permission requested in context,
    // for a reason the member can see, is permission that gets granted.
    final needed = widget.isVideo
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    final statuses = await needed.request();

    if (statuses.values.any((s) => !s.isGranted)) {
      if (!mounted) return;
      setState(() => _starting = false);
      _fail(widget.isVideo
          ? 'Camera and microphone access are needed for video calls.'
          : 'Microphone access is needed for calls.');
      return;
    }

    final failure = widget.incomingCallId != null
        ? await _session.accept(
            incomingCallId: widget.incomingCallId!,
            peerDisplayName: widget.peerName,
            video: widget.isVideo,
          )
        : await _session.dial(
            conversationId: widget.conversationId,
            peerDisplayName: widget.peerName,
            video: widget.isVideo,
          );

    if (!mounted) return;
    setState(() => _starting = false);
    if (failure != null) _fail(failure);
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    router.go('/chat');
  }

  void _fail(String message) {
    final needsPlan = message.toLowerCase().contains('plan');
    if (needsPlan) {
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
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.surfaceHighest),
    );
    Future.delayed(const Duration(milliseconds: 900), _leave);
  }

  void _onChange() {
    if (!mounted) return;
    if (_session.phase == CallPhase.connected && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (_session.phase == CallPhase.ended) {
      _ticker?.cancel();
      final why = _session.error;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        if (why != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(why), backgroundColor: AppColors.surfaceHighest),
          );
        }
        _leave();
      });
    }
    setState(() {});
  }

  String get _status {
    switch (_session.phase) {
      case CallPhase.dialling:   return 'Calling…';
      case CallPhase.ringing:    return 'Ringing…';
      case CallPhase.connecting: return 'Connecting…';
      case CallPhase.connected:  return _elapsed;
      case CallPhase.ended:      return 'Call ended';
      case CallPhase.idle:       return '';
    }
  }

  String get _elapsed {
    final start = _session.connectedAt;
    if (start == null) return '00:00';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _session.removeListener(_onChange);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _session.phase == CallPhase.connected;
    final showVideo = _session.isVideo && _session.cameraOn;

    return PopScope(
      // Leaving the screen must hang up. A call that keeps running behind a
      // back-swipe is a live microphone the member thinks they closed.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Captured before the await: the context from build() is not safe to
        // reach across an async gap, and this one is a hang-up.
        await _session.hangUp();
        _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_session.isVideo && connected && _session.remoteRenderer.srcObject != null)
              RTCVideoView(
                _session.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _placeholder(),

            // Local preview — shown as soon as the camera is up, not only
            // after the other side connects (same as the working Masthi Chat call).
            if (showVideo)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                width: 108,
                height: 152,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: AppColors.surface,
                    child: RTCVideoView(
                      _session.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // Name and status
            Positioned(
              top: MediaQuery.of(context).padding.top + 24,
              left: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    style: AppTextStyles.headlineSmall.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style: AppTextStyles.labelMedium.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

            if (_starting)
              const Center(
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
              ),

            _controls(connected),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.goldMild),
              ),
              child: Center(
                child: Text(
                  widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                  style: AppTextStyles.displaySmall.copyWith(color: AppColors.gold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(_status, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _controls(bool connected) {
    return Positioned(
      left: 0, right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _round(
            icon: _session.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: !_session.micOn,
            onTap: () { AppHaptics.light(); _session.toggleMic(); },
          ),
          if (_session.isVideo) ...[
            const SizedBox(width: 16),
            _round(
              icon: _session.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              active: !_session.cameraOn,
              onTap: () { AppHaptics.light(); _session.toggleCamera(); },
            ),
            const SizedBox(width: 16),
            _round(
              icon: Icons.cameraswitch_rounded,
              onTap: () { AppHaptics.light(); _session.switchCamera(); },
            ),
          ],
          const SizedBox(width: 16),
          _round(
            icon: _session.speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            active: _session.speakerOn,
            onTap: () { AppHaptics.light(); _session.toggleSpeaker(); },
          ),
          const SizedBox(width: 16),
          _round(
            icon: Icons.call_end_rounded,
            background: AppColors.error,
            iconColor: Colors.white,
            onTap: () async {
              AppHaptics.heavy();
              await _session.hangUp();
              _leave();
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
