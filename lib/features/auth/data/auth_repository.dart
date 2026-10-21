import 'package:dio/dio.dart';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/app_storage.dart';

class AuthRepository {
  final Dio _dio = DioClient.instance;

  Future<void> sendOtp(String phone) async {
    try {
      String countryCode = '+91';
      String phoneNumber = phone;
      if (phone.startsWith('+')) {
        // Simple extraction assuming 2-digit country code like +91
        countryCode = phone.substring(0, 3);
        phoneNumber = phone.substring(3);
      }
      await _dio.post(ApiEndpoints.sendOtp, data: {
        'phone_number': phoneNumber,
        'country_code': countryCode
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    try {
      String countryCode = '+91';
      String phoneNumber = phone;
      if (phone.startsWith('+')) {
        countryCode = phone.substring(0, 3);
        phoneNumber = phone.substring(3);
      }
      final response = await _dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone_number': phoneNumber,
          'country_code': countryCode,
          'otp': otp
        },
      );
      
      final data = response.data['data'];
      final String accessToken = data['access_token'];
      final String refreshToken = data['refresh_token'];
      final bool isNewUser = data['is_new_user'] ?? false;
      
      await AppStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      final user = data['user'];
      if (user != null) {
        await AppStorage.saveUserId(user['id']);
        AppStorage.saveOnboardingComplete(user['is_onboarding_complete'] ?? false);
        AppStorage.saveReviewStatus(user['review_status']);
      }

      // Register FCM token right after login so push works for closed app.
      await syncFcmToken();
      
      return {
        'is_new_user': isNewUser,
        'user': data['user'],
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateFcmToken(String fcmToken) async {
    try {
      await _dio.put(
        ApiEndpoints.updateFcmToken,
        data: {
          'fcm_token': fcmToken,
          'device_type': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (_) {
      // Background fail-safe
    }
  }

  Future<void> syncFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await updateFcmToken(token);
    } catch (_) {
      // Best-effort only
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(ApiEndpoints.logout);
    } catch (_) {}
    await AppStorage.clearAll();
  }

  Exception _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        if (data['errors'] != null && data['errors'] is List) {
          final errors = data['errors'] as List;
          if (errors.isNotEmpty) {
            return AuthException(errors.map((err) => '• ${err['message']}').join('\n'));
          }
        }
        return AuthException(
          data['message']?.toString() ?? 'An error occurred',
          code: data['code']?.toString(),
        );
      }
    }
    return AuthException('Detailed network error. Please try again.');
  }
}

class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException(this.message, {this.code});

  bool get isSuspended => code == 'ACCOUNT_SUSPENDED';

  @override
  String toString() => message;
}
