import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/utils/profile_code.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../../discover/bloc/discover_filters.dart';
import '../../discover/data/discover_repository.dart';
import '../../discover/widgets/discover_filter_sheet.dart';

/// Browse tab. Lists the profiles this member has come across on Discover,
/// with filters and paging, and opens any profile by its ID ("GM-…"), seen or
/// not and whatever the Discover daily limit, so a shared profile can always
/// be found. Kept off Discover on purpose: Discover is for new people.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _pageSize = 20;
  static const _denominations = {
    'protestant': 'Protestant',
    'catholic': 'Catholic',
    'orthodox': 'Orthodox',
    'csi': 'CSI',
    'pentecostal': 'Pentecostal',
    'born_again': 'Born Again',
    'other': 'Other',
  };

  final _repo = DiscoverRepository();
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  String?
  _action; // null = all, 'liked' (interest sent), 'passed' (not contacted)
  DiscoverFilters _filters = DiscoverFilters.defaults();
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  // Bumped on every new search; answers to an older one are dropped.
  int _query = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _query++;
    setState(() {
      _items.clear();
      _page = 0;
      _total = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final query = _query;
    setState(() => _loading = true);
    try {
      final res = await _repo.fetchSeen(
        page: _page + 1,
        limit: _pageSize,
        q: _search.text,
        action: _action,
        filters: _filters.isDefault ? null : _filters,
      );
      if (!mounted || query != _query) return;
      setState(() {
        _page++;
        _items.addAll(res.profiles);
        _total = res.total;
        _hasMore = res.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || query != _query) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  Future<void> _openFilters() async {
    AppHaptics.light();
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscoverFilterSheet(currentFilters: _filters),
    );
    if (result != null && mounted) {
      _filters = result;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = !_filters.isDefault;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Browse', style: AppTextStyles.headlineLarge),
                      Text(
                        'Find any profile by its ID',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    icon: Badge(
                      isLabelVisible: hasFilters,
                      backgroundColor: AppColors.gold,
                      smallSize: 8,
                      child: Icon(Icons.tune_rounded, color: AppColors.gold),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by name or profile ID (GM-…)',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.gold),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            _search.clear();
                            _reload();
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.surfaceHighest,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.surfaceHighest,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.gold),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('All', null),
                  _chip('Interest sent', 'liked'),
                  _chip('Not contacted', 'passed'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _page == 0 && _loading
                      ? ' '
                      : '$_total profile${_total == 1 ? '' : 's'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? action) {
    final selected = _action == action;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          if (selected) return;
          AppHaptics.light();
          _action = action;
          _reload();
        },
        labelStyle: AppTextStyles.labelMedium.copyWith(
          color: selected ? AppColors.textOnGold : AppColors.textSecondary,
        ),
        selectedColor: AppColors.gold,
        backgroundColor: AppColors.surfaceElevated,
        side: BorderSide(
          color: selected ? AppColors.gold : AppColors.surfaceHighest,
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty && _loading) {
      return const SkeletonList(padding: EdgeInsets.fromLTRB(20, 8, 20, 0));
    }
    if (_items.isEmpty && _error != null) {
      return _message(
        Icons.wifi_off_rounded,
        'Could not load',
        _error!,
        action: TextButton(
          onPressed: _reload,
          child: Text('Try again', style: TextStyle(color: AppColors.gold)),
        ),
      );
    }
    if (_items.isEmpty) {
      final text = _search.text.trim();
      if (_looksLikeId(text)) {
        return _message(
          Icons.badge_outlined,
          'No profile with this ID',
          'Check the ID and try again. Profiles that are hidden, under review '
              'or blocked cannot be opened.',
        );
      }
      final searching =
          text.isNotEmpty || !_filters.isDefault || _action != null;
      return _message(
        Icons.manage_search_rounded,
        searching ? 'No one matches' : 'Nothing here yet',
        searching
            ? 'Try another name, profile ID or filter.'
            : 'Profiles you come across on Discover appear here. To open a '
                  'profile someone shared, search its ID.',
      );
    }
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _error != null
                    ? TextButton(
                        onPressed: _loadMore,
                        child: Text(
                          'Load more',
                          style: TextStyle(color: AppColors.gold),
                        ),
                      )
                    : SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      ),
              ),
            );
          }
          return _tile(_items[i]);
        },
      ),
    );
  }

  Widget _tile(Map<String, dynamic> p) {
    final id = (p['id'] ?? p['user_id'])?.toString() ?? '';
    final photo = thumbOr(p, 'primary_photo_200', 'primary_photo');
    final name = p['name']?.toString() ?? p['first_name']?.toString() ?? '—';
    final age = p['age'];
    final city = p['city']?.toString() ?? p['location_city']?.toString();
    final denom = _denominations[p['denomination']?.toString()];
    final code = p['profile_code']?.toString() ?? profileCode(id);
    final details = [
      city,
      denom,
    ].whereType<String>().where((s) => s.isNotEmpty);

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: id.isEmpty ? null : () => context.push('/profile/$id'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.surfaceHighest,
                backgroundImage: photo == null
                    ? null
                    : avatarImage(context, photo, 56),
                child: photo == null
                    ? Icon(Icons.person, color: AppColors.gold)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
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
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      code,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _status(p),
                  if (p['seen_action'] == 'liked') const SizedBox(height: 6),
                  if (p['seen_action'] == 'liked')
                    Text(
                      _when(p['seen_at']),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "GM-5786407D" or 8+ hex digits: searched across every member.
  static bool _looksLikeId(String text) => RegExp(
    r'^(gm[-\s]?)?[0-9a-f]{8}[0-9a-f-]*$',
    caseSensitive: false,
  ).hasMatch(text.trim());

  /// Only what is worth knowing at a glance; nothing for profiles simply
  /// come across.
  Widget _status(Map<String, dynamic> p) {
    if (p['seen_action'] != 'liked') return const SizedBox.shrink();
    final status = p['interest_status']?.toString();
    final (String text, Color color) = status == 'accepted'
        ? ('Connected', AppColors.success)
        : status == 'rejected'
        ? ('Declined', AppColors.error)
        : ('Interest sent', AppColors.gold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: AppTextStyles.labelSmall.copyWith(color: color)),
    );
  }

  static String _when(Object? iso) {
    final t = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (t == null) return '';
    final days = DateTime.now().difference(t).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${t.day} ${months[t.month - 1]}';
  }

  Widget _message(IconData icon, String title, String hint, {Widget? action}) {
    return ListView(
      // Scrollable so pull-to-refresh style gestures do not feel dead.
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
      children: [
        Icon(icon, size: 48, color: AppColors.goldMild),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(child: action),
        ],
      ],
    );
  }
}
