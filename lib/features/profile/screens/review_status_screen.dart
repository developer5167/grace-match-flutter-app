import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/widgets/app_button.dart';
import '../data/review_repository.dart';

/// After onboarding the member used to sit on a dead "under review" screen.
/// Staff could only approve or reject, and a missing photo had no way back.
///
/// This screen is the inbox: every item staff asked for (or that is obviously
/// missing) is listed. Fix now opens the matching screen; when they return we
/// mark that item done and open the next one. When the list is empty the
/// profile goes back to the staff queue.
class ReviewStatusScreen extends StatefulWidget {
  const ReviewStatusScreen({super.key});

  @override
  State<ReviewStatusScreen> createState() => _ReviewStatusScreenState();
}

class _ReviewStatusScreenState extends State<ReviewStatusScreen> {
  final _repo = ReviewRepository();
  ReviewInbox? _inbox;
  Object? _error;
  bool _loading = true;
  bool _working = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inbox = await _repo.fetch();
      if (inbox.reviewStatus != null) {
        AppStorage.saveReviewStatus(inbox.reviewStatus);
      }
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _loading = false;
        if (inbox.resubmitted) {
          _banner = 'Sent back for review. We will take another look.';
        }
      });
      if (inbox.reviewStatus == 'approved' && mounted) {
        context.go('/discover');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _runQueue() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      while (mounted) {
        final open = _inbox?.open ?? const <ReviewActionItem>[];
        if (open.isEmpty) {
          try {
            final done = await _repo.submitAll();
            if (!mounted) return;
            if (done.reviewStatus != null) {
              AppStorage.saveReviewStatus(done.reviewStatus);
            }
            setState(() {
              _inbox = done;
              _banner = done.resubmitted
                  ? 'Sent back for review. We will take another look.'
                  : 'Nothing left to send.';
            });
            if (done.reviewStatus == 'approved') context.go('/discover');
          } catch (e) {
            if (!mounted) return;
            setState(() => _banner = _repo.errorMessage(e));
          }
          break;
        }

        final action = open.first;
        await context.push(action.route);
        if (!mounted) return;
        try {
          final next = await _repo.submit(action.actionType);
          if (next.reviewStatus != null) {
            AppStorage.saveReviewStatus(next.reviewStatus);
          }
          setState(() {
            _inbox = next;
            if (next.resubmitted) {
              _banner = 'Sent back for review. We will take another look.';
            }
          });
          if (next.reviewStatus == 'approved' && mounted) {
            context.go('/discover');
            break;
          }
        } catch (e) {
          if (!mounted) return;
          setState(() => _banner = _repo.errorMessage(e));
          await _reload();
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = _inbox;
    final status = inbox?.reviewStatus ?? AppStorage.getReviewStatus();
    final isRejected = status == 'rejected';
    final open = inbox?.open ?? const <ReviewActionItem>[];
    final hasWork = open.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading && inbox == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : RefreshIndicator(
                color: AppColors.gold,
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                  children: [
                    _hero(isRejected, hasWork),
                    const SizedBox(height: 36),
                    Text(
                      hasWork
                          ? 'Action needed'
                          : isRejected
                              ? 'Application update'
                              : 'Profile under review',
                      style: AppTextStyles.headlineMedium,
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 120.ms),
                    const SizedBox(height: 12),
                    Text(
                      _bodyCopy(isRejected, hasWork, inbox?.reviewNote),
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 220.ms),
                    if (_banner != null) ...[
                      const SizedBox(height: 16),
                      _noteCard(_banner!, gold: true),
                    ],
                    if (inbox?.reviewNote != null &&
                        inbox!.reviewNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _noteCard(inbox.reviewNote!),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _noteCard(_repo.errorMessage(_error!)),
                    ],
                    if (inbox != null && inbox.actions.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      ...inbox.actions.map(_actionTile),
                    ],
                    const SizedBox(height: 36),
                    if (hasWork)
                      AppButton(
                        label: open.length == 1
                            ? 'Fix ${open.first.title}'
                            : 'Fix ${open.length} items',
                        isLoading: _working,
                        onPressed: _runQueue,
                      )
                    else
                      AppButton(
                        label: 'Refresh status',
                        isLoading: _loading,
                        onPressed: _reload,
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.push('/support'),
                      child: Text(
                        'Contact support',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.gold),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        AppStorage.clearAll();
                        context.go('/auth/phone');
                      },
                      child: Text(
                        'Sign out',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _bodyCopy(bool isRejected, bool hasWork, String? note) {
    if (hasWork) {
      return 'Open each item, add what is missing, and we will send everything back to our team.';
    }
    if (isRejected) {
      return note?.trim().isNotEmpty == true
          ? 'Please read the note below. You can still send updates from this screen if anything is listed.'
          : 'We could not approve this profile yet. Contact support if you need help.';
    }
    return 'Our team is reviewing your profile. You will get a notification when it is approved.';
  }

  Widget _hero(bool isRejected, bool hasWork) {
    final color = isRejected
        ? AppColors.error
        : hasWork
            ? AppColors.gold
            : AppColors.gold;
    return Center(
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(
          isRejected
              ? Icons.error_outline_rounded
              : hasWork
                  ? Icons.assignment_late_rounded
                  : Icons.access_time_rounded,
          size: 52,
          color: color,
        ),
      ),
    ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack);
  }

  Widget _noteCard(String text, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gold ? AppColors.goldSubtle : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold ? AppColors.goldMild : AppColors.surfaceHighest),
      ),
      child: Text(text, style: AppTextStyles.bodyMedium),
    );
  }

  Widget _actionTile(ReviewActionItem action) {
    final done = !action.isOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: done || _working
              ? null
              : () async {
                  setState(() => _working = true);
                  try {
                    await context.push(action.route);
                    if (!mounted) return;
                    final next = await _repo.submit(action.actionType);
                    if (next.reviewStatus != null) {
                      AppStorage.saveReviewStatus(next.reviewStatus);
                    }
                    setState(() {
                      _inbox = next;
                      if (next.resubmitted) {
                        _banner = 'Sent back for review. We will take another look.';
                      }
                    });
                  } catch (e) {
                    if (mounted) setState(() => _banner = _repo.errorMessage(e));
                    await _reload();
                  } finally {
                    if (mounted) setState(() => _working = false);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? Colors.green : AppColors.gold,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.title, style: AppTextStyles.labelLarge),
                      if (action.hint.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          action.hint,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!done)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
