import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_language.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A poster staff publish from the admin site: shown once when the member
/// opens the app, until they press OK. The server remembers the OK, so a
/// reinstall or another phone does not show it again; a newer poster does.
class PosterGate {
  PosterGate._();

  static bool _busy = false;
  static DateTime? _lastCheck;
  // Shown this session but not yet answered (the app was backgrounded):
  // not shown again until the next cold start or a newer poster.
  static final Set<String> _shownThisSession = {};

  /// Check for a poster and show it. Safe to call often: it checks at most
  /// once every few minutes and never stacks two.
  static Future<void> maybeShow(BuildContext context) async {
    if (_busy) return;
    final now = DateTime.now();
    if (_lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(minutes: 5)) {
      return;
    }
    _busy = true;
    _lastCheck = now;
    try {
      final res = await DioClient.instance.get('/posters/current');
      final raw = res.data?['data']?['poster'];
      if (raw is! Map || !context.mounted) return;
      final poster = Map<String, dynamic>.from(raw);
      final id = poster['id']?.toString() ?? '';
      if (id.isEmpty || _shownThisSession.contains(id)) return;
      _shownThisSession.add(id);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => _PosterDialog(poster: poster),
      );
    } catch (_) {
      // A poster is never worth an error on screen.
    } finally {
      _busy = false;
    }
  }

  static Future<void> _markSeen(String id) async {
    try {
      await DioClient.instance.post('/posters/$id/seen');
    } catch (_) {}
  }
}

class _PosterDialog extends StatelessWidget {
  const _PosterDialog({required this.poster});
  final Map<String, dynamic> poster;

  String? _text(String key) {
    final v = poster[key]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final telugu = AppLanguage.instance.isTelugu;
    final title = (telugu ? _text('title_te') : null) ?? _text('title') ?? '';
    final body = (telugu ? _text('body_te') : null) ?? _text('body') ?? '';
    final image = _text('image_url');
    final linkRoute = _text('link_route');
    final linkLabel = _text('link_label');
    final id = poster['id'].toString();
    final maxImage = MediaQuery.sizeOf(context).height * 0.42;

    void close({String? goTo}) {
      PosterGate._markSeen(id);
      // Looked up before the pop: the dialog's context is gone after it.
      final router = GoRouter.of(context);
      Navigator.of(context, rootNavigator: true).pop();
      if (goTo != null) router.push(goTo);
    }

    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (image != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxImage),
                child: CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, __) => Container(
                    height: maxImage * 0.8,
                    color: AppColors.surfaceHighest,
                  ),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                children: [
                  if (linkRoute != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => close(goTo: linkRoute),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: BorderSide(color: AppColors.gold),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(linkLabel ?? tr('Open')),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => close(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.textOnGold,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(tr('OK')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
