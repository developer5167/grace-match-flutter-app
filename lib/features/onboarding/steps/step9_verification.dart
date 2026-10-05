import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../screens/onboarding_screen.dart';

/// Step 9 — a verification selfie.
///
/// Staff compare it with the profile photos to award "Photo verified". It is
/// optional: Continue works without it, and it can be done later from
/// Profile → Verification, along with identity (DigiLocker).
class Step9Verification extends StatefulWidget {
  const Step9Verification({super.key});

  @override
  State<Step9Verification> createState() => _Step9VerificationState();
}

class _Step9VerificationState extends OnboardingStepState<Step9Verification> {
  String? _selfiePath;
  final ImagePicker _picker = ImagePicker();

  @override
  Map<String, dynamic>? getStepData() {
    // An empty map lets the member continue without a selfie.
    if (_selfiePath == null) return {};
    return {'verification_selfie_path': _selfiePath};
  }

  Future<void> _takeSelfie() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (shot != null) setState(() => _selfiePath = shot.path);
  }

  @override
  Widget build(BuildContext context) {
    final taken = _selfiePath != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.goldMild),
            ),
            child: const Icon(Icons.face_retouching_natural_rounded, size: 48, color: AppColors.gold),
          ),
          const SizedBox(height: 24),
          Text('Show it\'s really you', style: AppTextStyles.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Take a quick selfie. Our team compares it with your profile photo and adds a '
            '"Photo verified" label to your profile. The selfie is never shown to other members.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          GestureDetector(
            onTap: _takeSelfie,
            child: Container(
              width: double.infinity,
              height: 240,
              decoration: BoxDecoration(
                color: taken ? AppColors.goldSubtle : AppColors.surfaceHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: taken ? AppColors.gold : AppColors.goldMild, width: 2),
              ),
              child: taken
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.file(File(_selfiePath!), fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_front_rounded, size: 56, color: AppColors.textTertiary),
                        const SizedBox(height: 14),
                        Text('Tap to take a selfie',
                            style: AppTextStyles.labelMedium.copyWith(color: AppColors.gold)),
                      ],
                    ),
            ),
          ),
          if (taken)
            TextButton.icon(
              onPressed: _takeSelfie,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retake'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
          const SizedBox(height: 12),
          Text(
            'Face the camera in good light, without sunglasses. You can also skip this and do it later.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
