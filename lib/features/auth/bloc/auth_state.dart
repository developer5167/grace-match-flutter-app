import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class OtpSentSuccess extends AuthState {
  final String phone;
  const OtpSentSuccess(this.phone);

  @override
  List<Object?> get props => [phone];
}

class AuthAuthenticated extends AuthState {
  final bool isNewUser;
  final Map<String, dynamic> user;

  const AuthAuthenticated({required this.isNewUser, required this.user});

  @override
  List<Object?> get props => [isNewUser, user];
}

class AuthError extends AuthState {
  final String message;
  final String? code;
  const AuthError(this.message, {this.code});

  bool get isSuspended => code == 'ACCOUNT_SUSPENDED';

  @override
  List<Object?> get props => [message, code];
}
