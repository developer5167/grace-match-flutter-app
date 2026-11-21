import 'package:flutter/gestures.dart';
import '../../../core/l10n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import '../screens/onboarding_screen.dart';

class Step10Final extends StatefulWidget {
  const Step10Final({super.key});

  @override
  State<Step10Final> createState() => _Step10FinalState();
}

class _Step10FinalState extends OnboardingStepState<Step10Final> {
  String? _managedBy;
  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => context.push('/terms');
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => launchUrl(
      Uri.parse('${AppConstants.siteUrl}/privacy'),
      mode: LaunchMode.inAppBrowserView,
    );

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  bool _agreeTerms = false;

  // Maps: display label → API value
  final _managers = {
    'Self': 'self',
    'Parent': 'parents',
    'Sibling': 'others',
    'Relative': 'others',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final profile = parent?.onboardingData?['profile'];
      if (profile != null && mounted) {
        setState(() {
          if (profile['profile_managed_by'] != null) {
            _managedBy = _managers.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['profile_managed_by'],
                  orElse: () => null,
                )
                ?.key;
          }
        });
      }
    });
  }

  @override
  Map<String, dynamic>? getStepData() {
    if (_managedBy == null || !_agreeTerms) {
      return null;
    }
    return {'profile_managed_by': _managers[_managedBy]};
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.goldenGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.celebration_rounded,
                  color: AppColors.textOnGold,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    tr(
                      'You are almost done!\nGraceMatch is excited to welcome you.',
                    ),
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.textOnGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          _fieldLabel(tr('This profile is managed by')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _managers.keys
                .map(
                  (m) => _selectChip(
                    m,
                    _managedBy,
                    (v) => setState(() => _managedBy = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _agreeTerms,
                  activeColor: AppColors.gold,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _agreeTerms = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: tr(
                      'I confirm the details provided are true and I agree to the ',
                    ),
                    style: AppTextStyles.bodyMedium,
                    children: [
                      TextSpan(
                        text: tr('Terms & Community Rules'),
                        recognizer: _termsTap,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.gold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(text: tr(' and ')),
                      TextSpan(
                        text: tr('Privacy Policy'),
                        recognizer: _privacyTap,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.gold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(
                        text: tr(
                          '. I understand there is zero tolerance for abusive '
                          'or objectionable content, and accounts that post it '
                          'are removed.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(label, style: AppTextStyles.labelLarge),
  );

  Widget _selectChip(
    String label,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: isSelected ? AppColors.goldSubtle : AppColors.surfaceElevated,
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.surfaceHighest,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          tr(label),
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected ? AppColors.gold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
