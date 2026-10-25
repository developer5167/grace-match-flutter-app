import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'update_gate.dart';

/// One check per cold start. Splash and the router both ask, so a launch that
/// skips the splash (an answered call) still stops when this platform is off.
class MaintenanceGate {
  MaintenanceGate._();

  static bool? _blocked;
  static String message =
      'GraceMatch is temporarily unavailable. Please try again shortly.';

  static Future<bool> blocked({bool refresh = false}) async {
    if (!refresh && _blocked != null) return _blocked!;
    final policy = await UpdateGate.fetch();
    _blocked = policy?.maintenanceForDevice ?? false;
    if (policy != null && policy.maintenanceMessage.trim().isNotEmpty) {
      message = policy.maintenanceMessage.trim();
    }
    return _blocked!;
  }
}

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final still = await MaintenanceGate.blocked(refresh: true);
    if (!mounted) return;
    if (!still) {
      context.go('/splash');
      return;
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(),
                Icon(Icons.build_circle_outlined, color: AppColors.gold, size: 48),
                const SizedBox(height: 20),
                Text(
                  'Under maintenance',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  MaintenanceGate.message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _checking ? null : _retry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: BorderSide(color: AppColors.goldMild),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                    child: _checking
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                          )
                        : const Text('Try again'),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
