import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import '../screens/onboarding_screen.dart';

class Step3Personal extends StatefulWidget {
  const Step3Personal({super.key});

  @override
  State<Step3Personal> createState() => _Step3PersonalState();
}

class _Step3PersonalState extends OnboardingStepState<Step3Personal> {
  final _heightCtrl = TextEditingController();
  final _educationCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _salaryRange;
  String? _jobSector;

  final _sectorOptions = {
    'Private': 'pvt',
    'Government': 'govt',
    'Business / Self-employed': 'business',
    'Other': 'other',
  };

  @override
  Map<String, dynamic>? getStepData() {
    if (_heightCtrl.text.isEmpty ||
        _educationCtrl.text.isEmpty ||
        _professionCtrl.text.isEmpty ||
        _salaryRange == null ||
        _jobSector == null) {
      return null;
    }
    return {
      'height_cm': int.tryParse(_heightCtrl.text) ?? 0,
      'education': _educationCtrl.text.trim(),
      'profession': _professionCtrl.text.trim(),
      'job_sector': _sectorOptions[_jobSector],
      'annual_income_min': _salaryMinMax[_salaryRange]![0],
      'annual_income_max': _salaryMinMax[_salaryRange]![1],
      'bio': _bioCtrl.text.trim(),
    };
  }

  // Maps: display label → [min, max] income values
  final _salaryMinMax = {
    'Less than ₹3 Lakhs': [0, 300000],
    '₹3L - ₹6L': [300000, 600000],
    '₹6L - ₹10L': [600000, 1000000],
    '₹6L - ₹10L': [600000, 1000000],
    '₹10L - ₹15L': [1000000, 1500000],
    '₹15L - ₹25L': [1500000, 2500000],
    '₹25L and above': [2500000, 10000000],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final profile = parent?.onboardingData?['profile'];
      if (profile != null && mounted) {
        setState(() {
          if (profile['height_cm'] != null)
            _heightCtrl.text = profile['height_cm'].toString();
          if (profile['education'] != null)
            _educationCtrl.text = profile['education'];
          if (profile['profession'] != null)
            _professionCtrl.text = profile['profession'];
          if (profile['bio'] != null) _bioCtrl.text = profile['bio'];

          if (profile['job_sector'] != null) {
            _jobSector = _sectorOptions.entries
                .cast<MapEntry<String, String>?>()
                .firstWhere(
                  (e) => e?.value == profile['job_sector'],
                  orElse: () => null,
                )
                ?.key;
          }

          if (profile['annual_income_min'] != null) {
            final min = profile['annual_income_min'];
            _salaryRange = _salaryMinMax.entries
                .cast<MapEntry<String, List<int>>?>()
                .firstWhere((e) => e?.value[0] == min, orElse: () => null)
                ?.key;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Height (in cm)'),
          _inputField(_heightCtrl, 'e.g. 175', isNumber: true),
          const SizedBox(height: 24),

          _fieldLabel('Highest Education'),
          _inputField(_educationCtrl, 'e.g. B.Tech Computer Science'),
          const SizedBox(height: 24),

          _fieldLabel('Current Profession'),
          _inputField(_professionCtrl, 'e.g. Software Engineer'),
          const SizedBox(height: 24),

          _fieldLabel('Working Sector'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sectorOptions.keys
                .map(
                  (s) => _selectChip(
                    s,
                    _jobSector,
                    (v) => setState(() => _jobSector = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),

          _fieldLabel('Annual Income'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _salaryMinMax.keys
                .map(
                  (r) => _selectChip(
                    r,
                    _salaryRange,
                    (v) => setState(() => _salaryRange = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),

          _fieldLabel('Bio / Self Introduction'),
          TextField(
            controller: _bioCtrl,
            maxLines: 4,
            style: AppTextStyles.labelLarge,
            decoration: const InputDecoration(
              hintText:
                  'Tell us about yourself, your faith, and what you are looking for in a partner...',
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: AppTextStyles.labelMedium),
  );

  Widget _inputField(
    TextEditingController ctrl,
    String hint, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: AppTextStyles.labelLarge,
      decoration: InputDecoration(hintText: hint),
    );
  }

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
}
