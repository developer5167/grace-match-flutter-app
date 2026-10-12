import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart' as di;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/network/socket_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/bloc/profile_bloc.dart';
import '../../profile/bloc/profile_event.dart';
import '../../profile/bloc/profile_state.dart';
import '../../profile/data/profile_repository.dart';

/// Privacy & shortcuts aligned with `/profile/settings` (backend PUT).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(const FetchProfileEvent(silentRefresh: true));
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    if (_busy || body.isEmpty) return;
    setState(() => _busy = true);
    AppHaptics.light();
    try {
      await di.sl<ProfileRepository>().updateSettings(body);
      if (!mounted) return;
      context.read<ProfileBloc>().add(const FetchProfileEvent(silentRefresh: true));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Saved'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Log out?', style: AppTextStyles.headlineSmall),
        content: Text(
          'You will be signed out from this device.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      di.sl<SocketService>().disconnect();
      await di.sl<AuthRepository>().logout();
      if (!mounted) return;
      context.go('/auth/phone');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        Map<String, dynamic> profile = {};
        if (state is ProfileLoaded) {
          final data = state.profile;
          final p = data['profile'];
          if (p is Map<String, dynamic>) profile = p;
        }

        final visibility = profile['profile_visibility']?.toString() ?? 'everyone';
        final whoChat = profile['who_can_chat']?.toString() ?? 'interests_only';
        final contactOk = profile['is_contact_sharing_allowed'] != false;
        final imagesLocked = profile['is_images_locked'] == true;
        final typingPush = profile['typing_push_enabled'] != false;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.gold),
              onPressed: () {
                AppHaptics.selection();
                context.pop();
              },
            ),
            title: Text('Privacy & settings', style: AppTextStyles.headlineMedium),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  Text(
                    'Control who discovers you, how members reach you, and your photos.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Who can see your profile'),
                  const SizedBox(height: 12),
                  _radioTile<String>(
                    title: 'Everyone on GraceMatch',
                    subtitle: 'Your profile can appear in Discover for suitable matches.',
                    value: 'everyone',
                    group: visibility,
                    onPick: (_) => _patch({'profile_visibility': 'everyone'}),
                  ),
                  _radioTile<String>(
                    title: 'Interest & connections',
                    subtitle: 'Only people you have interacted with (sent/received interest) can open your full profile.',
                    value: 'interests_only',
                    group: visibility,
                    onPick: (_) => _patch({'profile_visibility': 'interests_only'}),
                  ),
                  _radioTile<String>(
                    title: 'Hidden',
                    subtitle: 'Your profile stays off Discover until you switch back.',
                    value: 'hidden',
                    group: visibility,
                    onPick: (_) => _patch({'profile_visibility': 'hidden'}),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('Messaging'),
                  const SizedBox(height: 12),
                  _radioTile<String>(
                    title: 'Matched connections',
                    subtitle: 'Only after both sides accept interest can chat open (recommended).',
                    value: 'interests_only',
                    group: whoChat,
                    onPick: (_) => _patch({'who_can_chat': 'interests_only'}),
                  ),
                  _radioTile<String>(
                    title: 'Open to messages',
                    subtitle: 'Stored for your preference; chat still unlocks when you connect in the app.',
                    value: 'everyone',
                    group: whoChat,
                    onPick: (_) => _patch({'who_can_chat': 'everyone'}),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('Contact & photos'),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: 'Allow contact requests',
                    subtitle:
                        'Premium members may request your number. You can approve each request or turn this off.',
                    value: contactOk,
                    onChanged: (v) => _patch({'is_contact_sharing_allowed': v}),
                  ),
                  const SizedBox(height: 8),
                  _switchTile(
                    title: 'Lock photos until connected',
                    subtitle:
                        'Hide your photos from people you are not matched with yet. Off by default — turn this on if you want them private.',
                    value: imagesLocked,
                    onChanged: (v) => _patch({'is_images_locked': v}),
                  ),
                  const SizedBox(height: 8),
                  _switchTile(
                    title: 'Typing notifications',
                    subtitle:
                        'Get a banner when a match starts typing to you, even if you are not in the chat. The banner disappears when they stop or you open the conversation.',
                    value: typingPush,
                    onChanged: (v) => _patch({'typing_push_enabled': v}),
                  ),
                  const SizedBox(height: 32),
                  // Support, above Profile & matching rather than buried at
                  // the bottom: a member looking for this is usually looking
                  // for it because something has gone wrong.
                  _sectionTitle('Help'),
                  const SizedBox(height: 12),
                  _linkTile(
                    icon: Icons.support_agent_rounded,
                    title: 'Help & support',
                    subtitle: 'Payments, your account, verification, safety — ask us anything.',
                    onTap: () {
                      AppHaptics.selection();
                      context.push('/support');
                    },
                  ),

                  const SizedBox(height: 32),
                  _sectionTitle('Profile & matching'),
                  const SizedBox(height: 12),
                  _linkTile(
                    icon: Icons.tune_rounded,
                    title: 'Partner preferences',
                    subtitle: 'Age, denomination, castes, salary range…',
                    onTap: () {
                      AppHaptics.selection();
                      context.push('/onboarding', extra: 5);
                    },
                  ),
                  const SizedBox(height: 12),
                  _linkTile(
                    icon: Icons.block_rounded,
                    title: 'Blocked accounts',
                    subtitle: 'Block or report from someone’s profile.',
                    onTap: () {
                      AppHaptics.selection();
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            'Use ⋮ or report on any profile screen to block.',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _busy ? null : _logout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.error.withAlpha(120)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.logout_rounded, color: AppColors.error),
                            const SizedBox(width: 12),
                            Text(
                              'Log out',
                              style: AppTextStyles.labelLarge.copyWith(color: AppColors.error),
                            ),
                            const Spacer(),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Notifications use your device permissions. Critical alerts still reach you inside the app.',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
              if (_busy)
                const LinearProgressIndicator(
                  backgroundColor: AppColors.surfaceHighest,
                  color: AppColors.gold,
                  minHeight: 2,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: AppTextStyles.headlineSmall.copyWith(color: AppColors.gold));

  Widget _radioTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required T group,
    required ValueChanged<T?> onPick,
  }) {
    final selected = group == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.goldSubtle : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _busy ? null : () => onPick(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.gold : AppColors.textTertiary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.labelLarge),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceHighest),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.gold.withAlpha(140),
            onChanged: _busy ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
