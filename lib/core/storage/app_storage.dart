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
  //
  // The access token is read on every request and every route change. It is
  // kept in memory once read, so those reads stop going to the keychain /
  // keystore. Every write in this isolate goes through [saveTokens] and
  // [clearAll], which update the copy. A background isolate (a call declined
  // from the lock screen) can rotate the tokens on its own, so the copy is
  // dropped when the app comes back to the foreground ([reloadTokens]).
  static String? _accessToken;
  static bool _accessTokenLoaded = false;
  // Bumped by every write, so a read that started before it cannot put the
  // old value back into memory.
  static int _tokenWrites = 0;

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _tokenWrites++;
    _accessToken = accessToken;
    _accessTokenLoaded = true;
    await Future.wait([
      _secure.write(key: StorageKeys.accessToken, value: accessToken),
      _secure.write(key: StorageKeys.refreshToken, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() async {
    if (_accessTokenLoaded) return _accessToken;
    final writes = _tokenWrites;
    final token = await _secure.read(key: StorageKeys.accessToken);
    if (writes != _tokenWrites) {
      // Written while this read was out; the write is newer.
      return _accessTokenLoaded ? _accessToken : token;
    }
    _accessToken = token;
    _accessTokenLoaded = true;
    return token;
  }

  /// Forget the in-memory access token; the next read goes to secure
  /// storage. For when another isolate may have written it.
  static void reloadTokens() {
    _tokenWrites++;
    _accessToken = null;
    _accessTokenLoaded = false;
  }

  static Future<String?> getRefreshToken() =>
      _secure.read(key: StorageKeys.refreshToken);

  static Future<void> saveUserId(String userId) =>
      _secure.write(key: StorageKeys.userId, value: userId);

  static Future<String?> getUserId() => _secure.read(key: StorageKeys.userId);

  static Future<void> clearAll() async {
    _tokenWrites++;
    _accessToken = null;
    _accessTokenLoaded = true;
    await _secure.deleteAll();
    if (_prefs.isOpen) {
      await _prefs.delete(StorageKeys.onboardingStep);
      await _prefs.delete(StorageKeys.onboardingComplete);
      await _prefs.delete('review_status');
      await _prefs.delete(StorageKeys.membershipPlan);
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

  static String? getReviewStatus() => _prefs.get('review_status') as String?;

  static bool wasCallScreenPermissionAsked() =>
      _prefs.get('call_fsi_asked', defaultValue: false) as bool;

  static void markCallScreenPermissionAsked() =>
      _prefs.put('call_fsi_asked', true);

  static void saveSkippedUpdateVersion(String version) =>
      _prefs.put(StorageKeys.skippedUpdateVersion, version);

  static String? getSkippedUpdateVersion() =>
      _prefs.get(StorageKeys.skippedUpdateVersion) as String?;

  static void saveMembershipPlan(String name) =>
      _prefs.put(StorageKeys.membershipPlan, name);

  static String? getMembershipPlan() =>
      _prefs.get(StorageKeys.membershipPlan) as String?;

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
