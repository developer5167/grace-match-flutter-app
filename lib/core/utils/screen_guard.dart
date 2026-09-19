import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:screen_protector/screen_protector.dart';

import '../network/dio_client.dart';
import '../constants/app_constants.dart';

/// Screenshot handling for screens that show someone else's photos.
///
/// What is actually achievable, stated plainly:
///
///   Android  already covered app-wide. MainActivity.kt sets FLAG_SECURE for
///            the whole window at startup, which blocks screenshots and blanks
///            the app in the recents switcher. This class deliberately does
///            NOT touch it — calling preventScreenshotOff() on the way out of
///            a profile would disable that app-wide protection for the rest of
///            the session, which is the opposite of the intent.
///   iOS       screenshots cannot be blocked at all. They can only be detected
///            after the fact, so that is what happens here.
///
/// Where prevention is impossible, the fallback is honesty: tell the person
/// whose photos were captured. That is what they would want to know, and it is
/// what deters the casual version of this.
///
/// Every call is best-effort. A platform channel failing must never take down
/// the screen the member was trying to look at.
class ScreenGuard {
  ScreenGuard._();

  /// Hide the screen from the iOS app switcher while photos are on it.
  ///
  /// Android is skipped entirely: FLAG_SECURE is already set for the whole
  /// window, and reaching for the plugin here would only give this class the
  /// power to switch it off later.
  static Future<void> protect() async {
    if (!Platform.isIOS) return;
    try {
      await ScreenProtector.protectDataLeakageOn();
    } catch (e) {
      debugPrint('screen protection unavailable: $e');
    }
  }

  /// Undo [protect]. iOS only, for the same reason.
  static Future<void> release() async {
    if (!Platform.isIOS) return;
    try {
      await ScreenProtector.protectDataLeakageOff();
    } catch (e) {
      debugPrint('screen protection release failed: $e');
    }
  }

  /// Watch for screenshots and report them.
  ///
  /// iOS only in practice — Android has already blocked it by this point.
  static Future<void> watch(String subjectUserId, {String surface = 'profile'}) async {
    if (!Platform.isIOS) return;
    try {
      // Second callback is screen recording — the same concern, and on iOS
      // the only warning the subject will ever get about it.
      ScreenProtector.addListener(
        () => report(subjectUserId, surface: surface),
        (isRecording) {
          if (isRecording) report(subjectUserId, surface: surface);
        },
      );
    } catch (e) {
      debugPrint('screenshot listener unavailable: $e');
    }
  }

  static Future<void> unwatch() async {
    try {
      ScreenProtector.removeListener();
    } catch (_) {
      // Nothing to do; the screen is going away regardless.
    }
  }

  /// Tell the server, which tells the person who was captured.
  ///
  /// Deliberately silent on failure: the member who took the screenshot is not
  /// the audience for an error about it.
  static Future<void> report(String subjectUserId, {String surface = 'profile'}) async {
    try {
      await DioClient.instance.post(ApiEndpoints.screenshotAlert, data: {
        'subject_id': subjectUserId,
        'surface': surface,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('screenshot report failed: $e');
    }
  }
}
