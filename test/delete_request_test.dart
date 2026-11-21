import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/di/injection.dart' as di;
import 'package:grace_match/core/theme/app_theme.dart';
import 'package:grace_match/features/auth/data/auth_repository.dart';
import 'package:grace_match/features/auth/delete_account.dart';

class _FakeAuth extends AuthRepository {
  String? sentReason;
  int calls = 0;
  @override
  Future<DateTime> requestAccountDeletion({String? reason}) async {
    calls++;
    sentReason = reason;
    return DateTime(2026, 11, 21);
  }
}

void main() {
  late _FakeAuth fake;
  DateTime? result;

  setUp(() {
    fake = _FakeAuth();
    if (di.sl.isRegistered<AuthRepository>())
      di.sl.unregister<AuthRepository>();
    di.sl.registerSingleton<AuthRepository>(fake);
    result = null;
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async =>
                  result = await confirmRequestAccountDeletion(ctx),
              child: const Text('Delete account'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Delete account'));
    await t.pumpAndSettle();
  }

  testWidgets('asks politely why; reasons and note are sent with the request', (
    t,
  ) async {
    await open(t);
    expect(find.text("We're sorry to see you go"), findsOneWidget);

    await t.tap(find.text('I found my partner elsewhere'));
    await t.enterText(find.byType(TextField), 'Thank you for the service');
    await t.pump();
    await t.ensureVisible(find.text('Request deletion'));
    await t.tap(find.text('Request deletion'));
    await t.pumpAndSettle();

    expect(fake.calls, 1);
    expect(
      fake.sentReason,
      'I found my partner elsewhere. Thank you for the service',
    );
    expect(
      find.text(
        'Your account delete request has been sent. Our team will delete your account and sign you out.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
  });

  testWidgets('the reason is optional', (t) async {
    await open(t);
    await t.ensureVisible(find.text('Request deletion'));
    await t.tap(find.text('Request deletion'));
    await t.pumpAndSettle();
    expect(fake.calls, 1);
    expect(fake.sentReason, '');
  });

  testWidgets('"Keep my account" sends nothing', (t) async {
    await open(t);
    await t.ensureVisible(find.text('Keep my account'));
    await t.tap(find.text('Keep my account'));
    await t.pumpAndSettle();
    expect(fake.calls, 0);
    expect(result, isNull);
  });
}
