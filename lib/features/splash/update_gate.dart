import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_version.dart';

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.enabled,
    required this.latestVersion,
    required this.mandatory,
    required this.title,
    required this.message,
    this.androidUrl,
    this.iosUrl,
  });

  final bool enabled;
  final String latestVersion;
  final bool mandatory;
  final String title;
  final String message;
  final String? androidUrl;
  final String? iosUrl;

  factory AppUpdatePolicy.fromJson(Map<String, dynamic> json) {
    return AppUpdatePolicy(
      enabled: json['enabled'] == true,
      latestVersion: (json['latest_version'] ?? '').toString(),
      mandatory: json['mandatory'] == true,
      title: (json['title'] ?? 'Update available').toString(),
      message: (json['message'] ??
              'A newer version of GraceMatch is ready. Update to keep using the app.')
          .toString(),
      androidUrl: json['android_url']?.toString(),
      iosUrl: json['ios_url']?.toString(),
    );
  }

  String? get storeUrl {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (iosUrl != null && iosUrl!.isNotEmpty) ? iosUrl : androidUrl;
    }
    return (androidUrl != null && androidUrl!.isNotEmpty) ? androidUrl : iosUrl;
  }
}

class UpdateGate {
  UpdateGate._();

  static Future<AppUpdatePolicy?> fetch() async {
    try {
      final resp = await DioClient.instance.get(ApiEndpoints.publicAppUpdate);
      final data = resp.data['data'];
      if (data is Map<String, dynamic>) {
        return AppUpdatePolicy.fromJson(data);
      }
      if (data is Map) {
        return AppUpdatePolicy.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('Update policy fetch failed: $e');
    }
    return null;
  }

  /// After splash. Returns once the member may continue (or never, if mandatory
  /// and they have not updated).
  static Future<void> maybePrompt(BuildContext context) async {
    final policy = await fetch();
    if (policy == null || !policy.enabled || policy.latestVersion.isEmpty) {
      return;
    }
    if (!context.mounted) return;

    final info = await PackageInfo.fromPlatform();
    final installed = policy.latestVersion.contains('+')
        ? '${info.version}+${info.buildNumber}'
        : info.version;

    if (compareAppVersions(installed, policy.latestVersion) >= 0) {
      return;
    }

    if (!policy.mandatory) {
      final skipped = AppStorage.getSkippedUpdateVersion();
      if (skipped == policy.latestVersion) return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !policy.mandatory,
      builder: (dialogContext) => PopScope(
        canPop: !policy.mandatory,
        child: _UpdateDialog(policy: policy),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.policy});

  final AppUpdatePolicy policy;

  Future<void> _openStore(BuildContext context) async {
    final raw = policy.storeUrl;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (policy.mandatory) return;
    if (context.mounted) Navigator.of(context).pop();
  }

  void _skip(BuildContext context) {
    AppStorage.saveSkippedUpdateVersion(policy.latestVersion);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceHighest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.goldMild),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.goldSubtle,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.system_update_alt_rounded,
                  color: AppColors.gold, size: 26),
            ),
            const SizedBox(height: 18),
            Text(
              policy.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              policy.message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _openStore(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.textOnGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Update now', style: AppTextStyles.buttonText),
              ),
            ),
            if (!policy.mandatory) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => _skip(context),
                  child: Text(
                    'Skip',
                    style: AppTextStyles.buttonTextSecondary.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
