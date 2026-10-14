import 'package:flutter/material.dart';

/// The store app speaks Finnish and English. Newer screens use `tr(context, en, fi)` from
/// core/strings.dart; this table only holds the sign-in screen's original strings.
class AppLocalizations {
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ?? AppLocalizations(const Locale('en'));
  }

  final Locale locale;
  AppLocalizations(this.locale);

  /// Languages the whole app is written in (no others are offered: they would be mostly English).
  static const Map<String, String> languages = {
    'fi': 'Suomi',
    'en': 'English',
  };

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'login': 'Sign in',
      'email': 'Email or phone number',
      'password': 'Password',
      'welcomeBack': 'Welcome back',
      'signIn': 'Sign in to your store account',
    },
    'fi': {
      'login': 'Kirjaudu sisään',
      'email': 'Sähköposti tai puhelinnumero',
      'password': 'Salasana',
      'welcomeBack': 'Tervetuloa takaisin',
      'signIn': 'Kirjaudu kauppatilillesi',
    },
  };

  String get(String key) => translate(key);

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.languages.containsKey(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
