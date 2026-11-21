import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_haptics.dart';
import 'app_language.dart';

/// "English | తెలుగు": switches the whole app at once. Each name is written
/// in its own script so anyone can find theirs.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  static const _options = [('en', 'English'), ('te', 'తెలుగు')];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final current = AppLanguage.instance.code;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.surfaceHighest),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (code, name) in _options)
                GestureDetector(
                  onTap: () {
                    if (code == current) return;
                    AppHaptics.selection();
                    AppLanguage.instance.set(code);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: code == current
                          ? AppColors.gold
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      name,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: code == current
                            ? AppColors.textOnGold
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
