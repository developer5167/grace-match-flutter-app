import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/storage/app_storage.dart';
import '../widgets/step_indicator.dart';
import '../steps/step1_basic.dart';
import '../steps/step2_faith.dart';
import '../steps/step3_personal.dart';
import '../steps/step4_lifestyle.dart';
import '../steps/step5_family.dart';
import '../steps/step6_preferences.dart';
import '../steps/step7_hobbies.dart';
import '../steps/step8_photos.dart';
import '../steps/step9_verification.dart';
import '../steps/step10_final.dart';
import '../bloc/onboarding_bloc.dart';
import '../bloc/onboarding_event.dart';
import '../bloc/onboarding_state.dart';

class OnboardingScreen extends StatefulWidget {
  final int? initialStep;
  final String? fixAction;
  const OnboardingScreen({super.key, this.initialStep, this.fixAction});

  @override
  State<OnboardingScreen> createState() => OnboardingScreenState();
}

class OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  late int _currentStep;
  static const int _totalSteps = 10;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep ?? 0;
    _pageController = PageController(initialPage: _currentStep);
    context.read<OnboardingBloc>().add(LoadStatusEvent());
  }

  // Keys to access step data
  final List<GlobalKey<OnboardingStepState>> _stepKeys = 
      List.generate(10, (index) => GlobalKey<OnboardingStepState>());

  final _stepTitles = [
    'About You',
    'Your Faith',
    'Career & Life',
    'Lifestyle',
    'Family',
    'Partner Preferences',
    'Hobbies',
    'Photos',
    'Verification',
    'Almost There!',
  ];

  final _stepSubtitles = [
    'Let\'s start with the basics',
    'Your faith is your foundation',
    'Tell us about your career',
    'How do you like to live?',
    'Tell us about your family',
    'What are you looking for?',
    'What do you enjoy?',
    'Show your best smile',
    'Build trust with others',
    'Who manages this profile?',
  ];

  Map<String, dynamic>? onboardingData;



  void _nextStep() {
    final currentKey = _stepKeys[_currentStep];
    final stepData = currentKey.currentState?.getStepData();

    if (stepData == null) {
      // Step validation failed or data not ready
      AppHaptics.error();
      return;
    }

    // Save step data to backend
    context.read<OnboardingBloc>().add(SaveStepEvent(_currentStep + 1, stepData));
  }

  bool get _isFixing => widget.initialStep != null || widget.fixAction != null;

  void _onStepSaved() {
    if (_isFixing) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/review-status');
      }
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Completed onboarding
      AppStorage.saveOnboardingComplete(true);
      if (mounted) {
        context.go('/discover');
      }
    }
  }

  String _getStepTitle() {
    if (_isFixing) {
      final titles = [
        'Basic Info', 'Faith Details', 'Bio & Details', 'Lifestyle',
        'Family Background', 'Partner Preferences', 'Hobbies', 'My Photos',
        'Verification', 'Finalize'
      ];
      return 'Edit ${titles[_currentStep]}';
    }
    return 'GraceMatch';
  }

  void _prevStep() {
    if (_isFixing && (widget.initialStep == null || _currentStep == widget.initialStep)) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profile');
      }
      return;
    }
    
    if (_currentStep > 0) {
      AppHaptics.light();
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      setState(() => _currentStep--);
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/auth/phone');
      }
    }
  }

  void _finalize() async {
    await AppHaptics.match();
    context.go('/discover');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnboardingBloc, OnboardingState>(
      listener: (context, state) {
        if (state is OnboardingStatusLoaded) {
          onboardingData = state.data;
          int fetchedStep = onboardingData!['current_step'] ?? 0;
          if (widget.initialStep != null) {
            fetchedStep = widget.initialStep!;
          }
          if (fetchedStep >= _totalSteps) fetchedStep = _totalSteps - 1;
          setState(() {
            _currentStep = fetchedStep;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentStep);
            }
          });
        } else if (state is StepSavedSuccess) {
          _onStepSaved();
        } else if (state is OnboardingError) {
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
        if (onboardingData == null && (state is OnboardingLoading || state is OnboardingInitial)) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
          );
        }

        final isLoading = state is OnboardingLoading;
        
        final List<Widget> steps = [
          Step1Basic(key: _stepKeys[0]),
          Step2Faith(key: _stepKeys[1]),
          Step3Personal(key: _stepKeys[2]),
          Step4Lifestyle(key: _stepKeys[3]),
          Step5Family(key: _stepKeys[4]),
          Step6Preferences(key: _stepKeys[5]),
          Step7Hobbies(key: _stepKeys[6]),
          Step8Photos(key: _stepKeys[7]),
          Step9Verification(key: _stepKeys[8]),
          Step10Final(key: _stepKeys[9]),
        ];

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(isLoading),
                if (!_isFixing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    child: OnboardingStepIndicator(
                      total: _totalSteps,
                      current: _currentStep,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _isFixing ? 'Edit ${_stepTitles[_currentStep]}' : _stepTitles[_currentStep],
                          key: ValueKey('title_$_currentStep'),
                          style: AppTextStyles.headlineLarge,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _stepSubtitles[_currentStep],
                          key: ValueKey('sub_$_currentStep'),
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: steps,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: AppButton(
                    label: _isFixing
                        ? 'Save'
                        : _currentStep == _totalSteps - 1
                            ? 'Complete Profile ✓'
                            : 'Continue',
                    isLoading: isLoading,
                    onPressed: _nextStep,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isLoading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          if (_currentStep > 0 || _isFixing)
            IconButton(
              onPressed: isLoading ? null : _prevStep,
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textPrimary),
            )
          else
            const SizedBox(width: 48),
          const Spacer(),
          if (!_isFixing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.goldSubtle,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.goldMild),
              ),
              child: Text(
                '${_currentStep + 1} / $_totalSteps',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold),
              ),
            )
          else
            const SizedBox(width: 48),
          const Spacer(),
          if (!_isFixing && _currentStep != 7 && _currentStep != 9)
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      AppHaptics.light();
                      _onStepSaved();
                    },
              child: Text('Skip', style: AppTextStyles.labelMedium),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

abstract class OnboardingStepState<T extends StatefulWidget> extends State<T> {
  Map<String, dynamic>? getStepData();
}
