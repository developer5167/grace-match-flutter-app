import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';

class AppStorage {
  AppStorage._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ─── Secure Storage (Tokens) ──────────────────────────────────
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _secure.write(key: StorageKeys.accessToken, value: accessToken),
      _secure.write(key: StorageKeys.refreshToken, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() =>
      _secure.read(key: StorageKeys.accessToken);

  static Future<String?> getRefreshToken() =>
      _secure.read(key: StorageKeys.refreshToken);

  static Future<void> saveUserId(String userId) =>
      _secure.write(key: StorageKeys.userId, value: userId);

  static Future<String?> getUserId() =>
      _secure.read(key: StorageKeys.userId);

  static Future<void> clearAll() async {
    await _secure.deleteAll();
    if (_prefs.isOpen) {
      await _prefs.delete(StorageKeys.onboardingStep);
      await _prefs.delete(StorageKeys.onboardingComplete);
      await _prefs.delete('review_status');
    }
  }

  // ─── Hive Boxes ───────────────────────────────────────────────
  static late Box _prefs;

  static Future<void> init() async {
    await Hive.initFlutter();
    _prefs = await Hive.openBox('prefs');
  }

  static void saveOnboardingStep(int step) =>
      _prefs.put(StorageKeys.onboardingStep, step);

  static int getOnboardingStep() =>
      _prefs.get(StorageKeys.onboardingStep, defaultValue: 0) as int;

  static void saveOnboardingComplete(bool val) =>
      _prefs.put(StorageKeys.onboardingComplete, val);

  static bool isOnboardingComplete() =>
      _prefs.get(StorageKeys.onboardingComplete, defaultValue: false) as bool;

  static void saveReviewStatus(String? status) =>
      _prefs.put('review_status', status);

  static String? getReviewStatus() =>
      _prefs.get('review_status') as String?;

  static bool wasCallScreenPermissionAsked() =>
      _prefs.get('call_fsi_asked', defaultValue: false) as bool;

  static void markCallScreenPermissionAsked() => _prefs.put('call_fsi_asked', true);

  static void saveSkippedUpdateVersion(String version) =>
      _prefs.put(StorageKeys.skippedUpdateVersion, version);

  static String? getSkippedUpdateVersion() =>
      _prefs.get(StorageKeys.skippedUpdateVersion) as String?;

  /// Shared profile the guest opened (or tapped Get the app for) before login.
  static void setPendingShareProfile(String? userId) {
    if (userId == null || userId.isEmpty) {
      _prefs.delete(StorageKeys.pendingShareProfileId);
    } else {
      _prefs.put(StorageKeys.pendingShareProfileId, userId);
    }
  }

  static String? getPendingShareProfile() =>
      _prefs.get(StorageKeys.pendingShareProfileId) as String?;

  /// Full in-app profile once the member is approved; otherwise keep waiting.
  static String? takeShareResumeRoute() {
    final id = getPendingShareProfile();
    if (id == null) return null;
    if (!isOnboardingComplete()) return null;
    if (getReviewStatus() != 'approved') return null;
    _prefs.delete(StorageKeys.pendingShareProfileId);
    return '/profile/$id';
  }
}
