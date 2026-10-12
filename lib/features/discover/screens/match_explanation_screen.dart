import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

/// Displays an AI-generated explanation of why two profiles are a good match.
/// Accessible via the public profile screen ("Why We Match" button).
class MatchExplanationScreen extends StatefulWidget {
  final String targetUserId;
  final String targetName;
  final String? targetPhoto;
  final int? compatibility;

  const MatchExplanationScreen({
    super.key,
    required this.targetUserId,
    required this.targetName,
    this.targetPhoto,
    this.compatibility,
  });

  @override
  State<MatchExplanationScreen> createState() => _MatchExplanationScreenState();
}

class _MatchExplanationScreenState extends State<MatchExplanationScreen> {
  String? _explanation;
  String? _myPhoto;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMyPhoto();
    _fetchExplanation();
  }

  Future<void> _fetchMyPhoto() async {
    try {
      final resp = await DioClient.instance.get(ApiEndpoints.myProfile);
      final data = resp.data['data'];
      if (data is! Map) return;

      String? pickFrom(dynamic value) {
        if (value is String && value.isNotEmpty) return value;
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is String && first.isNotEmpty) return first;
          if (first is Map) {
            final m = Map<String, dynamic>.from(first);
            final url = m['photo_url']?.toString() ??
                m['url']?.toString() ??
                m['image_url']?.toString() ??
                m['secure_url']?.toString() ??
                m['avatar_url']?.toString();
            if (url != null && url.isNotEmpty) return url;
          }
        }
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          final url = m['photo_url']?.toString() ??
              m['profile_photo_url']?.toString() ??
              m['image_url']?.toString() ??
              m['secure_url']?.toString() ??
              m['avatar_url']?.toString();
          if (url != null && url.isNotEmpty) return url;
        }
        return null;
      }

      final profile = data['profile'];
      final myPhoto = pickFrom(data['photos']) ??
          pickFrom(data['profile_photos']) ??
          pickFrom(profile) ??
          pickFrom(data['user']) ??
          pickFrom(data['photo_url']) ??
          pickFrom(data['profile_photo_url']);

      if (!mounted) return;
      setState(() => _myPhoto = myPhoto);
    } catch (_) {
      // Non-fatal: we still show placeholder avatar if my photo fetch fails.
    }
  }

  Future<void> _fetchExplanation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await DioClient.instance.get(
        ApiEndpoints.matchExplanation(widget.targetUserId),
      );
      setState(() {
        _explanation = resp.data['data']['explanation'] as String?;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load match explanation. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Why You Match', style: AppTextStyles.headlineMedium),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildProfileRow(),
              const SizedBox(height: 32),
              if (widget.compatibility != null) _buildCompatibilityBadge(),
              const SizedBox(height: 32),
              _buildExplanationCard(),
              const SizedBox(height: 24),
              _buildFaithNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildAvatar('You', _myPhoto),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.favorite, color: AppColors.gold, size: 28),
              const SizedBox(height: 4),
              Text(
                '✝',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.gold.withAlpha(180),
                ),
              ),
            ],
          ),
        ),
        _buildAvatar(widget.targetName, widget.targetPhoto),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1);
  }

  Widget _buildAvatar(String name, String? photo) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold, width: 2),
          ),
          child: ClipOval(
            child: photo != null
                ? CachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.surfaceHighest),
                    errorWidget: (_, __, ___) =>
                        Icon(Icons.person, color: AppColors.gold),
                  )
                : Container(
                    color: AppColors.surfaceHighest,
                    child: Icon(
                      Icons.person,
                      color: AppColors.gold,
                      size: 32,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(name, style: AppTextStyles.labelLarge),
      ],
    );
  }

  Widget _buildCompatibilityBadge() {
    final pct = widget.compatibility!;
    final color = pct >= 75
        ? AppColors.success
        : pct >= 50
        ? AppColors.gold
        : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            '$pct% Compatibility Score',
            style: AppTextStyles.labelLarge.copyWith(color: color),
          ),
        ],
      ),
    ).animate().scale(duration: 400.ms, curve: Curves.elasticOut);
  }

  Widget _buildExplanationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldMild),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.goldSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: AppColors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AI Match Insight',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            Column(
              children: [
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  color: AppColors.gold,
                  backgroundColor: AppColors.surfaceHighest,
                ),
                const SizedBox(height: 16),
                Text(
                  'Analyzing your compatibility...',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
            )
          else if (_error != null)
            Column(
              children: [
                Text(
                  _error!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _fetchExplanation,
                  child: Text(
                    'Retry',
                    style: TextStyle(color: AppColors.gold),
                  ),
                ),
              ],
            )
          else
            Text(
              _explanation ?? 'No explanation available.',
              style: AppTextStyles.bodyLarge.copyWith(
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ).animate().fadeIn(duration: 600.ms),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1);
  }

  Widget _buildFaithNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.crossSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text(
            '✝',
            style: TextStyle(fontSize: 20, color: AppColors.cross),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'GraceMatch uses faith, values, and lifestyle to find your best match.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.cross),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms, duration: 500.ms);
  }
}
