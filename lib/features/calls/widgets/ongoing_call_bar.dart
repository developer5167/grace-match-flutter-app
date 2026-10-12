import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/theme/app_text_styles.dart';
import '../data/call_manager.dart';
import '../data/call_session.dart';

/// Wraps the whole app. While a call is live and its screen is closed, a bar
/// sits above every page — tap it to go back to the call — and a video call
/// keeps a small picture of the other person floating over the app.
class OngoingCallLayer extends StatelessWidget {
  final Widget child;

  const OngoingCallLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final manager = CallManager.instance;
    return ValueListenableBuilder<CallSession?>(
      valueListenable: manager.active,
      builder: (context, session, _) {
        if (session == null) return child;
        return ValueListenableBuilder<bool>(
          valueListenable: manager.screenOpen,
          builder: (context, open, _) => ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              final show = !open && session.isLive;
              if (!show) return child;
              return _withBar(context, session);
            },
          ),
        );
      },
    );
  }

  Widget _withBar(BuildContext context, CallSession session) {
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        Column(
          children: [
            _CallBar(session: session, topInset: media.padding.top),
            Expanded(
              // The bar takes the status-bar area, so pages below must not
              // pad for it a second time.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        ),
        if (session.isVideo && session.hasRemoteVideo && session.phase == CallPhase.connected)
          _FloatingVideo(session: session, top: media.padding.top + 64),
      ],
    );
  }
}

class _CallBar extends StatefulWidget {
  final CallSession session;
  final double topInset;

  const _CallBar({required this.session, required this.topInset});

  @override
  State<_CallBar> createState() => _CallBarState();
}

class _CallBarState extends State<_CallBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _label {
    final s = widget.session;
    if (s.reconnecting) return 'Reconnecting…';
    switch (s.phase) {
      case CallPhase.connected:
        final start = s.connectedAt;
        if (start == null) return 'On call';
        final d = DateTime.now().difference(start);
        final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
        final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
        return d.inHours > 0 ? '${d.inHours}:$m:$sec' : '$m:$sec';
      case CallPhase.ringing:
        return 'Ringing…';
      case CallPhase.connecting:
        return 'Connecting…';
      default:
        return 'Calling…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Material(
      color: const Color(0xFF1E8E3E),
      child: InkWell(
        onTap: CallManager.instance.openScreen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, widget.topInset + 6, 8, 6),
          child: Row(
            children: [
              Icon(
                s.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.peerName} · $_label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
                ),
              ),
              Text(
                'Tap to return',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white70),
              ),
              // No tooltip: this sits above the navigator, where there is no
              // overlay for one to draw in.
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: s.hangUp,
                icon: const Icon(Icons.call_end_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingVideo extends StatefulWidget {
  final CallSession session;
  final double top;

  const _FloatingVideo({required this.session, required this.top});

  @override
  State<_FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<_FloatingVideo> {
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    const w = 104.0, h = 148.0;
    final size = MediaQuery.of(context).size;
    final pos = _pos ?? Offset(size.width - w - 12, widget.top);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: CallManager.instance.openScreen,
        onPanUpdate: (d) => setState(() {
          final next = pos + d.delta;
          _pos = Offset(
            next.dx.clamp(0, size.width - w),
            next.dy.clamp(widget.top, size.height - h - 24),
          );
        }),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: w,
            height: h,
            child: RTCVideoView(
              widget.session.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ),
    );
  }
}
