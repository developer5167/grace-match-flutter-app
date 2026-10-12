import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../screens/onboarding_screen.dart';

class Step8Photos extends StatefulWidget {
  const Step8Photos({super.key});

  @override
  State<Step8Photos> createState() => _Step8PhotosState();
}

class _Step8PhotosState extends OnboardingStepState<Step8Photos>
    with AutomaticKeepAliveClientMixin {
  // Each slot: local file path OR existing network URL
  final List<String?> _photoPaths = List.filled(6, null);

  // DB photo IDs for already-uploaded photos (null for new local selections)
  final List<String?> _photoIds = List.filled(6, null);

  // IDs of existing photos that the user removed (need server-side delete)
  final List<String> _deletedPhotoIds = [];

  // Review status of existing photos (from server)
  final List<String?> _reviewStatuses = List.filled(6, null);

  final ImagePicker _picker = ImagePicker();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final parent = context.findAncestorStateOfType<OnboardingScreenState>();
      final photos = parent?.onboardingData?['photos'] as List?;
      if (photos != null && mounted) {
        setState(() {
          for (int i = 0; i < photos.length && i < 6; i++) {
            final p = photos[i];
            if (p is Map) {
              _photoPaths[i] = p['photo_url'] as String?;
              _photoIds[i] = p['id']?.toString();
              _reviewStatuses[i] = p['review_status'] as String?;
            } else if (p is String) {
              _photoPaths[i] = p;
            }
          }
        });
      }
    });
  }

  @override
  Map<String, dynamic>? getStepData() {
    // Collect newly selected local file paths
    final localPaths = <String>[];
    for (int i = 0; i < 6; i++) {
      final path = _photoPaths[i];
      if (path != null && !path.startsWith('http')) {
        localPaths.add(path);
      }
    }

    // Need at least one photo (existing or new)
    final hasAny = _photoPaths.any((p) => p != null);
    if (!hasAny) return null;

    return {
      '_localPhotoPaths': localPaths,
      '_deletedPhotoIds': List<String>.from(_deletedPhotoIds),
    };
  }

  Future<void> _pickPhoto(int index) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null && mounted) {
      setState(() {
        // If replacing an existing uploaded photo, mark it for deletion
        if (_photoIds[index] != null) {
          _deletedPhotoIds.add(_photoIds[index]!);
          _photoIds[index] = null;
          _reviewStatuses[index] = null;
        }
        _photoPaths[index] = image.path;
      });
    }
  }

  void _removePhoto(int index) {
    setState(() {
      if (_photoIds[index] != null) {
        _deletedPhotoIds.add(_photoIds[index]!);
        _photoIds[index] = null;
        _reviewStatuses[index] = null;
      }
      _photoPaths[index] = null;
    });
  }

  Color _statusBorderColor(int index) {
    final status = _reviewStatuses[index];
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    if (status == 'pending') return Colors.amber;
    return index == 0 ? AppColors.gold : AppColors.surfaceHighest;
  }

  Widget? _statusBadge(int index) {
    final status = _reviewStatuses[index];
    if (status == null) return null;
    Color color;
    IconData icon;
    switch (status) {
      case 'approved':
        color = Colors.green;
        icon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        color = Colors.red;
        icon = Icons.cancel_rounded;
        break;
      default: // pending
        color = Colors.amber;
        icon = Icons.hourglass_top_rounded;
    }
    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload up to 6 photos. The first photo will be your profile picture. Smiles get more matches!',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.goldSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.goldMild),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.gold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Photos will be uploaded when you tap Continue. New photos need admin approval before becoming visible.',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (context, index) => _buildPhotoSlot(index),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPhotoSlot(int index) {
    final path = _photoPaths[index];
    final hasPhoto = path != null;
    final isNetwork = path != null && path.startsWith('http');

    return GestureDetector(
      onTap: () => _pickPhoto(index),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _statusBorderColor(index),
            width: hasPhoto ? 2 : 1,
          ),
        ),
        child: hasPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: isNetwork
                        ? CachedNetworkImage(imageUrl: path, fit: BoxFit.cover)
                        : Image.file(File(path), fit: BoxFit.cover),
                  ),
                  if (_statusBadge(index) != null) _statusBadge(index)!,
                  Positioned(
                    top: -4,
                    right: -4,
                    child: GestureDetector(
                      onTap: () => _removePhoto(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        color: Colors.black54,
                        child: Text(
                          'Primary',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.overline.copyWith(color: AppColors.gold),
                        ),
                      ),
                    ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      color: index == 0 ? AppColors.gold : AppColors.textTertiary,
                      size: 28,
                    ),
                    if (index == 0) ...[
                      const SizedBox(height: 4),
                      Text('Required', style: AppTextStyles.overline.copyWith(color: AppColors.gold)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
