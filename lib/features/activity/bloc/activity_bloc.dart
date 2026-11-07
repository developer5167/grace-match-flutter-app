import 'package:flutter_bloc/flutter_bloc.dart';
import 'activity_event.dart';
import 'activity_state.dart';
import '../data/activity_repository.dart';

class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  final ActivityRepository _repository;

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
    emit(ActivityLoading());
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
      emit(ActivityError(e.toString()));
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
    try {
      await _repository.markAllRead();
      if (prev != null) {
        final updated = prev.notifications.map((n) {
          return {...n, 'is_read': true};
        }).toList();
        emit(prev.copyWith(notifications: updated, unreadNotifications: 0));
      }
    } catch (_) {}
  }

  Future<void> _onMarkOneRead(
    MarkOneReadEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    if (prev == null) return;
    try {
      await _repository.markOneRead(event.notificationId);
      final updated = prev.notifications.map((n) {
        if (n['id'] == event.notificationId) return {...n, 'is_read': true};
        return n;
      }).toList();
      final unread = updated.where((n) => n['is_read'] != true).length;
      emit(prev.copyWith(notifications: updated, unreadNotifications: unread));
    } catch (_) {}
  }

  Future<void> _onToggleShortlist(
    ToggleShortlistEvent event,
    Emitter<ActivityState> emit,
  ) async {
    final prev = state is ActivityLoaded ? state as ActivityLoaded : null;
    try {
      await _repository.toggleShortlist(event.targetUserId);
      // Refresh shortlist
      add(const FetchShortlistsEvent());
    } catch (e) {
      if (prev != null) emit(prev);
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
