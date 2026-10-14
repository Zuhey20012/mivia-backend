import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('fi');

  Locale get locale => _locale;

  /// The app is written in Finnish and English only.
  static const List<String> supportedCodes = ['fi', 'en'];

  LocaleProvider() {
    _loadLocale();
  }

  void setLocale(Locale locale) async {
    if (!supportedCodes.contains(locale.languageCode)) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null && supportedCodes.contains(languageCode)) {
      _locale = Locale(languageCode);
      notifyListeners();
    }
  }
}
