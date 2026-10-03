import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

/// Numbers and dates from the API are parsed defensively.
///
/// Postgres NUMERIC columns arrive as strings, and a cast that assumes
/// otherwise crashes the screen. That already happened once on the offers
/// screen; there is no reason to learn it twice.
int _int(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString())?.toInt() ?? fallback;
}

DateTime _date(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

/// What a member can write to support about.
class SupportCategory {
  final String key;
  final String label;
  final String? hint;

  const SupportCategory({required this.key, required this.label, this.hint});

  factory SupportCategory.fromJson(Map<String, dynamic> j) => SupportCategory(
        key: j['key']?.toString() ?? 'other',
        label: j['label']?.toString() ?? 'Something else',
        hint: j['hint']?.toString(),
      );
}

class SupportTicket {
  final String id;
  final String category;
  final String subject;
  final String status;
  final String priority;
  final String? lastMessage;
  final int unread;
  final DateTime lastMessageAt;
  final DateTime createdAt;

  /// Whether support has allowed this member to attach a photo.
  ///
  /// Off until a support member turns it on for this conversation. Most
  /// questions need no picture, and an always-visible attach button is an
  /// open image upload on an endpoint that exists to handle complaints.
  final bool attachmentsEnabled;

  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.status,
    required this.priority,
    required this.lastMessage,
    required this.unread,
    required this.lastMessageAt,
    required this.createdAt,
    required this.attachmentsEnabled,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: j['id'].toString(),
        category: j['category']?.toString() ?? 'other',
        subject: j['subject']?.toString() ?? '',
        status: j['status']?.toString() ?? 'open',
        priority: j['priority']?.toString() ?? 'normal',
        lastMessage: j['last_message']?.toString(),
        unread: _int(j['unread_for_member']),
        lastMessageAt: _date(j['last_message_at']),
        createdAt: _date(j['created_at']),
        attachmentsEnabled: j['attachments_enabled'] == true,
      );

  bool get isSettled => status == 'resolved' || status == 'closed';

  /// What the member should understand from the status, in their words.
  String get statusLabel {
    switch (status) {
      case 'open':            return 'Sent';
      case 'awaiting_staff':  return 'Waiting for support';
      case 'awaiting_member': return 'Support replied';
      case 'resolved':        return 'Resolved';
      case 'closed':          return 'Closed';
      default:                return status;
    }
  }
}

class SupportMessage {
  final String id;
  final String senderType; // member | staff | system
  final String? senderName;
  final String? body;
  final String? attachmentUrl;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.senderType,
    required this.senderName,
    required this.body,
    required this.attachmentUrl,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: j['id'].toString(),
        senderType: j['sender_type']?.toString() ?? 'system',
        senderName: j['sender_name']?.toString(),
        body: j['body']?.toString(),
        attachmentUrl: j['attachment_url']?.toString(),
        createdAt: _date(j['created_at']),
      );

  bool get isMine => senderType == 'member';
}

class SupportRepository {
  final _dio = DioClient.instance;

  Future<List<SupportCategory>> categories() async {
    final res = await _dio.get(ApiEndpoints.supportCategories);
    final list = res.data['data']?['categories'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => SupportCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<SupportTicket>> tickets() async {
    final res = await _dio.get(ApiEndpoints.supportTickets);
    final list = res.data['data']?['tickets'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int> unread() async {
    try {
      final res = await _dio.get(ApiEndpoints.supportUnread);
      return _int(res.data['data']?['unread']);
    } catch (_) {
      // A badge is not worth an error state.
      return 0;
    }
  }

  /// Opens a conversation.
  ///
  /// The server refuses a second open conversation in the same category and
  /// returns the existing one — surfaced here as [DuplicateTicket] so the UI
  /// can take the member to the thread they already have instead of showing
  /// them an error for something that is not their mistake.
  Future<SupportTicket> open({
    required String category,
    required String subject,
    required String message,
  }) async {
    try {
      final res = await _dio.post(ApiEndpoints.supportTickets, data: {
        'category': category,
        'subject': subject.trim(),
        'message': message.trim(),
      });
      return SupportTicket.fromJson(Map<String, dynamic>.from(res.data['data']));
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 409 && data is Map) {
        throw DuplicateTicket(
          ticketId: data['data']?['ticket_id']?.toString() ?? '',
          message: data['message']?.toString() ?? 'You already have a conversation about this.',
        );
      }
      throw Exception(_message(e));
    }
  }

  Future<({SupportTicket ticket, List<SupportMessage> messages})> thread(String id) async {
    final res = await _dio.get(ApiEndpoints.supportTicket(id));
    final d = Map<String, dynamic>.from(res.data['data']);
    final raw = d['messages'];
    return (
      ticket: SupportTicket.fromJson(Map<String, dynamic>.from(d['ticket'])),
      messages: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => SupportMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <SupportMessage>[],
    );
  }

  /// Reply, optionally with a photo.
  ///
  /// The server refuses an attachment when support has not enabled it for this
  /// conversation, so hiding the button is a convenience rather than the
  /// control — the permission lives on the server.
  Future<SupportMessage> reply(
    String ticketId,
    String message, {
    String? imagePath,
  }) async {
    try {
      final Object data;
      if (imagePath != null) {
        data = FormData.fromMap({
          if (message.trim().isNotEmpty) 'message': message.trim(),
          'attachment': await MultipartFile.fromFile(imagePath),
        });
      } else {
        data = {'message': message.trim()};
      }

      final res = await _dio.post(ApiEndpoints.supportMessages(ticketId), data: data);
      return SupportMessage.fromJson(Map<String, dynamic>.from(res.data['data']));
    } on DioException catch (e) {
      throw Exception(_message(e));
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return 'Could not reach support. Please try again.';
  }
}

/// Thrown when the member already has an open conversation in this category.
class DuplicateTicket implements Exception {
  final String ticketId;
  final String message;
  const DuplicateTicket({required this.ticketId, required this.message});

  @override
  String toString() => message;
}
