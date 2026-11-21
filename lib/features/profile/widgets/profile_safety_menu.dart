import 'package:flutter/material.dart';
import '../../../core/l10n/app_language.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// "⋯" on someone's profile: report or block them without needing a chat
/// first (App Store guideline 1.2: user-generated content must be reportable
/// and abusive members blockable wherever they appear).
class ProfileSafetyMenu extends StatelessWidget {
  final String userId;
  final String name;
  const ProfileSafetyMenu({
    super.key,
    required this.userId,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('More'),
      icon: Icon(Icons.more_vert_rounded, color: AppColors.gold),
      color: AppColors.surfaceHighest,
      onSelected: (v) => v == 'report' ? _report(context) : _block(context),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.error, size: 20),
              SizedBox(width: 10),
              Text(tr('Report profile'), style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              SizedBox(width: 10),
              Text('Block $name', style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _block(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Block $name?', style: AppTextStyles.labelLarge),
        content: Text(
          tr(
            'You will not see each other anywhere in Grace Match, and they '
            'cannot contact you. You can unblock them later in Settings.',
          ),
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Block'), style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _send(context, ApiEndpoints.block, {
      'blocked_user_id': userId,
    }, done: '$name is blocked.');
  }

  Future<void> _report(BuildContext context) async {
    String reason = 'fake_profile';
    final details = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Report $name?', style: AppTextStyles.labelLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Our team reviews every report. They will not be told who '
                    'reported them, and they will be blocked from contacting you.',
                  ),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  dropdownColor: AppColors.surfaceHighest,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: 'fake_profile',
                      child: Text(tr('Fake profile')),
                    ),
                    DropdownMenuItem(
                      value: 'inappropriate',
                      child: Text(tr('Inappropriate photos or text')),
                    ),
                    DropdownMenuItem(
                      value: 'harassment',
                      child: Text(tr('Harassment or abuse')),
                    ),
                    DropdownMenuItem(
                      value: 'money_request',
                      child: Text(tr('Asked for money')),
                    ),
                    DropdownMenuItem(
                      value: 'already_married',
                      child: Text(tr('Already married')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(tr('Something else')),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => reason = v ?? reason),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: details,
                  maxLines: 3,
                  maxLength: 500,
                  style: AppTextStyles.bodySmall,
                  decoration: InputDecoration(
                    hintText: tr('What happened? (optional)'),
                    hintStyle: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                tr('Report and block'),
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    final text = details.text.trim();
    details.dispose();
    if (ok != true || !context.mounted) return;
    await _send(
      context,
      ApiEndpoints.reportAndExit,
      {
        'reported_user_id': userId,
        'reason': reason,
        if (text.isNotEmpty) 'details': text,
      },
      done: 'Reported. Our team will review it, and $name cannot contact you.',
    );
  }

  Future<void> _send(
    BuildContext context,
    String path,
    Map<String, dynamic> body, {
    required String done,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await DioClient.instance.post(path, data: body);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/discover');
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('Could not send. Please try again.')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
