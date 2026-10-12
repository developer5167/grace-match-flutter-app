import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../widgets/profile_card.dart';
import '../widgets/action_buttons.dart';
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
  bool _isAnimatingOut = false;
  List<Map<String, dynamic>> _profiles = [];

  @override
  void initState() {
    super.initState();
    context.read<DiscoverBloc>().add(const FetchFeedEvent());
  }

  void _onSwipe(bool liked, {bool superLike = false}) async {
    if (_isAnimatingOut || _currentIndex >= _profiles.length) return;

    final currentProfile = _profiles[_currentIndex];

    if (superLike) {
      try {
        await DiscoverRepository().sendInterest(
          currentProfile['id'].toString(),
          isSuperInterest: true,
        );
      } catch (e) {
        if (!mounted) return;
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
        final lower = msg.toLowerCase();
        if (lower.contains('plan') || lower.contains('upgrade') || lower.contains('super')) {
          context.push('/subscription');
        }
        return;
      }
      await _advanceCard(liked: true);
      return;
    }

    context.read<DiscoverBloc>().add(SwipeProfileEvent(
      targetUserId: currentProfile['id'].toString(),
      isInterest: liked,
    ));

    await _advanceCard(liked: liked);
  }

  Future<void> _advanceCard({required bool liked}) async {
    setState(() => _isAnimatingOut = true);

    if (liked) {
      await AppHaptics.heavy();
    } else {
      await AppHaptics.light();
    }

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    setState(() {
      _isAnimatingOut = false;
      _currentIndex++;
    });
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
      setState(() => _currentIndex = 0);
      context.read<DiscoverBloc>().add(FetchFeedEvent(filters: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      builder: (context, state) {
        if (state is DiscoverLoading && _profiles.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          );
        }

        if (state is DiscoverError && _profiles.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Text(state.message, style: const TextStyle(color: Colors.white)),
            ),
          );
        }

        final activeFilters = state is DiscoverLoaded
            ? state.activeFilters
            : DiscoverFilters.defaults();
        final dailyMatches = state is DiscoverLoaded ? state.dailyMatches : <Map<String, dynamic>>[];

        if (state is DiscoverLoaded) {
          _profiles = state.profiles;
        }

        final hasProfiles = _currentIndex < _profiles.length;

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
                                  padding: const EdgeInsets.fromLTRB(44, 20, 44, 80),
                                  child: ProfileCard(
                                    profile: _profiles[_currentIndex + 1],
                                    scale: 0.95,
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(24, 8, 24, 80),
                                child: ProfileCard(
                                  key: ValueKey(_profiles[_currentIndex]['id']),
                                  profile: _profiles[_currentIndex],
                                  onSwipeLeft: () => _onSwipe(false),
                                  onSwipeRight: () => _onSwipe(true),
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
                const SizedBox(height: 100),
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
                    color: hasFilters ? AppColors.goldSubtle : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFilters ? AppColors.gold : AppColors.surfaceHighest,
                    ),
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: hasFilters ? AppColors.gold : AppColors.gold, size: 20),
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
              Text("Today's Picks",
                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.gold)),
              const SizedBox(width: 6),
              Text('· ${matches.length} curated for you',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
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
              final photo = m['primary_photo'] as String?;
              final name  = m['first_name'] as String? ?? '?';
              final compat = m['compatibility'] as int? ?? 0;
              final uid   = m['user_id']?.toString() ?? m['id']?.toString() ?? '';
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
                                    placeholder: (_, __) =>
                                        Container(color: AppColors.surfaceHighest),
                                    errorWidget: (_, __, ___) =>
                                        Icon(Icons.person, color: AppColors.gold),
                                  )
                                : Container(
                                    color: AppColors.surfaceHighest,
                                    child: Icon(Icons.person, color: AppColors.gold),
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
    final limitReached = context.read<DiscoverBloc>().state is DiscoverLoaded &&
        (context.read<DiscoverBloc>().state as DiscoverLoaded).limitReached;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✝', style: TextStyle(fontSize: 56, color: AppColors.goldMild)),
          const SizedBox(height: 16),
          Text(
            limitReached ? "Today's matches are done" : "You've seen everyone for now",
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
          if (limitReached)
            TextButton(
              onPressed: () => context.push('/subscription'),
              child: Text('See plans', style: TextStyle(color: AppColors.gold)),
            )
          else
            TextButton(
              onPressed: () =>
                  context.read<DiscoverBloc>().add(const FetchFeedEvent()),
              child: Text('Refresh Feed', style: TextStyle(color: AppColors.gold)),
            ),
        ],
      ),
    );
  }
}
