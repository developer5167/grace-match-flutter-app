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
import 'features/calls/data/incoming_call_watcher.dart';
import 'features/calls/screens/call_screen.dart';
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
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // No UI work here — system tray notification is shown automatically by FCM
  // when the backend sends both notification + data payloads.
}

// Handles gracematch.app/p/:userId links after the app is already running.
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
  // Expected: https://gracematch.app/p/<userId>
  final segments = uri.pathSegments;
  if (segments.length >= 2 && segments[0] == 'p') {
    final userId = segments[1];
    AppRouter.router.push('/profile/$userId');
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

  // Initialize DI
  di.init();

  // Init storage before any authenticated network calls (e.g. FCM token sync)
  await AppStorage.init();

  // FCM Setup
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Local Notifications for foreground
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(android: initializationSettingsAndroid));
  const androidChannel = AndroidNotificationChannel(
    'gracematch_default',
    'General',
    description: 'General notifications for GraceMatch',
    importance: Importance.high,
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Suppress if the user is already inside the conversation this message belongs to
    final incomingConvId = message.data['conversation_id'];
    if (incomingConvId != null &&
        incomingConvId == ActiveChatState.conversationId) {
      return; // Socket already delivered it live — no duplicate notification
    }

    final notification = message.notification;
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
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

  // Sync FCM token for logged-in user on app start.
  final authRepository = AuthRepository();
  final startupToken = await FirebaseMessaging.instance.getToken();
  if (startupToken != null && startupToken.isNotEmpty) {
    debugPrint('FCM_TOKEN: $startupToken');
    await authRepository.updateFcmToken(startupToken);
  } else {
    debugPrint('FCM_TOKEN: <null>');
  }

  // Keep backend token updated when FCM rotates token.
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    debugPrint('FCM_TOKEN_REFRESHED: $token');
    await authRepository.updateFcmToken(token);
  });

  // Connect Sockets
  di.sl<SocketService>().connect();

  // A call can arrive while the member is anywhere in the app, so the listener
  // lives above the routes rather than on the call screen — otherwise the only
  // place a call could be received is the screen you reach by making one.
  CallScreenFactory.builder = ({
    required socket,
    required conversationId,
    required peerName,
    required isVideo,
    incomingCallId,
  }) =>
      CallScreen(
        socket: socket,
        conversationId: conversationId,
        peerName: peerName,
        isVideo: isVideo,
        incomingCallId: incomingCallId,
      );

  IncomingCallWatcher(
    socket: di.sl<SocketService>(),
    navigatorKey: AppRouter.rootNavigatorKey,
  ).start();

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
  await AppRouter.init();

  // App Links — handle incoming deep links while the app is running.
  // Cold-start links are handled by the router's redirect logic when
  // GoRouter picks up the initial URI automatically (Flutter 3.x+).
  _initAppLinks();

  runApp(const GraceMatchApp());
}

class GraceMatchApp extends StatelessWidget {
  const GraceMatchApp({super.key});

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
            child: child!,
          );
        },
      ),
    );
  }
}
