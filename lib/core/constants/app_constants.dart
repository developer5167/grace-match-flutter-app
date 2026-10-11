import 'package:flutter/foundation.dart';

class AppConstants {
  AppConstants._();
  /// API base URL. Override for local/dev:
  ///
  ///   flutter run --dart-define=API_BASE_URL=https://<tunnel>/api/v1
  ///
  /// Release builds default to production. assertReleaseConfig() still
  /// refuses a store build that was pointed at the old ngrok tunnel.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.gracematch.sotersystems.in/api/v1',
  );

  /// Socket origin, derived from baseUrl unless overridden explicitly.
  static const String socketUrl = String.fromEnvironment('SOCKET_URL');

  /// True when the app is still pointing at the development tunnel.
  static bool get isUsingDevTunnel => baseUrl.contains('ngrok');

  /// Fails fast in a release build that forgot --dart-define=API_BASE_URL.
  /// A store release pinned to a dev tunnel is unrecoverable without a new
  /// submission, so this is worth crashing over at startup.
  static void assertReleaseConfig() {
    if (kReleaseMode && isUsingDevTunnel) {
      throw StateError(
        'Release build is pointing at the development tunnel. '
        'Rebuild with --dart-define=API_BASE_URL=https://<your-api-host>/api/v1',
      );
    }
  }
  static const String appName = 'GraceMatch';
  static const String tagline = 'Where faith meets forever';

  /// Public website. iOS purchases open here instead of Razorpay (App Store
  /// rule). Override with --dart-define=SITE_URL=... if the domain changes.
  static const String siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://gracematch.sotersystems.in',
  );
}

class ApiEndpoints {
  ApiEndpoints._();
  // Auth
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String updateFcmToken = '/auth/fcm-token';

  // Onboarding
  static const String onboardingStatus = '/onboarding/status';
  static const String onboardingHobbies = '/onboarding/hobbies';
  static const String onboardingPhoto = '/onboarding/photo';
  static const String onboarding = '/onboarding';
  static String onboardingStep(int step) => '/onboarding/step/$step';

  // Profile
  static const String myProfile = '/profile/me';
  static String publicProfile(String id) => '/profile/$id';
  static String shareProfile(String id) => '/share/profile/$id';
  static const String updateFamily = '/profile/family';
  static const String updatePreferences = '/profile/preferences';
  static const String updateSettings = '/profile/settings';

  // Discover
  static const String discoverFeed = '/discover/feed';

  // Interests
  static const String sendInterest = '/interests';
  static const String interestsList = '/interests/list';
  static String acceptInterest(String id) => '/interests/$id/accept';
  static String rejectInterest(String id) => '/interests/$id/reject';

  // Chat
  static const String conversations = '/chat/conversations';
  static String messages(String convId) => '/chat/$convId/messages';
  static String markRead(String convId) => '/chat/$convId/read';
  static String userStatus(String userId) => '/chat/user-status/$userId';

  // Trust
  static String matchExplanation(String id) => '/trust/explanation/$id';
  static const String report = '/trust/report';
  static const String block = '/trust/block';
  static const String verifyIdentity = '/trust/verify-identity';

  // Subscriptions
  static const String plans = '/subscriptions/plans';
  static const String publicPlans = '/public/plans';
  static const String razorpayOrder = '/subscriptions/razorpay/order';

  // Notifications
  static const String notifications = '/notifications';
  static const String notificationsUnread = '/notifications/unread';
  static const String notificationsReadAll = '/notifications/read-all';
  static String notificationRead(String id) => '/notifications/$id/read';

  // Activity
  static const String activityBootstrap = '/activity/bootstrap'; // single call for entire tab
  static const String activitySummary = '/activity/summary';
  static const String activityViews = '/activity/views';
  static const String activityShortlists = '/activity/shortlists';
  static const String activityShortlistsCheck = '/activity/shortlists/check';

  // Premium / Contact reveal
  static const String spotlight = '/premium/spotlight';
  static const String entitlements = '/premium/entitlements';
  static const String contactRequest = '/premium/contact-request';
  static String contactStatus(String targetUserId) => '/premium/contact-status/$targetUserId';
  static const String contactRespond = '/premium/contact-request'; // /:id/respond appended in repo
  static String contactRespondAction(String id) => '/premium/contact-request/$id/respond';
  static String contactRevoke(String id) => '/premium/contact-request/$id/revoke';

  // ─── Trust ──────────────────────────────────────────────────
  static const String reportAndExit      = '/trust/report-and-exit';
  static const String digilockerStart    = '/trust/digilocker/start';
  static const String ageCheck           = '/onboarding/age-check';
  static const String digilockerStatus   = '/trust/digilocker/status';
  static const String screenshotAlert    = '/trust/screenshot';
  static const String verificationSelfie = '/trust/verification-selfie';

  // ─── Calls ──────────────────────────────────────────────────
  static const String iceServers  = '/calls/ice-servers';
  static const String callHistory = '/calls/history';

  // ─── Support ────────────────────────────────────────────────
  static const String supportTickets    = '/support';
  static const String supportCategories = '/support/categories';
  static const String supportUnread     = '/support/unread';
  static String supportTicket(String id)   => '/support/$id';
  static String supportMessages(String id) => '/support/$id/messages';

  // ─── Offers ─────────────────────────────────────────────────
  static const String offers         = '/offers';
  static const String offersValidate = '/offers/validate';
  static const String contactRequestsIncoming = '/premium/contact-requests/incoming';

  // Growth
  static const String successStories = '/growth/success-stories';
  static const String analytics = '/growth/analytics';

  // App-level bootstrap (single call on launch)
  static const String appBootstrap = '/bootstrap';
  static const String publicAppUpdate = '/public/app-update';

  // Review loop — items staff asked the member to fix
  static const String reviewActions = '/review/actions';
  static const String reviewSubmit = '/review/actions/submit';
  static const String reviewSubmitAll = '/review/actions/submit-all';

  // Discover
  static const String dailyMatches = '/discover/daily-matches';

  // Subscription payment
  static const String razorpayVerify = '/subscriptions/razorpay/verify';
}

class StorageKeys {
  StorageKeys._();
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userId = 'user_id';
  static const String onboardingComplete = 'onboarding_complete';
  static const String onboardingStep = 'onboarding_step';
  static const String skippedUpdateVersion = 'skipped_update_version';
  static const String pendingShareProfileId = 'pending_share_profile_id';
}

class AppDurations {
  AppDurations._();
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 550);
  static const Duration verySlow = Duration(milliseconds: 800);
  static const Duration pageTransition = Duration(milliseconds: 400);
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 100;
}
