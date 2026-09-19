import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/offers_repository.dart';

/// Offers.
///
/// Two kinds of offer share this list: public ones and ones created for this
/// member. The personal ones sort first and are visually distinct, because an
/// offer addressed to you is a different thing from a banner, and burying it
/// among public promotions wastes the gesture.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final _repo = OffersRepository();
  late Future<List<Offer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchOffers();
  }

  Future<void> _refresh() async {
    final next = _repo.fetchOffers();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Offers', style: AppTextStyles.headlineSmall),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Offer>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
            );
          }
          if (snap.hasError) {
            return _message(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load offers',
              subtitle: 'Check your connection and pull down to try again.',
              onRetry: _refresh,
            );
          }

          final offers = snap.data ?? const <Offer>[];
          if (offers.isEmpty) {
            return RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  _message(
                    icon: Icons.local_offer_outlined,
                    title: 'No offers right now',
                    subtitle: "When there's an offer for you, it will appear here "
                        'and you will get a notification.',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.gold,
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: offers.length,
              itemBuilder: (context, i) => _OfferCard(offer: offers[i])
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: i * 70))
                  .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
            ),
          );
        },
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
    Future<void> Function()? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onRetry,
                child: Text('Try again',
                    style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    final spent = offer.alreadyUsed;
    final accent = offer.isPersonal ? AppColors.rose : AppColors.gold;

    return Opacity(
      opacity: spent ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: spent ? AppColors.surfaceHighest : accent.withAlpha(90),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Headline row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (offer.isPersonal)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.roseSubtle,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'JUST FOR YOU',
                              style: AppTextStyles.overline.copyWith(
                                color: AppColors.rose,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        Text(offer.headline,
                            style: AppTextStyles.headlineSmall.copyWith(color: accent)),
                        const SizedBox(height: 4),
                        Text(offer.title, style: AppTextStyles.labelLarge),
                        if (offer.description != null && offer.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            offer.description!,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (spent)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.textTertiary, size: 20),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Code, and what it is worth
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: spent
                          ? null
                          : () {
                              AppHaptics.light();
                              Clipboard.setData(ClipboardData(text: offer.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Code ${offer.code} copied'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppColors.surfaceHighest,
                                ),
                              );
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surfaceHighest),
                        ),
                        child: Row(
                          children: [
                            Text(
                              offer.code,
                              style: AppTextStyles.labelLarge.copyWith(
                                letterSpacing: 1.6,
                                color: spent ? AppColors.textTertiary : AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (!spent)
                              const Icon(Icons.copy_rounded,
                                  size: 14, color: AppColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Footer: what it applies to, when it ends, and the way in
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.surfaceHighest)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.planName == null
                              ? 'Any plan'
                              : 'On ${offer.planName}',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          spent ? 'Already used' : offer.expiryLabel,
                          style: AppTextStyles.overline.copyWith(
                            color: spent
                                ? AppColors.textTertiary
                                : offer.isEndingSoon
                                    ? AppColors.roseDark
                                    : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!spent)
                    TextButton(
                      onPressed: () {
                        AppHaptics.selection();
                        // The code travels with the tap, so the member never
                        // has to retype what they were just shown.
                        context.push('/subscription?coupon=${offer.code}');
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: accent.withAlpha(30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        offer.inProgress ? 'Continue' : 'Use offer',
                        style: AppTextStyles.labelMedium.copyWith(color: accent),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
