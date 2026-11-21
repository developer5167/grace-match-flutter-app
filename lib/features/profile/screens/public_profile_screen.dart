import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../../core/l10n/app_language.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/profile_code.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_haptics.dart';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/widgets/full_screen_gallery.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_state.dart';
import '../bloc/profile_event.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/utils/screen_guard.dart';
import '../../activity/bloc/activity_bloc.dart';
import '../../activity/bloc/activity_event.dart';
import '../../discover/screens/match_explanation_screen.dart';
import '../../discover/widgets/profile_card.dart' show PhotoVerifiedLabel;
import '../../discover/widgets/profile_list_card.dart'
    show denominationLabels, marriagePlanLabel, MarriagePlanTag;
import '../../calls/data/call_manager.dart';
import '../widgets/profile_safety_menu.dart';
import '../../../core/utils/faith_labels.dart';

class PublicProfileScreen extends StatefulWidget {
  final String? userId; // If null, shows own profile preview
  final bool showBottomActions;
  const PublicProfileScreen({
    super.key,
    this.userId,
    this.showBottomActions = true,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late PageController _headerPageController;
  // The star after a tap; null until then, when the server's
  // is_shortlisted decides.
  bool? _shortlisted;
  int _currentPhotoIndex = 0;
  String? _myUserId;

  // Contact reveal state
  Map<String, dynamic>? _contactStatus; // outgoing, incoming, phone
  bool _contactLoading = false;
  bool _contactRequesting = false;
  CallEntitlements? _calls;

  @override
  void initState() {
    super.initState();
    _headerPageController = PageController();
    _loadMyUserId();
    _loadCallOptions();
    if (widget.userId != null) {
      context.read<ProfileBloc>().add(FetchProfileEvent(userId: widget.userId));
      // Someone else's photos are on screen. Block the screenshot where the
      // platform allows it (Android), and where it does not (iOS), at least
      // tell the person whose photos they are.
      ScreenGuard.protect();
      ScreenGuard.watch(widget.userId!, surface: 'profile');
    } else {
      context.read<ProfileBloc>().add(FetchProfileEvent());
    }
  }

  @override
  void deactivate() {
    // Released here as well as in dispose: navigating away without disposing
    // would otherwise leave the whole app unscreenshottable.
    if (widget.userId != null) {
      ScreenGuard.unwatch();
      ScreenGuard.release();
    }
    super.deactivate();
  }

  Future<void> _loadMyUserId() async {
    final id = await AppStorage.getUserId();
    if (mounted) setState(() => _myUserId = id);
  }

  Future<void> _loadCallOptions() async {
    final calls = await CallManager.instance.entitlements(refresh: false);
    if (mounted) setState(() => _calls = calls);
  }

  Future<void> _startCall({
    required String conversationId,
    required String peerName,
    required String peerPhoto,
    required bool video,
  }) async {
    AppHaptics.selection();
    final messenger = ScaffoldMessenger.of(context);
    final failure = await CallManager.instance.startOutgoing(
      conversationId: conversationId,
      peerName: peerName,
      peerPhoto: peerPhoto,
      video: video,
    );
    if (!mounted) return;
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failure),
          backgroundColor: AppColors.surfaceHighest,
        ),
      );
    }
  }

  // contact_status is now embedded in the profile response for accepted matches.
  // _loadContactStatus is only called as a fallback (e.g. after a new contact request).
  Future<void> _loadContactStatus() async {
    if (widget.userId == null || _contactLoading) return;
    if (mounted) setState(() => _contactLoading = true);
    try {
      final dio = DioClient.instance;
      final resp = await dio.get(ApiEndpoints.contactStatus(widget.userId!));
      if (mounted) {
        setState(
          () => _contactStatus = Map<String, dynamic>.from(
            resp.data['data'] ?? {},
          ),
        );
      }
    } catch (_) {
      // Non-fatal — contact reveal section just won't show
    } finally {
      if (mounted) setState(() => _contactLoading = false);
    }
  }

  /// Extract embedded contact_status from the loaded profile data.
  /// This avoids a second HTTP round-trip for accepted matches.
  void _maybeApplyEmbeddedContactStatus(Map<String, dynamic> profileData) {
    if (_contactStatus != null) return; // already set
    final embedded = profileData['contact_status'];
    if (embedded is Map) {
      setState(() => _contactStatus = Map<String, dynamic>.from(embedded));
    }
  }

  String _apiMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null)
        return data['message'].toString();
    }
    return e
        .toString()
        .replaceFirst('DioException: ', '')
        .replaceFirst('Exception: ', '');
  }

  Future<void> _requestContact() async {
    if (widget.userId == null || _contactRequesting) return;
    setState(() => _contactRequesting = true);
    try {
      final dio = DioClient.instance;
      final resp = await dio.post(
        ApiEndpoints.contactRequest,
        data: {'target_user_id': widget.userId},
      );
      final payload = resp.data is Map ? resp.data['data'] : null;
      if (payload is Map) {
        if (mounted) {
          setState(() => _contactStatus = Map<String, dynamic>.from(payload));
        }
      } else {
        _contactStatus = null;
        await _loadContactStatus();
      }
      if (mounted) {
        final msg = resp.data is Map && resp.data['message'] != null
            ? resp.data['message'].toString()
            : tr('Contact request sent ✓');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_apiMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _contactRequesting = false);
    }
  }

  @override
  void dispose() {
    _headerPageController.dispose();
    super.dispose();
  }

  void _nextPhoto(int total) {
    if (_currentPhotoIndex < total - 1) {
      final nextIndex = _currentPhotoIndex + 1;
      _headerPageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPhotoIndex = nextIndex);
      AppHaptics.light();
    }
  }

  void _prevPhoto() {
    if (_currentPhotoIndex > 0) {
      final prevIndex = _currentPhotoIndex - 1;
      _headerPageController.animateToPage(
        prevIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPhotoIndex = prevIndex);
      AppHaptics.light();
    }
  }

  Future<void> _openGallery(
    List<String> photos, {
    required bool imagesLocked,
  }) async {
    if (imagesLocked) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            tr('Photos unlock once you connect.'),
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
        ),
      );
      return;
    }
    final selectedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FullScreenGallery(images: photos, initialIndex: _currentPhotoIndex),
      ),
    );
    if (!mounted || selectedIndex == null) return;
    if (selectedIndex >= 0 && selectedIndex < photos.length) {
      setState(() => _currentPhotoIndex = selectedIndex);
      _headerPageController.jumpToPage(selectedIndex);
    }
  }

  List<String> _extractPhotoUrls(
    Map<String, dynamic> data,
    Map<String, dynamic> profile,
  ) {
    List<dynamic> pickPhotoList(dynamic value) {
      if (value is List) return value;
      if (value is String && value.contains(',')) {
        return value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const <dynamic>[];
    }

    final photoCandidates = <dynamic>[
      ...pickPhotoList(data['photos']),
      ...pickPhotoList(data['profile_photos']),
      ...pickPhotoList(data['gallery']),
      ...pickPhotoList(data['photo_urls']),
      ...pickPhotoList(data['images']),
      ...pickPhotoList(profile['photos']),
      ...pickPhotoList(profile['profile_photos']),
      ...pickPhotoList(profile['gallery']),
      ...pickPhotoList(profile['photo_urls']),
      ...pickPhotoList(profile['images']),
      if (data['user'] is Map)
        ...pickPhotoList((data['user'] as Map)['photos']),
      if (data['user'] is Map)
        ...pickPhotoList((data['user'] as Map)['profile_photos']),
      if (data['user'] is Map)
        ...pickPhotoList((data['user'] as Map)['gallery']),
      if (data['user'] is Map)
        ...pickPhotoList((data['user'] as Map)['photo_urls']),
      if (data['user'] is Map)
        ...pickPhotoList((data['user'] as Map)['images']),
    ];

    final photos = <String>[];

    for (final photo in photoCandidates) {
      if (photo is String) {
        if (photo.isNotEmpty) photos.add(photo);
        continue;
      }

      if (photo is Map) {
        final photoMap = photo.cast<dynamic, dynamic>();
        final url =
            photoMap['photo_url']?.toString() ??
            photoMap['url']?.toString() ??
            photoMap['image_url']?.toString() ??
            photoMap['secure_url']?.toString() ??
            photoMap['file_url']?.toString() ??
            photoMap['photo']?.toString() ??
            photoMap['src']?.toString();
        if (url != null && url.isNotEmpty) photos.add(url);
      }
    }

    final profileFallbacks = [
      profile['photo_url'],
      profile['profile_photo_url'],
      profile['image_url'],
      profile['secure_url'],
      profile['file_url'],
      profile['photo'],
      profile['avatar_url'],
      if (data['user'] is Map) (data['user'] as Map)['photo_url'],
      if (data['user'] is Map) (data['user'] as Map)['profile_photo_url'],
      if (data['user'] is Map) (data['user'] as Map)['image_url'],
      if (data['user'] is Map) (data['user'] as Map)['avatar_url'],
    ];
    for (final fallback in profileFallbacks) {
      final url = fallback?.toString();
      if (url != null && url.isNotEmpty) photos.add(url);
    }

    return photos.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileBloc, ProfileState>(
      // A failed send/accept/decline: the button is already back as it was.
      listenWhen: (_, curr) =>
          curr is ProfileLoaded &&
          curr.actionError != null &&
          curr.userId == widget.userId,
      listener: (context, state) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text((state as ProfileLoaded).actionError!),
            backgroundColor: AppColors.error,
          ),
        );
      },
      builder: (context, state) {
        if (state is ProfileLoading) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const SkeletonProfile(headerHeight: 480),
          );
        }

        if (state is ProfileError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        if (state is ProfileLoaded && state.userId != widget.userId) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const SkeletonProfile(headerHeight: 480),
          );
        }

        final data = state is ProfileLoaded
            ? state.profile
            : <String, dynamic>{};
        final profile = data['profile'] as Map<String, dynamic>? ?? {};
        final family = data['family'] as Map<String, dynamic>? ?? {};
        final imagesLocked = data['is_images_locked'] == true;
        final photos = _extractPhotoUrls(data, profile);
        if (_currentPhotoIndex >= photos.length && photos.isNotEmpty) {
          _currentPhotoIndex = photos.length - 1;
        }

        final name = profile['first_name'] ?? 'User';
        final dob = profile['date_of_birth'] != null
            ? DateTime.parse(profile['date_of_birth'].toString())
            : null;
        final age = dob != null ? (DateTime.now().year - dob.year) : 26;
        final bio = profile['bio'] ?? tr('No bio provided yet.');
        final hobbies =
            (data['hobbies'] as List?)
                ?.map((h) {
                  if (h is Map)
                    return h['name']?.toString() ??
                        h['hobby_name']?.toString() ??
                        '';
                  return h.toString();
                })
                .where((s) => s.isNotEmpty)
                .toList() ??
            [];

        String formatValue(String? val) {
          if (val == null) return tr('Not specified');
          return val
              .replaceAll('_', ' ')
              .split(' ')
              .map(
                (s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '',
              )
              .join(' ');
        }

        String formatCurrency(dynamic value) {
          if (value == null) return '0';
          String s = value.toString();
          if (s.length <= 3) return s;
          return s.replaceAllMapped(
            RegExp(r'(\d+)(\d{3})'),
            (Match m) => '${m[1]},${m[2]}',
          );
        }

        final viewedUserId = widget.userId;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 480,
                pinned: true,
                backgroundColor: AppColors.background,
                actions: viewedUserId != null
                    ? [
                        Builder(
                          builder: (_) {
                            final starred =
                                _shortlisted ?? data['is_shortlisted'] == true;
                            return IconButton(
                              tooltip: tr(
                                starred
                                    ? tr('Remove from shortlist')
                                    : tr('Add to shortlist'),
                              ),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  starred
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  key: ValueKey(starred),
                                  color: AppColors.gold,
                                ),
                              ),
                              onPressed: () {
                                AppHaptics.medium();
                                setState(() => _shortlisted = !starred);
                                context.read<ActivityBloc>().add(
                                  ToggleShortlistEvent(viewedUserId),
                                );
                                ScaffoldMessenger.maybeOf(context)
                                  ?..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      content: Text(
                                        tr(
                                          starred
                                              ? tr('Removed from shortlist')
                                              : tr('Added to shortlist'),
                                        ),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                              },
                            );
                          },
                        ),
                        // The public page only works for approved profiles
                        // visible to everyone, so only offer it for those.
                        if (profile['profile_visibility'] == 'everyone' &&
                            profile['review_status'] == 'approved')
                          Builder(
                            builder: (anchor) => IconButton(
                              tooltip: tr('Share profile'),
                              icon: Icon(
                                Icons.ios_share_rounded,
                                color: AppColors.gold,
                              ),
                              onPressed: () => _shareOtherProfile(
                                anchor,
                                viewedUserId,
                                name.toString(),
                              ),
                            ),
                          ),
                        ProfileSafetyMenu(
                          userId: viewedUserId,
                          name: name.toString(),
                        ),
                      ]
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (photos.isEmpty)
                        ColoredBox(
                          color: AppColors.surfaceElevated,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  imagesLocked
                                      ? Icons.lock_rounded
                                      : Icons.person_rounded,
                                  color: AppColors.textTertiary,
                                  size: 64,
                                ),
                                if (imagesLocked) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    tr('Photos hidden until you connect'),
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        Stack(
                          children: [
                            PageView.builder(
                              controller: _headerPageController,
                              physics: const BouncingScrollPhysics(),
                              itemCount: photos.length,
                              onPageChanged: (index) {
                                setState(() => _currentPhotoIndex = index);
                              },
                              itemBuilder: (context, index) => GestureDetector(
                                onTap: () =>
                                    _openGallery(photos, imagesLocked: false),
                                child: _PublicProfilePhotoTile(
                                  url: photos[index],
                                  locked: false,
                                ),
                              ),
                            ),
                            if (photos.length > 1) ...[
                              Positioned(
                                left: 12,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: AnimatedOpacity(
                                    opacity: _currentPhotoIndex > 0 ? 1 : 0.35,
                                    duration: const Duration(milliseconds: 150),
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.black38,
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _currentPhotoIndex > 0
                                            ? _prevPhoto
                                            : null,
                                        icon: const Icon(
                                          Icons.chevron_left_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: AnimatedOpacity(
                                    opacity:
                                        _currentPhotoIndex < photos.length - 1
                                        ? 1
                                        : 0.35,
                                    duration: const Duration(milliseconds: 150),
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.black38,
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            _currentPhotoIndex <
                                                photos.length - 1
                                            ? () => _nextPhoto(photos.length)
                                            : null,
                                        icon: const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                      // ── Page Indicator ──────────────────────────
                      if (photos.length > 1)
                        Positioned(
                          bottom: 40,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: SmoothPageIndicator(
                              controller: _headerPageController,
                              count: photos.length,
                              effect: ScrollingDotsEffect(
                                activeDotColor: AppColors.gold,
                                dotColor: Colors.white54,
                                dotHeight: 8,
                                dotWidth: 8,
                              ),
                            ),
                          ),
                        ),
                      if (photos.isNotEmpty)
                        Positioned(
                          top: 56,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${_currentPhotoIndex + 1} / ${photos.length}',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      IgnorePointer(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                AppColors.background,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$name, $age',
                            style: AppTextStyles.headlineLarge,
                          ),
                          const SizedBox(width: 8),
                          if (profile['trust_badge'] == true)
                            const Icon(
                              Icons.verified_rounded,
                              color: AppColors.blessing,
                              size: 24,
                            ),
                        ],
                      ),
                      if (profile['is_photo_verified'] == true) ...[
                        const SizedBox(height: 6),
                        const PhotoVerifiedLabel(),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (profile['denomination'] != null)
                            tr(
                              denominationLabels[profile['denomination']
                                      .toString()] ??
                                  formatValue(
                                    profile['denomination'].toString(),
                                  ),
                            ),
                          if (profile['location_city'] != null)
                            profile['location_city'].toString(),
                        ].join(' • '),
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.gold,
                        ),
                      ),
                      if (profileCode(
                        profile['user_id'] ?? widget.userId,
                      ).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          tr('Profile ID: {id}', {
                            'id': profileCode(
                              profile['user_id'] ?? widget.userId,
                            ),
                          }),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                      if (marriagePlanLabel(profile['marriage_intent'])
                          case final plan?) ...[
                        const SizedBox(height: 10),
                        MarriagePlanTag(plan),
                      ],
                      const SizedBox(height: 16),
                      _trustStrip(profile),
                      const SizedBox(height: 24),

                      _sectionTitle(tr('About Me')),
                      const SizedBox(height: 12),
                      Text(
                        bio,
                        style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 32),

                      _sectionTitle(tr('Faith & Lifestyle')),
                      const SizedBox(height: 16),
                      if (_faithQuote(profile) case final quote?) ...[
                        quote,
                        const SizedBox(height: 12),
                      ],
                      _infoGrid([
                        _infoTile(
                          Icons.church_rounded,
                          tr('Church'),
                          profile['church_name'] ?? tr('Not specified'),
                        ),
                        if (baptismLabels[profile['baptism_status']]
                            case final b?)
                          _infoTile(Icons.water_drop_rounded, tr('Baptism'), b),
                        if ((profile['ministries'] as List?)
                                ?.map((m) => ministryLabels['$m'])
                                .whereType<String>()
                                .map(tr)
                                .whereType<String>()
                                .join(', ')
                            case final serves? when serves.isNotEmpty)
                          _infoTile(
                            Icons.volunteer_activism_rounded,
                            tr('Serves in'),
                            serves,
                          ),
                        if (churchAfterMarriageLabels[profile['church_after_marriage']]
                            case final after?)
                          _infoTile(
                            Icons.favorite_rounded,
                            tr('Church after marriage'),
                            after,
                          ),
                        _infoTile(
                          Icons.auto_awesome_rounded,
                          tr('Church Involvement'),
                          formatValue(profile['church_involvement']),
                        ),
                        _infoTile(
                          Icons.smoking_rooms_rounded,
                          tr('Smoking'),
                          formatValue(profile['smoking']),
                        ),
                        _infoTile(
                          Icons.local_bar_rounded,
                          tr('Drinking'),
                          formatValue(profile['drinking']),
                        ),
                        _infoTile(
                          Icons.restaurant_rounded,
                          tr('Diet'),
                          formatValue(profile['diet']),
                        ),
                      ]),
                      const SizedBox(height: 32),

                      _sectionTitle(tr('Education & Career')),
                      const SizedBox(height: 16),
                      _infoGrid([
                        _infoTile(
                          Icons.work_rounded,
                          tr('Profession'),
                          profile['profession'] ?? tr('Not specified'),
                        ),
                        _infoTile(
                          Icons.school_rounded,
                          tr('Education'),
                          profile['education'] ?? tr('Not specified'),
                        ),
                        _infoTile(
                          Icons.payments_rounded,
                          tr('Annual Income'),
                          '₹ ${formatCurrency(profile['annual_income_min'])} - ${formatCurrency(profile['annual_income_max'])}',
                        ),
                        _infoTile(
                          Icons.height_rounded,
                          tr('Height'),
                          profile['height_cm'] == null
                              ? tr('Not specified')
                              : '${profile['height_cm']} cm',
                        ),
                      ]),
                      const SizedBox(height: 32),

                      _sectionTitle(tr('Family Background')),
                      const SizedBox(height: 16),
                      _infoGrid([
                        _infoTile(
                          Icons.family_restroom_rounded,
                          tr('Father'),
                          family['father_occupation'] ?? tr('Not specified'),
                        ),
                        _infoTile(
                          Icons.face_retouching_natural_rounded,
                          tr('Mother'),
                          family['mother_occupation'] ?? tr('Not specified'),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      if (family['sibling_details'] != null &&
                          (family['sibling_details'] as List).isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 12),
                          child: Text(
                            tr('Siblings'),
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.goldMild,
                            ),
                          ),
                        ),
                        ...(family['sibling_details'] as List).map((sib) {
                          final s = sib as Map<String, dynamic>;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.surfaceHighest,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: s['type'] == 'Brother'
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.pink.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    s['type'] == 'Brother'
                                        ? Icons.boy_rounded
                                        : Icons.girl_rounded,
                                    color: s['type'] == 'Brother'
                                        ? Colors.blue
                                        : Colors.pink,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${s['type']} • ${formatValue(s['marital_status'])}',
                                        style: AppTextStyles.labelLarge,
                                      ),
                                      if (s['education'] != null &&
                                          s['education'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            s['education'].toString(),
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ] else ...[
                        _infoTile(
                          Icons.people_rounded,
                          tr('Siblings'),
                          '${family['brothers_count'] ?? 0} Brothers, ${family['sisters_count'] ?? 0} Sisters',
                        ),
                      ],

                      const SizedBox(height: 32),
                      if (hobbies.isNotEmpty) ...[
                        _sectionTitle(tr('Interests & Hobbies')),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: hobbies
                              .map(
                                (h) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: AppColors.surfaceHighest,
                                    ),
                                  ),
                                  child: Text(
                                    tr(h),
                                    style: AppTextStyles.labelSmall,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 32),
                      ],

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomBar(data),
        );
      },
    );
  }

  Widget? _buildBottomBar(Map<String, dynamic> data) {
    if (!widget.showBottomActions) return null;
    if (widget.userId == null) return null; // Own profile preview
    if (_myUserId == null) return null; // Still loading current user ID

    final status = data['interaction_status'] ?? 'none';
    final senderId = data['interaction_sender_id']?.toString();
    final interestId = data['interest_id']?.toString();
    final conversationId = data['conversation_id']?.toString();
    final isReceiver = senderId != null && senderId != _myUserId;

    if (status == 'none') {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(color: AppColors.background.withOpacity(0.8)),
        child: Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.close_rounded,
                color: AppColors.error,
                onTap: () {
                  AppHaptics.light();
                  context.pop();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () {
                  AppHaptics.heavy();
                  context.read<ProfileBloc>().add(
                    SendInterestEvent(userId: widget.userId!),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.textOnGold,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mail_rounded),
                    SizedBox(width: 8),
                    Text(
                      tr('SEND INTEREST'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'sent') {
      if (isReceiver && interestId != null) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    AppHaptics.light();
                    context.read<ProfileBloc>().add(
                      RejectInterestEvent(interestId),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: AppColors.surfaceHighest),
                  ),
                  child: Text(
                    tr('DECLINE'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    AppHaptics.heavy();
                    context.read<ProfileBloc>().add(
                      AcceptInterestEvent(interestId),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.textOnGold,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    tr('ACCEPT'),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Wrapped in a Row like every other branch. Without it this is a
        // Container of unbounded height inside bottomNavigationBar, and the
        // Center then expands to fill the entire screen.
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.goldMild),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.gold,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        tr('INTEREST SENT'),
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    if (status == 'accepted') {
      // Prefer embedded contact_status (avoids a second HTTP call).
      // Fall back to the dedicated endpoint only when not available.
      if (_contactStatus == null && !_contactLoading) {
        if (data.containsKey('contact_status') &&
            data['contact_status'] != null) {
          Future.microtask(() => _maybeApplyEmbeddedContactStatus(data));
        } else {
          Future.microtask(_loadContactStatus);
        }
      }

      final outgoing = _contactStatus?['outgoing'] as Map?;
      final phone = _contactStatus?['phone'] as String?;
      final outStatus = outgoing?['status'] as String?;

      final otherName = data['profile'] is Map
          ? (data['profile'] as Map)['first_name']?.toString() ?? 'Member'
          : 'Member';
      final photos = data['photos'];
      String otherPhoto = '';
      if (photos is List && photos.isNotEmpty) {
        final first = photos.first;
        if (first is Map) {
          otherPhoto = first['photo_url']?.toString() ?? '';
        } else if (first is String) {
          otherPhoto = first;
        }
      }

      return Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        decoration: BoxDecoration(
          color: AppColors.background.withOpacity(0.97),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_calls?.voice == true || _calls?.video == true) ...[
              Row(
                children: [
                  if (_calls?.voice == true)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: conversationId == null
                            ? null
                            : () => _startCall(
                                conversationId: conversationId,
                                peerName: otherName,
                                peerPhoto: otherPhoto,
                                video: false,
                              ),
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: Text(tr('Voice')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: BorderSide(color: AppColors.goldMild),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  if (_calls?.voice == true && _calls?.video == true)
                    const SizedBox(width: 10),
                  if (_calls?.video == true)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: conversationId == null
                            ? null
                            : () => _startCall(
                                conversationId: conversationId,
                                peerName: otherName,
                                peerPhoto: otherPhoto,
                                video: true,
                              ),
                        icon: const Icon(Icons.videocam_rounded, size: 18),
                        label: Text(tr('Video')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.textOnGold,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            // Send Message button
            ElevatedButton(
              onPressed: () {
                AppHaptics.heavy();
                if (conversationId != null) {
                  final otherName = data['profile'] is Map
                      ? (data['profile'] as Map)['first_name']?.toString()
                      : null;
                  context.push(
                    '/chat/$conversationId',
                    extra: {
                      'name': otherName ?? 'Member',
                      'userId': widget.userId,
                    },
                  );
                } else {
                  context.go('/chat');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.textOnGold,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    tr('SEND MESSAGE'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Contact reveal row
            _ContactRevealTile(
              outStatus: outStatus,
              phone: phone,
              loading: _contactLoading || _contactRequesting,
              onRequest: _requestContact,
            ),
            const SizedBox(height: 10),
            // AI Match Explanation
            _buildWhyWeMatchButton(data),
          ],
        ),
      );
    }

    return null;
  }

  Widget _buildWhyWeMatchButton(Map<String, dynamic> data) {
    final profile = data['profile'] is Map
        ? data['profile'] as Map<String, dynamic>
        : data;
    final name = profile['first_name']?.toString() ?? 'this member';
    final photos = data['photos'] as List?;
    final primaryPhoto = photos != null && photos.isNotEmpty
        ? photos.firstWhere(
            (p) => p['is_primary'] == true,
            orElse: () => photos.first,
          )
        : null;
    final photoUrl = primaryPhoto is Map
        ? (primaryPhoto['url'] ?? primaryPhoto['photo_url'])?.toString()
        : null;
    final compat = data['compatibility'] as int?;

    return OutlinedButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchExplanationScreen(
              targetUserId: widget.userId!,
              targetName: name,
              targetPhoto: photoUrl,
              compatibility: compat,
            ),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: BorderSide(color: AppColors.goldMild),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: AppColors.gold),
          SizedBox(width: 8),
          Text(
            tr('Why you are compatible'),
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  /// What sets a profile here apart, said up front: staff review before it
  /// is shown, who manages it, and how contact works.
  Widget _trustStrip(Map<String, dynamic> profile) {
    final rows = <(IconData, String)>[
      if (profile['review_status'] == 'approved')
        (Icons.fact_check_rounded, tr('Reviewed by the Grace Match team')),
      if (profile['trust_badge'] == true)
        (Icons.verified_rounded, tr('ID verified')),
      if (profile['profile_managed_by'] == 'parents')
        (Icons.family_restroom_rounded, tr('Profile managed by parents')),
      (Icons.lock_outline_rounded, tr('Phone number hidden until both agree')),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blessingSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, text) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.blessing),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(text),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Shares this member's public profile link (the same page as "Share my
  /// profile"), so a family can look at it together.
  Future<void> _shareOtherProfile(
    BuildContext anchor,
    String userId,
    String name,
  ) async {
    final url = '${AppConstants.siteUrl}/p/$userId';
    final box = anchor.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await Share.share(
        'A profile on GraceMatch, the Telugu Christian matrimony app: $name\n$url',
        subject: 'GraceMatch – $name',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(tr('Could not open the share sheet. Try again.')),
        ),
      );
    }
  }

  /// The member's own words about their faith, and their favourite verse.
  Widget? _faithQuote(Map<String, dynamic> profile) {
    final journey = '${profile['faith_journey'] ?? ''}'.trim();
    final verse = '${profile['favourite_verse'] ?? ''}'.trim();
    if (journey.isEmpty && verse.isEmpty) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: AppColors.gold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (journey.isNotEmpty)
            Text(
              journey,
              style: AppTextStyles.bodyMedium.copyWith(
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (journey.isNotEmpty && verse.isNotEmpty)
            const SizedBox(height: 10),
          if (verse.isNotEmpty)
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 16, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Favourite verse: {verse}', {'verse': verse}),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      tr(title),
      style: AppTextStyles.headlineSmall.copyWith(color: AppColors.textPrimary),
    );
  }

  /// Two cards per row. Both cards in a row take the taller one's height, so
  /// a value that wraps onto a second line keeps the row even.
  Widget _infoGrid(List<Widget> children) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 16));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.gold),
          const SizedBox(height: 8),
          Text(
            tr(label),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          // Full value, wrapped: church names and income ranges are long.
          Text(value, style: AppTextStyles.labelLarge),
        ],
      ),
    );
  }
}

// ─── Contact Reveal Tile ──────────────────────────────────────
class _ContactRevealTile extends StatelessWidget {
  final String? outStatus; // null | pending | approved | rejected | revoked
  final String? phone;
  final bool loading;
  final VoidCallback onRequest;

  const _ContactRevealTile({
    required this.outStatus,
    required this.phone,
    required this.loading,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    // Only the requester who paid for this reveal sees the number.
    if (phone != null && phone!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2E1B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.phone_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Contact Number'),
                    style: AppTextStyles.overline.copyWith(
                      color: Colors.green.shade300,
                    ),
                  ),
                  Text(
                    phone!,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (outStatus == 'revoked') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceHighest),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.phonelink_erase_rounded,
              color: AppColors.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Sharing stopped. This reveal still counts on your plan.'),
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Pending — show waiting state
    if (outStatus == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.goldMild),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: AppColors.gold, size: 18),
            const SizedBox(width: 10),
            Text(
              tr('Contact request pending…'),
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold),
            ),
          ],
        ),
      );
    }

    // Rejected or null — show request button
    return OutlinedButton.icon(
      onPressed: loading ? null : onRequest,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.gold,
              ),
            )
          : const Icon(Icons.phone_in_talk_rounded, size: 18),
      label: Text(
        outStatus == 'rejected' ? tr('Request Again') : tr('Request Contact'),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: BorderSide(color: AppColors.goldMild),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _PublicProfilePhotoTile extends StatelessWidget {
  final String url;
  final bool locked;

  const _PublicProfilePhotoTile({required this.url, required this.locked});

  @override
  Widget build(BuildContext context) {
    final base = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // Blurred beyond recognition anyway: a 64px decode looks the same
      // under the blur and costs a fraction of the memory.
      memCacheWidth: locked
          ? 64
          : decodePx(context, MediaQuery.sizeOf(context).width),
      placeholder: (context, url) =>
          Center(child: CircularProgressIndicator(color: AppColors.gold)),
      errorWidget: (context, url, error) =>
          const Icon(Icons.broken_image, color: Colors.white),
    );
    if (!locked) return base;
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: base,
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  color: Colors.white.withOpacity(0.9),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  tr('Locked'),
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
