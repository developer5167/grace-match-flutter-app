import 'package:equatable/equatable.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final Map<String, dynamic> profile;
  final String? userId;

  /// Why the last send/accept/decline failed. The profile is already back as
  /// it was; the screen shows this once as a snackbar.
  final String? actionError;
  const ProfileLoaded(this.profile, {this.userId, this.actionError});

  @override
  List<Object?> get props => [profile, userId, actionError];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
