import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Tilts [child] in 3D as the phone tilts, like Netflix's title cards.
///
/// Tilt is measured against a slowly drifting rest position, so however the
/// member holds the phone the card sits level, and only a turn left/right (or
/// forward/back) moves it. Off while the tab is hidden (TickerMode) and when
/// the system asks for reduced motion.
class DeviceTilt extends StatefulWidget {
  const DeviceTilt({
    super.key,
    required this.child,
    this.maxAngle = 0.16,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;

  /// Largest rotation, in radians (about 9°).
  final double maxAngle;

  /// Shape of the light sheen, to match the card.
  final BorderRadius borderRadius;

  @override
  State<DeviceTilt> createState() => _DeviceTiltState();
}

class _DeviceTiltState extends State<DeviceTilt>
    with SingleTickerProviderStateMixin {
  // How far from rest (in g) gives full tilt, how fast rest follows the hand,
  // and how fast the card eases toward its target each frame.
  static const _fullTiltG = 0.28;
  static const _restDrift = 0.012;
  static const _ease = 0.14;

  late final Ticker _ticker = createTicker(_onTick);
  StreamSubscription<AccelerometerEvent>? _sub;
  double? _restX, _restY;
  double _targetX = 0, _targetY = 0;
  double _x = 0, _y = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _setActive(visible && !reduceMotion);
  }

  void _setActive(bool on) {
    if (on && _sub == null) {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(
            _onAccel,
            onError: (_) => _setActive(false),
            cancelOnError: true,
          );
      if (!_ticker.isActive) _ticker.start();
    } else if (!on && _sub != null) {
      _sub?.cancel();
      _sub = null;
      _restX = _restY = null;
      _targetX = _targetY = 0;
      if (_ticker.isActive) _ticker.stop();
      if (_x != 0 || _y != 0) setState(() => _x = _y = 0);
    }
  }

  void _onAccel(AccelerometerEvent e) {
    final gx = e.x / 9.81;
    final gy = e.y / 9.81;
    final restX = _restX ?? gx;
    final restY = _restY ?? gy;
    _restX = restX + (gx - restX) * _restDrift;
    _restY = restY + (gy - restY) * _restDrift;
    _targetX = ((gx - _restX!) / _fullTiltG).clamp(-1.0, 1.0);
    _targetY = ((gy - _restY!) / _fullTiltG).clamp(-1.0, 1.0);
  }

  void _onTick(Duration _) {
    final nx = _x + (_targetX - _x) * _ease;
    final ny = _y + (_targetY - _y) * _ease;
    if ((nx - _x).abs() < 0.0005 && (ny - _y).abs() < 0.0005) return;
    setState(() {
      _x = nx;
      _y = ny;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // perspective
      ..rotateY(-_x * widget.maxAngle)
      ..rotateX(-_y * widget.maxAngle * 0.6);

    // Sheen sweeps across opposite to the tilt, brightest near the raised edge.
    final shine = (math.max(_x.abs(), _y.abs()) * 0.16).clamp(0.0, 0.16);
    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (shine > 0.005)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment(-1 + _x, -1 + _y),
                      end: Alignment(1 + _x, 1 + _y),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: shine),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.2, 0.5, 0.8],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
