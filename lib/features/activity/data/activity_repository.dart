import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';

class ActivityRepository {
  final Dio _dio = DioClient.instance;

  // ── Bootstrap (single call — all sections) ──────────────────
  // Returns partial data even when individual sections fail.
  // The response shape is:
  // {
  //   notifications, unread_count,
  //   viewers, total_views, is_premium_views,
  //   shortlists,
  //   contact_requests,
  //   errors: { notifications, views, shortlists, contact_requests }
  // }
  Future<Map<String, dynamic>> fetchBootstrap() async {
    try {
      final res = await _dio.get(ApiEndpoints.activityBootstrap);
      return Map<String, dynamic>.from(res.data['data'] ?? {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ── Standalone section refreshes (used after individual actions) ──

  Future<Map<String, dynamic>> fetchNotifications({int page = 1}) async {
    try {
      final res = await _dio.get(ApiEndpoints.notifications, queryParameters: {'page': page});
      return Map<String, dynamic>.from(res.data['data'] ?? {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.put(ApiEndpoints.notificationsReadAll);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markOneRead(String id) async {
    try {
      await _dio.put(ApiEndpoints.notificationRead(id));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> fetchViews({int page = 1}) async {
    try {
      final res = await _dio.get(ApiEndpoints.activityViews, queryParameters: {'page': page});
      return Map<String, dynamic>.from(res.data['data'] ?? {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> fetchShortlists({int page = 1}) async {
    try {
      final res = await _dio.get(ApiEndpoints.activityShortlists, queryParameters: {'page': page});
      return Map<String, dynamic>.from(res.data['data'] ?? {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<bool> toggleShortlist(String targetUserId) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.activityShortlists,
        data: {'target_user_id': targetUserId},
      );
      return res.data['data']['is_shortlisted'] as bool? ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<bool> checkShortlisted(String targetUserId) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.activityShortlistsCheck,
        queryParameters: {'target_user_id': targetUserId},
      );
      return res.data['data']['is_shortlisted'] as bool? ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchIncomingContactRequests() async {
    try {
      final res = await _dio.get(ApiEndpoints.contactRequestsIncoming);
      final data = res.data['data'];
      if (data is List) {
        return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Approve, decline, or withdraw a contact request.
  ///
  /// Withdrawing is a different endpoint, not a third action: approving is a
  /// reply to a request, revoking is taking back something already given, and
  /// only the owner of the number can do it.
  Future<void> respondContactRequest(String requestId, String action) async {
    try {
      if (action == 'revoke') {
        await _dio.post(ApiEndpoints.contactRevoke(requestId));
        return;
      }
      await _dio.post(
        ApiEndpoints.contactRespondAction(requestId),
        data: {'action': action},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data['message'] ?? 'An error occurred';
    }
    return 'Network error. Please try again.';
  }
}
