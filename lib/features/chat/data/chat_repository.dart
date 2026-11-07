import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';

class ChatRepository {
  final Dio _dio = DioClient.instance;

  Future<List<Map<String, dynamic>>> fetchConversations() async {
    try {
      final response = await _dio.get(ApiEndpoints.conversations);
      return List<Map<String, dynamic>>.from(
        response.data['data']['conversations'],
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    try {
      final response = await _dio.get(ApiEndpoints.messages(conversationId));
      return List<Map<String, dynamic>>.from(response.data['data']['messages']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Returns `{ is_online: bool, last_seen_at: String? }` for a user.
  Future<Map<String, dynamic>> fetchUserStatus(String userId) async {
    try {
      final response = await _dio.get(ApiEndpoints.userStatus(userId));
      return Map<String, dynamic>.from(response.data['data'] as Map);
    } catch (_) {
      return {'is_online': false, 'last_seen_at': null};
    }
  }

  /// Marks all unread messages in [conversationId] as read.
  /// Fire-and-forget — errors are swallowed intentionally.
  Future<void> markRead(String conversationId) async {
    try {
      await _dio.post(ApiEndpoints.markRead(conversationId));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String text,
  ) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.messages(conversationId),
        data: {'content': text, 'message_type': 'text'},
      );
      return Map<String, dynamic>.from(response.data['data'] as Map);
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
