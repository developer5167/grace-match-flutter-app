import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

/// An offer as the member sees it.
///
/// The discount arithmetic is not repeated here. The server sends
/// `example_discount_inr` already worked out, because a card that computes its
/// own number will eventually disagree with checkout, and the member will
/// believe the card.
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
        discountValue: (j['discount_value'] as num?)?.toInt() ?? 0,
        maxDiscountInr: (j['max_discount_inr'] as num?)?.toInt(),
        planName: j['plan_name']?.toString(),
        expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? '') ?? DateTime.now(),
        isPersonal: j['is_personal'] == true,
        alreadyUsed: j['already_used'] == true,
        inProgress: j['in_progress'] == true,
        isUsable: j['is_usable'] == true,
        exampleDiscountInr: (j['example_discount_inr'] as num?)?.toInt() ?? 0,
        exampleOnPriceInr: (j['example_on_price_inr'] as num?)?.toInt() ?? 0,
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
        priceInr: (d['price_inr'] as num).toInt(),
        discountInr: (d['discount_inr'] as num).toInt(),
        finalInr: (d['final_inr'] as num).toInt(),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data?['message'] ?? 'Could not apply that code');
    }
  }
}
