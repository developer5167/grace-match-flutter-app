import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import '../screens/onboarding_screen.dart';

class Step4Lifestyle extends StatefulWidget {
  const Step4Lifestyle({super.key});

  @override
  State<Step4Lifestyle> createState() => _Step4LifestyleState();
}

class _Step4LifestyleState extends OnboardingStepState<Step4Lifestyle> {
  String? _diet;
  String? _smoke;
  String? _drink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final profile = parent?.onboardingData?['profile'];
      if (profile != null && mounted) {
        setState(() {
          _diet = profile['diet'];
          _smoke = profile['smoking'];
          _drink = profile['drinking'];
        });
      }
    });
  }

  @override
  Map<String, dynamic>? getStepData() {
    if (_diet == null || _smoke == null || _drink == null) {
      return null;
    }
    return {'diet': _diet, 'smoking': _smoke, 'drinking': _drink};
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Diet Preferences'),
          Row(
            children: [
              _choiceCard(
                'Veg',
                '🥗',
                'veg',
                _diet,
                (v) => setState(() => _diet = v),
              ),
              const SizedBox(width: 12),
              _choiceCard(
                'Non-Veg',
                '🍗',
                'non_veg',
                _diet,
                (v) => setState(() => _diet = v),
              ),
            ],
          ),
          const SizedBox(height: 32),

          _fieldLabel('Smoking Habit'),
          Row(
            children: [
              _choiceCard(
                'No',
                '🚭',
                'no',
                _smoke,
                (v) => setState(() => _smoke = v),
              ),
              const SizedBox(width: 12),
              _choiceCard(
                'Yes',
                '🚬',
                'yes',
                _smoke,
                (v) => setState(() => _smoke = v),
              ),
            ],
          ),
          const SizedBox(height: 32),

          _fieldLabel('Drinking Habit'),
          Row(
            children: [
              _choiceCard(
                'No',
                '🚫',
                'no',
                _drink,
                (v) => setState(() => _drink = v),
              ),
              const SizedBox(width: 12),
              _choiceCard(
                'Occasional',
                '🥂',
                'occasionally',
                _drink,
                (v) => setState(() => _drink = v),
              ),
              const SizedBox(width: 12),
              _choiceCard(
                'Yes',
                '🍺',
                'yes',
                _drink,
                (v) => setState(() => _drink = v),
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

  Widget _choiceCard(
    String title,
    String emoji,
    String value,
    String? current,
    ValueChanged<String> onChanged,
  ) {
    final isSelected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected
                ? AppColors.goldSubtle
                : AppColors.surfaceElevated,
            border: Border.all(
              color: isSelected ? AppColors.gold : AppColors.surfaceHighest,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                title,
                style: AppTextStyles.labelMedium.copyWith(
                  color: isSelected ? AppColors.gold : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
