// App Store screenshots from the real app, against a LOCAL server seeded with
// dummy data (grace-match-backend/scripts/dev-device.sh). Never point this at
// the live API. App Store Connect's slot for this app is 6.1"/6.3"
// (1206 x 2622): use the iPhone 17 Pro simulator.
//
//   python3 integration_test/shot_server.py <sim-udid> build/store_screenshots &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/store_screenshots_test.dart -d <sim-udid> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:5050/api/v1 --dart-define=STORE_SCREENSHOTS=true
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grace_match/core/router/app_router.dart';
import 'package:grace_match/features/discover/widgets/profile_list_card.dart';
import 'package:grace_match/main.dart' as app;

Future<void> wait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> until(WidgetTester t, Finder f, {int ms = 20000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await wait(t, 200);
  }
}

/// Asks the Mac-side helper (shot_server.py on :8787) to capture the
/// simulator screen now. Flutter's own takeScreenshot came out blank here.
Future<void> shot(WidgetTester t, String name) async {
  await wait(t, 300);
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('http://127.0.0.1:8787/shot?name=$name'));
    await (await req.close()).drain<void>();
  } finally {
    c.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (t) async {
    app.main();
    await wait(t, 5000);

    final phone = find.byType(TextField);
    if (phone.evaluate().isNotEmpty) {
      await t.enterText(phone.first, '9000000001');
      await wait(t, 500);
      await t.tap(find.text('Continue'));
      await wait(t, 1000);
    }

    // Discover: recommended row and the first biodata card.
    await until(t, find.byType(ProfileListCard));
    await wait(t, 3000);
    await shot(t, '01-discover');

    // A full card with its details and actions.
    await t.drag(find.byType(Scrollable).last, const Offset(0, -290));
    await wait(t, 2000);
    await shot(t, '02-discover-card');

    // A profile: trust panel, then faith / education / family.
    final photo = find.descendant(
      of: find.byType(ProfileListCard).first,
      matching: find.byType(AspectRatio),
    );
    await t.ensureVisible(photo);
    await wait(t, 500);
    await t.tap(photo, warnIfMissed: false);
    await until(t, find.text('About Me'));
    await wait(t, 3000);
    await shot(t, '03-profile');
    await t.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await wait(t, 1500);
    await shot(t, '04-profile-details');

    AppRouter.router.go('/interests');
    await wait(t, 3000);
    await shot(t, '05-interests');

    AppRouter.router.go('/chat');
    await wait(t, 3000);
    final sarah = find.text('Sarah');
    if (sarah.evaluate().isNotEmpty) {
      await t.tap(sarah.first);
      await wait(t, 3000);
      await shot(t, '07-chat');
    }
  });
}
