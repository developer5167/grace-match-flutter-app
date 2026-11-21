// Repro: open Chat first thing after sign-in (local dummy-data server).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grace_match/core/router/app_router.dart';
import 'package:grace_match/features/chat/bloc/chat_bloc.dart';
import 'package:grace_match/features/chat/bloc/chat_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grace_match/core/widgets/skeleton.dart';
import 'package:grace_match/main.dart' as app;

Future<void> wait(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('chat opens on first visit', (t) async {
    app.main();
    await wait(t, 5000);
    final phone = find.byType(TextField);
    if (phone.evaluate().isNotEmpty) {
      await t.enterText(phone.first, '9000000001');
      await wait(t, 300);
      await t.tap(find.text('Continue'));
      await wait(t, 6000);
    }
    AppRouter.router.go('/chat');
    await wait(t, 2500);
    await t.tap(find.text('Sarah').first);
    for (var i = 0; i < 16; i++) {
      await wait(t, 500);
      final ctx = t.element(find.byType(Scaffold).last);
      final s = ctx.read<ChatBloc>().state;
      debugPrint('CHATDBG t=${(i + 1) * 500}ms state=${s.runtimeType}'
          '${s is ChatError ? ' error=${s.message}' : ''}'
          ' sarah=${find.text('Sarah').evaluate().length}'
          ' skeleton=${find.byType(SkeletonList).evaluate().length}'
          ' msg=${find.textContaining('Bethel AG').evaluate().length}'
          ' spinner=${find.byType(CircularProgressIndicator).evaluate().length}');
    }
  });
}
