import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/theme/membership_palette.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../data/auth_repository.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;
  final SocketService _socket;

  AuthBloc(this._repository, this._socket) : super(AuthInitial()) {
    on<SendOtpEvent>(_onSendOtp);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<LogoutEvent>(_onLogout);
  }

  Future<void> _onSendOtp(SendOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _repository.sendOtp(event.phone);
      emit(OtpSentSuccess(event.phone));
    } catch (e) {
      emit(_errorFrom(e));
    }
  }

  Future<void> _onVerifyOtp(VerifyOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final data = await _repository.verifyOtp(event.phone, event.otp);
      await _socket.connect();
      emit(AuthAuthenticated(
        isNewUser: data['is_new_user'],
        user: data['user'],
      ));
    } catch (e) {
      emit(_errorFrom(e));
    }
  }

  AuthError _errorFrom(Object e) {
    if (e is AuthException) return AuthError(e.message, code: e.code);
    return AuthError(e.toString());
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    _socket.disconnect();
    await _repository.logout();
    MembershipTheme.instance.reset();
    emit(AuthInitial());
  }
}
