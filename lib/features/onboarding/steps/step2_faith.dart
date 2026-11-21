import 'package:flutter/material.dart';
import '../../../core/l10n/app_language.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/utils/faith_labels.dart';

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
  // Optional faith details (API values).
  String? _baptism;
  final Set<String> _ministries = {};
  String? _afterMarriage;
  final _verseCtrl = TextEditingController();
  final _journeyCtrl = TextEditingController();

  @override
  void dispose() {
    _churchNameCtrl.dispose();
    _casteCtrl.dispose();
    _verseCtrl.dispose();
    _journeyCtrl.dispose();
    super.dispose();
  }

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
          if (baptismLabels.containsKey(profile['baptism_status'])) {
            _baptism = profile['baptism_status'];
          }
          if (profile['ministries'] is List) {
            _ministries.addAll(
              (profile['ministries'] as List)
                  .map((e) => '$e')
                  .where(ministryLabels.containsKey),
            );
          }
          if (churchAfterMarriageLabels.containsKey(
            profile['church_after_marriage'],
          )) {
            _afterMarriage = profile['church_after_marriage'];
          }
          if (profile['favourite_verse'] != null) {
            _verseCtrl.text = '${profile['favourite_verse']}';
          }
          if (profile['faith_journey'] != null) {
            _journeyCtrl.text = '${profile['faith_journey']}';
          }

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
      'baptism_status': _baptism ?? '',
      'ministries': _ministries.toList(),
      'church_after_marriage': _afterMarriage ?? '',
      'favourite_verse': _verseCtrl.text.trim(),
      'faith_journey': _journeyCtrl.text.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(tr('Denomination')),
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
          _sectionLabel(tr('Church Name')),
          TextField(
            controller: _churchNameCtrl,
            style: AppTextStyles.labelLarge,
            decoration: InputDecoration(
              hintText: tr('e.g. CSI Cathedral Kochi'),
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel(tr('How soon are you planning to marry?')),
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
          _sectionLabel(tr('Faith Level')),
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
          _sectionLabel(tr('Church Involvement')),
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
          _sectionLabel(tr('Caste (Optional)')),
          TextField(
            controller: _casteCtrl,
            style: AppTextStyles.labelLarge,
            decoration: InputDecoration(hintText: tr('e.g. Syrian Christian')),
          ),

          const SizedBox(height: 32),
          Text(tr('More about your faith'), style: AppTextStyles.headlineSmall),
          const SizedBox(height: 4),
          Text(
            tr(
              'Optional. Families often ask about these. Share only what you '
              'are comfortable with.',
            ),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          _sectionLabel(tr('Baptism')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in baptismLabels.entries)
                _choice(
                  e.value,
                  _baptism == e.key,
                  () => setState(
                    () => _baptism = _baptism == e.key ? null : e.key,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),
          _sectionLabel(tr('I serve in (choose any)')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in ministryLabels.entries)
                _choice(
                  e.value,
                  _ministries.contains(e.key),
                  () => setState(
                    () => _ministries.contains(e.key)
                        ? _ministries.remove(e.key)
                        : _ministries.add(e.key),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),
          _sectionLabel(tr('Church after marriage')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in churchAfterMarriageLabels.entries)
                _choice(
                  e.value,
                  _afterMarriage == e.key,
                  () => setState(
                    () =>
                        _afterMarriage = _afterMarriage == e.key ? null : e.key,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),
          _sectionLabel(tr('Favourite Bible verse')),
          TextField(
            controller: _verseCtrl,
            maxLength: 200,
            style: AppTextStyles.labelLarge,
            decoration: InputDecoration(
              hintText: tr('e.g. Joshua 24:15'),
              counterText: '',
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel(tr('My faith journey')),
          TextField(
            controller: _journeyCtrl,
            maxLength: 400,
            minLines: 3,
            maxLines: 5,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: tr(
                'A few lines about your faith and church life, in your own words.',
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// A chip that toggles (unlike _selectChip, which selects one by label).
  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: selected ? AppColors.goldSubtle : AppColors.surfaceElevated,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.surfaceHighest,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          tr(label),
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? AppColors.gold : AppColors.textSecondary,
          ),
        ),
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
          tr(label),
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected ? AppColors.gold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
