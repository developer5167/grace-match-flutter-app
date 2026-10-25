import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_links/app_links.dart';
import 'core/constants/app_constants.dart';
import 'core/storage/app_storage.dart';
import 'core/state/active_chat_state.dart';
import 'core/router/app_router.dart';
import 'core/notifications/push_center.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/membership_palette.dart';
import 'core/di/injection.dart' as di;
import 'core/network/socket_service.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as ck;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'features/calls/data/call_kit.dart';
import 'features/calls/data/call_manager.dart';
import 'features/calls/widgets/ongoing_call_bar.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/onboarding/bloc/onboarding_bloc.dart';
import 'features/discover/bloc/discover_bloc.dart';
import 'features/interests/bloc/interests_bloc.dart';
import 'features/profile/bloc/profile_bloc.dart';
import 'features/chat/bloc/chat_bloc.dart';
import 'features/subscriptions/bloc/subscription_bloc.dart';
import 'features/activity/bloc/activity_bloc.dart';
import 'firebase_options.dart';


// Background message handler — must be top-level, called when app is killed/background.
//
// Rings with the phone's call UI: full screen on the lock screen, a ringing
// notification with Accept and Decline otherwise. Runs in its own isolate, so
// it must not touch Hive or the service locator.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = Map<String, dynamic>.from(message.data);
  if (CallKit.isIncoming(data)) {
    final call = CallKit.parse(data);
    if (call != null) await CallKit.ring(call);
    return;
  }
  if (CallKit.isCancelled(data)) {
    final id = data['call_id']?.toString();
    if (id != null && id.isNotEmpty) await CallKit.dismissIfRinging(id);
    return;
  }
  if (_isTypingCleared(data)) {
    await PushCenter.ensurePlugin();
    await PushCenter.clear([data['tag']?.toString() ?? 'typing:${data['conversation_id']}']);
    return;
  }
  // Data-only Android messages: the app draws the tray item so tap and
  // dismiss both work. System-drawn FCM notifications do neither reliably.
  final title = message.notification?.title ?? data['title']?.toString();
  final body = message.notification?.body ?? data['body']?.toString();
  if (title != null && title.isNotEmpty) {
    await PushCenter.showForeground(title: title, body: body, data: data);
  }
}

bool _isTypingCleared(Map<String, dynamic> data) =>
    data['kind']?.toString() == 'typing_cleared' || data['type']?.toString() == 'typing_cleared';

// The call UI's buttons, pressed while the app is not running. Accept needs
// nothing here: it launches the app, which picks the call up on start.
@pragma('vm:entry-point')
Future<void> _callKitBackgroundHandler(ck.CallEvent event) async {
  if (event is ck.CallEventActionCallDecline) {
    await CallKit.rejectOverHttp(event.callKitParams.id);
  } else if (event is ck.CallEventActionCallEnded) {
    await CallKit.endOverHttp(event.callKitParams.id);
  }
}

// Handles https://<site>/p/:userId links after the app is already running.
void _initAppLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    _handleAppLink(uri);
  });

  // Also handle the initial link if the app was cold-started via a link
  appLinks.getInitialLink().then((uri) {
    if (uri != null) _handleAppLink(uri);
  });
}

