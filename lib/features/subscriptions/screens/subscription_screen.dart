import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../bloc/subscription_bloc.dart';
import '../../profile/bloc/profile_bloc.dart';
import '../../profile/bloc/profile_event.dart';
import '../../offers/data/offers_repository.dart';

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

  /// Ask the server what the code is worth on this plan. Read-only: trying a
  /// code must never consume it.
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
            body: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
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
                const SizedBox(height: 40),
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
            const Icon(Icons.local_offer_rounded, size: 15, color: AppColors.gold),
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
                    borderSide: const BorderSide(color: AppColors.goldMild),
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
                  ? const SizedBox(
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

  /// Converts the backend features JSONB object into human-readable bullet strings.
  /// Values of -1 mean "Unlimited"; 0 / false means skip.
  List<String> _featuresToStrings(dynamic raw) {
    if (raw == null) return [];

    final Map<String, dynamic> map = raw is Map ? Map<String, dynamic>.from(raw) : {};

    String count(dynamic v, String singular, String plural) {
      if (v == null || v == false || v == 0) return '';
      if (v == -1 || v == true) return 'Unlimited $plural';
      return '$v ${v == 1 ? singular : plural}';
    }

    final lines = <String>[];

    void add(dynamic v, String Function(dynamic) fn) {
      final s = fn(v);
      if (s.isNotEmpty) lines.add(s);
    }

    add(map['unlimited_swipes'], (v) => v == true ? 'Unlimited daily swipes' : '');
    add(map['see_who_viewed'], (v) => v == true ? 'See who viewed your profile' : '');
    add(
        map['contact_reveals_per_month'],
        (v) =>
            count(v, 'Contact reveal', 'Contact reveals') +
            (v != -1 && v != null && v != 0 ? ' / month' : ''));
    add(map['spotlight_boosts'], (v) => count(v, 'Spotlight boost', 'Spotlight boosts'));
    add(map['super_interests'], (v) => count(v, 'Super interest', 'Super interests'));
    add(map['priority_discover'], (v) => v == true ? 'Priority in discovery' : '');
    add(map['dedicated_support'], (v) => v == true ? 'Dedicated support' : '');

    return lines.where((s) => s.isNotEmpty).toList();
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
    final bool isPopular = plan['name']?.toString().toLowerCase() == 'gold';
    final List<String> features = _featuresToStrings(plan['features']);
    final bool isCurrentActive = plan['is_current_active'] == true;
    final bool canPurchase = plan['can_purchase'] != false;
    final bool buttonDisabled = isProcessing || !canPurchase;
    final currentSub = plan['current_subscription'];
    final expiryText = currentSub is Map ? _formatExpiry(currentSub['expires_at']) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPopular ? AppColors.gold : AppColors.surfaceHighest,
          width: isPopular ? 2 : 1,
        ),
        gradient: isPopular
            ? LinearGradient(
                colors: [AppColors.surfaceElevated, AppColors.gold.withAlpha(20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                ),
              ),
              child: Text(
                'MOST POPULAR',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textOnGold,
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
                    Text(plan['name'] ?? 'Plan', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.gold)),
                    Text('${plan['duration_months']} Months', style: AppTextStyles.labelLarge),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${plan['price_inr']}', style: AppTextStyles.displayMedium),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Total', style: AppTextStyles.bodyMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(f, style: AppTextStyles.bodyMedium)),
                        ],
                      ),
                    )),
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

                // ── Coupon. Shown per plan because the same code can be valid
                //    on one plan and not another.
                if (canPurchase) _couponRow(plan),

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: buttonDisabled
                      ? null
                      : () {
                          final planId = plan['id'].toString();
                          context.read<SubscriptionBloc>().add(
                                InitiatePaymentEvent(
                                  plan,
                                  // Only send a code that this plan has
                                  // actually been priced against.
                                  couponCode: _applied.containsKey(planId)
                                      ? _applied[planId]!.code
                                      : null,
                                ),
                              );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPopular ? AppColors.gold : AppColors.surfaceHighest,
                    foregroundColor: isPopular ? AppColors.textOnGold : AppColors.gold,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isCurrentActive
                              ? 'Current Plan'
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
