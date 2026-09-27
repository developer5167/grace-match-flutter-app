import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The GraceMatch brand mark: two gold rings that drift apart, then converge
/// and interlock.
///
/// This is the app-side twin of the WebGL moment on the marketing site. The web
/// builds a real `TorusGeometry` with a metallic material; a stroked circle
/// cannot stand in for that, because what reads as "3D" is the lit tube and the
/// fact that one ring passes *through* the other — neither of which a flat
/// outline can show.
///
/// So this is an actual torus mesh: parametric vertices, a rotation matrix,
/// perspective projection, Blinn-Phong shading for the metal, and painter's
/// algorithm depth sorting. The triangles of *both* rings go into one sorted
/// list, which is what produces a true interlock rather than a fixed overlap.
///
/// It is one `drawVertices` call per frame, so the cost is the arithmetic, not
/// the rasterising.
///
/// [converge] is 0 (apart) to 1 (interlocked). [spin] is continuous rotation in
/// turns, matching the site's idle tumble.
class RingsMark extends StatelessWidget {
  const RingsMark({
    super.key,
    required this.converge,
    required this.spin,
    this.size = 132,
  });

  final double converge;
  final double spin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingsPainter(converge: converge, spin: spin),
        isComplex: true,
      ),
    );
  }
}

// ─── Geometry ────────────────────────────────────────────────
//
// The web uses TorusGeometry(1.5, 0.12, 48, 220). The same proportions are kept
// here; the segment counts are lower because this renders at ~132px, where more
// tessellation costs arithmetic and changes nothing you can see.

const double _kRingRadius = 1.5;
const double _kTubeRadius = 0.12;
const int _kTubular = 80; // segments around the ring
const int _kRadial = 12; // segments around the tube

/// Unit torus, computed once. Only the rotation and projection are per-frame.
class _TorusMesh {
  _TorusMesh() {
    final count = _kTubular * _kRadial;
    px = Float64List(count);
    py = Float64List(count);
    pz = Float64List(count);
    nx = Float64List(count);
    ny = Float64List(count);
    nz = Float64List(count);

    for (var i = 0; i < _kTubular; i++) {
      final u = (i / _kTubular) * 2 * math.pi;
      final cosU = math.cos(u), sinU = math.sin(u);

      for (var j = 0; j < _kRadial; j++) {
        final v = (j / _kRadial) * 2 * math.pi;
        final cosV = math.cos(v), sinV = math.sin(v);
        final k = i * _kRadial + j;

        // Surface of revolution: a circle of radius _kTubeRadius swept around
        // a circle of radius _kRingRadius.
        final ringX = _kRingRadius + _kTubeRadius * cosV;
        px[k] = ringX * cosU;
        py[k] = ringX * sinU;
        pz[k] = _kTubeRadius * sinV;

        // For a torus the normal is simply the direction from the tube's
        // centreline out to the surface — no differencing required.
        nx[k] = cosV * cosU;
        ny[k] = cosV * sinU;
        nz[k] = sinV;
      }
    }
  }

  late final Float64List px, py, pz, nx, ny, nz;
}

final _mesh = _TorusMesh();

