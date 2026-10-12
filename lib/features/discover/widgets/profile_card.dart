import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';

class ProfileCard extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final double scale;

  const ProfileCard({
    super.key,
    required this.profile,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.scale = 1.0,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _dragController;
  late PageController _pageController;
  int _currentPhotoIndex = 0;
  Offset _dragOffset = Offset.zero;
  double _rotation = 0;
  bool _isDragging = false;
  Timer? _photoTimer;

  @override
  void initState() {
    super.initState();
    _dragController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pageController = PageController();
    _startPhotoTimer();
  }

  void _startPhotoTimer() {
    _photoTimer?.cancel();
    _photoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final photos = _extractPhotoUrls();
      if (photos == null || photos.length <= 1) return;
      // Only auto-advance when user is not dragging
      if (_isDragging) return;
      final nextIndex = (_currentPhotoIndex + 1) % photos.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPhotoIndex = nextIndex);
    });
  }

  @override
  void dispose() {
    _photoTimer?.cancel();
    _dragController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.profile['id'] ?? oldWidget.profile['user_id'];
    final newId = widget.profile['id'] ?? widget.profile['user_id'];
    if (oldId != newId) {
      _currentPhotoIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _startPhotoTimer();
    }
  }

  void _onPanStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
      _rotation = _dragOffset.dx / 350; // max ~25 degree rotation
    });
  }

  void _onPanEnd(DragEndDetails details) async {
    final threshold = MediaQuery.of(context).size.width * 0.35;

    if (_dragOffset.dx > threshold) {
      // Swipe right = Like
      await AppHaptics.heavy();
      widget.onSwipeRight?.call();
    } else if (_dragOffset.dx < -threshold) {
      // Swipe left = Pass
      await AppHaptics.light();
      widget.onSwipeLeft?.call();
    } else {
      // Snap back
      setState(() {
        _dragOffset = Offset.zero;
        _rotation = 0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final likeOpacity = (_dragOffset.dx / 120).clamp(0.0, 1.0);
    final passOpacity = (-_dragOffset.dx / 120).clamp(0.0, 1.0);

    return Transform.scale(
      scale: widget.scale,
      child: GestureDetector(
        onPanStart: widget.onSwipeLeft != null ? _onPanStart : null,
        onPanUpdate: widget.onSwipeLeft != null ? _onPanUpdate : null,
        onPanEnd: widget.onSwipeLeft != null ? _onPanEnd : null,
        onTap: () {
          final id = widget.profile['id'] ?? widget.profile['user_id'];
          if (id != null) {
            AppHaptics.light();
            context.push('/profile/$id');
          } else {
            debugPrint('Error: Profile ID is null for ${widget.profile['name']}');
          }
        },
        child: AnimatedContainer(
          duration: _isDragging
              ? Duration.zero
              : const Duration(milliseconds: 300),
          transform: Matrix4.translationValues(_dragOffset.dx, _dragOffset.dy * 0.3, 0)
            ..rotateZ(_rotation * 0.3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                // ── Background Photo ─────────────────────────
                _buildPhoto(),

                // ── Photo Navigation Taps ────────────────────
                // Only covers the upper 70% to allow tapping the bottom info area to open profile
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 120,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _prevPhoto,
                          behavior: HitTestBehavior.translucent,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _nextPhoto,
                          behavior: HitTestBehavior.translucent,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Photo Indicator ──────────────────────────
                _buildPhotoIndicator(),

                // ── Gradient Overlay ─────────────────────────
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.profileCardGradient,
                  ),
                ),

                // ── LIKE/PASS Overlay indicators ─────────────
                Positioned(
                  top: 40,
                  left: 24,
                  child: Opacity(
                    opacity: likeOpacity,
                    child: Transform.rotate(
                      angle: -0.3,
                      child: _stampBadge('INTEREST', AppColors.blessing),
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 24,
                  child: Opacity(
                    opacity: passOpacity,
                    child: Transform.rotate(
                      angle: 0.3,
                      child: _stampBadge('PASS', AppColors.error),
                    ),
                  ),
                ),

                // ── Profile Info ─────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Name + Age + Trust badge
                        Row(
                          children: [
                            Text(
                              '${widget.profile['name']}, ${widget.profile['age']}',
                              style: AppTextStyles.profileName,
                            ),
                            if (widget.profile['trust_badge'] == true) ...[
                              const SizedBox(width: 8),
                              _trustBadge(),
                            ],
                          ],
                        ),
                        if (widget.profile['is_photo_verified'] == true) ...[
                          const SizedBox(height: 4),
                          const PhotoVerifiedLabel(),
                        ],
                        const SizedBox(height: 6),

                        // Denomination + City
                        Row(
                          children: [
                            Icon(Icons.church_rounded,
                                size: 14, color: AppColors.gold),
                            const SizedBox(width: 4),
                            Text(
                              widget.profile['denomination'] ?? '',
                              style: AppTextStyles.profileMeta
                                  .copyWith(color: AppColors.gold),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.location_on_rounded,
                                size: 14,
                                color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              widget.profile['city'] ?? '',
                              style: AppTextStyles.profileMeta,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Profession
                        Row(
                          children: [
                            const Icon(Icons.work_rounded,
                                size: 14, color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              widget.profile['profession'] ?? '',
                              style: AppTextStyles.profileMeta,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Compatibility score
                        _compatibilityBar(
                            widget.profile['compatibility'] as int? ?? 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().scale(
        begin: const Offset(0.92, 0.92),
        end: const Offset(1.0, 1.0),
        duration: 400.ms,
        curve: Curves.easeOutCubic,
      ).fadeIn(duration: 300.ms),
    );
  }

  void _nextPhoto() {
    final photos = _extractPhotoUrls();
    if (photos == null || photos.length <= 1) return;

    if (_currentPhotoIndex < photos.length - 1) {
      final nextIndex = _currentPhotoIndex + 1;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPhotoIndex = nextIndex);
      AppHaptics.light();
    }
  }

  void _prevPhoto() {
    if (_currentPhotoIndex > 0) {
      final prevIndex = _currentPhotoIndex - 1;
      _pageController.animateToPage(
        prevIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPhotoIndex = prevIndex);
      AppHaptics.light();
    }
  }

  Widget _buildPhotoIndicator() {
    final photos = _extractPhotoUrls();
    if (photos == null || photos.length <= 1) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Row(
        children: List.generate(
          photos.length,
          (index) => Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: index == _currentPhotoIndex
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  if (index == _currentPhotoIndex)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    final photos = _extractPhotoUrls();

    if (photos == null || photos.isEmpty) {
      final locked = widget.profile['is_images_locked'] == true;
      return Container(
        color: AppColors.surfaceElevated,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked ? Icons.lock_rounded : Icons.person_rounded,
                color: AppColors.textTertiary,
                size: 80,
              ),
              if (locked) ...[
                const SizedBox(height: 12),
                Text(
                  'Photos hidden until you connect',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final url = photos[index];
        // Photos on this card were allowed through by the server. Blurring
        // them here because of a leftover `is_images_locked` flag hid every
        // profile until a match, which nobody had asked for.
        final img = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_, __) => Container(
            color: AppColors.surfaceElevated,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.gold),
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: AppColors.surfaceElevated,
            child: const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary),
          ),
          fadeInDuration: const Duration(milliseconds: 300),
        );
        return img;
      },
    );
  }

  List<String>? _extractPhotoUrls() {
    final photos = widget.profile['photos'] as List?;
    if (photos == null) return null;

    final urls = <String>[];
    for (final photo in photos) {
      if (photo is String) {
        if (photo.isNotEmpty) urls.add(photo);
        continue;
      }

      if (photo is Map) {
        final photoMap = photo.cast<dynamic, dynamic>();
        final url = photoMap['url']?.toString() ??
            photoMap['photo_url']?.toString() ??
            photoMap['image_url']?.toString() ??
            photoMap['secure_url']?.toString() ??
            photoMap['file_url']?.toString();
        if (url != null && url.isNotEmpty) urls.add(url);
      }
    }

    return urls;
  }

  Widget _trustBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.blessingSubtle,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.blessing),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded,
              color: AppColors.blessing, size: 12),
          const SizedBox(width: 3),
          Text('Verified',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.blessing)),
        ],
      ),
    );
  }

  Widget _stampBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.headlineSmall.copyWith(
            color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _compatibilityBar(int score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Match Score',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textTertiary)),
            const Spacer(),
            Text('$score%',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.gold, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: AppColors.surfaceHighest,
            valueColor: AlwaysStoppedAnimation(AppColors.gold),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

/// "Photo verified" — staff accepted a selfie as the face in the photos.
/// Deliberately quieter than the ✅ Verified tick, which means identity.
class PhotoVerifiedLabel extends StatelessWidget {
  const PhotoVerifiedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.face_retouching_natural_rounded, color: AppColors.blessing, size: 13),
        const SizedBox(width: 4),
        Text('Photo verified',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.blessing)),
      ],
    );
  }
}
