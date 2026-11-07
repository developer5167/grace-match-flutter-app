import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grace_match/features/subscriptions/bloc/subscription_bloc.dart';
import 'package:grace_match/features/subscriptions/data/subscription_repository.dart';
import 'package:grace_match/features/subscriptions/screens/subscription_screen.dart';

class _FakePlans extends SubscriptionRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchPlans() async => [
        {
          'id': 'free',
          'name': 'bronze',
          'display_name': 'Bronze',
          'price_inr': 0,
          'is_free': true,
          'is_current_active': true,
          'duration_months': 0,
          'entitlements': [
            {'label': '20 curated matches / day', 'included': true},
          ],
        },
        {
          'id': 'gold',
          'name': 'gold',
          'display_name': 'Gold',
          'price_inr': 1999,
          'duration_months': 3,
          'featured': true,
          'entitlements': [
            {'label': 'Voice calls with matches', 'included': true},
          ],
        },
      ];
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => SubscriptionBloc(_FakePlans()),
        child: const SubscriptionScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS: plans and features, no prices, Get started opens the sheet',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pump(tester);

    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Voice calls with matches'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Problem with a payment?'), findsNothing);
    expect(find.text('Subscribe Now'), findsNothing);

    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Plan changes happen outside the app'), findsOneWidget);
    expect(
      find.text('All plan changes are handled through your GraceMatch account, outside the app.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Plan changes happen outside the app'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android keeps prices and checkout', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pump(tester);
    expect(find.text('₹1999'), findsOneWidget);
    expect(find.text('Subscribe Now'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
