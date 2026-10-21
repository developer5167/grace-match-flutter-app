import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Public website contact form. Suspended members cannot open in-app tickets.
class ContactSupport {
  ContactSupport._();

  static Uri get uri => Uri.parse('${AppConstants.siteUrl}/contact').replace(
        queryParameters: const {'topic': 'support'},
      );

  static Future<bool> open() async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Used when login (or any other gate) refuses a suspended account.
  static Future<void> showSuspendedDialog(BuildContext context, {String? message}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Account suspended', style: AppTextStyles.headlineMedium),
        content: Text(
          message ??
              'This account has been suspended. Use the website contact form and we will look into it.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              open();
            },
            child: const Text('Contact support'),
          ),
        ],
      ),
    );
  }
}
