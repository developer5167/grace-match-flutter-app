import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

/// An offer as the member sees it.
///
/// The discount arithmetic is not repeated here. The server sends
/// `example_discount_inr` already worked out, because a card that computes its
/// own number will eventually disagree with checkout, and the member will
/// believe the card.

/// Read a number that may arrive as a number, a numeric string, or not at all.
///
/// Postgres NUMERIC columns come back from node-postgres as strings, so
/// `price_inr` arrives as "999.00" rather than 999. Casting that straight to
/// `num` throws "String is not a subtype of num" and takes down the screen.
/// The server now sends numbers, but the client should not be one deploy away
/// from a crash: parsing defensively costs nothing and this is money, on a
/// screen a member reaches with their card out.
int _int(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString())?.toInt() ?? fallback;
}

/// Same, but keeps null meaningful — "no cap" is not "a cap of zero".
int? _intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString())?.toInt();
}

class Offer {
  final String id;
  final String code;
  final String title;
  final String? description;
  final String discountType; // percent | flat
  final int discountValue;
  final int? maxDiscountInr;
  final String? planName;
  final DateTime expiresAt;
  final bool isPersonal;
  final bool alreadyUsed;
  final bool inProgress;
  final bool isUsable;
  final int exampleDiscountInr;
  final int exampleOnPriceInr;

  const Offer({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscountInr,
    required this.planName,
    required this.expiresAt,
    required this.isPersonal,
    required this.alreadyUsed,
    required this.inProgress,
    required this.isUsable,
    required this.exampleDiscountInr,
    required this.exampleOnPriceInr,
  });

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'].toString(),
        code: j['code']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Offer',
        description: j['description']?.toString(),
        discountType: j['discount_type']?.toString() ?? 'flat',
        discountValue: _int(j['discount_value']),
        maxDiscountInr: _intOrNull(j['max_discount_inr']),
        planName: j['plan_name']?.toString(),
        expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? '') ?? DateTime.now(),
        isPersonal: j['is_personal'] == true,
        alreadyUsed: j['already_used'] == true,
        inProgress: j['in_progress'] == true,
        isUsable: j['is_usable'] == true,
        exampleDiscountInr: _int(j['example_discount_inr']),
        exampleOnPriceInr: _int(j['example_on_price_inr']),
      );

  /// "20% off" / "₹300 off" — the headline on the card.
  String get headline =>
      discountType == 'percent' ? '$discountValue% OFF' : '₹$discountValue OFF';

  Duration get timeLeft => expiresAt.difference(DateTime.now());

  /// Urgency is a product decision, not a display one: under two days is when
  /// the reminder notification goes out, so the card should agree with it.
  bool get isEndingSoon => !timeLeft.isNegative && timeLeft.inHours <= 48;

  String get expiryLabel {
    final d = timeLeft;
    if (d.isNegative) return 'Expired';
    if (d.inHours < 1) return 'Ends in ${d.inMinutes} min';
    if (d.inHours < 24) return 'Ends in ${d.inHours} hr';
    return 'Ends in ${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  }
}

class CouponPreview {
  final String code;
  final int priceInr;
  final int discountInr;
  final int finalInr;

  const CouponPreview({
    required this.code,
    required this.priceInr,
    required this.discountInr,
    required this.finalInr,
  });
}

class OffersRepository {
  final _dio = DioClient.instance;

  Future<List<Offer>> fetchOffers() async {
    final res = await _dio.get(ApiEndpoints.offers);
    final list = res.data['data']?['offers'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Offer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Price preview. Throws the server's own message so the member is told the
  /// actual reason — already used, wrong plan, expired — not "invalid code".
  Future<CouponPreview> validate({required String code, required String planId}) async {
    try {
      final res = await _dio.post(ApiEndpoints.offersValidate, data: {
        'code': code.trim().toUpperCase(),
        'plan_id': planId,
      });
      final d = Map<String, dynamic>.from(res.data['data']);
      return CouponPreview(
        code: d['code'].toString(),
        priceInr: _int(d['price_inr']),
        discountInr: _int(d['discount_inr']),
        finalInr: _int(d['final_inr']),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? 'Could not apply that code');
    }
  }
}
