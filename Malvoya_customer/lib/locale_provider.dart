import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_language.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('fi');

  Locale get locale => _locale;

  // Only fully translated languages are offered
  static const List<String> supportedCodes = ['en', 'fi'];

  LocaleProvider() {
    _loadLocale();
  }

  void setLocale(Locale locale) async {
    if (!supportedCodes.contains(locale.languageCode)) return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    AppLanguage.set(locale.languageCode);
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
      AppLanguage.set(languageCode);
      notifyListeners();
    } else {
      try {
        final sysLocale = WidgetsBinding.instance.platformDispatcher.locale;
        if (supportedCodes.contains(sysLocale.languageCode)) {
          _locale = Locale(sysLocale.languageCode);
        } else {
          _locale = const Locale('fi');
        }
        AppLanguage.set(_locale.languageCode);
        notifyListeners();
      } catch (_) {
        _locale = const Locale('fi');
        notifyListeners();
      }
    }
  }
}
