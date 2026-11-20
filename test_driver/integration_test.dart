import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Each takeScreenshot() is captured from the simulator display itself
/// (`simctl io screenshot`) into build/store_screenshots/NAME.png. SIM_UDID
/// names the simulator.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final out = 'build/store_screenshots/$name.png';
    await Directory('build/store_screenshots').create(recursive: true);
    final udid = Platform.environment['SIM_UDID'] ?? 'booted';
    final r = await Process.run('xcrun', ['simctl', 'io', udid, 'screenshot', out]);
    return r.exitCode == 0;
  },
);
