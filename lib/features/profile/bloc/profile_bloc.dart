import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../data/profile_repository.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _repository;

  ProfileBloc(this._repository) : super(ProfileInitial()) {
    on<FetchProfileEvent>(_onFetchProfile);
    on<UpdateSettingsEvent>(_onUpdateSettings);
    on<SendInterestEvent>(_onSendInterest);
    on<AcceptInterestEvent>(_onAcceptInterest);
    on<RejectInterestEvent>(_onRejectInterest);
  }

  Future<void> _onAcceptInterest(AcceptInterestEvent event, Emitter<ProfileState> emit) async {
    try {
      await _repository.acceptInterest(event.interestId);
      if (state is ProfileLoaded) {
        final current = state as ProfileLoaded;
        emit(ProfileLoaded({
          ...current.profile,
          'interaction_status': 'accepted'
        }, userId: current.userId));
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onRejectInterest(RejectInterestEvent event, Emitter<ProfileState> emit) async {
    try {
      await _repository.rejectInterest(event.interestId);
      if (state is ProfileLoaded) {
        final current = state as ProfileLoaded;
        emit(ProfileLoaded({
          ...current.profile,
          'interaction_status': 'rejected'
        }, userId: current.userId));
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onSendInterest(SendInterestEvent event, Emitter<ProfileState> emit) async {
    try {
      await _repository.sendInterest(event.userId, isSuper: event.isSuper);
      if (state is ProfileLoaded) {
        final current = state as ProfileLoaded;
        // userId MUST be carried over. The profile screen renders a spinner
        // whenever state.userId != the profile it is showing, so emitting
        // without it leaves the screen loading forever.
        // interaction_sender_id is left as it was. Going from 'none' it is
        // null, which is what the bottom bar needs to show "interest sent"
        // rather than the accept/decline pair meant for the receiver.
        emit(ProfileLoaded({
          ...current.profile,
          'interaction_status': 'sent',
        }, userId: current.userId));
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onFetchProfile(FetchProfileEvent event, Emitter<ProfileState> emit) async {
    final silentOwnProfile =
        event.silentRefresh && event.userId == null && state is ProfileLoaded;
    if (!silentOwnProfile) emit(ProfileLoading());
    ProfileLoaded? previous;
    if (state is ProfileLoaded) previous = state as ProfileLoaded;
    try {
      final profile = event.userId != null
          ? await _repository.fetchProfile(event.userId!)
          : await _repository.fetchMyProfile();
      emit(ProfileLoaded(profile, userId: event.userId ?? previous?.userId));
    } catch (e) {
      if (silentOwnProfile && previous != null) {
        emit(previous);
        return;
      }
      emit(ProfileError(e.toString()));
    }
  }

  Future<void> _onUpdateSettings(UpdateSettingsEvent event, Emitter<ProfileState> emit) async {
    final previous = state is ProfileLoaded ? state as ProfileLoaded : null;
    try {
      // PUT returns updated settings fields directly — merge them into local state
      // to avoid a second GET /profile/me round-trip.
      final updatedSettings = await _repository.updateSettings(event.settings);
      if (previous != null && updatedSettings.isNotEmpty) {
        final fullData = Map<String, dynamic>.from(previous.profile);
        final profileSection = Map<String, dynamic>.from(
          fullData['profile'] is Map ? fullData['profile'] as Map<String, dynamic> : {},
        );
        profileSection.addAll(updatedSettings);
        fullData['profile'] = profileSection;
        emit(ProfileLoaded(fullData, userId: previous.userId));
      } else {
        add(const FetchProfileEvent(silentRefresh: true));
      }
    } catch (e) {
      if (previous != null) emit(previous);
      else emit(ProfileError(e.toString()));
    }
  }
}
