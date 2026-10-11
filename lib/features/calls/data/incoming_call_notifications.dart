import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// High-priority incoming-call tray notification — Accept / Decline on the
/// shade, and a full-screen intent when the phone is locked or idle.
const incomingCallChannel = AndroidNotificationChannel(
  'gracematch_incoming_calls',
  'Incoming calls',
  description: 'Incoming voice and video calls',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const acceptCallActionId = 'call_accept';
const declineCallActionId = 'call_decline';

Map<String, dynamic> incomingCallPayload(Map<String, dynamic> data) => {
      'kind': 'incoming_call',
      'call_id': data['call_id']?.toString() ?? '',
      'conversation_id': data['conversation_id']?.toString() ?? '',
      'caller_name': data['caller_name']?.toString() ?? 'Someone',
      'is_video': data['is_video']?.toString() ?? 'true',
    };

Future<void> showIncomingCallNotification(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final callId = data['call_id']?.toString() ?? '';
  if (callId.isEmpty) return;

  final name = data['caller_name']?.toString() ?? 'Someone';
  final isVideo = data['is_video']?.toString() != 'false';
  final payload = jsonEncode(incomingCallPayload(data));
  final id = callId.hashCode & 0x7fffffff;

  await plugin.show(
    id,
    isVideo ? 'Incoming video call' : 'Incoming voice call',
    name,
    NotificationDetails(
      android: AndroidNotificationDetails(
        incomingCallChannel.id,
        incomingCallChannel.name,
        channelDescription: incomingCallChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        actions: const [
          AndroidNotificationAction(
            declineCallActionId,
            'Decline',
            cancelNotification: true,
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            acceptCallActionId,
            'Accept',
            showsUserInterface: true,
          ),
        ],
      ),
    ),
    payload: payload,
  );
}

Future<void> cancelIncomingCallNotification(
  FlutterLocalNotificationsPlugin plugin,
  String? callId,
) async {
  if (callId == null || callId.isEmpty) return;
  await plugin.cancel(callId.hashCode & 0x7fffffff);
}

Map<String, dynamic>? decodeCallPayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

bool isIncomingCallData(Map<String, dynamic> data) {
  final kind = data['kind']?.toString();
  final type = data['type']?.toString();
  return kind == 'incoming_call' || type == 'incoming_call';
}
