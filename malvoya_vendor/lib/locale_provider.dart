import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('fi');

  Locale get locale => _locale;

  /// The current language for code without a BuildContext (e.g. API error messages).
  static String currentCode = 'fi';

  /// The app is written in Finnish and English only.
  static const List<String> supportedCodes = ['fi', 'en'];

  LocaleProvider() {
    _loadLocale();
  }

  /// Called when the user picks another language (main.dart passes it on to the server, so push
  /// notifications and emails follow it).
  static void Function(String code)? onUserChange;

  void setLocale(Locale locale) async {
    if (!supportedCodes.contains(locale.languageCode)) return;
    final changed = locale.languageCode != currentCode;
    _locale = locale;
    currentCode = locale.languageCode;
    notifyListeners();
    if (changed) onUserChange?.call(currentCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null && supportedCodes.contains(languageCode)) {
      _locale = Locale(languageCode);
      currentCode = languageCode;
      notifyListeners();
    }
  }
}
