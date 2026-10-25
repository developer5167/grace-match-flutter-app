import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/notifications/push_center.dart';
import 'package:dio/dio.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/membership_palette.dart';
import '../../core/storage/app_storage.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/rings_mark.dart';
import 'maintenance_screen.dart';
import 'update_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _navigate();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    // Permission and the cold-start notification are handled after the first
    // frame. Waiting here keeps that tap from losing the race with Discover.
    final maintenanceCheck = MaintenanceGate.blocked();
    await PushCenter.launchReady;
    final startTime = DateTime.now();
    
    final token = await AppStorage.getAccessToken();
    
    if (token != null) {
      try {
        // Single bootstrap call — replaces the old GET /profile/me and also
        // returns badge counts + subscription status for the app session.
        final resp = await DioClient.instance.get(ApiEndpoints.appBootstrap);
        final data = resp.data['data'];
        if (data is Map) {
          MembershipTheme.instance.applyFrom(data['subscription']);
          final user = data['user'];
          if (user is Map) {
            AppStorage.saveOnboardingComplete(
                user['is_onboarding_complete'] ?? false);
            AppStorage.saveReviewStatus(user['review_status']?.toString());
          }
        }
      } on DioException catch (e) {
        debugPrint('Splash bootstrap error: ${e.message}');
      } catch (e) {
        debugPrint('Splash error: $e');
      }
    }

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    // A notification tap should not sit on the splash screen. Everything
    // else keeps the brand pause.
    final remaining = PushCenter.hasPending ? 0 : 2800 - elapsed;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }
    
    if (!mounted) return;

    final blocked = await maintenanceCheck;
    if (!mounted) return;
    if (blocked) {
      PushCenter.finishStartupDiscarding();
      context.go('/maintenance');
      return;
    }

    // Admin-controlled update gate. Fail-open: if the check cannot run,
    // members still get into the app.
    try {
      await UpdateGate.maybePrompt(context);
    } catch (e) {
      debugPrint('Update gate error: $e');
    }

    if (!mounted) return;

    if (token == null) {
      PushCenter.finishStartupDiscarding();
      final pending = AppStorage.getPendingShareProfile();
      context.go(pending != null ? '/p/$pending' : '/auth/phone');
      return;
    }

    if (!AppStorage.isOnboardingComplete()) {
      PushCenter.finishStartupDiscarding();
      context.go('/onboarding');
      return;
    }

    final share = AppStorage.takeShareResumeRoute();
    if (share != null) {
      PushCenter.finishStartupDiscarding();
      context.go(share);
      return;
    }
    // Opened by tapping a notification: go to what it was about.
    if (PushCenter.finishStartup()) return;
    context.go('/discover');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: Stack(
          children: [
            // ── Background radial glow ─────────────────────────
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.7,
                      colors: [
                        AppColors.gold
                            .withAlpha((_glowAnimation.value * 30).toInt()),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Cross decorative element (top-left) ────────────
            Positioned(
              top: -60,
              left: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withAlpha(30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ───────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand mark: the same two rings as the app icon and the
                  // web logo, converging the way they do on the site. It runs
                  // its own entrance, so no scale/elastic here — the two would
                  // fight each other.
                  const AnimatedRingsMark(size: 150)
                      .animate()
                      .fadeIn(duration: 500.ms),

                  const SizedBox(height: 28),

                  // Brand name
                  Text(
                    'GraceMatch',
                    style: AppTextStyles.displayMedium.copyWith(
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [
                            AppColors.gold,
                            AppColors.goldLight,
                            AppColors.gold,
                          ],
                        ).createShader(
                            const Rect.fromLTWH(0, 0, 250, 50)),
                    ),
                  )
                      .animate(delay: 400.ms)
                      .slideY(
                        begin: 0.3,
                        end: 0,
                        duration: 600.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 8),

                  // Tagline
                  Text(
                    'Where faith meets forever',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  )
                      .animate(delay: 700.ms)
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),
                ],
              ),
            ),

            // ── Bottom loading indicator ───────────────────────
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      backgroundColor: AppColors.surfaceHighest,
                      valueColor: AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                ),
              ),
            )
                .animate(delay: 1000.ms)
                .fadeIn(duration: 400.ms),
          ],
        ),
      ),
    );
  }

}