void _handleAppLink(Uri uri) {
  // Expected: https://gracematch.sotersystems.in/p/<userId>
  final segments = uri.pathSegments;
  if (segments.length >= 2 && segments[0] == 'p') {
    final userId = segments[1];
    AppStorage.setPendingShareProfile(userId);
    AppRouter.router.go('/p/$userId');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A release build pinned to the dev tunnel cannot be fixed without a new
  // store submission, so fail loudly here rather than silently in the field.
  AppConstants.assertReleaseConfig();

  final firebaseReady = await _initFirebase();
  if (firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  // Android only. iOS has no registerBackgroundHandler; calling it throws
  // MissingPluginException and the error is async, so a try/catch here misses it.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await FlutterCallkitIncoming.onBackgroundMessage(_callKitBackgroundHandler);
  }

  di.init();

  // Init storage before any authenticated network calls (e.g. FCM token sync)
  try {
    await AppStorage.init().timeout(const Duration(seconds: 5));
    MembershipTheme.bindPersist(AppStorage.saveMembershipPlan);
    MembershipTheme.restore(AppStorage.getMembershipPlan());
  } catch (e, st) {
    debugPrint('Storage init failed: $e\n$st');
  }

  // Answered on the lock screen while the app was closed: the call is
  // already accepted, and the app opens straight into it. Bounded so a
  // stuck native call cannot hold the white launch screen up.
  final answeredOnLaunch = await _answeredCallOnLaunch();

  // Connect early: answering needs the socket, and every second here is a
  // second the caller hears ringing after the member picked up.
  di.sl<SocketService>().connect();
  CallManager.instance.start(di.sl<SocketService>());

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await AppRouter.init(initialLocation: answeredOnLaunch != null ? '/call' : '/splash');
  if (answeredOnLaunch != null) {
    CallManager.instance.acceptIncoming(
      answeredOnLaunch,
      fromCallKit: true,
      navigate: false,
    );
  }

  // App Links — handle incoming deep links while the app is running.
  // Cold-start links are handled by the router's redirect logic when
  // GoRouter picks up the initial URI automatically (Flutter 3.x+).
  _initAppLinks();

  runApp(const GraceMatchApp());

  // The notification prompt needs a visible window. On a fresh TestFlight
  // install this used to be awaited above, the system dialog never appeared,
  // and runApp was never reached — the white launch screen stayed forever.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_prepareNotifications(firebaseReady));
  });
}

Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
    return true;
  } catch (e, st) {
    debugPrint('Firebase init failed: $e\n$st');
    return false;
  }
}

Future<IncomingCallData?> _answeredCallOnLaunch() async {
  try {
    final hasSession = await AppStorage.getAccessToken()
        .timeout(const Duration(seconds: 3));
    if (hasSession == null) return null;
    return await CallKit.takeAcceptedOnLaunch()
        .timeout(const Duration(seconds: 3));
  } catch (e, st) {
    debugPrint('Launch call check failed: $e\n$st');
    return null;
  }
}

