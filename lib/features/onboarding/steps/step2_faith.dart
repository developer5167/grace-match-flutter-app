import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';

import '../screens/onboarding_screen.dart';

class Step2Faith extends StatefulWidget {
  const Step2Faith({super.key});
  @override
  State<Step2Faith> createState() => _Step2FaithState();
}

class _Step2FaithState extends OnboardingStepState<Step2Faith> {
  String? _denomination;
  String? _marriageIntent;
  String? _faithLevel;
  String? _churchInvolvement;
  final _churchNameCtrl = TextEditingController();
  final _casteCtrl = TextEditingController();

  // Maps: display label → API value
  final _denominations = {
    'CSI': 'csi',
    'Catholic': 'catholic',
    'Pentecostal': 'pentecostal',
    'Protestant': 'protestant',
    'Born Again': 'born_again',
    'Orthodox': 'orthodox',
    'Other': 'other',
  };
  final _intents = {
    'Ready Now': 'ready_now',
    'Within 6 Months': 'within_6_months',
    'Within 1 Year': 'within_1_year',
    'Within 2 Years': 'within_2_years',
  };
  final _faithLevels = {
    'Very Strong': 'very_strong',
    'Strong': 'strong',
    'Moderate': 'moderate',
    'Growing': 'growing',
  };
  final _involvements = {
    'Very Active': 'very_active',
    'Active': 'active',
    'Occasional': 'occasional',
    'Rare': 'rare',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final profile = parent?.onboardingData?['profile'];
      if (profile != null && mounted) {
        setState(() {
          if (profile['church_name'] != null)
            _churchNameCtrl.text = profile['church_name'];
          if (profile['caste'] != null) _casteCtrl.text = profile['caste'];

          // Reverse lookups
          if (profile['denomination'] != null) {
            _denomination = _denominations.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['denomination'],
                  orElse: () => null,
                )
                ?.key;
          }
          if (profile['marriage_intent'] != null) {
            _marriageIntent = _intents.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['marriage_intent'],
                  orElse: () => null,
                )
                ?.key;
          }
          if (profile['faith_level'] != null) {
            _faithLevel = _faithLevels.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['faith_level'],
                  orElse: () => null,
                )
                ?.key;
          }
          if (profile['church_involvement'] != null) {
            _churchInvolvement = _involvements.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['church_involvement'],
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
    if (_denomination == null ||
        _marriageIntent == null ||
        _faithLevel == null ||
        _churchInvolvement == null ||
        _churchNameCtrl.text.isEmpty) {
      return null;
    }
    return {
      'denomination': _denominations[_denomination],
      'marriage_intent': _intents[_marriageIntent],
      'faith_level': _faithLevels[_faithLevel],
      'church_involvement': _involvements[_churchInvolvement],
      'church_name': _churchNameCtrl.text.trim(),
      'caste': _casteCtrl.text.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Denomination'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _denominations.keys
                .map(
                  (d) => _selectChip(
                    d,
                    _denomination,
                    (v) => setState(() => _denomination = v),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Church Name'),
          TextField(
            controller: _churchNameCtrl,
            style: AppTextStyles.labelLarge,
            decoration: const InputDecoration(
              hintText: 'e.g. CSI Cathedral Kochi',
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Marriage Intent'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _intents.keys
                .map(
                  (i) => _selectChip(
                    i,
                    _marriageIntent,
                    (v) => setState(() => _marriageIntent = v),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Faith Level'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _faithLevels.keys
                .map(
                  (f) => _selectChip(
                    f,
                    _faithLevel,
                    (v) => setState(() => _faithLevel = v),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Church Involvement'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _involvements.keys
                .map(
                  (c) => _selectChip(
                    c,
                    _churchInvolvement,
                    (v) => setState(() => _churchInvolvement = v),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Caste (Optional)'),
          TextField(
            controller: _casteCtrl,
            style: AppTextStyles.labelLarge,
            decoration: const InputDecoration(
              hintText: 'e.g. Syrian Christian',
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: AppTextStyles.labelLarge),
  );

  Widget _selectChip(
    String label,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () {
        AppHaptics.selection();
        onTap(label);
      },
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
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected ? AppColors.gold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
