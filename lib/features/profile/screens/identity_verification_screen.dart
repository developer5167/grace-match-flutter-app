import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  File? _selectedImage;
  bool _isUploading = false;
  final _picker = ImagePicker();

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _uploadId() async {
    if (_selectedImage == null) return;

    setState(() => _isUploading = true);

    try {
      final formData = FormData.fromMap({
        'id_proof': await MultipartFile.fromFile(
          _selectedImage!.path,
          filename: 'id_proof.jpg',
        ),
      });

      final response = await DioClient.instance.post(
        ApiEndpoints.verifyIdentity,
        data: formData,
      );

      if (response.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ID Proof uploaded successfully! Admin will verify it soon.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Identity Verification'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      // The action is pinned in bottomNavigationBar rather than floated with a
      // Spacer. SafeArea then keeps it clear of the home indicator, and it
      // cannot be pushed off-screen by a tall preview or a small device.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: ElevatedButton(
          onPressed: (_selectedImage == null || _isUploading) ? null : _uploadId,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.textOnGold,
            disabledBackgroundColor: AppColors.surfaceHighest,
            disabledForegroundColor: AppColors.textTertiary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          child: _isUploading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _selectedImage == null
                      ? 'Select an ID photo first'
                      : 'Submit for Verification',
                ),
        ),
      ),
      // Scrollable: a 200px preview plus copy overflows a small screen, and
      // the old Column had no scroll view at all.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.shield_rounded, size: 80, color: AppColors.gold),
            const SizedBox(height: 24),
            Text(
              'Verify Your Identity',
              style: AppTextStyles.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Upload a clear photo of your Government issued ID (Aadhar, PAN, or Passport) to get the verification badge.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _isUploading ? null : _pickImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.surfaceHighest,
                    style: BorderStyle.solid,
                  ),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_rounded,
                              size: 48, color: AppColors.goldMild),
                          const SizedBox(height: 12),
                          Text('Select ID Photo', style: AppTextStyles.labelMedium),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedImage != null)
              TextButton.icon(
                onPressed: _isUploading ? null : _pickImage,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Choose a different photo'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
