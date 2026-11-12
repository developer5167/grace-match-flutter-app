import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/membership_palette.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../data/profile_repository.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _repository;
  // Profile fetches out right now, by user id ('' for the member's own).
  final Map<String, int> _inFlight = {};

  ProfileBloc(this._repository) : super(ProfileInitial()) {
    on<FetchProfileEvent>(_onFetchProfile);
    on<UpdateSettingsEvent>(_onUpdateSettings);
    on<SendInterestEvent>(_onSendInterest);
    on<AcceptInterestEvent>(_onAcceptInterest);
    on<RejectInterestEvent>(_onRejectInterest);
  }

  Future<void> _onAcceptInterest(
    AcceptInterestEvent event,
    Emitter<ProfileState> emit,
  ) => _interactOptimistically(
    emit,
    status: 'accepted',
    call: () => _repository.acceptInterest(event.interestId),
  );

  Future<void> _onRejectInterest(
    RejectInterestEvent event,
    Emitter<ProfileState> emit,
  ) => _interactOptimistically(
    emit,
    status: 'rejected',
    call: () => _repository.rejectInterest(event.interestId),
  );

  // userId MUST be carried over. The profile screen renders a placeholder
  // whenever state.userId != the profile it is showing, so emitting without
  // it leaves the screen loading forever.
  // interaction_sender_id is left as it was. Going from 'none' it is null,
  // which is what the bottom bar needs to show "interest sent" rather than the
  // accept/decline pair meant for the receiver.
  Future<void> _onSendInterest(
    SendInterestEvent event,
    Emitter<ProfileState> emit,
  ) => _interactOptimistically(
    emit,
    status: 'sent',
    call: () => _repository.sendInterest(event.userId, isSuper: event.isSuper),
  );

  /// Shows [status] at once, then calls the server. On failure the profile
  /// goes back to its previous status with [ProfileLoaded.actionError] set
  /// for a snackbar; a loaded profile is never replaced by [ProfileError].
  Future<void> _interactOptimistically(
    Emitter<ProfileState> emit, {
    required String status,
    required Future<dynamic> Function() call,
  }) async {
    final before = state is ProfileLoaded ? state as ProfileLoaded : null;
    if (before != null) {
      emit(
        ProfileLoaded({
          ...before.profile,
          'interaction_status': status,
        }, userId: before.userId),
      );
    }
    try {
      await call();
    } catch (e) {
      if (before == null) {
        // Nothing was on screen to put back.
        emit(ProfileError(e.toString()));
        return;
      }
      final now = state;
      // Put the old status back only if this profile is still showing the
      // status set above (a refresh may have brought the server's own).
      if (now is ProfileLoaded &&
          now.userId == before.userId &&
          now.profile['interaction_status'] == status) {
        emit(
          ProfileLoaded(
            {
              ...now.profile,
              'interaction_status': before.profile['interaction_status'],
            },
            userId: now.userId,
            actionError: e.toString().replaceFirst('Exception: ', ''),
          ),
        );
      }
    }
  }

  Future<void> _onFetchProfile(
    FetchProfileEvent event,
    Emitter<ProfileState> emit,
  ) async {
    final key = event.userId ?? '';
    // An identical open of the same profile while one is out adds nothing.
    // Silent refreshes always run: they follow a change (settings, a
    // purchase) and must not be answered by a request sent before it.
    if (!event.silentRefresh && (_inFlight[key] ?? 0) > 0) return;

    // Only keep the screen up while refreshing the very profile it shows. A
    // different one (someone else's, or the member's own after viewing
    // someone else's) must not show the old data under the new screen.
    final previous = state is ProfileLoaded ? state as ProfileLoaded : null;
    final keepOnScreen = previous != null && previous.userId == event.userId;
    if (!keepOnScreen) emit(ProfileLoading());

    _inFlight[key] = (_inFlight[key] ?? 0) + 1;
    try {
      final profile = event.userId != null
          ? await _repository.fetchProfile(event.userId!)
          : await _repository.fetchMyProfile();
      if (event.userId == null) {
        MembershipTheme.instance.applyFrom(profile['subscription']);
      }
      emit(ProfileLoaded(profile, userId: event.userId));
    } catch (e) {
      // A failed refresh keeps the profile that was on screen (it was never
      // replaced, so there is nothing to emit).
      if (keepOnScreen) return;
      emit(ProfileError(e.toString()));
    } finally {
      final n = (_inFlight[key] ?? 1) - 1;
      if (n <= 0) {
        _inFlight.remove(key);
      } else {
        _inFlight[key] = n;
      }
    }
  }

  Future<void> _onUpdateSettings(
    UpdateSettingsEvent event,
    Emitter<ProfileState> emit,
  ) async {
    final previous = state is ProfileLoaded ? state as ProfileLoaded : null;
    try {
      // PUT returns updated settings fields directly — merge them into local state
      // to avoid a second GET /profile/me round-trip.
      final updatedSettings = await _repository.updateSettings(event.settings);
      if (previous != null && updatedSettings.isNotEmpty) {
        final fullData = Map<String, dynamic>.from(previous.profile);
        final profileSection = Map<String, dynamic>.from(
          fullData['profile'] is Map
              ? fullData['profile'] as Map<String, dynamic>
              : {},
        );
        profileSection.addAll(updatedSettings);
        fullData['profile'] = profileSection;
        emit(ProfileLoaded(fullData, userId: previous.userId));
      } else {
        add(const FetchProfileEvent(silentRefresh: true));
      }
    } catch (e) {
      if (previous != null)
        emit(previous);
      else
        emit(ProfileError(e.toString()));
    }
  }
}
