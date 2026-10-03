import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../data/notifications_repository.dart';

/// Everything the app has ever told this member, in one place.
///
/// The Activity tab shows the recent few; this is the full history, paged.
/// Tapping one takes you where it was about — a notification you cannot act on
/// is just a receipt.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = NotificationsRepository();
  final _scroll = ScrollController();

  final List<AppNotification> _items = [];
  int _page = 1;
  int _unread = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 400;
    if (nearEnd && _hasMore && !_loadingMore && !_loading) _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loading = true; _error = null; _page = 1; _hasMore = true; });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final res = await _repo.fetch(page: reset ? 1 : _page);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _unread = res.unreadCount;
        _hasMore = res.hasMore;
        _page = (reset ? 1 : _page) + 1;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; _loadingMore = false; });
    }
  }

  Future<void> _markAllRead() async {
    AppHaptics.light();
    // Optimistic: the list is already on screen and the call is idempotent.
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
      _unread = 0;
    });
    try {
      await _repo.markAllRead();
    } catch (_) {
      if (mounted) _load(reset: true);
    }
  }

  Future<void> _open(AppNotification n) async {
    AppHaptics.selection();
    if (!n.isRead) {
      setState(() {
        final i = _items.indexWhere((x) => x.id == n.id);
        if (i != -1) _items[i] = _items[i].copyWith(isRead: true);
        _unread = (_unread - 1).clamp(0, 1 << 30);
      });
      _repo.markRead(n.id).catchError((_) {});
    }

    final dest = _destinationFor(n);
    if (dest != null && mounted) context.push(dest);
  }

  /// Where a notification leads. Null means there is nowhere useful to go.
  String? _destinationFor(AppNotification n) {
    final d = n.data;
    switch (n.type) {
      case 'new_message':
        final c = d['conversation_id'];
        return c == null ? '/chat' : '/chat/$c';
      case 'interest_received':
      case 'interest_accepted':
      case 'interest_rejected':
        return '/interests';
      case 'profile_viewed':
      case 'shortlisted':
        return '/activity';
      case 'contact_request':
      case 'contact_approved':
        return '/activity';
      case 'offer':
      case 'offer_expiring':
        return '/offers';
      case 'support_reply':
        // Straight into the thread. A support notification that lands on a
        // list is a second tap for someone already waiting on an answer.
        final ticket = d['ticket_id'];
        return ticket == null ? '/support' : '/support/$ticket';
      case 'checkout_reminder':
        return '/subscription';
      case 'subscription_expiring':
      case 'boost_expired':
        return '/subscription';
      case 'daily_matches':
        return '/discover';
      default:
        final sender = d['sender_id'] ?? d['requester_id'] ?? d['viewer_id'];
        return sender == null ? null : '/profile/$sender';
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'new_message':          return Icons.chat_bubble_rounded;
      case 'interest_received':    return Icons.favorite_rounded;
      case 'interest_accepted':    return Icons.celebration_rounded;
      case 'interest_rejected':    return Icons.heart_broken_rounded;
      case 'profile_viewed':       return Icons.visibility_rounded;
      case 'shortlisted':          return Icons.bookmark_rounded;
      case 'contact_request':
      case 'contact_approved':     return Icons.contact_phone_rounded;
      case 'offer':                return Icons.local_offer_rounded;
      case 'support_reply':        return Icons.support_agent_rounded;
      case 'checkout_reminder':    return Icons.shopping_cart_rounded;
      case 'offer_expiring':       return Icons.timer_outlined;
      case 'subscription_expiring':return Icons.workspace_premium_rounded;
      case 'daily_matches':        return Icons.auto_awesome_rounded;
      default:                     return Icons.notifications_rounded;
    }
  }

  Color _tintFor(String type) {
    switch (type) {
      case 'offer':
      case 'offer_expiring':
      case 'checkout_reminder':
        return AppColors.rose;
      case 'support_reply':
        return AppColors.gold;
      case 'interest_accepted':
        return AppColors.gold;
      default:
        return AppColors.textSecondary;
    }
  }

  String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return DateFormat('dd MMM').format(t);
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
        title: Row(
          children: [
            Text('Notifications', style: AppTextStyles.headlineSmall),
            if (_unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('$_unread',
                    style: AppTextStyles.overline.copyWith(color: AppColors.textOnGold)),
              ),
            ],
          ],
        ),
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold)),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _empty(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load notifications',
        subtitle: 'Pull down to try again.',
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.gold,
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.22),
            _empty(
              icon: Icons.notifications_none_rounded,
              title: 'Nothing yet',
              subtitle: 'Interests, messages and offers will show up here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
                ),
              ),
            );
          }

          final n = _items[i];
          final tint = _tintFor(n.type);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(n),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  // Unread is carried by the surface, not by a dot alone — the
                  // list should be scannable without hunting for markers.
                  color: n.isRead ? AppColors.surface : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: n.isRead ? AppColors.surface : AppColors.goldMild,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: tint.withAlpha(28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_iconFor(n.type), size: 17, color: tint),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title, style: AppTextStyles.labelLarge),
                          if (n.body.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              n.body,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_when(n.createdAt),
                        style: AppTextStyles.overline
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
