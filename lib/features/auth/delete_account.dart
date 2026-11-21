import 'package:flutter/material.dart';

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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: Text('Delete your account?', style: AppTextStyles.headlineSmall),
      content: Text(
        'We will send a request to the GraceMatch team. They will permanently '
        'delete your profile, photos, messages and phone number, and sign you '
        'out. You can keep using the app until then.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(
            'Send request',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  try {
    final requestedAt = await di.sl<AuthRepository>().requestAccountDeletion();
    if (!context.mounted) return requestedAt;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Request sent', style: AppTextStyles.headlineSmall),
        content: Text(
          'Your account delete request has been sent. Our team will delete '
          'your account and sign you out.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
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
        pending ? 'Account deletion requested' : 'Delete account',
        style: AppTextStyles.labelLarge.copyWith(
          color: pending ? AppColors.textTertiary : AppColors.error,
        ),
      ),
    );
  }
}
