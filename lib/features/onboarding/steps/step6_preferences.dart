import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../bloc/onboarding_bloc.dart';
import '../bloc/onboarding_state.dart';
import '../screens/onboarding_screen.dart';

class Step6Preferences extends StatefulWidget {
  const Step6Preferences({super.key});

  @override
  State<Step6Preferences> createState() => _Step6PreferencesState();
}

class _Step6PreferencesState extends OnboardingStepState<Step6Preferences> {
  RangeValues _ageRange = const RangeValues(22, 35);
  RangeValues _heightRange = const RangeValues(150, 180); // in cm
  String _selectedDenom = '';
  bool _denominationFlexible = true;
  bool _hasLoaded = false;

  // Maps: display label → API value
  final _denomMap = {
    'Any': 'any',
    'CSI': 'csi',
    'Catholic': 'catholic',
    'Pentecostal': 'pentecostal',
    'Protestant': 'protestant',
    'Born Again': 'born_again',
    'Orthodox': 'orthodox',
    'Other': 'other',
  };

  String? _professionPreference;
  RangeValues _salaryRange = const RangeValues(0, 50); // In Lakhs/annum

  final _professionOptions = {
    'Private': 'pvt',
    'Government': 'govt',
    'Other': 'other',
    'Any': 'any',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData([Map<String, dynamic>? data]) {
    if (_hasLoaded && data == null) return;

    final parent = context.findAncestorStateOfType<OnboardingScreenState>();
    final prefs = (data ?? parent?.onboardingData)?['partner_preferences'];
    if (prefs != null && mounted) {
      setState(() {
        _hasLoaded = true;
        final minAge = (prefs['age_min'] as num?)?.toDouble() ?? 22.0;
        final maxAge = (prefs['age_max'] as num?)?.toDouble() ?? 35.0;
        _ageRange = RangeValues(minAge, maxAge);

        final minHeight = (prefs['height_min'] as num?)?.toDouble() ?? 140.0;
        final maxHeight = (prefs['height_max'] as num?)?.toDouble() ?? 220.0;
        _heightRange = RangeValues(minHeight, maxHeight);

        final minSalary = (prefs['salary_min'] as num?)?.toDouble() ?? 0.0;
        final maxSalary = (prefs['salary_max'] as num?)?.toDouble() ?? 50.0;
        _salaryRange = RangeValues(minSalary, maxSalary);

        if (prefs['profession_preference'] != null) {
          final prefValue = prefs['profession_preference'];
          _professionPreference = _professionOptions.keys.firstWhere(
            (k) => _professionOptions[k] == prefValue,
            orElse: () => 'Any',
          );
        }

        if (prefs['denomination_flexible'] != null) {
          _denominationFlexible = prefs['denomination_flexible'];
        }

        if (prefs['preferred_denominations'] != null) {
          dynamic denoms = prefs['preferred_denominations'];
          List<dynamic> denomList = [];

          if (denoms is List) {
            denomList = denoms;
          } else if (denoms is String && denoms.isNotEmpty) {
            denomList = denoms
                .replaceAll('{', '')
                .replaceAll('}', '')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }

          if (denomList.isNotEmpty) {
            final d = denomList.first;
            final key = _denomMap.keys.firstWhere(
              (k) => _denomMap[k] == d.toString().toLowerCase(),
              orElse: () => 'Any',
            );
            _selectedDenom = key;
            _denominationFlexible =
                (key == 'Any' || (prefs['denomination_flexible'] ?? false));
          } else {
            _selectedDenom = 'Any';
            _denominationFlexible = true;
          }
        } else {
          _selectedDenom = 'Any';
          _denominationFlexible = true;
        }
      });
    }
  }

  @override
  Map<String, dynamic>? getStepData() {
    final bool isAny = _selectedDenom == 'Any';
    final apiDenoms = isAny ? <String>[] : [_denomMap[_selectedDenom]!];

    return {
      'age_min': _ageRange.start.round(),
      'age_max': _ageRange.end.round(),
      'height_min': _heightRange.start.round(),
      'height_max': _heightRange.end.round(),
      'preferred_denominations': apiDenoms,
      'denomination_flexible': isAny || _denominationFlexible,
      'profession_preference': _professionPreference != null
          ? _professionOptions[_professionPreference]
          : 'any',
      'salary_min': _salaryRange.start.round(),
      'salary_max': _salaryRange.end.round(),
    };
  }

  void _toggleDenomination(String denomination) {
    setState(() {
      _selectedDenom = denomination;
      _denominationFlexible = (denomination == 'Any');
      _hasLoaded = true; // Mark as interacted to prevent reload
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OnboardingBloc, OnboardingState>(
      listener: (context, state) {
        if (state is OnboardingStatusLoaded) {
          _loadData(state.data);
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Age Range (Years)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_ageRange.start.round()}',
                  style: AppTextStyles.labelLarge,
                ),
                Text(
                  '${_ageRange.end.round()}',
                  style: AppTextStyles.labelLarge,
                ),
              ],
            ),
            RangeSlider(
              values: _ageRange,
              min: 18,
              max: 60,
              activeColor: AppColors.gold,
              inactiveColor: AppColors.surfaceHighest,
              onChanged: (values) => setState(() => _ageRange = values),
            ),
            const SizedBox(height: 24),

            _fieldLabel('Height Range (cm)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_heightRange.start.round()}',
                  style: AppTextStyles.labelLarge,
                ),
                Text(
                  '${_heightRange.end.round()}',
                  style: AppTextStyles.labelLarge,
                ),
              ],
            ),
            RangeSlider(
              values: _heightRange,
              min: 140,
              max: 220,
              activeColor: AppColors.gold,
              inactiveColor: AppColors.surfaceHighest,
              onChanged: (values) => setState(() => _heightRange = values),
            ),
            const SizedBox(height: 24),

            _fieldLabel('Preferred Denominations'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _denomMap.keys
                  .map(
                    (d) => _multiSelectChip(
                      d,
                      _selectedDenom == d,
                      () => _toggleDenomination(d),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            // Flexibility checkbox removed as per single-select requirement
            const SizedBox(height: 24),

            _fieldLabel('Profession Preference'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _professionOptions.keys
                  .map(
                    (p) => _selectChip(
                      p,
                      _professionPreference,
                      (v) => setState(() => _professionPreference = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),

            _fieldLabel('Annual Salary Range (Lakhs)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_salaryRange.start.round()}L',
                  style: AppTextStyles.labelLarge,
                ),
                Text(
                  '${_salaryRange.end.round()}L+',
                  style: AppTextStyles.labelLarge,
                ),
              ],
            ),
            RangeSlider(
              values: _salaryRange,
              min: 0,
              max: 100,
              activeColor: AppColors.gold,
              inactiveColor: AppColors.surfaceHighest,
              onChanged: (values) => setState(() => _salaryRange = values),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: AppTextStyles.labelMedium),
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
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected ? AppColors.gold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _multiSelectChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