// ─── Painter ─────────────────────────────────────────────────

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.converge, required this.spin});

  final double converge;
  final double spin;

  // Camera, mirroring the web scene: 45° field of view, seven units back.
  static const double _camDistance = 7.0;
  static const double _worldHalfHeight = 2.35;

  // Key light warm and high, rim light cool and low — the same two lights the
  // web scene uses, so the metal picks up the same colour breakup.
  static const double _lx = 0.46, _ly = 0.62, _lz = 0.64;
  static const double _rx = -0.60, _ry = -0.38, _rz = 0.70;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = (size.shortestSide / 2) / _worldHalfHeight;

    // Ring A: starts face-on and to the left, ends edge-on and centred.
    // Ring B: starts already turned a quarter and to the right.
    // These are the site's start and end values, interpolated by `converge`.
    final t = converge;
    final spinRad = spin * 2 * math.pi;

    // Land face-on so each ring is a circle. A 6° opposite pitch is enough
    // for a true interlock (so the overlap does not z-fight) without reading
    // as an oval. Ring B still starts quarter-turned so the splash converges.
    const pitch = 0.10;
    final ringA = _Ring(
      tx: _lerp(-2.4, -0.78, t),
      rotX: spinRad * 0.5 + pitch,
      rotY: 0,
      rotZ: 0,
      base: AppColors.gold,
    );
    final ringB = _Ring(
      tx: _lerp(2.4, 0.78, t),
      rotX: -spinRad * 0.5 - pitch,
      rotY: _lerp(math.pi * 0.5, 0, t),
      rotZ: 0,
      base: AppColors.goldLight,
    );

    // Warm halo, brightening as the rings meet — the site's glow, which is
    // what stops the metal reading as flat against a near-black ground.
    if (converge > 0.01) {
      final halo = Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          size.shortestSide * 0.52,
          [
            AppColors.gold.withValues(alpha: 0.20 * converge),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        );
      canvas.drawCircle(Offset(cx, cy), size.shortestSide * 0.52, halo);
    }

    final buf = _scratch;
    buf.count = 0;
    _build(ringA, cx, cy, scale, buf);
    _build(ringB, cx, cy, scale, buf);

    // Painter's algorithm. Both rings sort together — that single detail is
    // what makes them genuinely interlock rather than one always sitting on
    // top of the other. Only the index list is sorted, so nothing is allocated
    // per frame.
    final n = buf.count;
    final order = buf.order;
    final depths = buf.depth;
    final idx = List<int>.generate(n, (i) => i, growable: false)
      ..sort((a, b) => depths[a].compareTo(depths[b]));
    for (var i = 0; i < n; i++) {
      order[i] = idx[i];
    }

    final positions = Float32List(n * 6);
    final colors = Int32List(n * 3);

    for (var i = 0; i < n; i++) {
      final t = order[i];
      final src = t * 6;
      final dst = i * 6;
      positions[dst] = buf.xy[src];
      positions[dst + 1] = buf.xy[src + 1];
      positions[dst + 2] = buf.xy[src + 2];
      positions[dst + 3] = buf.xy[src + 3];
      positions[dst + 4] = buf.xy[src + 4];
      positions[dst + 5] = buf.xy[src + 5];

      final csrc = t * 3;
      final cdst = i * 3;
      colors[cdst] = buf.col[csrc];
      colors[cdst + 1] = buf.col[csrc + 1];
      colors[cdst + 2] = buf.col[csrc + 2];
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );

    // BlendMode.dst keeps the vertex colours exactly as computed; anything else
    // mixes in the paint's colour and washes the shading out.
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
  }

  void _build(_Ring ring, double cx, double cy, double scale, _Scratch out) {
    final count = _kTubular * _kRadial;

    // Rotation matrix, built once per ring rather than per vertex.
    final cxr = math.cos(ring.rotX), sxr = math.sin(ring.rotX);
    final cyr = math.cos(ring.rotY), syr = math.sin(ring.rotY);
    final czr = math.cos(ring.rotZ), szr = math.sin(ring.rotZ);

    // R = Rz · Ry · Rx (the order three.js applies for Euler 'XYZ')
    final m00 = czr * cyr;
    final m01 = czr * syr * sxr - szr * cxr;
    final m02 = czr * syr * cxr + szr * sxr;
    final m10 = szr * cyr;
    final m11 = szr * syr * sxr + czr * cxr;
    final m12 = szr * syr * cxr - czr * sxr;
    final m20 = -syr;
    final m21 = cyr * sxr;
    final m22 = cyr * cxr;

    final sx = Float64List(count);
    final sy = Float64List(count);
    final wz = Float64List(count);
    final col = Int32List(count);

    for (var k = 0; k < count; k++) {
      // Position → rotate → translate
      final lx = _mesh.px[k], ly = _mesh.py[k], lz = _mesh.pz[k];
      final wx = m00 * lx + m01 * ly + m02 * lz + ring.tx;
      final wy = m10 * lx + m11 * ly + m12 * lz;
      final wzz = m20 * lx + m21 * ly + m22 * lz;
      wz[k] = wzz;

      // Perspective divide
      final persp = _camDistance / (_camDistance - wzz);
      sx[k] = cx + wx * persp * scale;
      sy[k] = cy - wy * persp * scale;

      // Normal → rotate (rotation is orthonormal, so no inverse-transpose)
      final ax = _mesh.nx[k], ay = _mesh.ny[k], az = _mesh.nz[k];
      final tnx = m00 * ax + m01 * ay + m02 * az;
      final tny = m10 * ax + m11 * ay + m12 * az;
      final tnz = m20 * ax + m21 * ay + m22 * az;

      col[k] = _shade(tnx, tny, tnz, ring.base);
    }

    // Quads → triangles, with backface culling in screen space.
    for (var i = 0; i < _kTubular; i++) {
      final i2 = (i + 1) % _kTubular;
      for (var j = 0; j < _kRadial; j++) {
        final j2 = (j + 1) % _kRadial;

        final a = i * _kRadial + j;
        final b = i2 * _kRadial + j;
        final c = i2 * _kRadial + j2;
        final d = i * _kRadial + j2;

        // Signed area: negative means we are looking at the inside of the
        // tube, which is always hidden by the outside.
        final area = (sx[b] - sx[a]) * (sy[c] - sy[a]) -
            (sx[c] - sx[a]) * (sy[b] - sy[a]);
        if (area <= 0) continue;

        final depth = (wz[a] + wz[b] + wz[c] + wz[d]) * 0.25;

        out.add(sx[a], sy[a], sx[b], sy[b], sx[c], sy[c],
            col[a], col[b], col[c], depth);
        out.add(sx[a], sy[a], sx[c], sy[c], sx[d], sy[d],
            col[a], col[c], col[d], depth);
      }
    }
  }

  /// Shading for a metal.
  ///
  /// A metal lit only by point lights comes out muddy brown — most of what you
  /// see on real gold is the environment reflected back at you. The web scene
  /// gets that from a PMREM environment map plus ACES tone mapping; here the
  /// same job is done by a bright hemisphere term, so the tube stays gold all
  /// the way round instead of falling to near-black away from the key light.
  /// The specular is tinted by the base colour, which is what separates gold
  /// from grey plastic with a yellow coat of paint.
  int _shade(double nx, double ny, double nz, Color base) {
    final key = math.max(0.0, nx * _lx + ny * _ly + nz * _lz);
    final rim = math.max(0.0, nx * _rx + ny * _ry + nz * _rz);

    // Hemisphere "environment": brighter from above, never fully dark below.
    final hemi = 0.5 + 0.5 * ny;

    // Half-vector against the view direction (0, 0, 1).
    const hx = _lx, hy = _ly, hz = _lz + 1.0;
    final hlen = math.sqrt(hx * hx + hy * hy + hz * hz);
    final ndh = math.max(0.0, (nx * hx + ny * hy + nz * hz) / hlen);
    final spec = math.pow(ndh, 34.0).toDouble();

    // A grazing angle reflects more — the bright lip along the tube's edge.
    final fresnel = math.pow(1.0 - math.max(0.0, nz.abs()), 3.0).toDouble();

    final lit = 0.46 + 0.52 * key + 0.34 * hemi + 0.26 * fresnel;

    double channel(double baseC, double roseC, double hiC) =>
        baseC * 255.0 * lit + roseC * 255.0 * rim * 0.16 + hiC * 255.0 * spec * 1.15;

    final r = channel(base.r, AppColors.rose.r, AppColors.textPrimary.r);
    final g = channel(base.g, AppColors.rose.g, AppColors.textPrimary.g);
    final b = channel(base.b, AppColors.rose.b, AppColors.textPrimary.b);

    return 0xFF000000 |
        (r.clamp(0, 255).toInt() << 16) |
        (g.clamp(0, 255).toInt() << 8) |
        b.clamp(0, 255).toInt();
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.converge != converge || old.spin != spin;
}

