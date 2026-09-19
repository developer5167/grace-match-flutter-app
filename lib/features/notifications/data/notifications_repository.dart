import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'].toString(),
        type: j['type']?.toString() ?? 'system',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data']) : const {},
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id, type: type, title: title, body: body, data: data,
        isRead: isRead ?? this.isRead, createdAt: createdAt,
      );
}

class NotificationPage {
  final List<AppNotification> items;
  final int unreadCount;
  final bool hasMore;

  const NotificationPage({
    required this.items,
    required this.unreadCount,
    required this.hasMore,
  });
}

class NotificationsRepository {
  final _dio = DioClient.instance;

  Future<NotificationPage> fetch({int page = 1, int limit = 30}) async {
    final res = await _dio.get(
      ApiEndpoints.notifications,
      queryParameters: {'page': page, 'limit': limit},
    );
    final d = Map<String, dynamic>.from(res.data['data'] ?? {});
    final raw = d['notifications'];
    return NotificationPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      unreadCount: (d['unread_count'] as num?)?.toInt() ?? 0,
      hasMore: d['has_more'] == true,
    );
  }

  Future<void> markRead(String id) =>
      _dio.put(ApiEndpoints.notificationRead(id));

  Future<void> markAllRead() => _dio.put(ApiEndpoints.notificationsReadAll);
}
