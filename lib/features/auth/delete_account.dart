import 'package:flutter/material.dart';
import '../../core/l10n/app_language.dart';

import '../../core/di/injection.dart' as di;
import '../../core/network/socket_service.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'data/auth_repository.dart';

/// Account deletion from the app is a request: staff complete it from the
/// admin inbox. Until then the member keeps using the app normally, and the
/// Delete account button shows the request as pending.
///
/// Returns when the request was sent (or was already open), so the caller can
/// show the pending state. Returns null when the member cancelled or it failed.
Future<DateTime?> confirmRequestAccountDeletion(BuildContext context) async {
  // The member's reason (optional), or null when they cancelled.
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _LeavingSheet(),
  );
  if (reason == null || !context.mounted) return null;

  try {
    final requestedAt = await di.sl<AuthRepository>().requestAccountDeletion(
      reason: reason,
    );
    if (!context.mounted) return requestedAt;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(tr('Request sent'), style: AppTextStyles.headlineSmall),
        content: Text(
          tr(
            'Your account delete request has been sent. Our team will delete '
            'your account and sign you out.',
          ),
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('OK')),
          ),
        ],
      ),
    );
    return requestedAt;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return null;
  }
}

/// The server no longer accepts this session: staff deleted the account (or
/// the session ended for good). Sign out locally and go to the phone screen.
/// Safe to call more than once.
bool _signingOut = false;
Future<void> signOutEndedSession({String? message}) async {
  if (_signingOut) return;
  _signingOut = true;
  try {
    try {
      di.sl<SocketService>().disconnect();
    } catch (_) {}
    await AppStorage.clearAll();
    AppRouter.router.go('/auth/phone');
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = AppRouter.rootNavigatorKey.currentContext;
        if (ctx == null) return;
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
      });
    }
  } finally {
    _signingOut = false;
  }
}

/// "Delete account" for screens that show it as a text button (review status).
/// Disabled with "Deletion requested" while a request is open.
class DeleteAccountTextButton extends StatefulWidget {
  const DeleteAccountTextButton({super.key, this.enabled = true});
  final bool enabled;

  @override
  State<DeleteAccountTextButton> createState() =>
      _DeleteAccountTextButtonState();
}

class _DeleteAccountTextButtonState extends State<DeleteAccountTextButton> {
  DateTime? _pendingSince;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    di.sl<AuthRepository>().accountDeletionRequestedAt().then(
      (at) {
        if (mounted) {
          setState(() {
            _pendingSince = at;
            _loaded = true;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loaded = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingSince != null;
    return TextButton(
      onPressed: !widget.enabled || !_loaded || pending
          ? null
          : () async {
              final at = await confirmRequestAccountDeletion(context);
              if (at != null && mounted) setState(() => _pendingSince = at);
            },
      child: Text(
        pending ? tr('Account deletion requested') : tr('Delete account'),
        style: AppTextStyles.labelLarge.copyWith(
          color: pending ? AppColors.textTertiary : AppColors.error,
        ),
      ),
    );
  }
}

/// "We're sorry to see you go": asks, politely and optionally, why the member
/// is leaving, then confirms the deletion request. Pops the reason ('' when
/// none was given), or null when the member keeps their account.
class _LeavingSheet extends StatefulWidget {
  const _LeavingSheet();

  @override
  State<_LeavingSheet> createState() => _LeavingSheetState();
}

class _LeavingSheetState extends State<_LeavingSheet> {
  static const _reasons = [
    'I found my partner on GraceMatch',
    'I found my partner elsewhere',
    'Not enough suitable profiles',
    'Privacy or safety concerns',
    'Plans are too expensive',
    'The app is hard to use',
    'I am taking a break',
    'Something else',
  ];

  final Set<String> _picked = {};
  final _more = TextEditingController();

  @override
  void dispose() {
    _more.dispose();
    super.dispose();
  }

  String get _reason {
    final more = _more.text.trim();
    return [
      if (_picked.isNotEmpty) _picked.join(', '),
      if (more.isNotEmpty) more,
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "We're sorry to see you go",
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Could you tell us what made you decide to leave? It helps us '
                'make GraceMatch better for every family. This is optional.',
              ),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _reasons)
                  FilterChip(
                    label: Text(tr(r)),
                    selected: _picked.contains(r),
                    onSelected: (on) =>
                        setState(() => on ? _picked.add(r) : _picked.remove(r)),
                    showCheckmark: false,
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: _picked.contains(r)
                          ? AppColors.textOnGold
                          : AppColors.textSecondary,
                    ),
                    selectedColor: AppColors.gold,
                    backgroundColor: AppColors.surfaceHighest,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _more,
              maxLines: 3,
              maxLength: 500,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: tr('Anything else you would like to tell us?'),
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Our team will then permanently delete your profile, photos, '
                'messages and phone number, and sign you out. You can keep using '
                'the app until then.',
              ),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: Text(tr('Keep my account')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(_reason),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(tr('Request deletion')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
