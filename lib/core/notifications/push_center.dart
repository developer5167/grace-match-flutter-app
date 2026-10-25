import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../router/app_router.dart';

/// Where a notification goes when tapped, and taking it down again once the
/// member has seen what it was about.
///
/// The server sends every push with a `route` (the screen to open) and a
/// `tag` (`chat:<id>`, `typing:<id>`, `interests`, `views`…). Android posts a
/// push under its tag, so a second message from the same chat replaces the
/// first, and [clear] can remove it when the chat is opened from inside the
/// app rather than from the notification.
class PushCenter {
  PushCenter._();

  static final plugin = FlutterLocalNotificationsPlugin();

  /// Cold-start push handling. The splash screen waits on this before it
  /// picks a route, so a notification tap is not lost. It is completed from
  /// the first frame — requesting permission before the window exists hangs
  /// a fresh iOS install on the white launch screen.
  static final Completer<void> _launchReady = Completer<void>();
  static Future<void> get launchReady => _launchReady.future;

  static void markLaunchReady() {
    if (!_launchReady.isCompleted) _launchReady.complete();
  }

  /// A route from a tap that arrived before the app was ready to show it —
  /// a cold start, where the splash screen is still deciding where to go.
  static String? _pending;
  static bool _ready = false;
  static bool _pluginReady = false;

  /// Return true when the response was fully handled and should not open a route.
  static bool Function(NotificationResponse response)? extraResponseHandler;

