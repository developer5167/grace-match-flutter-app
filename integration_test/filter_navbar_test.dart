// The bottom bar fades out while the filter sheet is open (local server).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grace_match/core/router/app_router.dart';
import 'package:grace_match/core/widgets/app_shell.dart';
import 'package:grace_match/main.dart' as app;

Future<void> wait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> shot(String name) async {
  final c = HttpClient();
  try {
    final r = await c.getUrl(Uri.parse('http://127.0.0.1:8787/shot?name=$name'));
    await (await r.close()).drain<void>();
  } catch (_) {
  } finally {
    c.close();
  }
}

double barOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(find.ancestor(
      of: find.byIcon(Icons.explore_rounded),
      matching: find.byType(AnimatedOpacity),
    ).first)
    .opacity;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('filter sheet hides the bottom bar', (t) async {
    app.main();
    await wait(t, 5000);
    if (find.byType(TextField).evaluate().isNotEmpty) {
      await t.enterText(find.byType(TextField).first, '9000000001');
      await wait(t, 300);
      await t.tap(find.text('Continue'));
      await wait(t, 6000);
    }
    AppRouter.router.go('/discover');
    await wait(t, 2500);
    expect(barOpacity(t), 1);
    await t.tap(find.byIcon(Icons.tune_rounded).first);
    await wait(t, 800);
    expect(AppShell.navBarHidden.value, isTrue);
    expect(barOpacity(t), 0);
    await shot('filter-open');
    await t.tapAt(const Offset(200, 40)); // the scrim above the sheet
    await wait(t, 800);
    expect(AppShell.navBarHidden.value, isFalse);
    expect(barOpacity(t), 1);
    await shot('filter-closed');
  });
}
