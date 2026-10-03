import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/support_repository.dart';

/// Start a conversation with support.
///
/// The category is asked first and asked plainly, because it decides which
/// staff see it and what history is put in front of them. "Payment problem"
/// arrives with the member's transactions attached; "Safety concern" arrives
/// with their reports. Getting that right is the difference between a
/// two-minute reply and a day of back and forth.
class NewTicketScreen extends StatefulWidget {
  /// Preselects a category when support is opened from a specific screen.
  final String? initialCategory;

  const NewTicketScreen({super.key, this.initialCategory});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _repo = SupportRepository();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  late Future<List<SupportCategory>> _categories = _repo.categories();
  String? _selected;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCategory;
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _ready =>
      _selected != null &&
      _subject.text.trim().length >= 3 &&
      _message.text.trim().length >= 5;

  Future<void> _send() async {
    setState(() { _sending = true; _error = null; });
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final ticket = await _repo.open(
        category: _selected!,
        subject: _subject.text,
        message: _message.text,
      );
      if (!mounted) return;
      router.pop(true);
      router.push('/support/${ticket.id}');
    } on DuplicateTicket catch (e) {
      // Not an error the member caused: take them to the thread they have.
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.surfaceHighest,
      ));
      router.pop(true);
      if (e.ticketId.isNotEmpty) router.push('/support/${e.ticketId}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('New message', style: AppTextStyles.headlineSmall),
      ),
      body: FutureBuilder<List<SupportCategory>>(
        future: _categories,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2));
          }

          final categories = snap.data ?? const <SupportCategory>[];
          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textTertiary),
                    const SizedBox(height: 16),
                    Text('Could not reach support',
                        style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Check your connection and try again.',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => setState(() => _categories = _repo.categories()),
                      child: Text('Try again',
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text('What is this about?', style: AppTextStyles.labelLarge),
              const SizedBox(height: 10),
              ...categories.map((c) => _CategoryTile(
                    category: c,
                    selected: _selected == c.key,
                    onTap: () {
                      AppHaptics.selection();
                      setState(() => _selected = c.key);
                    },
                  )),

              const SizedBox(height: 24),
              Text('Give it a title', style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              _field(_subject, 'Charged but my plan did not activate', maxLines: 1, maxLength: 160),

              const SizedBox(height: 20),
              Text('Tell us what happened', style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              _field(_message,
                  'The more detail the better — when it happened, what you saw, '
                  'and anything you have already tried.',
                  maxLines: 6, maxLength: 4000),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.roseDark)),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _ready && !_sending ? _send : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.textOnGold,
                  disabledBackgroundColor: AppColors.surfaceHighest,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: AppColors.textOnGold, strokeWidth: 2))
                    : Text('Send to support', style: AppTextStyles.buttonText),
              ),
              const SizedBox(height: 12),
              Text('We usually reply within a day.',
                  style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                  textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {required int maxLines, required int maxLength}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      maxLength: maxLength,
      style: AppTextStyles.bodyMedium,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surface,
        counterStyle: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.surfaceHighest),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.surfaceHighest),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.goldMild),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final SupportCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.goldSubtle : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.gold : AppColors.surfaceHighest),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.label,
                        style: AppTextStyles.labelMedium.copyWith(
                            color: selected ? AppColors.gold : AppColors.textPrimary)),
                    if (category.hint != null) ...[
                      const SizedBox(height: 2),
                      Text(category.hint!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}
