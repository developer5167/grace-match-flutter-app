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
import 'core/theme/app_theme.dart';
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

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// Background message handler — must be top-level, called when app is killed/background.
//
// Rings with the phone's call UI: full screen on the lock screen, a ringing
// notification with Accept and Decline otherwise. Runs in its own isolate, so
// it must not touch Hive or the service locator.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  if (CallKit.isIncoming(data)) {
    final call = CallKit.parse(data);
    if (call != null) await CallKit.ring(call);
    return;
  }
  if (CallKit.isCancelled(data)) {
    final id = data['call_id']?.toString();
    if (id != null && id.isNotEmpty) await CallKit.dismissIfRinging(id);
  }
}

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

  // Initialize Firebase
await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); 
   FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FlutterCallkitIncoming.onBackgroundMessage(_callKitBackgroundHandler);

  // Initialize DI
  di.init();

  // Init storage before any authenticated network calls (e.g. FCM token sync)
  await AppStorage.init();

  // Answered on the lock screen while the app was closed: the call is
  // already accepted, and the app opens straight into it.
  final hasSession = await AppStorage.getAccessToken() != null;
  final answeredOnLaunch = hasSession ? await CallKit.takeAcceptedOnLaunch() : null;

  // Connect early: answering needs the socket, and every second here is a
  // second the caller hears ringing after the member picked up.
  di.sl<SocketService>().connect();
  CallManager.instance.start(di.sl<SocketService>());

  // FCM Setup
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Local Notifications for foreground
  const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );
  const androidChannel = AndroidNotificationChannel(
    'gracematch_default',
    'General',
    description: 'General notifications for GraceMatch',
    importance: Importance.high,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

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

    // Suppress if the user is already inside the conversation this message belongs to
    final incomingConvId = message.data['conversation_id'];
    if (incomingConvId != null &&
        incomingConvId == ActiveChatState.conversationId) {
      return; // Socket already delivered it live — no duplicate notification
    }

    final notification = message.notification;
    if (notification != null) {
      _localNotifications.show(
        message.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gracematch_default',
            'General',
            channelDescription: 'General notifications for GraceMatch',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    }
  });

  // Sync FCM token for logged-in user on app start. Not awaited: it is a
  // network round trip, and start-up — an answered call included — should
  // not wait on it.
  final authRepository = AuthRepository();
  FirebaseMessaging.instance.getToken().then((startupToken) async {
    if (startupToken != null && startupToken.isNotEmpty) {
      debugPrint('FCM_TOKEN: $startupToken');
      await authRepository.updateFcmToken(startupToken);
    } else {
      debugPrint('FCM_TOKEN: <null>');
    }
  }).catchError((Object e) {
    debugPrint('FCM_TOKEN failed: $e');
  });

  // Keep backend token updated when FCM rotates token.
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    debugPrint('FCM_TOKEN_REFRESHED: $token');
    await authRepository.updateFcmToken(token);
  });

  // Screenshot & screen-recording protection (Android only via FLAG_SECURE).
  // Implemented natively in MainActivity.kt — no package needed.

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent system UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Enable edge-to-edge rendering
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Init router (needs async for token check)
  await AppRouter.init(initialLocation: answeredOnLaunch != null ? '/call' : '/splash');
  if (answeredOnLaunch != null) {
    CallManager.instance.acceptIncoming(
      answeredOnLaunch,
      fromCallKit: true,
      navigate: false,
    );
  }

  void openFromPush(RemoteMessage message) {
    final data = message.data;
    if (CallKit.isIncoming(data)) {
      CallManager.instance.onIncoming(data);
      return;
    }
    final route = data['route']?.toString();
    final kind = data['kind']?.toString();
    if (route != null && route.startsWith('/')) {
      AppRouter.router.go(route);
      return;
    }
    if (kind == 'contact_request' || kind == 'contact_approved') {
      AppRouter.router.go('/activity');
      return;
    }
    if (kind == 'REVIEW_ACTIONS' ||
        kind == 'APPLICATION_RESULT' ||
        kind == 'PHOTO_REVIEW_RESULT' ||
        kind == 'ADMIN_MESSAGE') {
      AppRouter.router.go('/review-status');
    }
  }

  FirebaseMessaging.onMessageOpenedApp.listen(openFromPush);
  final launchedFrom = await FirebaseMessaging.instance.getInitialMessage();
  if (launchedFrom != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openFromPush(launchedFrom));
  }

  // App Links — handle incoming deep links while the app is running.
  // Cold-start links are handled by the router's redirect logic when
  // GoRouter picks up the initial URI automatically (Flutter 3.x+).
  _initAppLinks();

  runApp(const GraceMatchApp());
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
      child: MaterialApp.router(
        title: 'GraceMatch',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: AppRouter.router,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            child: OngoingCallLayer(child: child!),
          );
        },
      ),
    );
  }
}
