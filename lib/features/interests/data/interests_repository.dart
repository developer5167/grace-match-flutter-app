import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';

class InterestsRepository {
  final Dio _dio = DioClient.instance;

  Future<Map<String, List<Map<String, dynamic>>>> fetchInterests() async {
    try {
      final response = await _dio.get(ApiEndpoints.interestsList);
      final data = response.data['data'];

      return {
        'received': List<Map<String, dynamic>>.from(data['received'] ?? []),
        'matches': List<Map<String, dynamic>>.from(data['matches'] ?? []),
        'sent': List<Map<String, dynamic>>.from(data['sent'] ?? []),
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Returns the response data map (e.g. `{conversation_id: "..."}` for accept).
  Future<Map<String, dynamic>?> handleAction(
    String interestId, {
    required bool accept,
  }) async {
    try {
      final url = accept
          ? ApiEndpoints.acceptInterest(interestId)
          : ApiEndpoints.rejectInterest(interestId);
      final resp = await _dio.post(url);
      final data = resp.data['data'];
      return data is Map<String, dynamic> ? data : null;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data['message'] ?? 'An error occurred';
    }
    return 'Detailed network error. Please try again.';
  }
}
