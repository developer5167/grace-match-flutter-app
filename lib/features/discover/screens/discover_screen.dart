import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../widgets/profile_card.dart';
import '../widgets/action_buttons.dart';
import '../widgets/device_tilt.dart';
import '../widgets/discover_filter_sheet.dart';
import '../bloc/discover_bloc.dart';
import '../bloc/discover_event.dart';
import '../bloc/discover_state.dart';
import '../bloc/discover_filters.dart';
import '../data/discover_repository.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  int _currentIndex = 0;
  // Set while a super interest is on its way; stops a second tap sending it
  // twice (or to the next card) before the first returns.
  bool _superBusy = false;
  // Bumped to rebuild the top card from scratch, centred: a drag-swipe made
  // while a super interest was out was ignored and left the card off-screen.
  int _cardEpoch = 0;
  List<Map<String, dynamic>> _profiles = [];
  // Feed generation the deck position belongs to. A replaced feed starts at
  // its first card.
  int? _generation;
  final Set<String> _precached = {};

  @override
  void initState() {
    super.initState();
    context.read<DiscoverBloc>().add(const FetchFeedEvent());
  }

  void _onSwipe(bool liked, {bool superLike = false}) async {
    if (_superBusy || _currentIndex >= _profiles.length) return;

    final currentProfile = _profiles[_currentIndex];

    if (superLike) {
      _superBusy = true;
      try {
        await DiscoverRepository().sendInterest(
          currentProfile['id'].toString(),
          isSuperInterest: true,
        );
      } catch (e) {
        _superBusy = false;
        if (!mounted) return;
        setState(() => _cardEpoch++);
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
        final lower = msg.toLowerCase();
        if (lower.contains('plan') ||
            lower.contains('upgrade') ||
            lower.contains('super')) {
          context.push('/subscription');
        }
        return;
      }
      _superBusy = false;
      if (!mounted) return;
      _advanceCard(liked: true);
      return;
    }

    context.read<DiscoverBloc>().add(
      SwipeProfileEvent(
        targetUserId: currentProfile['id'].toString(),
        isInterest: liked,
      ),
    );

    _advanceCard(liked: liked);
  }

  void _advanceCard({required bool liked}) {
    // Fired, not awaited: the next card shows at once.
    if (liked) {
      AppHaptics.heavy();
    } else {
      AppHaptics.light();
    }
    setState(() => _currentIndex++);
    _maybeFetchMore();
  }

  /// Top the deck up while a few cards are still left to swipe.
  void _maybeFetchMore() {
    final state = context.read<DiscoverBloc>().state;
    if (state is! DiscoverLoaded || state.hasReachedMax) return;
    if (_profiles.length - _currentIndex <= 3) {
      context.read<DiscoverBloc>().add(const FetchMoreFeedEvent());
    }
  }

  /// Start downloading the photos the member will see next, at the size the
  /// card decodes them, so the next swipe does not land on a spinner.
  void _precacheUpcoming() {
    final urls = <String>[
      if (_currentIndex + 1 < _profiles.length)
        ...?ProfileCard.photoUrls(_profiles[_currentIndex + 1]),
      if (_currentIndex + 2 < _profiles.length)
        ...?ProfileCard.photoUrls(_profiles[_currentIndex + 2])?.take(1),
    ].where(_precached.add).toList();
    if (urls.isEmpty) return;
    final width = ProfileCard.photoDecodeWidth(context);
    for (final url in urls) {
      precacheImage(
        ResizeImage(CachedNetworkImageProvider(url), width: width),
        context,
        onError: (_, __) {},
      );
    }
  }

  Future<void> _openFilterSheet(DiscoverFilters current) async {
    AppHaptics.light();
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscoverFilterSheet(currentFilters: current),
    );
    if (result != null && mounted) {
      // The deck goes back to its first card when the filtered feed arrives.
      context.read<DiscoverBloc>().add(FetchFeedEvent(filters: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      builder: (context, state) {
        if ((state is DiscoverLoading || state is DiscoverInitial) &&
            _profiles.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(DiscoverFilters.defaults()),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: SkeletonCard(),
                    ),
                  ),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
                ],
              ),
            ),
          );
        }

        if (state is DiscoverError && _profiles.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        final activeFilters = state is DiscoverLoaded
            ? state.activeFilters
            : DiscoverFilters.defaults();
        final dailyMatches = state is DiscoverLoaded
            ? state.dailyMatches
            : <Map<String, dynamic>>[];

        if (state is DiscoverLoaded) {
          _profiles = state.profiles;
          if (_generation != state.generation) {
            // A new feed (refresh, filters, or the first load after coming
            // back to this tab) starts from its first card.
            _generation = state.generation;
            _currentIndex = 0;
          }
        }

        final hasProfiles = _currentIndex < _profiles.length;
        if (hasProfiles) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _precacheUpcoming();
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(activeFilters),
                if (dailyMatches.isNotEmpty) _buildDailyMatches(dailyMatches),
                Expanded(
                  child: hasProfiles
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_currentIndex + 1 < _profiles.length)
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    32,
                                    14,
                                    32,
                                    8,
                                  ),
                                  child: ProfileCard(
                                    profile: _profiles[_currentIndex + 1],
                                    scale: 0.95,
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  8,
                                ),
                                child: DeviceTilt(
                                  child: ProfileCard(
                                    key: ValueKey(
                                      '${_profiles[_currentIndex]['id']}#$_cardEpoch',
                                    ),
                                    profile: _profiles[_currentIndex],
                                    onSwipeLeft: () => _onSwipe(false),
                                    onSwipeRight: () => _onSwipe(true),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildEmptyState(),
                ),
                if (hasProfiles)
                  DiscoverActionButtons(
                    onPass: () => _onSwipe(false),
                    onInterest: () => _onSwipe(true),
                    onSuperInterest: () => _onSwipe(true, superLike: true),
                  ),
                // The shell's nav bar floats over the page (extendBody), and
                // Flutter reports its full height, home indicator included,
                // as bottom padding. A fixed 100 was shorter than the bar on
                // Face ID iPhones, so it covered the action buttons.
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
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
              Text('Discover', style: AppTextStyles.headlineLarge),
              Text(
                'Telugu Christian Matches',
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
  Widget _buildDailyMatches(List<Map<String, dynamic>> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.gold, size: 16),
              const SizedBox(width: 8),
              Text(
                "Today's Picks",
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.gold),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${matches.length} curated for you',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) {
              final m = matches[i];
              final photo = thumbOr(m, 'primary_photo_200', 'primary_photo');
              final name = m['first_name'] as String? ?? '?';
              final compat = m['compatibility'] as int? ?? 0;
              final uid = m['user_id']?.toString() ?? m['id']?.toString() ?? '';
              return GestureDetector(
                onTap: () {
                  if (uid.isNotEmpty) context.push('/profile/$uid');
                },
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.gold, width: 2),
                          ),
                          child: ClipOval(
                            child: photo != null
                                ? CachedNetworkImage(
                                    imageUrl: photo,
                                    fit: BoxFit.cover,
                                    memCacheWidth: decodePx(context, 56),
                                    placeholder: (_, __) => Container(
                                      color: AppColors.surfaceHighest,
                                    ),
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.person,
                                      color: AppColors.gold,
                                    ),
                                  )
                                : Container(
                                    color: AppColors.surfaceHighest,
                                    child: Icon(
                                      Icons.person,
                                      color: AppColors.gold,
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$compat%',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textOnGold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 60,
                      child: Text(
                        name,
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildEmptyState() {
    final limitReached =
        context.read<DiscoverBloc>().state is DiscoverLoaded &&
        (context.read<DiscoverBloc>().state as DiscoverLoaded).limitReached;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✝', style: TextStyle(fontSize: 56, color: AppColors.goldMild)),
          const SizedBox(height: 16),
          Text(
            limitReached
                ? "Today's matches are done"
                : "You've seen everyone for now",
            style: AppTextStyles.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            limitReached
                ? 'Upgrade for unlimited daily matches'
                : 'Check back tomorrow for new matches',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 24),
          // Browse is never limited: profiles already come across, and any
          // profile by its ID.
          OutlinedButton.icon(
            onPressed: () => context.go('/browse'),
            icon: Icon(Icons.manage_search_rounded, color: AppColors.gold),
            label: Text(
              'Browse profiles',
              style: TextStyle(color: AppColors.gold),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.gold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (limitReached)
            TextButton(
              onPressed: () => context.push('/subscription'),
              child: Text('See plans', style: TextStyle(color: AppColors.gold)),
            )
          else
            TextButton(
              // The deck goes back to its first card when the new feed
              // arrives (see `generation` in build).
              onPressed: () =>
                  context.read<DiscoverBloc>().add(const FetchFeedEvent()),
              child: Text(
                'Refresh Feed',
                style: TextStyle(color: AppColors.gold),
              ),
            ),
        ],
      ),
    );
  }
}
