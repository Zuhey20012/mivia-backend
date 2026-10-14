import 'package:flutter/material.dart';

/// Copy for the welcome and sign-in screens. The rest of the app uses `tr(context, en, fi)`.
/// Only English and Finnish are offered, because only they are fully translated.
class AppLocalizations {
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ?? AppLocalizations(const Locale('en'));
  }

  final Locale locale;
  AppLocalizations(this.locale);

  static final Map<String, String> languages = {
    'en': 'English',
    'fi': 'Suomi',
  };

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'selectLanguage': 'Select language',
      'login': 'Log in',
      'email': 'Email',
      'password': 'Password',
      'welcomeBack': 'Welcome back',
      'signIn': 'Sign in to your courier account',
      'courierWelcomeTitle': 'Deliver with Malvoya',
      'courierWelcomeSubtitle': 'Deliver orders from local fashion stores when it suits you. You choose your jobs and see the pay before you accept.',
      'courierBadge': 'LOCAL DELIVERIES • FINLAND',
      'courierRate': 'Pay shown on every job before you accept',
      'whyDeliver': 'How it works',
      'applyToDeliver': 'Apply to deliver',
      'alreadyPartnerSignIn': 'Already a courier? Sign in',
      'perkFlexible': 'You decide when',
      'perkFlexibleDesc': 'Go online when it suits you and decline any job without consequences. There are no shifts or minimum hours.',
      'perkEarnings': 'Pay shown up front',
      'perkEarningsDesc': 'Each offer shows your pay and how it is worked out before you accept. Tips go to you in full. The pay for each delivery is sent to your Stripe account right after the handover.',
      'perkRetail': 'Local trips',
      'perkRetailDesc': 'Carry clothes and accessories from local stores to customers nearby. Jobs are offered first to couriers within 7.5 km of the store.',
      'perkVehicle': 'Your choice of vehicle',
      'perkVehicleDesc': 'Bicycle, e-bike, scooter or car. You choose how you ride.',
      'perkEntrepreneur': 'Independent entrepreneur',
      'perkEntrepreneurDesc': 'You deliver as an independent entrepreneur and may also work for other platforms. You need to be 18 or older, have the right to work in Finland and a Y-tunnus (or a light-entrepreneur service), and you handle your own taxes and insurance.',
      'earlyTitle': 'Malvoya is just starting',
      'earlyDesc': 'There are only a few stores and customers so far, so jobs may be rare at first. We do not promise any number of jobs or level of earnings.',
      'malvoyaCourier': 'Malvoya Courier',
    },
    'fi': {
      'selectLanguage': 'Valitse kieli',
      'login': 'Kirjaudu sisään',
      'email': 'Sähköposti',
      'password': 'Salasana',
      'welcomeBack': 'Tervetuloa takaisin',
      'signIn': 'Kirjaudu lähettitilillesi',
      'courierWelcomeTitle': 'Toimita Malvoyalla',
      'courierWelcomeSubtitle': 'Toimita paikallisten muotikauppojen tilauksia silloin kun sinulle sopii. Valitset keikkasi ja näet palkkion ennen hyväksymistä.',
      'courierBadge': 'PAIKALLISET TOIMITUKSET • SUOMI',
      'courierRate': 'Palkkio näkyy jokaisessa keikassa ennen hyväksyntää',
      'whyDeliver': 'Näin se toimii',
      'applyToDeliver': 'Hae lähetiksi',
      'alreadyPartnerSignIn': 'Oletko jo lähetti? Kirjaudu sisään',
      'perkFlexible': 'Päätät itse milloin',
      'perkFlexibleDesc': 'Mene linjoille silloin kun sinulle sopii ja kieltäydy mistä tahansa keikasta ilman seurauksia. Ei vuoroja eikä minimitunteja.',
      'perkEarnings': 'Palkkio näkyy etukäteen',
      'perkEarningsDesc': 'Jokainen tarjous näyttää palkkiosi ja sen laskutavan ennen kuin hyväksyt. Tipit saat kokonaan. Toimituksen palkkio lähetetään Stripe-tilillesi heti luovutuksen jälkeen.',
      'perkRetail': 'Paikallisia matkoja',
      'perkRetailDesc': 'Kuljeta vaatteita ja asusteita paikallisista kaupoista lähellä oleville asiakkaille. Keikat tarjotaan ensin läheteille 7,5 km:n säteellä kaupasta.',
      'perkVehicle': 'Valitse kulkuneuvosi',
      'perkVehicleDesc': 'Polkupyörä, sähköpyörä, skootteri tai auto. Päätät itse.',
      'perkEntrepreneur': 'Itsenäinen yrittäjä',
      'perkEntrepreneurDesc': 'Toimitat itsenäisenä yrittäjänä ja voit tehdä keikkoja myös muille alustoille. Sinun pitää olla vähintään 18-vuotias ja sinulla pitää olla oikeus tehdä työtä Suomessa sekä Y-tunnus (tai laskutuspalvelu). Hoidat itse verosi ja vakuutuksesi.',
      'earlyTitle': 'Malvoya on vasta aloittamassa',
      'earlyDesc': 'Kauppoja ja asiakkaita on vielä vähän, joten keikkoja voi aluksi olla harvoin. Emme lupaa tiettyä määrää keikkoja tai ansioita.',
      'malvoyaCourier': 'Malvoya Courier',
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
  bool shouldReload(_AppLocalizationsDelegate old) => true;
}
