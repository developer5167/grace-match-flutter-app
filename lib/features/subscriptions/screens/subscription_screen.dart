import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/membership_palette.dart';
import '../bloc/subscription_bloc.dart';
import '../../profile/bloc/profile_bloc.dart';
import '../../profile/bloc/profile_event.dart';
import '../../offers/data/offers_repository.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/app_haptics.dart';

class SubscriptionScreen extends StatefulWidget {
  /// Prefilled when the member arrived by tapping an offer, so they never have
  /// to retype a code the app just showed them.
  final String? initialCoupon;

  const SubscriptionScreen({super.key, this.initialCoupon});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  /// Kept across [PaymentPending] / [PaymentProcessed] / [SubscriptionError]
  /// so the plan list does not disappear when checkout opens or fails.
  List<Map<String, dynamic>> _cachedPlans = [];

  // ── Coupon state.
  //
  // Held per plan, because the same code can be valid on one plan and not
  // another, and a preview shown against the wrong plan is a quoted price the
  // member will not be charged.
  late final TextEditingController _couponCtl =
      TextEditingController(text: widget.initialCoupon ?? '');
  final _offers = OffersRepository();
  final Map<String, CouponPreview> _applied = {};
  String? _couponError;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    context.read<SubscriptionBloc>().add(FetchPlansEvent());
  }

  @override
  void dispose() {
    _couponCtl.dispose();
    super.dispose();
  }

  bool get _payOnWebsite => !kIsWeb && Platform.isIOS;

  Future<void> _openWebsite() async {
    final uri = Uri.parse(AppConstants.siteUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the website. Try again from Safari.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _applyCoupon(String planId) async {
    final code = _couponCtl.text.trim();
    if (code.isEmpty) return;

    setState(() { _checking = true; _couponError = null; });
    try {
      final preview = await _offers.validate(code: code, planId: planId);
      if (!mounted) return;
      setState(() {
        _applied[planId] = preview;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applied.remove(planId);
        _couponError = e.toString().replaceFirst('Exception: ', '');
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SubscriptionBloc, SubscriptionState>(
      listener: (context, state) {
        if (state is PlansLoaded) {
          setState(() => _cachedPlans = List<Map<String, dynamic>>.from(state.plans));
        }
        if (state is PaymentProcessed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message ?? (state.success ? 'Success' : 'Failed')),
              backgroundColor: state.success ? Colors.green : Colors.red,
            ),
          );
          if (state.success) {
            // Refresh premium plans immediately (disables current active plan).
            context.read<SubscriptionBloc>().add(FetchPlansEvent());
            // Refresh My Profile so premium badge/plan updates immediately.
            context.read<ProfileBloc>().add(const FetchProfileEvent(silentRefresh: true));
            // Auto close premium screen after a successful purchase so user
            // instantly sees updated profile state without manual restart.
            Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted) Navigator.of(context).maybePop();
            });
          }
        } else if (state is SubscriptionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (state is SubscriptionLoading && _cachedPlans.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text('Premium Plans', style: AppTextStyles.headlineMedium),
              elevation: 0,
              backgroundColor: AppColors.background,
            ),
            body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          );
        }

        if (state is SubscriptionError && _cachedPlans.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text('Premium Plans', style: AppTextStyles.headlineMedium),
              elevation: 0,
              backgroundColor: AppColors.background,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(state.message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
          );
        }

        final plans = _cachedPlans;
        final isProcessing = state is PaymentPending;

        if (plans.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text('Premium Plans', style: AppTextStyles.headlineMedium),
              elevation: 0,
              backgroundColor: AppColors.background,
            ),
            body: const Center(child: Text('No active plans found.', style: TextStyle(color: Colors.white))),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Premium Plans', style: AppTextStyles.headlineMedium),
            elevation: 0,
            backgroundColor: AppColors.background,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Unlock Your God-Given Match Faster',
                  style: AppTextStyles.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Get direct contacts, unlimited matches, and priority spotlight.',
                  style: AppTextStyles.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Asked for here because this is where a payment problem
                // happens. Making somebody hunt through Settings while they
                // are already annoyed is how a fixable problem becomes a
                // refund request.
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      AppHaptics.selection();
                      context.push('/support/new?category=payment');
                    },
                    icon: const Icon(Icons.support_agent_rounded,
                        size: 16, color: AppColors.textSecondary),
                    label: Text('Problem with a payment?',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(height: 24),
                ...plans.map((plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildPlanCard(
                        plan: plan,
                        context: context,
                        isProcessing: isProcessing,
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The coupon box, and what it did to this plan's price.
  Widget _couponRow(Map<String, dynamic> plan) {
    final planId = plan['id'].toString();
    final applied = _applied[planId];

    if (applied != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.goldSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.goldMild),
        ),
        child: Row(
          children: [
            Icon(Icons.local_offer_rounded, size: 15, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${applied.code} applied',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${applied.discountInr} off — you pay ₹${applied.finalInr}',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _applied.remove(planId);
                _couponError = null;
              }),
              child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _couponCtl,
                textCapitalization: TextCapitalization.characters,
                style: AppTextStyles.labelMedium.copyWith(letterSpacing: 1.2),
                decoration: InputDecoration(
                  hintText: 'Have an offer code?',
                  hintStyle:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.surfaceHighest),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.surfaceHighest),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldMild),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _checking ? null : () => _applyCoupon(planId),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.surfaceHighest,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _checking
                  ? SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          color: AppColors.gold, strokeWidth: 2),
                    )
                  : Text('Apply',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
            ),
          ],
        ),
        if (_couponError != null) ...[
          const SizedBox(height: 8),
          Text(
            _couponError!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.roseDark),
          ),
        ],
      ],
    );
  }

  /// Same entitlement rows the website shows, in catalog order.
  List<Map<String, dynamic>> _entitlements(Map<String, dynamic> plan) {
    final ents = plan['entitlements'];
    if (ents is List && ents.isNotEmpty) {
      return ents.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) return e;
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{};
      }).toList();
    }

    // Older API: rebuild the list from the features blob so the card is never
    // blank just because entitlements were missing.
    final raw = plan['features'];
    if (raw is! Map) return [];
    final map = Map<String, dynamic>.from(raw);
    const catalog = <List<String>>[
      ['daily_matches', '20 curated matches / day'],
      ['see_who_viewed', 'See who viewed your profile'],
      ['voice_calls', 'Voice calls with matches'],
      ['video_calls', 'Video calls with matches'],
      ['priority_discover', 'Priority in discovery'],
      ['dedicated_support', 'Dedicated support'],
    ];
    final rows = <Map<String, dynamic>>[];
    for (final row in catalog) {
      final on = map[row[0]] == true;
      rows.add({'key': row[0], 'label': row[1], 'compare': row[1], 'included': on});
    }

    String intLabel(dynamic v, String one, String many, String unlimited) {
      if (v == -1 || v == true) return unlimited;
      final n = int.tryParse(v?.toString() ?? '') ?? 0;
      if (n <= 0) return many;
      return '$n ${n == 1 ? one : many}';
    }

    bool intOn(dynamic v) {
      if (v == -1 || v == true) return true;
      final n = int.tryParse(v?.toString() ?? '') ?? 0;
      return n > 0;
    }

    rows.add({
      'key': 'contact_reveals_per_month',
      'label': intLabel(map['contact_reveals_per_month'], 'contact reveal / month', 'contact reveals / month', 'Unlimited contact reveals'),
      'compare': 'Contact reveals per month',
      'included': intOn(map['contact_reveals_per_month']),
    });
    rows.add({
      'key': 'spotlight_boosts',
      'label': intLabel(map['spotlight_boosts'], 'spotlight boost', 'spotlight boosts', 'Unlimited spotlight boosts'),
      'compare': 'Spotlight boosts',
      'included': intOn(map['spotlight_boosts']),
    });
    rows.add({
      'key': 'super_interests',
      'label': intLabel(map['super_interests'], 'super interest', 'super interests', 'Unlimited super interests'),
      'compare': 'Super interests',
      'included': intOn(map['super_interests']),
    });
    return rows;
  }

  String _rupees(dynamic value) {
    final n = num.tryParse(value?.toString() ?? '') ?? 0;
    return '₹${n.toStringAsFixed(0)}';
  }

  String _termLabel(dynamic months) {
    final n = int.tryParse(months?.toString() ?? '') ?? 0;
    if (n == 1) return '1 Month';
    return '$n Months';
  }

  String? _formatExpiry(dynamic value) {
    if (value == null) return null;
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return null;
    }
  }

  Widget _buildPlanCard({
    required Map<String, dynamic> plan,
    required BuildContext context,
    required bool isProcessing,
  }) {
    final palette = MembershipPalette.of(plan['name']?.toString());
    final bool isPopular = plan['featured'] == true ||
        plan['name']?.toString().toLowerCase() == 'gold';
    final List<Map<String, dynamic>> entitlements = _entitlements(plan);
    final bool isCurrentActive = plan['is_current_active'] == true;
    final bool isFree = plan['is_free'] == true ||
        (num.tryParse(plan['price_inr']?.toString() ?? '') ?? 0) <= 0;
    final bool canPurchase = !isFree && plan['can_purchase'] != false;
    final bool buttonDisabled = isProcessing || !canPurchase;
    final currentSub = plan['current_subscription'];
    final expiryText = currentSub is Map ? _formatExpiry(currentSub['expires_at']) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCurrentActive || isPopular ? palette.metal : palette.mild,
          width: isCurrentActive || isPopular ? 2 : 1,
        ),
        gradient: LinearGradient(
          colors: [AppColors.surfaceElevated, palette.metal.withAlpha(22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: palette.gradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
            ),
            child: Text(
              isPopular ? 'MOST POPULAR · ${palette.label.toUpperCase()}' : palette.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.onMetal,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan['display_name']?.toString() ?? plan['name'] ?? 'Plan',
                      style: AppTextStyles.headlineLarge.copyWith(color: palette.metal),
                    ),
                    Text(
                      isFree ? 'Always' : _termLabel(plan['duration_months']),
                      style: AppTextStyles.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isFree ? 'Free' : _rupees(plan['price_inr']),
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(isFree ? 'forever' : 'Total', style: AppTextStyles.bodyMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ...entitlements.map((f) {
                  final included = f['included'] == true;
                  final text = included
                      ? (f['label']?.toString() ?? '')
                      : (f['compare']?.toString() ?? f['label']?.toString() ?? '');
                  if (text.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          included ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                          color: included ? palette.metal : AppColors.textTertiary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            text,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: included ? null : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (isCurrentActive) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.blessingSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.blessing.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: AppColors.blessing, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Current active plan',
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.blessing),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (expiryText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Active until $expiryText',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                ],
                const SizedBox(height: 20),

                if (canPurchase && !_payOnWebsite) _couponRow(plan),

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: buttonDisabled
                      ? null
                      : () {
                          if (_payOnWebsite) {
                            _openWebsite();
                            return;
                          }
                          final planId = plan['id'].toString();
                          context.read<SubscriptionBloc>().add(
                                InitiatePaymentEvent(
                                  plan,
                                  couponCode: _applied.containsKey(planId)
                                      ? _applied[planId]!.code
                                      : null,
                                ),
                              );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.metal,
                    foregroundColor: palette.onMetal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: isProcessing && !_payOnWebsite
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isFree
                              ? (isCurrentActive ? 'Your plan' : 'Included free')
                              : isCurrentActive
                                  ? 'Current Plan'
                                  : _payOnWebsite
                                      ? 'Open website'
                                      : (isPopular ? 'Subscribe Now' : 'Choose Plan'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
