import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pinput/pinput.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_button.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phone;
  const OtpVerificationScreen({super.key, required this.phone});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final pinputController = TextEditingController();
  final focusNode = FocusNode();
  int _secondsRemaining = 30;
  Timer? _timer;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _secondsRemaining = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    pinputController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _verifyOtp(String otp) {
    AppHaptics.light();
    context.read<AuthBloc>().add(VerifyOtpEvent(phone: widget.phone, otp: otp));
  }
  
  void _resendOtp() {
    AppHaptics.medium();
    context.read<AuthBloc>().add(SendOtpEvent(widget.phone));
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: AppTextStyles.bodyLarge.copyWith(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHighest),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.gold, width: 2),
      boxShadow: [
        BoxShadow(
          color: AppColors.gold.withAlpha(40),
          blurRadius: 12,
          spreadRadius: 2,
        ),
      ],
    );

    final errorPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.error, width: 2),
    );

    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          if (state.isNewUser) {
            context.go('/onboarding');
          } else {
            context.go(AppStorage.takeShareResumeRoute() ?? '/discover');
          }
        } else if (state is AuthError) {
          setState(() {
            _hasError = true;
            pinputController.clear();
          });
          AppHaptics.error();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message, style: const TextStyle(color: Colors.white)),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  
                  Text(
                    'Verify Code',
                    style: AppTextStyles.displaySmall,
                  ).animate().fadeIn(duration: 400.ms).slideX(),
                  
                  const SizedBox(height: 8),
                  
                  Text.rich(
                    TextSpan(
                      text: 'Code sent to ',
                      style: AppTextStyles.bodyLarge,
                      children: [
                        TextSpan(
                          text: widget.phone,
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.gold),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideX(),
                  
                  const SizedBox(height: 48),
                  
                  // PINPUT Fields
                  Center(
                    child: Pinput(
                      length: 6,
                      controller: pinputController,
                      focusNode: focusNode,
                      defaultPinTheme: defaultPinTheme,
                      focusedPinTheme: focusedPinTheme,
                      errorPinTheme: errorPinTheme,
                      forceErrorState: _hasError,
                      onChanged: (_) => setState(() => _hasError = false),
                      onCompleted: _verifyOtp,
                      readOnly: isLoading,
                    )
                    .animate(target: _hasError ? 1 : 0)
                    .shakeX(hz: 8, amount: 4, duration: 400.ms),
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1),
                  
                  const SizedBox(height: 32),
                  
                  // Resend Timer
                  Center(
                    child: _secondsRemaining > 0
                        ? Text(
                            'Resend code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                            style: AppTextStyles.labelMedium,
                          )
                        : TextButton(
                            onPressed: isLoading ? null : _resendOtp,
                            child: Text(
                              'Resend Code',
                              style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold),
                            ),
                          ),
                  ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                  
                  const Spacer(),
                  
                  AppButton(
                    label: 'Verify',
                    isLoading: isLoading,
                    onPressed: pinputController.text.length == 6 ? () => _verifyOtp(pinputController.text) : null,
                  ).animate().fadeIn(delay: 400.ms, duration: 400.ms).slideY(begin: 0.2),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
        onPressed: () => context.pop(),
      ),
    );
  }
}
