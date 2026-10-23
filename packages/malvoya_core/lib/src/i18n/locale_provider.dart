import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_language.dart';

/// The app language as a `ChangeNotifier` for `MaterialApp.locale`.
///
/// Loads the saved choice (key `languageCode`; the customer app's older `selected_user_locale` is
/// still read), falls back to the phone's language when it is Finnish or English and to Finnish
/// otherwise, and keeps [AppLanguage.code] in sync for code without a `BuildContext`.
class LocaleProvider extends ChangeNotifier {
  /// Starts loading the saved language at once; until then the app is in Finnish.
  LocaleProvider({this.followSystem = true}) {
    _load();
  }

  /// Use the phone's language when nothing was saved yet (when it is Finnish or English).
  final bool followSystem;

  Locale _locale = const Locale('fi');

  /// The current locale ("fi" or "en").
  Locale get locale => _locale;

  /// Called when the user picks another language (not when the saved one is loaded), for example
  /// to save it on the account so pushes and emails follow it.
  void Function(String languageCode)? onUserChange;

  /// The user picked a language. Unsupported codes are ignored.
  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode;
    if (!AppLanguage.supportedCodes.contains(code)) return;
    final changed = code != _locale.languageCode || code != AppLanguage.code;
    _locale = Locale(code);
    AppLanguage.code = code;
    notifyListeners();
    if (changed) onUserChange?.call(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('languageCode', code);
    } catch (_) {}
  }

  /// [setLocale] by language code.
  Future<void> setLocaleCode(String languageCode) => setLocale(Locale(languageCode));

  /// The saved language, or null when nothing (supported) was saved.
  static Future<String?> savedCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('languageCode') ?? prefs.getString('selected_user_locale');
      return AppLanguage.supportedCodes.contains(saved) ? saved : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    var code = await savedCode();
    if (code == null && followSystem) {
      try {
        final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        if (AppLanguage.supportedCodes.contains(system)) code = system;
      } catch (_) {}
    }
    code ??= 'fi';
    _locale = Locale(code);
    AppLanguage.code = code;
    notifyListeners();
  }
}
