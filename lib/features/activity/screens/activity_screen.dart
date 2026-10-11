import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../bloc/activity_bloc.dart';
import '../bloc/activity_event.dart';
import '../bloc/activity_state.dart';
import 'package:intl/intl.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    context.read<ActivityBloc>().add(const FetchActivityEvent());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActivityBloc, ActivityState>(
      builder: (context, state) {
        final loaded = state is ActivityLoaded ? state : null;
        final unread = loaded?.unreadNotifications ?? 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            centerTitle: false,
            title: Text('Activity', style: AppTextStyles.headlineLarge),
            actions: [
              if (unread > 0)
                TextButton.icon(
                  onPressed: () {
                    AppHaptics.light();
                    context.read<ActivityBloc>().add(const MarkAllReadEvent());
                  },
                  icon: const Icon(Icons.done_all_rounded, size: 18, color: AppColors.gold),
                  label: Text('Mark all read',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold)),
                ),
              IconButton(
                tooltip: 'All notifications',
                onPressed: () {
                  AppHaptics.selection();
                  context.push('/notifications');
                },
                icon: const Icon(Icons.history_rounded,
                    size: 19, color: AppColors.textSecondary),
              ),
              IconButton(
                tooltip: 'Offers',
                onPressed: () {
                  AppHaptics.selection();
                  context.push('/offers');
                },
                icon: const Icon(Icons.local_offer_outlined,
                    size: 19, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 4),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.gold,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: AppTextStyles.labelMedium,
              dividerColor: AppColors.surfaceHighest,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Notifications'),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        _badge(unread),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Views'),
                const Tab(text: 'Shortlisted'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Contacts'),
                      Builder(builder: (context) {
                        final pendingCount = loaded?.contactRequests
                                .where((r) => r['status'] == 'pending')
                                .length ??
                            0;
                        if (pendingCount == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            _badge(pendingCount),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: state is ActivityLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : state is ActivityError
                  ? _buildError(state.message)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _NotificationsTab(
                          notifications: loaded?.notifications ?? [],
                          onRefresh: () {
                            context.read<ActivityBloc>().add(const FetchNotificationsEvent());
                          },
                        ),
                        _ViewsTab(
                          viewers: loaded?.viewers ?? [],
                          totalViews: loaded?.totalViews ?? 0,
                          isPremiumRequired: loaded?.viewsPremiumRequired ?? false,
                          onRefresh: () {
                            context.read<ActivityBloc>().add(const FetchViewsEvent());
                          },
                        ),
                        _ShortlistsTab(
                          profiles: loaded?.shortlists ?? [],
                          onRefresh: () {
                            context.read<ActivityBloc>().add(const FetchShortlistsEvent());
                          },
                        ),
                        _ContactRequestsTab(
                          requests: loaded?.contactRequests ?? [],
                          onRefresh: () {
                            context.read<ActivityBloc>().add(const FetchContactRequestsEvent());
                          },
                          onRespond: (id, action) {
                            context.read<ActivityBloc>().add(RespondContactRequestEvent(id, action));
                          },
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textOnGold,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildError(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 12),
            Text(msg, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.read<ActivityBloc>().add(const FetchActivityEvent()),
              child: Text('Retry', style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
            ),
          ],
        ),
      );
}

// ───────────────────────────────────────────────────────────────
// NOTIFICATIONS TAB
// ───────────────────────────────────────────────────────────────
class _NotificationsTab extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onRefresh;

  const _NotificationsTab({required this.notifications, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return _emptyState(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        subtitle: 'Interests, views, and messages will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.gold,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final n = notifications[i];
          final isRead = n['is_read'] == true;
          return _NotifTile(n: n, isRead: isRead)
              .animate()
              .fadeIn(duration: 300.ms, delay: (i * 40).ms);
        },
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> n;
  final bool isRead;
  const _NotifTile({required this.n, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final type = n['type']?.toString() ?? '';
    return Material(
      color: isRead ? AppColors.surfaceElevated : AppColors.goldSubtle,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          AppHaptics.light();
          if (!isRead) {
            context.read<ActivityBloc>().add(MarkOneReadEvent(n['id'].toString()));
          }
          _handleTap(context, type, n['data']);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typeIcon(type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n['title']?.toString() ?? '',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n['body']?.toString() ?? '',
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(n['created_at']?.toString()),
                      style: AppTextStyles.labelSmall,
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4, left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'interest_received':
        icon = Icons.favorite_rounded;
        color = AppColors.rose;
        break;
      case 'interest_accepted':
        icon = Icons.check_circle_rounded;
        color = AppColors.blessing;
        break;
      case 'new_message':
        icon = Icons.chat_bubble_rounded;
        color = AppColors.cross;
        break;
      case 'profile_viewed':
        icon = Icons.visibility_rounded;
        color = AppColors.gold;
        break;
      case 'shortlisted':
        icon = Icons.star_rounded;
        color = AppColors.gold;
        break;
      case 'contact_request':
        icon = Icons.contact_phone_rounded;
        color = AppColors.warning;
        break;
      default:
        icon = Icons.notifications_rounded;
        color = AppColors.textSecondary;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _handleTap(BuildContext context, String type, dynamic data) {
    final d = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    switch (type) {
      case 'interest_received':
        // Open the sender's profile — bottom bar shows Accept / Decline
        final senderId = d['sender_id']?.toString();
        if (senderId != null) context.push('/profile/$senderId');
        break;
      case 'interest_accepted':
        // They accepted → go straight to conversations
        final convId = d['conversation_id']?.toString();
        if (convId != null) {
          context.push('/chat/$convId', extra: {'name': 'Match'});
        } else {
          context.go('/chat');
        }
        break;
      case 'new_message':
        final convId = d['conversation_id']?.toString();
        if (convId != null) {
          context.push('/chat/$convId', extra: {'name': 'Message'});
        } else {
          context.go('/chat');
        }
        break;
      case 'profile_viewed':
      case 'shortlisted':
        final actorId = d['actor_id']?.toString();
        if (actorId != null) context.push('/profile/$actorId');
        break;
      case 'contact_request':
        // Go to conversations list, owner can decide there
        context.go('/chat');
        break;
      default:
        break;
    }
  }

  String _relativeTime(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// ───────────────────────────────────────────────────────────────
// VIEWS TAB
// ───────────────────────────────────────────────────────────────
class _ViewsTab extends StatelessWidget {
  final List<Map<String, dynamic>> viewers;
  final int totalViews;
  final bool isPremiumRequired;
  final VoidCallback onRefresh;

  const _ViewsTab({
    required this.viewers,
    required this.totalViews,
    required this.isPremiumRequired,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.gold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Stats card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.goldSubtle,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.goldMild),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_rounded, color: AppColors.gold, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$totalViews', style: AppTextStyles.headlineLarge),
                    Text('Profile views', style: AppTextStyles.bodySmall),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 20),
          if (isPremiumRequired) ...[
            _PremiumGate(
              message: 'Upgrade to Silver or above to see who viewed your profile.',
              onTap: () => context.push('/subscription'),
            ),
          ] else if (viewers.isEmpty) ...[
            _emptyState(
              icon: Icons.visibility_off_rounded,
              title: 'No views yet',
              subtitle: 'When someone opens your profile, they will appear here.',
            ),
          ] else ...[
            Text('Who viewed you', style: AppTextStyles.headlineSmall).animate().fadeIn(duration: 200.ms),
            const SizedBox(height: 12),
            ...viewers.asMap().entries.map((entry) {
              final i = entry.key;
              final v = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProfileMiniCard(profile: v, onTap: () {
                  final uid = v['user_id']?.toString();
                  if (uid != null) context.push('/profile/$uid');
                })
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (i * 50).ms),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// SHORTLISTS TAB
// ───────────────────────────────────────────────────────────────
class _ShortlistsTab extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onRefresh;

  const _ShortlistsTab({required this.profiles, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return _emptyState(
        icon: Icons.star_border_rounded,
        title: 'No shortlisted profiles',
        subtitle: "Tap ⭐ on someone's profile to save them here for later.",
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.gold,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: profiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = profiles[i];
          return _ProfileMiniCard(
            profile: p,
            trailing: IconButton(
              icon: const Icon(Icons.star_rounded, color: AppColors.gold),
              onPressed: () {
                AppHaptics.medium();
                context.read<ActivityBloc>().add(ToggleShortlistEvent(p['user_id'].toString()));
              },
            ),
            onTap: () {
              final uid = p['user_id']?.toString();
              if (uid != null) context.push('/profile/$uid');
            },
          ).animate().fadeIn(duration: 300.ms, delay: (i * 40).ms);
        },
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ───────────────────────────────────────────────────────────────
class _ProfileMiniCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ProfileMiniCard({
    required this.profile,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile['first_name']?.toString() ?? 'Member';
    final age = profile['age'];
    final city = profile['location_city']?.toString() ?? '';
    final denom = profile['denomination']?.toString() ?? '';
    final photoUrl = profile['photo_url']?.toString();
    final isTrusted = profile['trust_badge'] == true;

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceHighest,
                  border: Border.all(color: AppColors.goldMild),
                  image: photoUrl != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(photoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: photoUrl == null
                    ? const Icon(Icons.person_rounded, color: AppColors.textTertiary)
                    : null,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          age != null ? '$name, $age' : name,
                          style: AppTextStyles.labelLarge,
                        ),
                        if (isTrusted) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, color: AppColors.blessing, size: 14),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [if (denom.isNotEmpty) denom, if (city.isNotEmpty) city].join(' • '),
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumGate extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  const _PremiumGate({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldMild),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_rounded, color: AppColors.gold, size: 40),
          const SizedBox(height: 12),
          Text('Premium Feature', style: AppTextStyles.headlineSmall),
          const SizedBox(height: 8),
          Text(message,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.textOnGold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: onTap,
            child: Text('Upgrade Plan', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textOnGold)),
          ),
        ],
      ),
    );
  }
}

Widget _emptyState({required IconData icon, required String title, required String subtitle}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(subtitle,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

// ─── Contacts Tab ─────────────────────────────────────────────
class _ContactRequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final VoidCallback onRefresh;
  final void Function(String id, String action) onRespond;

  const _ContactRequestsTab({
    required this.requests,
    required this.onRefresh,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return _emptyState(
        icon: Icons.contacts_rounded,
        title: 'No Contact Requests',
        subtitle: "When someone requests your contact details, they'll appear here.",
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, i) {
          final r = requests[i];
          final status = r['status'] as String? ?? 'pending';
          final name   = r['first_name'] as String? ?? 'Someone';
          final photo  = r['primary_photo'] as String?;
          final userId = r['user_id']?.toString();
          final reqAt = r['requested_at'] ?? r['created_at'];
          final date   = reqAt != null
              ? DateFormat('dd MMM').format(DateTime.parse(reqAt.toString()))
              : '';
          final id = r['id']?.toString() ?? '';

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: userId == null
                  ? null
                  : () {
                      AppHaptics.selection();
                      context.push('/profile/$userId?source=activity');
                    },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: status == 'pending'
                        ? AppColors.goldMild
                        : status == 'approved'
                            ? Colors.green.withAlpha(80)
                            : AppColors.surfaceHighest,
                  ),
                ),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.surface,
                      backgroundImage: photo != null ? CachedNetworkImageProvider(photo) : null,
                      child: photo == null ? const Icon(Icons.person, color: AppColors.textTertiary) : null,
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.labelLarge),
                          const SizedBox(height: 2),
                          Text(
                            '${r['profession'] ?? ''} ${r['denomination'] != null ? '· ${r['denomination']}' : ''}'.trim(),
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(date, style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Action area
                    if (status == 'pending')
                      Row(
                        children: [
                          // Decline
                          GestureDetector(
                            onTap: () {
                              AppHaptics.light();
                              onRespond(id, 'reject');
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.error.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.error.withAlpha(60)),
                              ),
                              child: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Approve
                          GestureDetector(
                            onTap: () async {
                              AppHaptics.heavy();
                              final confirmed = await _confirmAccept(context, name);
                              if (confirmed == true) onRespond(id, 'approve');
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withAlpha(80)),
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                            ),
                          ),
                        ],
                      )
                    // Sharing your number is not a one-way door. An approval
                    // can be taken back, so the "Shared" chip is the control
                    // for undoing it rather than a read-only label.
                    else if (status == 'approved')
                      GestureDetector(
                        onTap: () async {
                          AppHaptics.light();
                          final confirmed = await _confirmRevoke(context, name);
                          if (confirmed == true) onRespond(id, 'revoke');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(25),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: Colors.green.withAlpha(60)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Shared',
                                style: AppTextStyles.overline.copyWith(color: Colors.green),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 14, color: Colors.green.withAlpha(180)),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          status == 'revoked' ? 'Withdrawn' : 'Declined',
                          style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
        },
      ),
    );
  }

  Future<bool?> _confirmAccept(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Share your number?', style: AppTextStyles.labelLarge),
        content: Text(
          'By accepting, your number will also be revealed to $name automatically. '
          'This counts as one contact reveal on the requester\'s plan.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Not now',
                style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Accept and share',
                style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }

  /// Confirm before withdrawing. Revoking is not destructive enough to warn
  /// about in red, but it is a real change to someone else's access, so it
  /// should not happen on a stray tap.
  Future<bool?> _confirmRevoke(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Stop sharing your number?', style: AppTextStyles.labelLarge),
        content: Text(
          '$name will no longer be able to see your contact details. '
          'This reveal still counts on the plan for this month.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep sharing',
                style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Stop sharing',
                style: AppTextStyles.labelMedium.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
