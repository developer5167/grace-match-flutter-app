import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/screens/phone_input_screen.dart';
import '../../features/auth/screens/otp_verification_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/discover/screens/discover_screen.dart';
import '../../features/interests/screens/interests_screen.dart';
import '../../features/chat/screens/conversations_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/activity/screens/activity_screen.dart';
import '../../features/profile/screens/my_profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/profile/screens/share_preview_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/subscriptions/screens/subscription_screen.dart';
import '../../features/offers/screens/offers_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/calls/screens/call_screen.dart';
import '../../features/support/screens/support_screen.dart';
import '../../features/support/screens/new_ticket_screen.dart';
import '../../features/support/screens/ticket_screen.dart';
import '../network/socket_service.dart';
import '../di/injection.dart' as di;
import '../../features/profile/screens/review_status_screen.dart';
import '../../features/profile/screens/identity_verification_screen.dart';
import '../storage/app_storage.dart';
import '../../core/widgets/app_shell.dart';

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  /// The root navigator, for things that must appear over whatever is on
  /// screen — an incoming call being the only one so far.
  static GlobalKey<NavigatorState> get rootNavigatorKey => _rootKey;
  static final _shellKey = GlobalKey<NavigatorState>();

  static late GoRouter router;

  static Future<void> init() async {
    router = GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/splash',
      redirect: (context, state) async {
        final isAuth = await AppStorage.getAccessToken() != null;
        final path = state.uri.path;

        if (path == '/splash') return null;

        if (!isAuth) {
          if (path.startsWith('/auth')) return null;
          if (path.startsWith('/p/')) return null;
          return '/auth/phone';
        }

        if (!AppStorage.isOnboardingComplete()) {
          if (path == '/onboarding') return null;
          return '/onboarding';
        }

        // Not approved yet: they may fix what staff asked for, talk to
        // support, or wait. Discover/chat stay closed until approval.
        final reviewStatus = AppStorage.getReviewStatus();
        if (reviewStatus != 'approved') {
          final fixing = path == '/review-status' ||
              path == '/onboarding' ||
              path == '/verify-identity' ||
              path == '/notifications' ||
              path.startsWith('/support');
          if (fixing) return null;
          return '/review-status';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/review-status',
          builder: (_, __) => const ReviewStatusScreen(),
        ),
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashScreen(),
        ),

        // ─── Auth Routes ──────────────────────────────────────
        GoRoute(
          path: '/auth/phone',
          builder: (_, __) => const PhoneInputScreen(),
          routes: [
            GoRoute(
              path: 'otp',
              builder: (_, state) {
                final phone = state.extra as String? ?? '';
                return OtpVerificationScreen(phone: phone);
              },
            ),
          ],
        ),

        // ─── Onboarding ───────────────────────────────────────
        GoRoute(
          path: '/onboarding',
          builder: (_, state) {
            final extraStep = state.extra is int ? state.extra as int : null;
            final queryStep = int.tryParse(state.uri.queryParameters['step'] ?? '');
            return OnboardingScreen(
              initialStep: extraStep ?? queryStep,
              fixAction: state.uri.queryParameters['action'],
            );
          },
        ),
        GoRoute(
          path: '/verify-identity',
          builder: (_, __) => const IdentityVerificationScreen(),
        ),

        // ─── Main Shell (bottom nav) ──────────────────────────
        ShellRoute(
          navigatorKey: _shellKey,
          builder: (_, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/discover',
              builder: (_, __) => const DiscoverScreen(),
            ),
            GoRoute(
              path: '/interests',
              builder: (_, __) => const InterestsScreen(),
            ),
            GoRoute(
              path: '/chat',
              builder: (_, __) => const ConversationsScreen(),
            ),
            GoRoute(
              path: '/activity',
              builder: (_, __) => const ActivityScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const MyProfileScreen(),
            ),
          ],
        ),

        // ─── Detail Routes (full screen) ──────────────────────
        GoRoute(
          path: '/chat/:convId',
          builder: (_, state) {
            final convId = state.pathParameters['convId']!;
            final extra = state.extra as Map<String, dynamic>?;
            return ChatScreen(
              conversationId: convId,
              otherUserName: extra?['name'] ?? '',
              otherUserPhoto: extra?['photo'],
              otherUserId: extra?['userId']?.toString(),
            );
          },
        ),
        GoRoute(
          path: '/profile/preview',
          builder: (_, __) => const PublicProfileScreen(),
        ),
        GoRoute(
          path: '/profile/:id',
          builder: (_, state) {
            final source = state.uri.queryParameters['source'];
            final hideActions = source == 'interests' || source == 'chat';
            return PublicProfileScreen(
              userId: state.pathParameters['id']!,
              showBottomActions: !hideActions,
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/subscription',
          // ?coupon= arrives when the member tapped "Use offer", so the code
          // is already in the box when the plans appear.
          builder: (_, state) => SubscriptionScreen(
            initialCoupon: state.uri.queryParameters['coupon'],
          ),
        ),
        GoRoute(
          path: '/offers',
          builder: (_, __) => const OffersScreen(),
        ),
        // Shared https://…/p/<userId> links. Guests see the public preview;
        // signed-in members get the full profile with actions.
        GoRoute(
          path: '/p/:id',
          redirect: (_, state) async {
            final authed = await AppStorage.getAccessToken() != null;
            if (authed &&
                AppStorage.isOnboardingComplete() &&
                AppStorage.getReviewStatus() == 'approved') {
              return '/profile/${state.pathParameters['id']}';
            }
            return null;
          },
          builder: (_, state) => SharePreviewScreen(
            userId: state.pathParameters['id']!,
          ),
        ),
        // Outgoing when `call` is absent, incoming when it carries the id of a
        // call that is already ringing.
        GoRoute(
          path: '/call/:conversationId',
          builder: (_, state) => CallScreen(
            socket: di.sl<SocketService>(),
            conversationId: state.pathParameters['conversationId']!,
            peerName: state.uri.queryParameters['name'] ?? 'Member',
            isVideo: state.uri.queryParameters['video'] != 'false',
            incomingCallId: state.uri.queryParameters['call'],
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        // Support. /support/new is declared before /support/:id so the literal
        // wins — otherwise "new" is matched as a ticket id and the member gets
        // a not-found instead of the compose screen.
        GoRoute(
          path: '/support',
          builder: (_, __) => const SupportScreen(),
        ),
        GoRoute(
          path: '/support/new',
          builder: (_, state) => NewTicketScreen(
            initialCategory: state.uri.queryParameters['category'],
          ),
        ),
        GoRoute(
          path: '/support/:id',
          builder: (_, state) => TicketScreen(ticketId: state.pathParameters['id']!),
        ),
      ],
    );
  }
}
