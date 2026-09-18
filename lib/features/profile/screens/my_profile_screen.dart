import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/storage/app_storage.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import 'package:go_router/go_router.dart';
import '../bloc/profile_state.dart';
import 'identity_verification_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Future<void> _refreshProfile() async {
    context.read<ProfileBloc>().add(const FetchProfileEvent(silentRefresh: true));
    // Give the bloc/network a brief window; UI state updates through BlocBuilder.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(FetchProfileEvent());
  }

  Future<void> _shareProfile(String name) async {
    final userId = await AppStorage.getUserId();
    if (userId == null) return;
    final url = 'https://gracematch.app/p/$userId';
    await Share.share(
      'Hey! Check out $name\'s profile on GraceMatch — the Telugu Christian Matrimony app 🙏✝\n$url',
      subject: 'GraceMatch – $name',
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          );
        }

        if (state is ProfileError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: Text(state.message, style: const TextStyle(color: Colors.white))),
          );
        }

        final data = state is ProfileLoaded ? state.profile : <String, dynamic>{};
        final profile = data['profile'] as Map<String, dynamic>? ?? {};
        
        final name = profile['first_name'] ?? profile['full_name'] ?? 'User';
        final dob = profile['date_of_birth'] != null ? DateTime.parse(profile['date_of_birth'].toString()) : null;
        final age = dob != null ? (DateTime.now().year - dob.year) : 26;
        final denomination = profile['denomination'] ?? 'CSI';
        final profession = profile['profession'] ?? 'Software Engineer';
        final photos = data['photos'] as List? ?? [];
        String? photoUrl;
        if (photos.isNotEmpty) {
          final firstPhoto = photos[0];
          if (firstPhoto is Map) {
            photoUrl = firstPhoto['photo_url'] as String?;
          } else if (firstPhoto is String) {
            photoUrl = firstPhoto;
          }
        }

        final hasRejected = photos.any((p) => p is Map && p['review_status'] == 'rejected');
        final hasPending = photos.any((p) => p is Map && p['review_status'] == 'pending');
        // These live under `verification`, not on the profile row. Reading them
        // off `profile` meant the panel was always "nothing submitted", even
        // immediately after a successful upload.
        final verification = data['verification'] as Map<String, dynamic>? ?? const {};
        final isVerified = verification['is_id_verified'] == true;
        final hasVideo = verification['has_selfie_video'] == true;
        final completionScore = (profile['profile_completion_score'] as num?)?.toInt() ?? 0;
        final subscription = data['subscription'] as Map<String, dynamic>? ?? const {};
        final isPremium = subscription['is_premium'] == true;
        final planName = subscription['plan_name']?.toString();

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.gold,
              backgroundColor: AppColors.surfaceElevated,
              onRefresh: _refreshProfile,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                SliverAppBar(
                  backgroundColor: AppColors.background,
                  pinned: true,
                  centerTitle: false,
                  title: Text('My Profile', style: AppTextStyles.headlineLarge),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded, color: AppColors.gold),
                      tooltip: 'Share Profile',
                      onPressed: () => _shareProfile(name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: AppColors.gold),
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Center(
                          child: SizedBox(
                            width: 136,
                            height: 136,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Completion ring
                                SizedBox.expand(
                                  child: CustomPaint(
                                    painter: _ScoreRingPainter(
                                      score: completionScore,
                                      trackColor: AppColors.surfaceHighest,
                                      fillColor: completionScore >= 80
                                          ? const Color(0xFF4CAF50)
                                          : completionScore >= 50
                                              ? AppColors.gold
                                              : const Color(0xFFEF5350),
                                    ),
                                  ),
                                ),
                                // Avatar inside ring
                                Container(
                                  width: 116,
                                  height: 116,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.surfaceElevated,
                                    image: photoUrl != null
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(photoUrl),
                                            fit: BoxFit.cover)
                                        : null,
                                  ),
                                  child: photoUrl == null
                                      ? const Icon(Icons.person, size: 56, color: AppColors.textTertiary)
                                      : null,
                                ),
                                // Score badge bottom-right
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.goldMild),
                                    ),
                                    child: Text(
                                      '$completionScore%',
                                      style: AppTextStyles.overline.copyWith(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$name, $age', style: AppTextStyles.headlineMedium),
                            if (isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, color: Colors.blue, size: 20),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$denomination • $profession', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                        
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Flexible(
                              child: OutlinedButton.icon(
                                onPressed: () => context.push('/profile/preview'),
                                icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                                label: const Text('Preview'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.gold,
                                  side: const BorderSide(color: AppColors.goldMild),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  minimumSize: const Size(0, 44),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: OutlinedButton.icon(
                                onPressed: () => _shareProfile(name),
                                icon: const Icon(Icons.ios_share_rounded, size: 18),
                                label: const Text('Share'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.gold,
                                  side: const BorderSide(color: AppColors.goldMild),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  minimumSize: const Size(0, 44),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Profile completion nudge card
                        if (completionScore < 100) ...[
                          const SizedBox(height: 16),
                          _ProfileCompletionCard(
                            score: completionScore,
                            profile: profile,
                            hasPhotos: photos.isNotEmpty,
                            hasVideo: hasVideo,
                            isVerified: isVerified,
                            onTap: (extra) {
                              // Verify identity chip should open govt ID upload screen directly.
                              if (extra == -1) {
                                // rootNavigator: true, otherwise this pushes
                                // onto the shell's inner Navigator and renders
                                // underneath the bottom tab bar.
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => const IdentityVerificationScreen(),
                                  ),
                                );
                                return;
                              }
                              context.push('/onboarding', extra: extra);
                            },
                          ),
                        ],

                        if (hasVideo) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.goldSubtle,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: AppColors.goldMild),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam_rounded, color: AppColors.gold, size: 14),
                                const SizedBox(width: 4),
                                Text('Video Identity Available', style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold)),
                              ],
                            ),
                          ),
                        ],

                        // My Photos section — always shown when photos exist
                        if (photos.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _buildMyPhotosSection(photos, hasRejected: hasRejected, hasPending: hasPending),
                        ],

                        const SizedBox(height: 32),
                        
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.push('/subscription'),
                            borderRadius: BorderRadius.circular(20),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: AppColors.goldenGradient,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(color: AppColors.gold.withAlpha(40), blurRadius: 16, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    const Icon(Icons.workspace_premium_rounded, size: 40, color: AppColors.textOnGold),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isPremium
                                                ? 'GraceMatch ${planName != null ? '${planName[0].toUpperCase()}${planName.substring(1)}' : 'Premium'}'
                                                : 'GraceMatch Free',
                                            style: AppTextStyles.labelLarge.copyWith(color: AppColors.textOnGold),
                                          ),
                                          Text(
                                            isPremium
                                                ? 'Subscription active'
                                                : 'Upgrade for 5x more matches',
                                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.surface),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textOnGold),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        _buildSettingsTile(
                          Icons.person_rounded, 
                          'Basic Information', 
                          'Name, age, and location',
                          onTap: () => context.push('/onboarding', extra: 0),
                        ),
                        _buildSettingsTile(
                          Icons.photo_library_rounded, 
                          'My Photos', 
                          'Manage your gallery',
                          onTap: () => context.push('/onboarding', extra: 7),
                        ),
                        _buildSettingsTile(
                          Icons.text_snippet_rounded, 
                          'Bio & Details', 
                          'Edit your personal intro',
                          onTap: () => context.push('/onboarding', extra: 2),
                        ),
                        _buildSettingsTile(
                          Icons.church_rounded, 
                          'Faith Details', 
                          'Denomination & Church',
                          onTap: () => context.push('/onboarding', extra: 1),
                        ),
                        _buildSettingsTile(
                          Icons.volunteer_activism_rounded, 
                          'Lifestyle & Hobbies', 
                          'Smoking, drinking, hobbies',
                          onTap: () => context.push('/onboarding', extra: 3), // Lifestyle is index 3
                        ),
                        _buildSettingsTile(
                          Icons.favorite_rounded, 
                          'My Hobbies', 
                          'Select what you love',
                          onTap: () => context.push('/onboarding', extra: 6), // Hobbies is index 6
                        ),
                        _buildSettingsTile(
                          Icons.family_restroom_rounded, 
                          'Family Background', 
                          'Update parent occupation',
                          onTap: () => context.push('/onboarding', extra: 4),
                        ),
                        _buildSettingsTile(
                          Icons.tune_rounded, 
                          'Partner Preferences', 
                          'Who are you looking for?',
                          onTap: () => context.push('/onboarding', extra: 5),
                        ),
                        _buildSettingsTile(
                          Icons.verified_user_rounded, 
                          'Identity Verification', 
                          isVerified ? 'Verified Account' : 'Trust badge status',
                          onTap: () => Navigator.of(context, rootNavigator: true)
                              .push(MaterialPageRoute(builder: (_) => const IdentityVerificationScreen())),
                        ),
                        _buildSettingsTile(
                          Icons.ios_share_rounded,
                          'Share My Profile',
                          'Invite someone via link',
                          onTap: () => _shareProfile(name),
                        ),
                        
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyPhotosSection(List photos, {required bool hasRejected, required bool hasPending}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasRejected
              ? Colors.red.withAlpha(100)
              : hasPending
                  ? Colors.amber.withAlpha(80)
                  : AppColors.surfaceHighest,
          width: (hasRejected || hasPending) ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.photo_library_rounded, color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('My Photos', style: AppTextStyles.labelLarge)),
                GestureDetector(
                  onTap: () => context.push('/onboarding', extra: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.goldMild),
                    ),
                    child: Text('Manage', style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold)),
                  ),
                ),
              ],
            ),
          ),

          // Rejection alert banner
          if (hasRejected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withAlpha(70)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Some photos were rejected. Tap Manage to upload replacements.',
                        style: AppTextStyles.labelSmall.copyWith(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (hasPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withAlpha(70)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Some photos are awaiting admin review before becoming visible.',
                        style: AppTextStyles.labelSmall.copyWith(color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 14),

          // Photo grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (_, i) {
                final p = photos[i];
                if (p is! Map) return const SizedBox.shrink();
                final url = p['photo_url'] as String? ?? '';
                final status = p['review_status'] as String? ?? 'approved';
                final reason = p['rejection_reason'] as String?;
                final isPrimary = p['is_primary'] == true;
                return _buildPhotoCard(url, status: status, reason: reason, isPrimary: isPrimary);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(String url, {required String status, String? reason, bool isPrimary = false}) {
    Color borderColor;
    Color badgeBg;
    Widget badgeIcon;

    switch (status) {
      case 'approved':
        borderColor = Colors.green.withAlpha(120);
        badgeBg = Colors.green;
        badgeIcon = const Icon(Icons.check_rounded, color: Colors.white, size: 10);
        break;
      case 'rejected':
        borderColor = Colors.red.withAlpha(180);
        badgeBg = Colors.red;
        badgeIcon = const Icon(Icons.close_rounded, color: Colors.white, size: 10);
        break;
      default: // pending
        borderColor = Colors.amber.withAlpha(180);
        badgeBg = Colors.amber;
        badgeIcon = const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 10);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            color: AppColors.surface,
            image: url.isNotEmpty
                ? DecorationImage(image: CachedNetworkImageProvider(url), fit: BoxFit.cover)
                : null,
          ),
          child: url.isEmpty
              ? const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary, size: 28)
              : null,
        ),

        // Status badge top-right
        Positioned(
          top: 5,
          right: 5,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
            child: badgeIcon,
          ),
        ),

        // Primary badge bottom
        if (isPrimary)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(140),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Text('Primary', textAlign: TextAlign.center,
                  style: AppTextStyles.overline.copyWith(color: AppColors.gold)),
            ),
          ),

        // Rejected reason overlay on tap
        if (status == 'rejected' && reason != null && reason.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Text(
                reason,
                style: AppTextStyles.overline.copyWith(color: Colors.red.shade300),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceHighest),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.goldSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.gold, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.labelSmall),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textTertiary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Score Ring Painter ───────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final int score;
  final Color trackColor;
  final Color fillColor;

  const _ScoreRingPainter({
    required this.score,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 5.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -pi / 2;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Arc
    if (score > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        2 * pi * (score / 100),
        false,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.score != score || old.fillColor != fillColor;
}

// ─── Profile Completion Nudge Card ───────────────────────────
class _ProfileCompletionCard extends StatelessWidget {
  final int score;
  final Map<String, dynamic> profile;
  final bool hasPhotos;
  final bool hasVideo;
  final bool isVerified;
  final void Function(int step) onTap;

  const _ProfileCompletionCard({
    required this.score,
    required this.profile,
    required this.hasPhotos,
    required this.hasVideo,
    required this.isVerified,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final missing = <_MissingItem>[];
    if (!hasPhotos)                      missing.add(_MissingItem('Add a photo', 7));
    if (profile['denomination'] == null) missing.add(_MissingItem('Add denomination', 1));
    if (profile['profession'] == null)   missing.add(_MissingItem('Add profession', 2));
    if (profile['bio'] == null || (profile['bio'] as String?)?.isEmpty == true)
                                         missing.add(_MissingItem('Write a bio', 2));
    if (profile['church_name'] == null)  missing.add(_MissingItem('Add church name', 1));
    // Use -1 as special action: open govt ID proof upload screen directly.
    if (!isVerified)                     missing.add(_MissingItem('Verify identity', -1));

    if (missing.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldMild.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text('Profile $score% Complete', style: AppTextStyles.labelLarge),
              const Spacer(),
              Text('${missing.length} left', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppColors.surfaceHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                score >= 80 ? const Color(0xFF4CAF50) : AppColors.gold,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: missing.take(3).map((item) => GestureDetector(
              onTap: () => onTap(item.step),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.goldSubtle,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.goldMild),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: AppColors.gold, size: 14),
                    const SizedBox(width: 4),
                    Text(item.label, style: AppTextStyles.overline.copyWith(color: AppColors.gold)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

class _MissingItem {
  final String label;
  final int step;
  const _MissingItem(this.label, this.step);
}

