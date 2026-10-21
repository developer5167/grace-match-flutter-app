import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/support/contact_support.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_button.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final _phoneController = TextEditingController();
  final String _selectedCode = '+91'; // Hardcoded for Telugu region mostly
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() {
      setState(() {
        _isValid = _phoneController.text.length == 10;
      });
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (!_isValid) return;
    AppHaptics.medium();
    FocusScope.of(context).unfocus();
    
    final fullPhone = '$_selectedCode${_phoneController.text}';
    context.read<AuthBloc>().add(SendOtpEvent(fullPhone));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is OtpSentSuccess) {
          final fullPhone = '$_selectedCode${_phoneController.text}';
          context.push('/auth/phone/otp', extra: fullPhone);
        } else if (state is AuthError) {
          if (state.isSuspended) {
            ContactSupport.showSuspendedDialog(context, message: state.message);
            return;
          }
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
                  
                  // Title
                  Text(
                    'What\'s your number?',
                    style: AppTextStyles.displaySmall,
                  ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                  
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Text(
                    'We will send a code to verify your identity.',
                    style: AppTextStyles.bodyLarge,
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideX(begin: -0.1),
                  
                  const SizedBox(height: 48),
                  
                  // Input Field
                  _buildPhoneInput()
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 400.ms)
                      .slideX(begin: -0.1),
                  
                  const Spacer(),
                  
                  // Terms text
                  Center(
                    child: Text(
                      'By continuing, you agree to our Terms of Service',
                      style: AppTextStyles.labelSmall,
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  AppButton(
                    label: 'Continue',
                    isLoading: isLoading,
                    onPressed: _isValid ? _onContinue : null,
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

  Widget _buildPhoneInput() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isValid ? AppColors.gold : AppColors.surfaceHighest,
          width: _isValid ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Country Code Dropdown (Simulated for aesthetics)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text(
                  '🇮🇳',
                  style: TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedCode,
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Phone Number Input
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              cursorColor: AppColors.gold,
              decoration: InputDecoration(
                hintText: '0000 0000 00',
                hintStyle: AppTextStyles.bodyLarge.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textTertiary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          
          // Validation Checkmark
          if (_isValid)
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.gold,
            ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
        ],
      ),
    );
  }
}
