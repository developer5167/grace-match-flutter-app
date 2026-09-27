import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../bloc/discover_filters.dart';

class DiscoverRepository {
  final Dio _dio = DioClient.instance;

  Future<({List<Map<String, dynamic>> profiles, bool limitReached})> fetchFeed({
    int page = 1,
    int limit = 10,
    DiscoverFilters? filters,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'limit': limit,
        ...?filters?.toQueryParams(),
      };
      final response = await _dio.get(
        ApiEndpoints.discoverFeed,
        queryParameters: params,
      );
      final data = response.data['data'];
      final profiles = data is Map && data['profiles'] is List
          ? List<Map<String, dynamic>>.from(data['profiles'])
          : <Map<String, dynamic>>[];
      return (
        profiles: profiles,
        limitReached: data is Map && data['limit_reached'] == true,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchDailyMatches() async {
    try {
      final response = await _dio.get(ApiEndpoints.dailyMatches);
      return List<Map<String, dynamic>>.from(response.data['data']['matches']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> sendInterest(String targetUserId, {bool isSuperInterest = false}) async {
    try {
      await _dio.post(ApiEndpoints.sendInterest, data: {
        'receiver_id': targetUserId,
        'is_super_interest': isSuperInterest,
        'type': isSuperInterest ? 'super_interest' : 'interest',
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> passProfile(String targetUserId) async {
    try {
      await _dio.post(ApiEndpoints.sendInterest, data: {
        'receiver_id': targetUserId,
        'type': 'pass',
      });
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
