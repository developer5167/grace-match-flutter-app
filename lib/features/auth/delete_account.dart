import 'package:flutter/material.dart';

import '../../core/di/injection.dart' as di;
import '../../core/network/socket_service.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'data/auth_repository.dart';

/// Confirms, then permanently erases the signed-in account and returns to
/// the phone screen. Safe to call from Settings, onboarding, or review.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text('Delete account?', style: AppTextStyles.headlineSmall),
      content: Text(
        'This permanently deletes your profile, photos, messages, and phone number from GraceMatch. You cannot undo this.',
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete account', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => Center(
      child: CircularProgressIndicator(color: AppColors.gold),
    ),
  );

  try {
    di.sl<SocketService>().disconnect();
    await di.sl<AuthRepository>().deleteAccount();
    AppRouter.rootNavigatorKey.currentState?.pop();
    AppRouter.router.go('/auth/phone');
  } catch (e) {
    AppRouter.rootNavigatorKey.currentState?.pop();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(e.toString()),
        backgroundColor: AppColors.error,
      ),
    );
  }
}
