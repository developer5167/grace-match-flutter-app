import 'package:flutter/material.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/l10n/app_language.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../widgets/profile_list_card.dart';
import '../widgets/device_tilt.dart';
import '../widgets/discover_filter_sheet.dart';
import '../bloc/discover_bloc.dart';
import '../bloc/discover_event.dart';
import '../bloc/discover_state.dart';
import '../bloc/discover_filters.dart';
import '../data/discover_repository.dart';

/// Discover: a scrolling list of reviewed profiles, each shown like a
/// marriage biodata with "Send interest" and "Not now". (Was a one-at-a-time
/// swipe deck; App Review read that as a dating app, guideline 4.3(b).)
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _scroll = ScrollController();
  final _repo = DiscoverRepository();
  // Per profile id: interest on its way or sent. Profiles put aside with
  // "Not now" are hidden for the rest of this feed.
  final Map<String, ListAction> _actions = {};
  final Set<String> _hidden = {};
  int? _generation;

  @override
  void initState() {
    super.initState();
    context.read<DiscoverBloc>().add(const FetchFeedEvent());
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _maybeFetchMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String _idOf(Map<String, dynamic> p) =>
      (p['id'] ?? p['user_id'])?.toString() ?? '';

  void _maybeFetchMore() {
    final state = context.read<DiscoverBloc>().state;
    if (state is! DiscoverLoaded || state.hasReachedMax) return;
    context.read<DiscoverBloc>().add(const FetchMoreFeedEvent());
  }

  Future<void> _sendInterest(String id, {bool priority = false}) async {
    if (id.isEmpty || _actions[id] != null) return;
    AppHaptics.heavy();
    setState(() => _actions[id] = ListAction.sending);
    try {
      await _repo.sendInterest(id, isSuperInterest: priority);
      if (!mounted) return;
      context.read<DiscoverBloc>().add(ProfileActedEvent(id));
      setState(() => _actions[id] = ListAction.sent);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            priority ? tr('Priority interest sent') : tr('Interest sent'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actions.remove(id));
      final msg = e.toString().replaceFirst('Exception: ', '');
      final lower = msg.toLowerCase();
      final needsPlan =
          lower.contains('plan') ||
          lower.contains('upgrade') ||
          lower.contains('limit') ||
          lower.contains('super');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.error,
          action: needsPlan
              ? SnackBarAction(
                  label: tr('See plans'),
                  textColor: Colors.white,
                  onPressed: () => context.push('/subscription'),
                )
              : null,
        ),
      );
    }
  }

  void _notNow(String id) {
    if (id.isEmpty) return;
    AppHaptics.light();
    context.read<DiscoverBloc>().add(
      SwipeProfileEvent(targetUserId: id, isInterest: false),
    );
    setState(() => _hidden.add(id));
    _maybeFetchMore();
  }

  Future<void> _openFilterSheet(DiscoverFilters current) async {
    AppHaptics.light();
    final result = await AppShell.withNavBarHidden(
      () => showModalBottomSheet<DiscoverFilters>(
        context: context,
        // Over the whole app, not just the tab: inside the tab the sheet kept
        // empty room at the bottom for the (hidden) bottom bar.
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DiscoverFilterSheet(currentFilters: current),
      ),
    );
    if (result != null && mounted) {
      context.read<DiscoverBloc>().add(FetchFeedEvent(filters: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      builder: (context, state) {
        if (state is DiscoverLoading || state is DiscoverInitial) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(DiscoverFilters.defaults()),
                  const Expanded(
                    child: SkeletonList(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (state is DiscoverError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(DiscoverFilters.defaults()),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.message,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => context.read<DiscoverBloc>().add(
                                const FetchFeedEvent(),
                              ),
                              child: Text(
                                tr('Try again'),
                                style: TextStyle(color: AppColors.gold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final loaded = state as DiscoverLoaded;
        if (_generation != loaded.generation) {
          // A replaced feed (refresh, filters) starts clean.
          _generation = loaded.generation;
          _actions.clear();
          _hidden.clear();
        }
        final profiles = loaded.profiles
            .where((p) => !_hidden.contains(_idOf(p)))
            .toList();
        final picks = loaded.dailyMatches;
        final bottom = MediaQuery.paddingOf(context).bottom + 24;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(loaded.activeFilters),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.gold,
                    onRefresh: () async => context.read<DiscoverBloc>().add(
                      FetchFeedEvent(filters: loaded.activeFilters),
                    ),
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
                      // Today's picks, the profiles, then the end message.
                      itemCount: 1 + profiles.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return picks.isEmpty
                              ? const SizedBox.shrink()
                              : _buildDailyMatches(picks);
                        }
                        if (i == profiles.length + 1) {
                          return loaded.hasReachedMax
                              ? _buildEndState(
                                  loaded.limitReached,
                                  empty: profiles.isEmpty,
                                )
                              : const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                        }
                        final p = profiles[i - 1];
                        final id = _idOf(p);
                        // The card tilts with the phone (as the old swipe
                        // card did), gently, so it stays easy to tap.
                        return DeviceTilt(
                          key: ValueKey(id),
                          maxAngle: 0.09,
                          borderRadius: BorderRadius.circular(20),
                          child: ProfileListCard(
                            profile: p,
                            action: _actions[id] ?? ListAction.none,
                            onOpen: () {
                              if (id.isNotEmpty) context.push('/profile/$id');
                            },
                            onInterest: () => _sendInterest(id),
                            onPriorityInterest: () =>
                                _sendInterest(id, priority: true),
                            onNotNow: () => _notNow(id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(DiscoverFilters activeFilters) {
    final hasFilters = !activeFilters.isDefault;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Discover'), style: AppTextStyles.headlineLarge),
              Text(
                tr('Reviewed profiles for marriage'),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.gold),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _openFilterSheet(activeFilters),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasFilters
                        ? AppColors.goldSubtle
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFilters
                          ? AppColors.gold
                          : AppColors.surfaceHighest,
                    ),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: hasFilters ? AppColors.gold : AppColors.gold,
                    size: 20,
                  ),
                ),
                if (hasFilters)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // ── Today's Picks ─────────────────────────────────────────────
  /// Today's recommendations: small biodata cards (photo, name, age,
  /// denomination and city). No score on the photo: a number on a face reads
  /// as rating people; compatibility is shown inside each profile card.
  Widget _buildDailyMatches(List<Map<String, dynamic>> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.gold, size: 16),
              const SizedBox(width: 8),
              Text(
                tr('Recommended for you today'),
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.gold),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 206,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            // Tilt with the phone, like the profile cards below.
            itemBuilder: (ctx, i) => DeviceTilt(
              maxAngle: 0.12,
              borderRadius: BorderRadius.circular(16),
              child: _pickCard(matches[i]),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _pickCard(Map<String, dynamic> m) {
    final photo = thumbOr(m, 'primary_photo_200', 'primary_photo');
    final name = m['first_name']?.toString() ?? 'Member';
    final age = m['age'];
    final uid = m['user_id']?.toString() ?? m['id']?.toString() ?? '';
    final denomEn = denominationLabels[m['denomination']?.toString()];
    final denom = denomEn == null ? null : tr(denomEn);
    final city = m['location_city']?.toString();
    final place = [
      if (denom != null) denom,
      if (city != null && city.isNotEmpty) city,
    ].join(' · ');
    const w = 132.0;
    return SizedBox(
      width: w,
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: uid.isEmpty ? null : () => context.push('/profile/$uid'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: w,
                height: 120,
                child: photo != null
                    ? CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.5),
                        memCacheWidth: decodePx(context, w),
                        placeholder: (_, __) =>
                            Container(color: AppColors.surfaceHighest),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.surfaceHighest,
                          child: Icon(Icons.person, color: AppColors.gold),
                        ),
                      )
                    : Container(
                        color: AppColors.surfaceHighest,
                        child: Icon(Icons.person, color: AppColors.gold),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      age == null ? name : '$name, $age',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (place.isNotEmpty)
                      Text(
                        place,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.gold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (m['profession'] != null)
                      Text(
                        m['profession'].toString(),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown below the last profile once there are no more to load.
  Widget _buildEndState(bool limitReached, {required bool empty}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✝', style: TextStyle(fontSize: 44, color: AppColors.goldMild)),
          const SizedBox(height: 12),
          Text(
            limitReached
                ? "You've seen today's profiles"
                : empty
                ? 'No new profiles right now'
                : "That's everyone for now",
            style: AppTextStyles.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            limitReached
                ? 'New profiles arrive tomorrow, or see plans for more each day.'
                : 'New members are reviewed by our team every day. Check back '
                      'soon, or widen your filters.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Browse is never limited: profiles already come across, and any
          // profile by its ID.
          OutlinedButton.icon(
            onPressed: () => context.go('/browse'),
            icon: Icon(Icons.manage_search_rounded, color: AppColors.gold),
            label: Text(
              tr('Browse profiles'),
              style: TextStyle(color: AppColors.gold),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.gold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (limitReached)
            TextButton(
              onPressed: () => context.push('/subscription'),
              child: Text(
                tr('See plans'),
                style: TextStyle(color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }
}
