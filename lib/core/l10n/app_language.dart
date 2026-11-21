import 'package:flutter/widgets.dart';

import '../storage/app_storage.dart';
import 'te.dart';

/// The app's language: English or Telugu, chosen in Settings or on the
/// sign-up screen and remembered on the phone. Text without a Telugu
/// translation yet stays in English.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();

  static const supported = [Locale('en'), Locale('te')];

  String _code = 'en';
  String get code => _code;
  bool get isTelugu => _code == 'te';
  Locale get locale => Locale(_code);

  /// Call after AppStorage.init().
  void load() => _code = AppStorage.getLanguage() == 'te' ? 'te' : 'en';

  void set(String code) {
    final next = code == 'te' ? 'te' : 'en';
    if (next == _code) return;
    _code = next;
    try {
      AppStorage.saveLanguage(next);
    } catch (_) {
      // Storage not open (tests, or it failed at launch): still switch now.
    }
    notifyListeners();
  }
}

/// The text in the current language. [en] is the English text, which is also
/// the key; {name} placeholders are filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = AppLanguage.instance.isTelugu ? (teluguStrings[en] ?? en) : en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}
