import 'package:equatable/equatable.dart';
import 'discover_filters.dart';

abstract class DiscoverEvent extends Equatable {
  const DiscoverEvent();

  @override
  List<Object?> get props => [];
}

class FetchFeedEvent extends DiscoverEvent {
  final int page;
  final DiscoverFilters? filters;
  const FetchFeedEvent({this.page = 1, this.filters});

  @override
  List<Object?> get props => [page, filters];
}

/// More profiles for the current feed, appended to the ones already loaded.
class FetchMoreFeedEvent extends DiscoverEvent {
  const FetchMoreFeedEvent();
}

class FetchDailyMatchesEvent extends DiscoverEvent {
  const FetchDailyMatchesEvent();
}

class SwipeProfileEvent extends DiscoverEvent {
  final String targetUserId;
  final bool isInterest;
  final bool isSuperInterest;

  const SwipeProfileEvent({
    required this.targetUserId,
    required this.isInterest,
    this.isSuperInterest = false,
  });

  @override
  List<Object?> get props => [targetUserId, isInterest, isSuperInterest];
}

/// The member answered [targetUserId] outside [SwipeProfileEvent] (an
/// interest sent and confirmed from the list). Only recorded, so paging
/// knows the server will no longer return them.
class ProfileActedEvent extends DiscoverEvent {
  final String targetUserId;
  const ProfileActedEvent(this.targetUserId);

  @override
  List<Object?> get props => [targetUserId];
}
