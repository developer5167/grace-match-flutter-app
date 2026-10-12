import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/app_constants.dart';

/// Verification, in two independent parts.
///
///  * Identity — earns the ✅ Verified tick. DigiLocker for almost everyone;
///    a passport reviewed by staff for members who cannot use DigiLocker
///    (NRIs, Aadhaar not linked to a mobile number).
///  * Photos — earns "Photo verified". A selfie that staff compare against the
///    profile photo. It does not gate the tick.
///
/// Until DigiLocker is configured on the server, identity falls back to a
/// document upload so nobody is left without a way to verify.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();

  bool _loading = true;

  // What the server knows about this member (from /profile/me).
  bool _idVerified = false;
  bool _photoVerified = false;
  bool _selfiePending = false;
  bool _documentPending = false;
  String? _idRejection;

  // ── DigiLocker.
  //
  // The member signs in on DigiLocker's own page, in an in-app browser, and
  // approves sharing. Nothing is typed into this app — no Aadhaar number ever
  // passes through it. When they close the browser and come back, the screen
  // asks the server what happened.
  bool _dlAvailable = false;
  bool _dlStarting = false;
  bool _dlWaiting = false;
  String? _dlMessage;

  // ── Passport / document upload.
  bool _showPassport = false;
  File? _document;
  bool _uploadingDocument = false;

  // ── Selfie.
  bool _uploadingSelfie = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from DigiLocker's page.
    if (state == AppLifecycleState.resumed && _dlWaiting) {
      _refresh(afterDigiLocker: true);
    }
  }

  Future<void> _refresh({bool afterDigiLocker = false}) async {
    Map<String, dynamic> me = const {};
    Map<String, dynamic> dl = const {};
    try {
      final res = await DioClient.instance.get(ApiEndpoints.myProfile);
      me = Map<String, dynamic>.from(res.data['data']?['verification'] ?? {});
    } catch (_) {/* shown as not verified; every action still works */}
    try {
      final res = await DioClient.instance.get(ApiEndpoints.digilockerStatus);
      dl = Map<String, dynamic>.from(res.data['data'] ?? {});
    } catch (_) {/* DigiLocker simply stays hidden */}

    if (!mounted) return;
    final last = dl['last_attempt'] is Map ? Map<String, dynamic>.from(dl['last_attempt']) : null;
    final wasVerified = _idVerified;
    setState(() {
      _loading = false;
      _idVerified = me['is_id_verified'] == true || dl['verified'] == true;
      _photoVerified = me['is_selfie_verified'] == true;
      _selfiePending = me['has_selfie'] == true && !_photoVerified;
      _documentPending = me['has_id_proof'] == true && !_idVerified;
      _idRejection = me['id_rejection_reason']?.toString();
      _dlAvailable = dl['available'] == true;
      _dlWaiting = false;
      if (afterDigiLocker && !_idVerified) {
        // The server's own explanation — "the date of birth does not match"
        // tells the member what to fix; a generic failure does not.
        _dlMessage = last?['message']?.toString() ??
            (last?['outcome'] == 'denied'
                ? 'Verification was cancelled. Nothing was shared.'
                : 'Verification did not complete. Please try again.');
      }
    });
    if (afterDigiLocker && _idVerified && !wasVerified) {
      _toast('Your identity is verified.', ok: true);
    }
  }

  void _toast(String message, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: ok ? AppColors.success : AppColors.error,
    ));
  }

  String _errorText(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      final msg = e.response?.data['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return fallback;
  }

  // ── DigiLocker ────────────────────────────────────────────────────────
  Future<void> _startDigiLocker() async {
    setState(() { _dlStarting = true; _dlMessage = null; });
    try {
      final res = await DioClient.instance.post(ApiEndpoints.digilockerStart);
      final url = res.data['data']?['authorize_url']?.toString();
      if (url == null) throw Exception('No DigiLocker link was returned');

      _dlWaiting = true;
      // A new authorize URL every tap. The in-app Custom Tab keeps the last
      // DigiLocker/callback page, so a retry was reopening the failed session
      // instead of starting again. Chrome/Safari as a real tab does not.
      final uri = Uri.parse(url);
      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      }
      if (!opened) throw Exception('Could not open DigiLocker');
    } catch (e) {
      _dlWaiting = false;
      _toast(_errorText(e, e is DioException
          ? 'Could not start DigiLocker verification.'
          : e.toString().replaceFirst('Exception: ', '')));
    } finally {
      if (mounted) setState(() => _dlStarting = false);
    }
  }

  // ── Passport / document ───────────────────────────────────────────────
  Future<void> _pickDocument() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() => _document = File(picked.path));
  }

  Future<void> _uploadDocument() async {
    if (_document == null) return;
    setState(() => _uploadingDocument = true);
    try {
      await DioClient.instance.post(
        ApiEndpoints.verifyIdentity,
        data: FormData.fromMap({
          // Explicit type: Dio otherwise sends application/octet-stream, which
          // the server's image filter rejects.
          'id_proof': await MultipartFile.fromFile(
            _document!.path,
            filename: 'id_proof.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        }),
      );
      setState(() { _document = null; _documentPending = true; _idRejection = null; });
      _toast('Received. Our team will review it, usually within a day.', ok: true);
    } catch (e) {
      _toast(_errorText(e, 'Upload failed. Please try again.'));
    } finally {
      if (mounted) setState(() => _uploadingDocument = false);
    }
  }

  // ── Selfie ────────────────────────────────────────────────────────────
  Future<void> _takeSelfie() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (shot == null) return;

    setState(() => _uploadingSelfie = true);
    try {
      await DioClient.instance.post(
        ApiEndpoints.verificationSelfie,
        data: FormData.fromMap({
          'selfie': await MultipartFile.fromFile(
            shot.path,
            filename: 'selfie.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        }),
      );
      setState(() => _selfiePending = true);
      _toast('Selfie received. Our team will confirm it shortly.', ok: true);
    } catch (e) {
      _toast(_errorText(e, 'Could not upload the selfie. Please try again.'));
    } finally {
      if (mounted) setState(() => _uploadingSelfie = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verification'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  _sectionTitle('Identity', 'Earns the Verified tick on your profile'),
                  const SizedBox(height: 12),
                  ..._identitySection(),
                  const SizedBox(height: 36),
                  _sectionTitle('Photos', 'Shows members your photos are really you'),
                  const SizedBox(height: 12),
                  _photoSection(),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.headlineSmall),
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      );

  Widget _doneCard(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.blessingSubtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.blessing.withAlpha(120)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.blessing, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.blessing)),
          ),
        ]),
      );

  Widget _waitingCard(String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceHighest),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ),
        ]),
      );

  Widget _goldButton(String label, VoidCallback? onPressed, {bool busy = false}) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.textOnGold,
            disabledBackgroundColor: AppColors.surfaceHighest,
            disabledForegroundColor: AppColors.textTertiary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          child: busy
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnGold))
              : Text(label),
        ),
      );

  List<Widget> _identitySection() {
    if (_idVerified) {
      return [_doneCard(Icons.verified_rounded, 'Identity verified')];
    }

    // DigiLocker not set up on the server yet: a reviewed document is the
    // only route, so show it directly and accept any government ID.
    if (!_dlAvailable) {
      return [_documentPanel(passportOnly: false)];
    }

    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.goldMild),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bolt_rounded, color: AppColors.gold, size: 20),
              const SizedBox(width: 6),
              Text('Instant', style: AppTextStyles.overline.copyWith(color: AppColors.gold)),
            ]),
            const SizedBox(height: 8),
            Text('Verify with DigiLocker', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Sign in to DigiLocker and approve sharing. We check your name, date of birth '
              'and gender against your profile. Your Aadhaar number is never shared with us.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            if (_dlMessage != null) ...[
              const SizedBox(height: 12),
              Text(_dlMessage!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.roseDark)),
            ],
            const SizedBox(height: 16),
            _goldButton('Continue with DigiLocker', _startDigiLocker, busy: _dlStarting),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (!_showPassport && !_documentPending)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _showPassport = true),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text("Don't have Aadhaar or living abroad? Use your passport",
                textAlign: TextAlign.center),
          ),
        ),
      if (_showPassport || _documentPending) ...[
        const SizedBox(height: 12),
        _documentPanel(passportOnly: true),
      ],
    ];
  }

  Widget _documentPanel({required bool passportOnly}) {
    if (_documentPending) {
      return _waitingCard(passportOnly
          ? 'Your passport is with our team. We usually review it within a day.'
          : 'Your document is with our team. We usually review it within a day.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          passportOnly
              ? 'Upload a clear photo of your passport\'s photo page. Our team reviews it, '
                  'usually within a day.'
              : 'Upload a clear photo of a government ID (Aadhaar, PAN or passport). '
                  'Our team reviews it, usually within a day.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        if (_idRejection != null && _idRejection!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Last upload was not accepted: $_idRejection',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.roseDark)),
        ],
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _uploadingDocument ? null : _pickDocument,
          child: Container(
            height: 170,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceHighest),
            ),
            child: _document != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(_document!, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded, size: 40, color: AppColors.goldMild),
                      const SizedBox(height: 10),
                      Text(passportOnly ? 'Select passport photo' : 'Select ID photo',
                          style: AppTextStyles.labelMedium),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        _goldButton(
          _document == null ? 'Select a photo first' : 'Submit for review',
          _document == null ? null : _uploadDocument,
          busy: _uploadingDocument,
        ),
      ],
    );
  }

  Widget _photoSection() {
    if (_photoVerified) {
      return _doneCard(Icons.face_retouching_natural_rounded, 'Photo verified');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selfiePending) ...[
          _waitingCard('Your selfie is with our team. We compare it with your profile photo, '
              'usually within a day.'),
          const SizedBox(height: 12),
        ] else ...[
          Text(
            'Take a clear selfie facing the camera, in good light, without sunglasses. '
            'Our team compares it with your main profile photo. The selfie is never shown '
            'to other members.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
        ],
        _goldButton(_selfiePending ? 'Retake selfie' : 'Take a selfie', _takeSelfie,
            busy: _uploadingSelfie),
      ],
    );
  }
}
