import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/net_image.dart';
import 'profile_card.dart';

/// What the member has done with a profile in the Discover list.
enum ListAction { none, sending, sent }

const denominationLabels = {
  'protestant': 'Protestant',
  'catholic': 'Catholic',
  'orthodox': 'Orthodox',
  'csi': 'CSI',
  'pentecostal': 'Pentecostal',
  'born_again': 'Born Again',
  'other': 'Christian',
};

/// One profile in the Discover list, laid out like a marriage biodata:
/// photo, then faith, education, career and family details, then actions.
/// Every profile in the feed has been approved by staff (the server only
/// returns `review_status = 'approved'`), so the "Reviewed" label is always
/// true here.
class ProfileListCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final ListAction action;
  final VoidCallback onOpen;
  final VoidCallback onInterest;
  final VoidCallback onPriorityInterest;
  final VoidCallback onNotNow;

  const ProfileListCard({
    super.key,
    required this.profile,
    required this.action,
    required this.onOpen,
    required this.onInterest,
    required this.onPriorityInterest,
    required this.onNotNow,
  });

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String? height(Object? cm) {
    final n = cm is num ? cm.toInt() : int.tryParse(cm?.toString() ?? '');
    if (n == null || n < 100 || n > 250) return null;
    final inches = (n / 2.54).round();
    return "${inches ~/ 12}' ${inches % 12}\"";
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = _text(p['name']) ?? _text(p['first_name']) ?? 'Member';
    final age = p['age'];
    final ht = height(p['height_cm']);
    final denom = denominationLabels[p['denomination']?.toString()];
    final city = _text(p['city']) ?? _text(p['location_city']);
    final education = _text(p['education']);
    final profession = _text(p['profession']);
    final church = _text(p['church_name']);
    final byParents = p['profile_managed_by']?.toString() == 'parents';
    final compat = p['compatibility'] is num
        ? (p['compatibility'] as num).round()
        : null;

    final heading = [
      age == null ? name : '$name, $age',
      if (ht != null) ht,
    ].join('  ·  ');
    final faithPlace = [
      if (denom != null) denom,
      if (city != null) city,
    ].join('  ·  ');

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 4 / 3, child: _photo(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: AppTextStyles.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (faithPlace.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      faithPlace,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (education != null)
                    _detail(Icons.school_rounded, education),
                  if (profession != null)
                    _detail(Icons.work_rounded, profession),
                  if (church != null) _detail(Icons.church_rounded, church),
                  if (byParents)
                    _detail(
                      Icons.family_restroom_rounded,
                      'Profile managed by parents',
                    ),
                  if (compat != null && compat > 0)
                    _detail(
                      Icons.handshake_rounded,
                      '$compat% compatible with your preferences',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _actions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final urls = ProfileCard.photoUrls(profile) ?? const [];
    final locked = profile['is_images_locked'] == true;
    final Widget image = urls.isEmpty
        ? Container(
            color: AppColors.surfaceHighest,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  locked ? Icons.lock_rounded : Icons.person_rounded,
                  color: AppColors.textTertiary,
                  size: 56,
                ),
                if (locked) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Photos shown after you connect',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          )
        : CachedNetworkImage(
            imageUrl: urls.first,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4), // faces sit high in portraits
            memCacheWidth: decodePx(context, MediaQuery.sizeOf(context).width),
            placeholder: (_, __) => Container(color: AppColors.surfaceHighest),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.surfaceHighest,
              child: const Icon(
                Icons.person_rounded,
                color: AppColors.textTertiary,
                size: 56,
              ),
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(left: 12, top: 12, child: _reviewedBadge()),
        if (profile['trust_badge'] == true)
          Positioned(right: 12, top: 12, child: _idVerifiedBadge()),
      ],
    );
  }

  Widget _reviewedBadge() => _pill(
    Icons.fact_check_rounded,
    'Reviewed by our team',
    AppColors.blessing,
  );

  Widget _idVerifiedBadge() =>
      _pill(Icons.verified_rounded, 'ID verified', AppColors.blessing);

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    if (action == ListAction.sent) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.blessingSubtle,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.blessing,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'Interest sent',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.blessing,
              ),
            ),
          ],
        ),
      );
    }
    final busy = action == ListAction.sending;
    return Row(
      children: [
        TextButton(
          onPressed: busy ? null : onNotNow,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            textStyle: AppTextStyles.labelLarge,
          ),
          child: const Text('Not now'),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Send priority interest',
          onPressed: busy ? null : onPriorityInterest,
          icon: const Icon(Icons.star_rounded, color: AppColors.cross),
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          onPressed: busy ? null : onInterest,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textOnGold,
                  ),
                )
              : const Icon(Icons.mail_rounded, size: 18),
          label: const Text('Send interest'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.textOnGold,
            disabledBackgroundColor: AppColors.goldMild,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: AppTextStyles.labelLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
