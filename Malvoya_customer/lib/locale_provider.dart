import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const List<String> supportedCodes = [
    'en', 'fi', 'sv', 'de', 'fr', 'nl', 'it', 'es', 'pt',
    'pl', 'ro', 'cs', 'hu', 'el', 'da', 'sk', 'bg', 'hr',
    'no', 'ru', 'tr', 'uk', 'ar', 'zh', 'hi'
  ];

  LocaleProvider() {
    _loadLocale();
  }

  void setLocale(Locale locale) async {
    if (!supportedCodes.contains(locale.languageCode)) return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
    await prefs.setString('selected_user_locale', locale.languageCode);
  }

  void setLocaleCode(String languageCode) {
    setLocale(Locale(languageCode));
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null && supportedCodes.contains(languageCode)) {
      _locale = Locale(languageCode);
      notifyListeners();
    } else {
      try {
        final sysLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (supportedCodes.contains(sysLocale.languageCode)) {
          _locale = Locale(sysLocale.languageCode);
        } else {
          _locale = const Locale('fi');
        }
        notifyListeners();
      } catch (_) {
        _locale = const Locale('fi');
        notifyListeners();
      }
    }
  }
}
