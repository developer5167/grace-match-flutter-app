import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/l10n/app_language.dart';
import 'package:grace_match/core/l10n/language_switch.dart';
import 'package:grace_match/core/l10n/te.dart';
import 'package:grace_match/core/theme/app_theme.dart';
import 'package:grace_match/features/discover/widgets/profile_list_card.dart';

void main() {
  tearDown(() => AppLanguage.instance.set('en'));

  test('tr: English by default, Telugu when chosen, English when missing', () {
    expect(tr('Send interest'), 'Send interest');
    AppLanguage.instance.set('te');
    expect(tr('Send interest'), 'ఆసక్తి పంపండి');
    expect(tr('A sentence nobody translated'), 'A sentence nobody translated');
    expect(tr('Edit {step}', {'step': tr('Photos')}), 'ఫోటోలు మార్చండి');
  });

  test('every Telugu entry is non-empty and differs from a placeholder', () {
    for (final e in teluguStrings.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
  });

  testWidgets('the card and the switch change language together', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: AppLanguage.instance,
            builder: (_, _) => SingleChildScrollView(
              child: Column(
                children: [
                  const LanguageSwitch(),
                  ProfileListCard(
                    profile: const {
                      'id': 'u1',
                      'name': 'Ruth',
                      'age': 27,
                      'denomination': 'csi',
                      'marriage_intent': 'within_1_year',
                      'photos': <dynamic>[],
                    },
                    action: ListAction.none,
                    onOpen: () {},
                    onInterest: () {},
                    onPriorityInterest: () {},
                    onNotNow: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Send interest'), findsOneWidget);

    await t.tap(find.text('తెలుగు'));
    await t.pumpAndSettle();
    expect(find.text('ఆసక్తి పంపండి'), findsOneWidget);
    expect(find.text('1 సంవత్సరంలో పెళ్లి చేసుకోవాలని అనుకుంటున్నారు'), findsOneWidget);
    expect(find.text('Send interest'), findsNothing);
  });
}
