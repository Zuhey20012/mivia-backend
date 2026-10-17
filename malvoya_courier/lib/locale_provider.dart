import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/server_messages.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('fi');

  Locale get locale => _locale;

  // Only fully translated languages are offered
  static const List<String> supportedCodes = ['en', 'fi'];

  /// Called when the user picks a language (not when the saved one is loaded), e.g. to tell the server.
  void Function(String languageCode)? onChanged;

  LocaleProvider() {
    _loadLocale();
  }

  void setLocale(Locale locale) async {
    if (!supportedCodes.contains(locale.languageCode)) return;
    _locale = locale;
    ServerMessages.languageCode = locale.languageCode;
    notifyListeners();
    onChanged?.call(locale.languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null && supportedCodes.contains(languageCode)) {
      _locale = Locale(languageCode);
      ServerMessages.languageCode = languageCode;
      notifyListeners();
    }
  }
}
