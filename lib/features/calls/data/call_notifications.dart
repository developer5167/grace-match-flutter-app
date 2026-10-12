import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/notifications/push_center.dart';
import 'call_session.dart';

/// Android tray item for a live call. Incoming already has CallKit's ringing
/// notification; outgoing did not, so this is what shows "Calling Priya" when
/// the member leaves the call screen.
class CallNotifications {
  CallNotifications._();

  static const id = 71001;
  static const channelId = 'gracematch_calls';
  static bool _channelReady = false;

  static Future<void> ensureChannel() async {
    if (_channelReady) return;
    await PushCenter.ensurePlugin();
    await PushCenter.plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            'Ongoing calls',
            description: 'Shown while you are on a GraceMatch call',
            importance: Importance.high,
            playSound: false,
            showBadge: false,
          ),
        );
    _channelReady = true;
  }

  static Future<void> show(CallSession session) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await ensureChannel();
    final connected = session.phase == CallPhase.connected;
    await PushCenter.plugin.show(
      id,
      session.peerName,
      _body(session),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Ongoing calls',
          channelDescription: 'Shown while you are on a GraceMatch call',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
          usesChronometer: connected,
          when: session.connectedAt?.millisecondsSinceEpoch,
          actions: const [
            AndroidNotificationAction(
              'call_hangup',
              'Hang up',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
      ),
      payload: jsonEncode({'kind': 'ongoing_call'}),
    );
  }

  static Future<void> hide() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await PushCenter.ensurePlugin();
    await PushCenter.plugin.cancel(id);
  }

  static String _body(CallSession session) {
    if (session.reconnecting) return 'Reconnecting…';
    switch (session.phase) {
      case CallPhase.connected:
        return session.isVideo ? 'On a video call' : 'On a voice call';
      case CallPhase.ringing:
        return session.isCaller ? 'Ringing…' : 'Connecting…';
      case CallPhase.connecting:
        return 'Connecting…';
      default:
        return session.isCaller ? 'Calling…' : 'Connecting…';
    }
  }
}
