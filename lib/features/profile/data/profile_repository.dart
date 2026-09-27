import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';

class ProfileRepository {
  final Dio _dio = DioClient.instance;

  Future<Map<String, dynamic>> fetchMyProfile() async {
    try {
      final response = await _dio.get(ApiEndpoints.myProfile);
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> fetchProfile(String userId) async {
    try {
      final response = await _dio.get(ApiEndpoints.publicProfile(userId));
      return response.data['data'];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> sendInterest(String userId, {bool isSuper = false}) async {
    try {
      await _dio.post(ApiEndpoints.sendInterest, data: {
        'receiver_id': userId,
        'is_super_interest': isSuper,
        'type': isSuper ? 'super_interest' : 'interest'
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> activateSpotlight() async {
    try {
      final response = await _dio.post(ApiEndpoints.spotlight);
      final data = response.data['data'];
      if (data is Map<String, dynamic>) return data;
      return {};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> acceptInterest(String interestId) async {
    try {
      await _dio.post(ApiEndpoints.acceptInterest(interestId));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> rejectInterest(String interestId) async {
    try {
      await _dio.post(ApiEndpoints.rejectInterest(interestId));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> settings) async {
    try {
      final response =
          await _dio.put(ApiEndpoints.updateSettings, data: settings);
      final data = response.data['data'];
      if (data is Map<String, dynamic>) return data;
      return {};
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
