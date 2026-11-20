import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'discover_event.dart';
import 'discover_state.dart';
import 'discover_filters.dart';
import '../data/discover_repository.dart';

class DiscoverBloc extends Bloc<DiscoverEvent, DiscoverState> {
  final DiscoverRepository _repository;
  int _currentPage = 1;
  DiscoverFilters _activeFilters = DiscoverFilters.defaults();
  int _generation = 0;
  bool _fetchingMore = false;
  // Everyone answered (interest or pass) since the feed was last replaced.
  // The server leaves them out, so they are not counted when asking for more.
  final Set<String> _acted = {};

  DiscoverBloc(this._repository) : super(DiscoverInitial()) {
    on<FetchFeedEvent>(_onFetchFeed);
    on<FetchMoreFeedEvent>(_onFetchMoreFeed);
    on<FetchDailyMatchesEvent>(_onFetchDailyMatches);
    on<SwipeProfileEvent>(_onSwipeProfile);
    on<ProfileActedEvent>((e, _) => _acted.add(e.targetUserId));
  }

  Future<void> _onFetchFeed(
    FetchFeedEvent event,
    Emitter<DiscoverState> emit,
  ) async {
    if (state is DiscoverInitial) emit(DiscoverLoading());
    _currentPage = event.page;
    if (event.filters != null) _activeFilters = event.filters!;

    // Today's picks do not depend on the feed, so both are asked for at once
    // on first load. Failures there are non-critical and silently ignored.
    final before = state is DiscoverLoaded ? state as DiscoverLoaded : null;
    final Future<List<Map<String, dynamic>>?>? dailyMatches =
        (before == null || before.dailyMatches.isEmpty)
        ? _repository.fetchDailyMatches().then<List<Map<String, dynamic>>?>(
            (m) => m,
            onError: (Object _) => null,
          )
        : null;

    try {
      final feed = await _repository.fetchFeed(
        page: _currentPage,
        filters: _activeFilters,
      );

      final existing = state is DiscoverLoaded
          ? (state as DiscoverLoaded)
          : null;
      _generation++;
      _acted.clear();
      emit(
        DiscoverLoaded(
          profiles: feed.profiles,
          hasReachedMax: feed.profiles.length < 10 || feed.limitReached,
          activeFilters: _activeFilters,
          dailyMatches: existing?.dailyMatches ?? [],
          limitReached: feed.limitReached,
          generation: _generation,
        ),
      );
    } catch (e) {
      emit(DiscoverError(e.toString()));
      return;
    }

    if (dailyMatches != null) {
      final matches = await dailyMatches;
      if (matches != null && state is DiscoverLoaded) {
        emit((state as DiscoverLoaded).copyWith(dailyMatches: matches));
      }
    }
  }

  /// Loads more of the list. Always page 1: the server leaves out everyone
  /// already answered, so offsets shift as the member acts. Instead page 1 is
  /// asked for everything still unanswered in the list plus 10 more, and
  /// anything already shown is dropped by id.
  Future<void> _onFetchMoreFeed(
    FetchMoreFeedEvent event,
    Emitter<DiscoverState> emit,
  ) async {
    final start = state;
    if (_fetchingMore || start is! DiscoverLoaded || start.hasReachedMax) {
      return;
    }
    _fetchingMore = true;
    try {
      final pending = start.profiles
          .where((p) => !_acted.contains(_idOf(p)))
          .length;
      final limit = (pending + 10).clamp(10, 100);
      final feed = await _repository.fetchFeed(
        page: 1,
        limit: limit,
        filters: _activeFilters,
      );
      final now = state;
      // Replaced meanwhile (refresh or new filters): these belong to the old
      // feed.
      if (now is! DiscoverLoaded || now.generation != start.generation) return;

      final seen = <String>{
        for (final p in now.profiles)
          if (_idOf(p) != null) _idOf(p)!,
      };
      final fresh = feed.profiles.where((p) {
        final id = _idOf(p);
        return id != null && seen.add(id);
      }).toList();

      emit(
        now.copyWith(
          profiles: fresh.isEmpty ? null : [...now.profiles, ...fresh],
          hasReachedMax:
              feed.profiles.length < limit ||
              fresh.isEmpty ||
              limit >= 100 ||
              feed.limitReached,
          limitReached: now.limitReached || feed.limitReached,
        ),
      );
    } catch (_) {
      // Non-critical: the list still has profiles and scrolling asks again.
    } finally {
      _fetchingMore = false;
    }
  }

  static String? _idOf(Map<String, dynamic> p) {
    final id = (p['id'] ?? p['user_id'])?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> _onFetchDailyMatches(
    FetchDailyMatchesEvent event,
    Emitter<DiscoverState> emit,
  ) async {
    try {
      final matches = await _repository.fetchDailyMatches();
      if (state is DiscoverLoaded) {
        emit((state as DiscoverLoaded).copyWith(dailyMatches: matches));
      }
    } catch (_) {
      // Daily matches are non-critical — silently ignore failures
    }
  }

  Future<void> _onSwipeProfile(
    SwipeProfileEvent event,
    Emitter<DiscoverState> emit,
  ) async {
    _acted.add(event.targetUserId);
    try {
      if (event.isInterest) {
        await _repository.sendInterest(
          event.targetUserId,
          isSuperInterest: event.isSuperInterest,
        );
      } else {
        await _repository.passProfile(event.targetUserId);
      }
    } catch (e) {
      debugPrint('Discover action failed: $e');
    }
  }
}