Future<void> _prepareNotifications(bool firebaseReady) async {
  try {
    if (!firebaseReady) return;

    final messaging = FirebaseMessaging.instance;
    await messaging
        .requestPermission(alert: true, badge: true, sound: true)
        .timeout(const Duration(seconds: 20));
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    void openFromPush(RemoteMessage message) {
      final data = message.data;
      if (CallKit.isIncoming(data)) {
        CallManager.instance.onIncoming(data);
        return;
      }
      PushCenter.open(data);
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (CallKit.isIncoming(message.data)) {
        CallManager.instance.onIncoming(message.data);
        return;
      }
      if (CallKit.isCancelled(message.data)) {
        final id = message.data['call_id']?.toString();
        if (id != null && id.isNotEmpty) CallManager.instance.onCancelled(id);
        return;
      }
      if (_isTypingCleared(message.data)) {
        PushCenter.clear([message.data['tag']?.toString() ?? 'typing:${message.data['conversation_id']}']);
        return;
      }

      // Suppress if the user is already inside the conversation this message belongs to
      final incomingConvId = message.data['conversation_id'];
      if (incomingConvId != null &&
          incomingConvId == ActiveChatState.conversationId) {
        PushCenter.clearChat(incomingConvId.toString());
        return; // Socket already delivered it live — no duplicate notification
      }

      final title = message.notification?.title ?? message.data['title']?.toString();
      final body = message.notification?.body ?? message.data['body']?.toString();
      if (title != null && title.isNotEmpty) {
        PushCenter.showForeground(
          title: title,
          body: body,
          data: message.data,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(openFromPush);

    // Sync FCM token for logged-in user on app start. Not awaited: it is a
    // network round trip, and start-up — an answered call included — should
    // not wait on it. On iOS the APNS token arrives after permission, so
    // getToken() fails if it is called in the same turn.
    final authRepository = AuthRepository();
    unawaited(_syncFcmToken(authRepository));

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      debugPrint('FCM_TOKEN_REFRESHED: $token');
      await authRepository.updateFcmToken(token);
    });

    // Only set when iOS launched the app by tapping a notification. Otherwise
    // the native call never answers, so it must not sit on the startup path.
    unawaited(_openLaunchNotification(openFromPush));
  } catch (e, st) {
    debugPrint('Notification startup failed: $e\n$st');
  } finally {
    // Splash is waiting on this. Local notifications must not hold it: on iOS
    // their plugin initialize can sit unanswered, and a timeout here used to
    // skip every Firebase listener above.
    PushCenter.markLaunchReady();
  }

  if (firebaseReady) unawaited(_initLocalNotifications());
}

Future<void> _openLaunchNotification(
  void Function(RemoteMessage message) openFromPush,
) async {
  try {
    final launchedFrom = await FirebaseMessaging.instance
        .getInitialMessage()
        .timeout(const Duration(seconds: 3));
    if (launchedFrom != null) openFromPush(launchedFrom);
  } catch (e) {
    if (e is! TimeoutException) {
      debugPrint('No launch notification: $e');
    }
  }
}

Future<void> _syncFcmToken(AuthRepository authRepository) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      String? apns;
      for (var attempt = 0; attempt < 10 && apns == null; attempt++) {
        apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      if (apns == null) {
        debugPrint(
          'FCM token skipped: Apple has not issued an APNS token. '
          'This is normal on the iOS Simulator.',
        );
        return;
      }
    }
    final startupToken = await FirebaseMessaging.instance.getToken();
    if (startupToken != null && startupToken.isNotEmpty) {
      debugPrint('FCM_TOKEN: $startupToken');
      await authRepository.updateFcmToken(startupToken);
    } else {
      debugPrint('FCM_TOKEN: <null>');
    }
  } catch (e) {
    debugPrint('FCM_TOKEN failed: $e');
  }
}

Future<void> _initLocalNotifications() async {
  try {
    await PushCenter.init().timeout(const Duration(seconds: 5));
    const androidChannel = AndroidNotificationChannel(
      'gracematch_default',
      'General',
      description: 'General notifications for GraceMatch',
      importance: Importance.high,
    );
    await PushCenter.plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  } catch (e) {
    debugPrint('Local notifications init failed: $e');
  }
}

class GraceMatchApp extends StatefulWidget {
  const GraceMatchApp({super.key});

  @override
  State<GraceMatchApp> createState() => _GraceMatchAppState();
}

class _GraceMatchAppState extends State<GraceMatchApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      di.sl<SocketService>().ensureConnected();
      CallManager.instance.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<AuthBloc>()),
        BlocProvider(create: (_) => di.sl<OnboardingBloc>()),
        BlocProvider(create: (_) => di.sl<DiscoverBloc>()),
        BlocProvider(create: (_) => di.sl<InterestsBloc>()),
        BlocProvider(create: (_) => di.sl<ProfileBloc>()),
        BlocProvider(create: (_) => di.sl<ChatBloc>()),
        BlocProvider(create: (_) => di.sl<SubscriptionBloc>()),
        BlocProvider(create: (_) => di.sl<ActivityBloc>()),
      ],
      child: ListenableBuilder(
        listenable: MembershipTheme.instance,
        builder: (context, _) {
          return MaterialApp.router(
            title: 'GraceMatch',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            routerConfig: AppRouter.router,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
                child: AnimatedTheme(
                  data: AppTheme.dark,
                  duration: const Duration(milliseconds: 280),
                  child: OngoingCallLayer(child: child!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
