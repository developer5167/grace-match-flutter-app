import 'package:flutter_bloc/flutter_bloc.dart';
import 'discover_event.dart';
import 'discover_state.dart';
import 'discover_filters.dart';
import '../data/discover_repository.dart';

class DiscoverBloc extends Bloc<DiscoverEvent, DiscoverState> {
  final DiscoverRepository _repository;
  int _currentPage = 1;
  DiscoverFilters _activeFilters = DiscoverFilters.defaults();

  DiscoverBloc(this._repository) : super(DiscoverInitial()) {
    on<FetchFeedEvent>(_onFetchFeed);
    on<FetchDailyMatchesEvent>(_onFetchDailyMatches);
    on<SwipeProfileEvent>(_onSwipeProfile);
  }

  Future<void> _onFetchFeed(FetchFeedEvent event, Emitter<DiscoverState> emit) async {
    if (state is DiscoverInitial) emit(DiscoverLoading());
    try {
      _currentPage = event.page;
      if (event.filters != null) _activeFilters = event.filters!;

      final feed = await _repository.fetchFeed(
        page: _currentPage,
        filters: _activeFilters,
      );

      final existing = state is DiscoverLoaded ? (state as DiscoverLoaded) : null;
      emit(DiscoverLoaded(
        profiles: feed.profiles,
        hasReachedMax: feed.profiles.length < 10 || feed.limitReached,
        activeFilters: _activeFilters,
        dailyMatches: existing?.dailyMatches ?? [],
        limitReached: feed.limitReached,
      ));

      // Fetch daily matches in parallel on first load
      if (existing == null || existing.dailyMatches.isEmpty) {
        add(const FetchDailyMatchesEvent());
      }
    } catch (e) {
      emit(DiscoverError(e.toString()));
    }
  }

  Future<void> _onFetchDailyMatches(
      FetchDailyMatchesEvent event, Emitter<DiscoverState> emit) async {
    try {
      final matches = await _repository.fetchDailyMatches();
      if (state is DiscoverLoaded) {
        emit((state as DiscoverLoaded).copyWith(dailyMatches: matches));
      }
    } catch (_) {
      // Daily matches are non-critical — silently ignore failures
    }
  }

  Future<void> _onSwipeProfile(SwipeProfileEvent event, Emitter<DiscoverState> emit) async {
    try {
      if (event.isInterest) {
        await _repository.sendInterest(event.targetUserId,
            isSuperInterest: event.isSuperInterest);
      } else {
        await _repository.passProfile(event.targetUserId);
      }
    } catch (e) {
      print('Swipe Error: $e');
    }
  }
}
