import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_language.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../data/review_repository.dart';

/// "Verifying your details": shown right after sign-up, and again after the
/// member fixes something.
///
/// The server checks every section (complete? text suitable? one clear face?
/// selfie matches?) and either approves the profile, lists what to fix, or
/// hands it to staff. This screen shows that section by section: a spinner,
/// then a tick or what to fix with a button that opens the right step. When
/// they come back, only what changed is checked again.
class VerifyProfileScreen extends StatefulWidget {
  const VerifyProfileScreen({super.key});

  @override
  State<VerifyProfileScreen> createState() => _VerifyProfileScreenState();
}

enum _Row { waiting, checking, done }

class _VerifyProfileScreenState extends State<VerifyProfileScreen> {
  static const _sections = [
    ('basic', 'Basic details'),
    ('faith', 'Faith details'),
    ('profile', 'About you'),
    ('family', 'Family'),
    ('preferences', 'Partner preferences'),
    ('photos', 'Photos'),
    ('selfie', 'Verification selfie'),
    ('identity', 'Identity (DigiLocker)'),
  ];
  static const _total = Duration(minutes: 2);

  final _repo = ReviewRepository();
  VerifyResult? _result;
  Object? _error;
  final Map<String, _Row> _rows = {};
  Timer? _ticker;
  Timer? _clock;
  int _secondsLeft = _total.inSeconds;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run(_sections.map((s) => s.$1).toSet());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  /// Check [keys] again (all of them the first time, then only what failed).
  Future<void> _run(Set<String> keys) async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _secondsLeft = _total.inSeconds;
      for (final k in keys) {
        _rows[k] = _Row.waiting;
      }
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 999));
    });

    // Rows light up one after another while the server works, then show
    // their results in the same order once it answers.
    final order = _sections.map((s) => s.$1).where(keys.contains).toList();
    var cursor = 0;
    VerifyResult? answer;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) return;
      setState(() {
        if (cursor < order.length && _rows[order[cursor]] == _Row.waiting) {
          _rows[order[cursor]] = _Row.checking;
        }
        if (answer != null && cursor < order.length) {
          _rows[order[cursor]] = _Row.done;
          cursor++;
          if (cursor < order.length) _rows[order[cursor]] = _Row.checking;
        } else if (answer == null && cursor < order.length - 1) {
          // Keep one row ahead spinning so the screen never looks stuck.
          final next = order.indexWhere((k) => _rows[k] == _Row.waiting);
          if (next != -1 && next <= cursor + 1)
            _rows[order[next]] = _Row.checking;
        }
        if (answer != null && cursor >= order.length) {
          t.cancel();
          _clock?.cancel();
          _running = false;
        }
      });
    });

    try {
      final r = await _repo.verify();
      AppStorage.saveReviewStatus(r.reviewStatus);
      if (!mounted) return;
      setState(() => _result = r);
      answer = r;
    } catch (e) {
      _ticker?.cancel();
      _clock?.cancel();
      if (!mounted) return;
      setState(() {
        _error = e;
        _running = false;
        for (final k in keys) {
          _rows[k] = _Row.done;
        }
      });
    }
  }

  VerifySection? _section(String key) {
    for (final s in _result?.sections ?? const <VerifySection>[]) {
      if (s.key == key) return s;
    }
    return null;
  }

  Future<void> _fix(VerifySection s) async {
    await context.push(s.route);
    if (!mounted) return;
    // Only the sections that were not passed are checked again.
    final again = (_result?.sections ?? const <VerifySection>[])
        .where((x) => x.status != 'passed')
        .map((x) => x.key)
        .toSet();
    _run(again.isEmpty ? {s.key} : again);
  }

  @override
  Widget build(BuildContext context) {
    final finished = !_running && (_result != null || _error != null);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Verifying your details'),
                    style: AppTextStyles.headlineMedium,
                  ),
                ),
                _timerChip(finished),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                'To keep GraceMatch genuine and free of fake profiles, every '
                'family completes all their details. This keeps everyone '
                'safe, including you.',
              ),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            for (final s in _sections) _row(s.$1, s.$2),
            const SizedBox(height: 12),
            if (finished) _outcome(),
          ],
        ),
      ),
    );
  }

  Widget _timerChip(bool finished) {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.goldSubtle,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.goldMild),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            finished ? Icons.check_rounded : Icons.timer_outlined,
            size: 15,
            color: AppColors.gold,
          ),
          const SizedBox(width: 4),
          Text(
            finished ? tr('Done') : '$m:$s',
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold),
          ),
        ],
      ),
    );
  }

  Widget _row(String key, String title) {
    final state = _rows[key] ?? _Row.done;
    final s = state == _Row.done ? _section(key) : null;
    final status = s?.status;

    Widget leading;
    if (state == _Row.waiting) {
      leading = Icon(
        Icons.radio_button_unchecked_rounded,
        color: AppColors.textTertiary,
        size: 24,
      );
    } else if (state == _Row.checking || (s == null && _error == null)) {
      leading = SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.gold,
          ),
        ),
      );
    } else {
      leading = switch (status) {
        'passed' => const Icon(
          Icons.check_circle_rounded,
          color: AppColors.blessing,
          size: 24,
        ),
        'failed' => const Icon(
          Icons.error_rounded,
          color: AppColors.warning,
          size: 24,
        ),
        'recommended' => Icon(
          Icons.verified_outlined,
          color: AppColors.gold,
          size: 24,
        ),
        _ => Icon(Icons.hourglass_top_rounded, color: AppColors.gold, size: 24),
      };
    }

    final subtitle = switch (state) {
      _Row.waiting => null,
      _Row.checking => tr('Checking…'),
      _Row.done => switch (status) {
        'passed' => tr('Looks good'),
        'review' =>
          s?.message != null
              ? tr(s!.message!)
              : tr('Our team will take a quick look.'),
        'recommended' => s?.message != null ? tr(s!.message!) : null,
        _ => null,
      },
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'failed' && state == _Row.done
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.surfaceHighest,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(title), style: AppTextStyles.labelLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (state == _Row.done && s != null && status == 'failed') ...[
            const SizedBox(height: 10),
            for (final i in s.issues)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${tr(i.field)}: ',
                        style: AppTextStyles.labelMedium,
                      ),
                      TextSpan(
                        text: tr(i.message),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _running ? null : () => _fix(s),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(tr('Fix now')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.textOnGold,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (state == _Row.done && s != null && status == 'recommended')
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: OutlinedButton(
                onPressed: () => context.push(s.route),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  side: BorderSide(color: AppColors.goldMild),
                  minimumSize: const Size(0, 38),
                ),
                child: Text(tr('Verify now')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _outcome() {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('We could not check your details right now. Please try again.'),
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: tr('Try again'),
            onPressed: () => _run(_sections.map((s) => s.$1).toSet()),
          ),
        ],
      );
    }
    final r = _result!;
    if (r.approved) {
      return _card(
        icon: Icons.celebration_rounded,
        title: tr('You are verified!'),
        body: tr(
          'Your profile is now live. Families can see you, and you can start exploring.',
        ),
        button: tr('Start exploring'),
        onPressed: () => context.go('/discover'),
      );
    }
    if (r.reviewStatus == 'changes_requested') {
      return Text(
        tr(
          'Please fix the items marked above. We will check only those again.',
        ),
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      );
    }
    return _card(
      icon: Icons.hourglass_top_rounded,
      title: tr('Almost there'),
      body: tr(
        'Our team will take a quick look and you will get a notification, usually within a day.',
      ),
      button: tr('OK'),
      onPressed: () => context.go('/review-status'),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String body,
    required String button,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.goldSubtle,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.goldMild),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppTextStyles.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          AppButton(label: button, onPressed: onPressed),
        ],
      ),
    );
  }
}
