import 'package:flutter_test/flutter_test.dart';

import 'package:grace_match/features/offers/data/offers_repository.dart';
import 'package:grace_match/features/notifications/data/notifications_repository.dart';

/// Parsing tests for what the API actually sends.
///
/// Every model here is built from a JSON map the server controls. A field that
/// is renamed, goes null, or arrives as a different type is the single most
/// common way a mobile screen breaks — and unlike the web, a crash here ships
/// to phones and cannot be hot-fixed. These run in milliseconds and need no
/// device, so they are the cheapest safety net the app has.
void main() {
  group('Offer parsing', () {
    final full = {
      'id': 'c1',
      'code': 'DIWALI25',
      'title': 'Diwali offer',
      'description': 'Festive discount',
      'discount_type': 'percent',
      'discount_value': 25,
      'max_discount_inr': 200,
      'plan_name': 'gold',
      'expires_at': '2099-01-01T00:00:00.000Z',
      'is_personal': true,
      'already_used': false,
      'in_progress': false,
      'is_usable': true,
      'example_discount_inr': 150,
      'example_on_price_inr': 600,
    };

    test('a complete payload parses', () {
      final o = Offer.fromJson(full);
      expect(o.code, 'DIWALI25');
      expect(o.discountValue, 25);
      expect(o.isPersonal, isTrue);
      expect(o.isUsable, isTrue);
      expect(o.headline, '25% OFF');
    });

    test('a flat discount reads as rupees', () {
      final o = Offer.fromJson({...full, 'discount_type': 'flat', 'discount_value': 300});
      expect(o.headline, '₹300 OFF');
    });

    // Nullable columns really do arrive null; the screen must not crash.
    test('nulls do not crash the parser', () {
      final o = Offer.fromJson({
        'id': 'c2',
        'code': 'X',
        'title': 'T',
        'description': null,
        'discount_type': 'flat',
        'discount_value': 100,
        'max_discount_inr': null,
        'plan_name': null,
        'expires_at': '2099-01-01T00:00:00.000Z',
      });
      expect(o.description, isNull);
      expect(o.planName, isNull);
      expect(o.maxDiscountInr, isNull);
      // Absent booleans must default to the safe answer, not to "usable".
      expect(o.alreadyUsed, isFalse);
      expect(o.isUsable, isFalse);
    });

    test('a malformed date does not throw', () {
      final o = Offer.fromJson({...full, 'expires_at': 'not-a-date'});
      expect(o.expiresAt, isA<DateTime>());
    });


    // ── REGRESSION: applying DIWALI25 threw
    //    "String is not a subtype of num".
    //
    // subscription_plans.price_inr is NUMERIC(10,2), and node-postgres returns
    // NUMERIC as a STRING to protect precision. So the API sent "999.00" and
    // the cast to num blew up on a screen the member reaches with their card
    // out. The original fixtures here used ints, which is why these tests
    // passed while production crashed — a payload invented by the test author
    // proves nothing about the one the server sends.
    test('REGRESSION: numeric strings from Postgres NUMERIC parse', () {
      final o = Offer.fromJson({
        ...full,
        'discount_value': '25',
        'max_discount_inr': '200.00',
        'example_discount_inr': '150.00',
        'example_on_price_inr': '600.00',
      });
      expect(o.discountValue, 25);
      expect(o.maxDiscountInr, 200);
      expect(o.exampleDiscountInr, 150);
      expect(o.exampleOnPriceInr, 600);
      expect(o.headline, '25% OFF');
    });

    test('a null cap stays null rather than becoming zero', () {
      // "no maximum" and "a maximum of nothing" are opposite meanings.
      final o = Offer.fromJson({...full, 'max_discount_inr': null});
      expect(o.maxDiscountInr, isNull);
    });

    test('an unparseable amount falls back instead of throwing', () {
      final o = Offer.fromJson({...full, 'discount_value': 'twenty-five'});
      expect(o.discountValue, 0);
    });

    test('expiry wording matches how long is left', () {
      DateTime soon(Duration d) => DateTime.now().add(d);
      String label(Duration d) => Offer.fromJson(
        {...full, 'expires_at': soon(d).toIso8601String()}).expiryLabel;

      expect(label(const Duration(minutes: 30)), contains('min'));
      expect(label(const Duration(hours: 5)), contains('hr'));
      expect(label(const Duration(days: 3)), contains('day'));
      expect(label(const Duration(days: -1)), 'Expired');
    });

    test('ending soon matches the 48-hour reminder window', () {
      bool soon(Duration d) => Offer.fromJson(
        {...full, 'expires_at': DateTime.now().add(d).toIso8601String()}).isEndingSoon;

      expect(soon(const Duration(hours: 10)), isTrue);
      expect(soon(const Duration(hours: 47)), isTrue);
      expect(soon(const Duration(days: 5)), isFalse);
      expect(soon(const Duration(hours: -1)), isFalse, reason: 'already expired is not "ending soon"');
    });
  });

  group('Notification parsing', () {
    test('a complete payload parses', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'offer',
        'title': 'A special offer',
        'body': '25% off',
        'data': {'coupon_id': 'c1'},
        'is_read': false,
        'created_at': '2026-10-03T05:46:04.506Z',
      });
      expect(n.type, 'offer');
      expect(n.isRead, isFalse);
      expect(n.data['coupon_id'], 'c1');
    });

    test('a missing data bag becomes an empty map, not a crash', () {
      final n = AppNotification.fromJson({
        'id': 'n2', 'type': 'system', 'title': 'T', 'body': '',
        'data': null, 'is_read': true, 'created_at': '2026-10-03T05:46:04.506Z',
      });
      expect(n.data, isEmpty);
      expect(n.isRead, isTrue);
    });

    test('an unknown type still parses', () {
      // The server can add a notification type before the app knows about it.
      final n = AppNotification.fromJson({
        'id': 'n3', 'type': 'something_new', 'title': 'T', 'body': 'B',
        'data': {}, 'is_read': false, 'created_at': '2026-10-03T05:46:04.506Z',
      });
      expect(n.type, 'something_new');
    });

    test('copyWith only changes read state', () {
      final n = AppNotification.fromJson({
        'id': 'n4', 'type': 'new_message', 'title': 'T', 'body': 'B',
        'data': {}, 'is_read': false, 'created_at': '2026-10-03T05:46:04.506Z',
      });
      final read = n.copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.id, n.id);
      expect(read.title, n.title);
    });
  });
}
