import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/features/discover/widgets/profile_list_card.dart';

void main() {
  final profile = <String, dynamic>{
    'id': 'u1',
    'name': 'Sravani',
    'age': 30,
    'height_cm': 163,
    'denomination': 'pentecostal',
    'city': 'Hyderabad',
    'education': 'MBBS',
    'profession': 'Anaesthetist',
    'church_name': 'Bethel Church',
    'profile_managed_by': 'parents',
    'compatibility': 77,
    'photos': <dynamic>[],
  };

  Future<void> pump(
    WidgetTester t,
    ListAction action, {
    VoidCallback? onInterest,
  }) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileListCard(
            profile: profile,
            action: action,
            onOpen: () {},
            onInterest: onInterest ?? () {},
            onPriorityInterest: () {},
            onNotNow: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('shows biodata details, review label and actions', (t) async {
    var sent = 0;
    await pump(t, ListAction.none, onInterest: () => sent++);
    expect(find.text("Sravani, 30  ·  5' 4\""), findsOneWidget);
    expect(find.text('Pentecostal  ·  Hyderabad'), findsOneWidget);
    expect(find.text('Reviewed by our team'), findsOneWidget);
    expect(find.text('Profile managed by parents'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    await t.ensureVisible(find.text('Send interest'));
    await t.pump();
    await t.tap(find.text('Send interest'));
    expect(sent, 1);
  });

  testWidgets('after sending, shows "Interest sent" instead of actions', (
    t,
  ) async {
    await pump(t, ListAction.sent);
    expect(find.text('Interest sent'), findsOneWidget);
    expect(find.text('Send interest'), findsNothing);
  });

  test('height in feet and inches, nonsense ignored', () {
    expect(ProfileListCard.height(170), "5' 7\"");
    expect(ProfileListCard.height(null), isNull);
    expect(ProfileListCard.height(20), isNull);
  });
}
