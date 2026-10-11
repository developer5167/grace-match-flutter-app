import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Logged-out view of a shared profile. Same fields as the website preview.
/// Interest, chat and contact stay behind login.
class SharePreviewScreen extends StatefulWidget {
  final String userId;
  const SharePreviewScreen({super.key, required this.userId});

  @override
  State<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends State<SharePreviewScreen> {
  Map<String, dynamic>? _profile;
  String _state = 'loading';

  @override
  void initState() {
    super.initState();
    AppStorage.setPendingShareProfile(widget.userId);
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await DioClient.instance.get(
        ApiEndpoints.shareProfile(widget.userId),
      );
      final data = resp.data['data'];
      if (!mounted) return;
      setState(() {
        _profile = data is Map<String, dynamic> ? data : null;
        _state = _profile == null ? 'error' : 'ok';
      });
    } on DioException {
      if (mounted) setState(() => _state = 'error');
    } catch (_) {
      if (mounted) setState(() => _state = 'error');
    }
  }

  void _login() {
    AppStorage.setPendingShareProfile(widget.userId);
    context.go('/auth/phone');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(AppConstants.appName, style: AppTextStyles.headlineSmall),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_state == 'loading') {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }
    if (_state == 'error' || _profile == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Profile unavailable', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'This profile is private, or the link has expired.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final p = _profile!;
    final name = p['name']?.toString() ?? 'Member';
    final age = p['age'];
    final photo = p['primary_photo']?.toString();
    final location = p['location']?.toString();
    final profession = p['profession']?.toString();
    final faith = [p['denomination'], p['church_name']].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final bio = p['bio']?.toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        if (photo != null && photo.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          age != null ? '$name  $age' : name,
          style: AppTextStyles.headlineMedium,
        ),
        if (location != null && location.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(location, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ],
        if (profession != null && profession.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(profession, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ],
        if (faith.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(faith, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ],
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(bio, style: AppTextStyles.bodyMedium.copyWith(height: 1.6)),
        ],
        const SizedBox(height: 24),
        Text(
          'Full profile, photos and contact details are available after you log in.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.textOnGold,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Log in to continue', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
