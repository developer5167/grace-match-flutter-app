import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

class SubscriptionRepository {
  final _dio = DioClient.instance;

  /// Same catalog the website reads. Auth adds whether this member already
  /// holds the plan; if that call fails we still show the public list so the
  /// screen is never empty while the site has prices.
  Future<List<Map<String, dynamic>>> fetchPlans() async {
    try {
      final response = await _dio.get(ApiEndpoints.plans);
      final plans = _parsePlanList(response.data);
      if (plans.isNotEmpty) return plans;
    } catch (_) {
      // Fall through to the public catalog.
    }

    final public = await _dio.get(ApiEndpoints.publicPlans);
    return _parsePlanList(public.data);
  }

  /// Creates the order. [couponCode] is priced by the server, never here —
  /// the amount the sheet opens with has to be the amount the server charges.
  Future<Map<String, dynamic>> createOrder(dynamic planId, {String? couponCode}) async {
    final id = planId.toString().trim();
    final response = await _dio.post(ApiEndpoints.razorpayOrder, data: {
      'plan_id': id,
      if (couponCode != null && couponCode.trim().isNotEmpty)
        'coupon_code': couponCode.trim().toUpperCase(),
    });
    return _asMap(response.data is Map ? (response.data['data'] ?? response.data) : response.data);
  }

  /// Verifies the payment signature server-side and activates the subscription.
  Future<bool> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final response = await _dio.post(ApiEndpoints.razorpayVerify, data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      return response.data['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _parsePlanList(dynamic payload) {
  dynamic raw = payload;
  if (raw is Map) {
    raw = raw['data'] ?? raw['plans'];
  }
  if (raw is Map) {
    raw = raw['plans'] ?? raw['data'];
  }
  if (raw is! List) return [];

  return raw.map<Map<String, dynamic>>((item) {
    final plan = _asMap(item);
    if (plan['features'] is Map) {
      plan['features'] = _asMap(plan['features']);
    }
    if (plan['entitlements'] is List) {
      plan['entitlements'] = (plan['entitlements'] as List)
          .map<Map<String, dynamic>>(_asMap)
          .toList();
    }
    if (plan['current_subscription'] is Map) {
      plan['current_subscription'] = _asMap(plan['current_subscription']);
    }
    return plan;
  }).toList();
}
