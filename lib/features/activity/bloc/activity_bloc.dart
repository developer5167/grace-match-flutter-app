import 'package:flutter_bloc/flutter_bloc.dart';
import 'activity_event.dart';
import 'activity_state.dart';
import '../data/activity_repository.dart';

class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  final ActivityRepository _repository;
  bool _fetchingAll = false;

  ActivityBloc(this._repository) : super(ActivityInitial()) {
    on<FetchActivityEvent>(_onFetchAll);
    on<FetchNotificationsEvent>(_onFetchNotifications);
    on<FetchViewsEvent>(_onFetchViews);
    on<FetchShortlistsEvent>(_onFetchShortlists);
    on<MarkAllReadEvent>(_onMarkAllRead);
    on<MarkOneReadEvent>(_onMarkOneRead);
    on<ToggleShortlistEvent>(_onToggleShortlist);
    on<FetchContactRequestsEvent>(_onFetchContactRequests);
    on<RespondContactRequestEvent>(_onRespondContactRequest);
  }

  // ── Fetch everything via single bootstrap call ──────────────
  // Server uses Promise.allSettled so partial data is returned even
  // when one section fails. We never show a full-screen error here.
  Future<void> _onFetchAll(
    FetchActivityEvent event,
    Emitter<ActivityState> emit,
  ) async {
    // One bootstrap at a time.
    if (_fetchingAll) return;
    _fetchingAll = true;
    // Tabs already on screen stay there while they refresh.
    final hadData = state is ActivityLoaded;
    if (!hadData) emit(ActivityLoading());
    try {
      final d = await _repository.fetchBootstrap();

      emit(
        ActivityLoaded(
          notifications: _asList(d['notifications']),
          unreadNotifications: (d['unread_count'] as num?)?.toInt() ?? 0,
          viewers: _asList(d['viewers']),
          totalViews: (d['total_views'] as num?)?.toInt() ?? 0,
          viewsPremiumRequired: d['is_premium_views'] != true,
          shortlists: _asList(d['shortlists']),
          contactRequests: _asList(d['contact_requests']),
        ),
      );
    } catch (e) {
      // A failed refresh keeps what the member was looking at.
      if (!(hadData && state is ActivityLoaded)) {
        emit(ActivityError(e.toString()));
      }
    } finally {
      _fetchingAll = false;
    }
  }

  // Individual section refreshes — keep the rest of the screen intact
  Future<void> _onFetchNotifications(
    FetchNotificationsEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      final data = await _repository.fetchNotifications();
      final notifs = _asList(data['notifications']);
      final unread = notifs.where((n) => n['is_read'] != true).length;
      emit(
        (prev ?? const ActivityLoaded()).copyWith(
          notifications: notifs,
          unreadNotifications: unread,
        ),
      );
    } catch (_) {
      if (prev != null) emit(prev);
    }
  }

  Future<void> _onFetchViews(
    FetchViewsEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      final data = await _repository.fetchViews();
      emit(
        (prev ?? const ActivityLoaded()).copyWith(
          viewers: _asList(data['viewers']),
          totalViews: (data['total_views'] as num?)?.toInt() ?? 0,
          viewsPremiumRequired: data['is_premium_required'] == true,
        ),
      );
    } catch (_) {
      if (prev != null) emit(prev);
    }
  }

  Future<void> _onFetchShortlists(
    FetchShortlistsEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      final data = await _repository.fetchShortlists();
      emit(
        (prev ?? const ActivityLoaded()).copyWith(
          shortlists: _asList(data['profiles']),
        ),
      );
    } catch (_) {
      if (prev != null) emit(prev);
    }
  }

  Future<void> _onMarkAllRead(
    MarkAllReadEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    // Optimistic: the list is on screen and the call is idempotent.
    if (prev != null) {
      final updated = prev.notifications.map((n) {
        return {...n, 'is_read': true};
      }).toList();
      emit(prev.copyWith(notifications: updated, unreadNotifications: 0));
    }
    try {
      await _repository.markAllRead();
    } catch (_) {
      // Put the unread ones back as they were.
      final now = state is ActivityLoaded ? state as ActivityLoaded : null;
      if (prev != null && now != null) {
        final wasUnread = {
          for (final n in prev.notifications)
            if (n['is_read'] != true) n['id'],
        };
        final reverted = now.notifications.map((n) {
          return wasUnread.contains(n['id']) ? {...n, 'is_read': false} : n;
        }).toList();
        emit(
          now.copyWith(
            notifications: reverted,
            unreadNotifications: reverted
                .where((n) => n['is_read'] != true)
                .length,
          ),
        );
      }
    }
  }

  Future<void> _onMarkOneRead(
    MarkOneReadEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    if (prev == null) return;
    // Optimistic: the tap already opened what it was about.
    emit(_withRead(prev, event.notificationId, true));
    try {
      await _repository.markOneRead(event.notificationId);
    } catch (_) {
      final now = state is ActivityLoaded ? state as ActivityLoaded : null;
      if (now != null) emit(_withRead(now, event.notificationId, false));
    }
  }

  ActivityLoaded _withRead(ActivityLoaded s, String id, bool read) {
    final updated = s.notifications.map((n) {
      // Compared as strings: the tile sends `n['id'].toString()`.
      if (n['id']?.toString() == id) return {...n, 'is_read': read};
      return n;
    }).toList();
    final unread = updated.where((n) => n['is_read'] != true).length;
    return s.copyWith(notifications: updated, unreadNotifications: unread);
  }

  Future<void> _onToggleShortlist(
    ToggleShortlistEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    // Already shortlisted means this toggle removes them: take them off the
    // list now. (Adding needs the server's copy of the profile, which the
    // refresh below brings.)
    final removing =
        prev != null &&
        prev.shortlists.any(
          (p) => p['user_id']?.toString() == event.targetUserId,
        );
    if (removing) {
      emit(
        prev.copyWith(
          shortlists: prev.shortlists
              .where((p) => p['user_id']?.toString() != event.targetUserId)
              .toList(),
        ),
      );
    }
    try {
      await _repository.toggleShortlist(event.targetUserId);
      // Refresh shortlist
      add(const FetchShortlistsEvent());
    } catch (e) {
      if (removing) {
        final now = state is ActivityLoaded ? state as ActivityLoaded : null;
        if (now != null) emit(now.copyWith(shortlists: prev.shortlists));
      }
    }
  }

  Future<void> _onFetchContactRequests(
    FetchContactRequestsEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      final data = await _repository.fetchIncomingContactRequests();
      emit((prev ?? const ActivityLoaded()).copyWith(contactRequests: data));
    } catch (e) {
      if (prev != null) emit(prev);
    }
  }

  Future<void> _onRespondContactRequest(
    RespondContactRequestEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      await _repository.respondContactRequest(event.requestId, event.action);
      // Refresh contact requests list
      add(const FetchContactRequestsEvent());
    } catch (e) {
      if (prev != null) emit(prev);
    }
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }
}
