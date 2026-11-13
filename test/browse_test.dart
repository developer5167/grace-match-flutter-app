import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/utils/profile_code.dart';
import 'package:grace_match/features/discover/bloc/discover_bloc.dart';
import 'package:grace_match/features/discover/bloc/discover_event.dart';
import 'package:grace_match/features/discover/bloc/discover_filters.dart';
import 'package:grace_match/features/discover/bloc/discover_state.dart';
import 'package:grace_match/features/discover/data/discover_repository.dart';

/// Feed served from a list; counts any call for already-seen profiles.
class FakeRepo extends DiscoverRepository {
  FakeRepo(this.feed);
  final List<Map<String, dynamic>> feed;
  int seenCalls = 0;

  @override
  Future<({List<Map<String, dynamic>> profiles, bool limitReached})> fetchFeed({
    int page = 1,
    int limit = 10,
    DiscoverFilters? filters,
  }) async => (profiles: feed, limitReached: false);

  @override
  Future<({List<Map<String, dynamic>> profiles, bool hasMore, int total})>
  fetchSeen({
    int page = 1,
    int limit = 20,
    String? q,
    String? action,
    DiscoverFilters? filters,
  }) async {
    seenCalls++;
    return (profiles: <Map<String, dynamic>>[], hasMore: false, total: 0);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDailyMatches() async => [];
}

void main() {
  test('Discover shows new people only; seen ones live in Browse', () async {
    final repo = FakeRepo([]);
    final bloc = DiscoverBloc(repo);
    bloc.add(const FetchFeedEvent());
    final s =
        await bloc.stream.firstWhere((s) => s is DiscoverLoaded)
            as DiscoverLoaded;
    expect(s.profiles, isEmpty);
    expect(repo.seenCalls, 0);
    await bloc.close();
  });

  test('profile ID is GM- and the first 8 characters, uppercased', () {
    expect(profileCode('5786407d-11f8-4f98-8221-6871f9398f0d'), 'GM-5786407D');
    expect(profileCode(null), '');
  });
}
