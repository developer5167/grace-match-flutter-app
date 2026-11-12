import 'package:equatable/equatable.dart';
import 'discover_filters.dart';

abstract class DiscoverState extends Equatable {
  const DiscoverState();

  @override
  List<Object?> get props => [];
}

class DiscoverInitial extends DiscoverState {}

class DiscoverLoading extends DiscoverState {}

class DiscoverLoaded extends DiscoverState {
  final List<Map<String, dynamic>> profiles;
  final bool hasReachedMax;
  final DiscoverFilters activeFilters;
  final List<Map<String, dynamic>> dailyMatches;
  final bool limitReached;

  /// Bumped each time the feed is replaced (first load, refresh, new
  /// filters), not when more profiles are appended. Discover goes back to the
  /// first card when it changes.
  final int generation;

  const DiscoverLoaded({
    required this.profiles,
    this.hasReachedMax = false,
    this.activeFilters = const DiscoverFilters(),
    this.dailyMatches = const [],
    this.limitReached = false,
    this.generation = 0,
  });

  DiscoverLoaded copyWith({
    List<Map<String, dynamic>>? profiles,
    bool? hasReachedMax,
    DiscoverFilters? activeFilters,
    List<Map<String, dynamic>>? dailyMatches,
    bool? limitReached,
    int? generation,
  }) {
    return DiscoverLoaded(
      profiles: profiles ?? this.profiles,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      activeFilters: activeFilters ?? this.activeFilters,
      dailyMatches: dailyMatches ?? this.dailyMatches,
      limitReached: limitReached ?? this.limitReached,
      generation: generation ?? this.generation,
    );
  }

  @override
  List<Object?> get props => [
    profiles,
    hasReachedMax,
    activeFilters,
    dailyMatches,
    limitReached,
    generation,
  ];
}

class DiscoverError extends DiscoverState {
  final String message;
  const DiscoverError(this.message);

  @override
  List<Object?> get props => [message];
}
