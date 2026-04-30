import 'package:flutter/material.dart';

class AppLocalizations {
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  final Locale locale;
  AppLocalizations(this.locale);

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'deliveringTo': 'Delivering to',
      'categories': 'Categories',
      'storesNearYou': 'Stores Near You',
      'activeDelivery': 'Active Delivery',
      'searchHint': 'Search for clothes, cosmetics...',
      'profile': 'Profile',
      'orders': 'Orders',
      'home': 'Home',
      'search': 'Search',
      'login': 'Log In',
      'email': 'Email',
      'password': 'Password',
    },
    'fi': {
      'deliveringTo': 'Toimitusosoite',
      'categories': 'Kategoriat',
      'storesNearYou': 'Kaupat lähelläsi',
      'activeDelivery': 'Aktiivinen toimitus',
      'searchHint': 'Hae vaatteita, kosmetiikkaa...',
      'profile': 'Profiili',
      'orders': 'Tilaukset',
      'home': 'Koti',
      'search': 'Haku',
      'login': 'Kirjaudu sisään',
      'email': 'Sähköposti',
      'password': 'Salasana',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? _localizedValues['en']![key] ?? key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'fi'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
