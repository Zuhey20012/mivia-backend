import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/**
 * Enterprise Reactive Locale Controller
 * Provides instantaneous app-wide locale switching and atomic widget tree relayout
 * with persistent storage across cold boots.
 */
class LocaleController extends ChangeNotifier {
  static const String _prefKey = 'selected_user_locale';
  Locale _currentLocale = const Locale('en');

  Locale get currentLocale => _currentLocale;
  Locale get locale => _currentLocale;

  static const List<String> supportedCodes = [
    'en', 'fi', 'sv', 'de', 'fr', 'nl', 'it', 'es', 'pt',
    'pl', 'ro', 'cs', 'hu', 'el', 'da', 'sk', 'bg', 'hr',
    'no', 'ru', 'tr', 'uk', 'ar', 'zh', 'hi'
  ];

  LocaleController() {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString(_prefKey) ?? prefs.getString('languageCode');
    if (languageCode != null && supportedCodes.contains(languageCode)) {
      _currentLocale = Locale(languageCode);
      notifyListeners();
    }
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedCodes.contains(languageCode)) return;
    if (_currentLocale.languageCode == languageCode) return;
    _currentLocale = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, languageCode);
    await prefs.setString('languageCode', languageCode);
    notifyListeners(); // Immediate atomic relayout across all mounted routes
  }
}
