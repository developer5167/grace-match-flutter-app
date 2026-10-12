import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/support_repository.dart';

/// Support — the member's list of conversations, and the way to start one.
///
/// Until now the app had no way to reach a human. Somebody whose payment
/// failed could give up or write a one-star review explaining the problem to
/// everyone except the people who could fix it.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _repo = SupportRepository();
  late Future<List<SupportTicket>> _future = _repo.tickets();

  Future<void> _refresh() async {
    final next = _repo.tickets();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Help & support', style: AppTextStyles.headlineSmall),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.textOnGold,
        onPressed: () async {
          AppHaptics.selection();
          final started = await context.push<bool>('/support/new');
          if (started == true) _refresh();
        },
        icon: const Icon(Icons.add_comment_rounded, size: 18),
        label: Text('New message', style: AppTextStyles.labelMedium
            .copyWith(color: AppColors.textOnGold)),
      ),
      body: FutureBuilder<List<SupportTicket>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2));
          }

          final tickets = snap.data ?? const <SupportTicket>[];

          return RefreshIndicator(
            color: AppColors.gold,
            onRefresh: _refresh,
            child: tickets.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.16),
                      _empty(snap.hasError),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: tickets.length,
                    itemBuilder: (context, i) => _TicketTile(
                      ticket: tickets[i],
                      onTap: () async {
                        AppHaptics.selection();
                        await context.push('/support/${tickets[i].id}');
                        _refresh();
                      },
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _empty(bool errored) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(errored ? Icons.cloud_off_rounded : Icons.support_agent_rounded,
              size: 46, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(errored ? 'Could not load your messages' : 'How can we help?',
              style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            errored
                ? 'Pull down to try again.'
                : 'Payments, your account, verification, safety — anything at all. '
                  'We usually reply within a day.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;

  const _TicketTile({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = ticket.unread > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: unread ? AppColors.surfaceElevated : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: unread ? AppColors.goldMild : AppColors.surfaceHighest),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(ticket.subject,
                        style: AppTextStyles.labelLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (unread)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(100)),
                      child: Text('${ticket.unread}',
                          style: AppTextStyles.overline
                              .copyWith(color: AppColors.textOnGold)),
                    ),
                ],
              ),
              if (ticket.lastMessage != null && ticket.lastMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(ticket.lastMessage!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(ticket.statusLabel,
                      style: AppTextStyles.overline.copyWith(
                        color: ticket.status == 'awaiting_member'
                            ? AppColors.gold
                            : AppColors.textTertiary,
                      )),
                  const Spacer(),
                  Text(DateFormat('dd MMM').format(ticket.lastMessageAt),
                      style: AppTextStyles.overline
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
