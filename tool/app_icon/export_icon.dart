/// Renders the splash [RingsMark] to the launcher PNG sources in assets/icons.
///
///   flutter test tool/app_icon/export_icon.dart
///   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/theme/app_colors.dart';
import 'package:grace_match/core/widgets/rings_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('export splash rings as launcher PNGs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Settled splash pose: fully interlocked, no tumble — a home-screen icon
    // has to be a single frame, not a random point in the spin.
    await _write(
      tester,
      filename: 'assets/icons/app_icon.png',
      ringSize: 760,
    );
    // Adaptive icons mask to a circle/squircle. Keep the rings inside the
    // inner ~66% so nothing is clipped on a Pixel vs a Samsung.
    await _write(
      tester,
      filename: 'assets/icons/app_icon_foreground.png',
      ringSize: 560,
    );
  });
}

Future<void> _write(
  WidgetTester tester, {
  required String filename,
  required double ringSize,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: AppColors.background,
          child: Center(
            child: RingsMark(converge: 1, spin: 0, size: ringSize),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // toImage is real async; the test zone would hang without runAsync.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(filename).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