class _Ring {
  const _Ring({
    required this.tx,
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.base,
  });

  final double tx, rotX, rotY, rotZ;
  final Color base;
}

/// Flat, reused triangle buffer. Painting happens on one thread, so a single
/// module-level instance is safe and keeps a 60fps animation from allocating a
/// thousand short-lived objects every frame.
class _Scratch {
  _Scratch(int maxTris)
      : xy = Float32List(maxTris * 6),
        col = Int32List(maxTris * 3),
        depth = Float64List(maxTris),
        order = Int32List(maxTris);

  final Float32List xy;
  final Int32List col;
  final Float64List depth;
  final Int32List order;
  int count = 0;

  void add(double x0, double y0, double x1, double y1, double x2, double y2,
      int c0, int c1, int c2, double d) {
    final i = count;
    final p = i * 6;
    xy[p] = x0;
    xy[p + 1] = y0;
    xy[p + 2] = x1;
    xy[p + 3] = y1;
    xy[p + 4] = x2;
    xy[p + 5] = y2;
    final c = i * 3;
    col[c] = c0;
    col[c + 1] = c1;
    col[c + 2] = c2;
    depth[i] = d;
    count = i + 1;
  }
}

// Two rings, every quad split into two triangles, nothing culled: the ceiling.
final _scratch = _Scratch(2 * _kTubular * _kRadial * 2);

double _lerp(double a, double b, double t) => a + (b - a) * t;

// ─── Driver ──────────────────────────────────────────────────

/// Runs [RingsMark] through its convergence once, then leaves it tumbling.
class AnimatedRingsMark extends StatefulWidget {
  const AnimatedRingsMark({
    super.key,
    this.size = 132,
    this.convergeDuration = const Duration(milliseconds: 1800),
    this.delay = Duration.zero,
  });

  final double size;
  final Duration convergeDuration;
  final Duration delay;

  @override
  State<AnimatedRingsMark> createState() => _AnimatedRingsMarkState();
}

class _AnimatedRingsMarkState extends State<AnimatedRingsMark>
    with TickerProviderStateMixin {
  late final AnimationController _converge;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();

    _converge = AnimationController(vsync: this, duration: widget.convergeDuration);
    // No idle tumble — a Y/X spin turns the circles into ovals, and the
    // settled frame has to match the circular app icon.
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 18));

    if (widget.delay == Duration.zero) {
      _converge.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _converge.forward();
      });
    }
  }

  @override
  void dispose() {
    _converge.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: _converge, curve: Curves.easeInOutCubic);

    return AnimatedBuilder(
      animation: Listenable.merge([eased, _spin]),
      builder: (_, __) => RingsMark(
        converge: eased.value,
        spin: _spin.value,
        size: widget.size,
      ),
    );
  }
}