  static const _channel = AndroidNotificationDetails(
    'gracematch_default',
    'General',
    channelDescription: 'General notifications for GraceMatch',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> ensurePlugin() async {
    if (_pluginReady) return;
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Firebase Messaging already asks for permission during startup.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (extraResponseHandler?.call(r) == true) return;
        final data = decode(r.payload);
        if (data != null) open(data);
      },
      // Android only. The iOS callback is a no-op, and registering it makes
      // initialize wait on a second engine that never answers in debug.
      onDidReceiveBackgroundNotificationResponse:
          defaultTargetPlatform == TargetPlatform.android
              ? notificationTapBackground
              : null,
    );
    _pluginReady = true;
  }

  static Future<void> init() async {
    await ensurePlugin();
    // iOS reports the notification that opened the app through Firebase.
    // This plugin call does not answer on the scene lifecycle.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final data = decode(launch?.notificationResponse?.payload);
      if (data != null) open(data);
    }
  }

  static Map<String, dynamic>? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  /// The screen for a push. Older pushes carry no route, so derive one.
  static String? routeFor(Map<String, dynamic> data) {
    final route = data['route']?.toString();
    if (route != null && route.startsWith('/')) return route;
    final type = data['type']?.toString();
    final kind = data['kind']?.toString();
    final conv = data['conversation_id']?.toString();
    if (conv != null && conv.isNotEmpty &&
        (type == 'new_message' ||
            type == 'interest_accepted' ||
            kind == 'missed_call' ||
            type == 'typing' ||
            kind == 'typing')) {
      return '/chat/$conv';
    }
    switch (type) {
      case 'interest_received':
        return '/interests?tab=received';
      case 'interest_rejected':
        return '/interests?tab=sent';
      case 'profile_viewed':
        return '/activity?tab=views';
      case 'shortlisted':
        return '/activity?tab=shortlisted';
      case 'contact_request':
      case 'contact_approved':
        return '/activity?tab=contacts';
      case 'new_message':
        return '/chat';
    }
    if (kind == 'contact_request' || kind == 'contact_response') {
      return '/activity?tab=contacts';
    }
    if (const ['REVIEW_ACTIONS', 'APPLICATION_RESULT', 'PHOTO_REVIEW_RESULT', 'ADMIN_MESSAGE']
        .contains(kind)) {
      return '/review-status';
    }
    if (kind == 'app_update') return '/splash';
    return '/activity?tab=notifications';
  }

  static bool get hasPending => _pending != null;

  /// A notification was tapped.
  static void open(Map<String, dynamic> data) {
    final route = routeFor(data);
    if (route == null) return;
    final tag = data['tag']?.toString();
    if (tag != null && tag.isNotEmpty) {
      clear([tag]);
    } else {
      final conv = data['conversation_id']?.toString();
      if (conv != null && conv.isNotEmpty) clearChat(conv);
    }
    if (!_ready) {
      _pending = route;
      return;
    }
    goTo(route);
  }

  /// Called by the splash screen once start-up is done. Returns true when it
  /// navigated to a tapped notification's screen.
  static bool finishStartup() {
    _ready = true;
    final route = _pending;
    _pending = null;
    if (route == null) return false;
    goTo(route);
    return true;
  }

  /// Start-up went somewhere a tapped notification cannot override — sign-in,
  /// onboarding. The tap is dropped.
  static void finishStartupDiscarding() {
    _ready = true;
    _pending = null;
  }

  /// Open [route] with a sensible screen under it, so back goes somewhere
  /// that makes sense rather than closing the app.
  static void goTo(String route) {
    void run() {
      try {
        final router = AppRouter.router;
        final path = Uri.parse(route).path;
        const tabs = ['/discover', '/interests', '/chat', '/activity', '/profile'];
        if (tabs.contains(path) || path == '/splash') {
          router.go(route);
          return;
        }
        final base = path.startsWith('/chat/')
            ? '/chat'
            : path.startsWith('/support')
                ? '/profile'
                : '/discover';
        router.go(base);
        // `go` replaces the stack asynchronously. Push on the next frame so
        // it lands on top of the tab rather than being dropped.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          try {
            router.push(route);
          } catch (e) {
            debugPrint('push $route failed: $e');
            router.go(route);
          }
        });
      } catch (e) {
        debugPrint('open $route failed: $e');
      }
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      run();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  static int _id(String tag) => tag.hashCode & 0x7fffffff;

  /// Show a push that arrived while the app was open (or as a data-only
  /// message in the background isolate), under the same tag the system would
  /// have used, so it replaces and clears the same way.
  static Future<void> showForeground({
    required String? title,
    required String? body,
    required Map<String, dynamic> data,
  }) async {
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) return;
    await ensurePlugin();
    final tag = data['tag']?.toString();
    final hasTag = tag != null && tag.isNotEmpty;
    final id = hasTag ? _id(tag) : data.hashCode & 0x7fffffff;
    final quiet = data['kind']?.toString() == 'typing' || data['type']?.toString() == 'typing';
    await plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.channelId,
          _channel.channelName,
          channelDescription: _channel.channelDescription,
          importance: _channel.importance,
          priority: _channel.priority,
          playSound: !quiet,
          enableVibration: !quiet,
          tag: hasTag ? tag : null,
          // Typing is a hint, not a demand: no sound, and it goes away on its own.
          timeoutAfter: quiet ? 15000 : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: !quiet,
          presentBadge: !quiet,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  /// Take down notifications by tag. Covers items we posted (id = hash of
  /// the tag) and any FCM-posted leftover that used id 0 with the same tag.
  static Future<void> clear(Iterable<String> tags) async {
    await ensurePlugin();
    final set = tags.where((t) => t.isNotEmpty).toSet();
    for (final tag in set) {
      final id = _id(tag);
      try {
        await plugin.cancel(0, tag: tag);
        await plugin.cancel(id, tag: tag);
        await plugin.cancel(id);
      } catch (e) {
        debugPrint('clear notification $tag failed: $e');
      }
    }
    try {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final active = await android?.getActiveNotifications();
      if (active == null) return;
      for (final n in active) {
        final tag = n.tag;
        if (tag != null && set.contains(tag)) {
          await plugin.cancel(n.id ?? 0, tag: tag);
        }
      }
    } catch (_) {}
  }

  /// Everything about one conversation: its messages, "is typing", a missed
  /// call, the match that opened it.
  static Future<void> clearChat(String conversationId) => clear([
        'chat:$conversationId',
        'typing:$conversationId',
        'missed:$conversationId',
      ]);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Payload is handled when the app comes up: [PushCenter.init] reads
  // getNotificationAppLaunchDetails. Nothing to do in this isolate.
}
