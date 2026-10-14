import 'package:flutter/material.dart';

/// Copy for the screens that use `AppLocalizations.of(context).translate(key)`.
/// Newer screens use `tr(context, en, fi)` from core/strings.dart.
/// Only English and Finnish are offered, because only they are fully translated.
class AppLocalizations {
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ?? AppLocalizations(const Locale('en'));
  }

  final Locale locale;
  AppLocalizations(this.locale);

  static const Map<String, String> languages = {
    'en': 'English',
    'fi': 'Suomi',
  };

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Navigation and home
      'home': 'Home',
      'search': 'Search',
      'orders': 'Orders',
      'profile': 'Profile',
      'viewBag': 'View bag',
      'deliveringTo': 'Delivering to',
      'categories': 'Categories',
      'storesNearYou': 'Stores near you',
      'couldNotLoadStores': 'Could not load stores. Pull down to refresh.',
      'launchingCityTitle': 'No stores here yet',
      'launchingCitySubtitle': 'Malvoya is just starting, and no store delivers to this address yet.',

      // Sign in and sign up
      'login': 'Log in',
      'logOut': 'Log out',
      'email': 'Email',
      'password': 'Password',
      'welcomeBack': 'Welcome back',
      'signInToContinue': 'Sign in to continue',
      'boutiques': 'Fashion from local stores',
      'or': 'or',
      'continueWithGoogle': 'Continue with Google',
      'continueWithPhone': 'Sign in with a one-time code',
      'signInWithPhone': 'Sign in with a one-time code',
      'sendVerificationCode': 'Send code',
      'verifyPhoneCode': 'Enter your code',
      'enterSmsCode': 'The 6-digit code',
      'verifyAndSignIn': 'Verify and sign in',
      'changePhone': 'Use another number or email',
      'guestLogin': 'Browse without an account',
      'dontHaveAccount': "Don't have an account?",
      'createOne': 'Create one',
      'createAccount': 'Create account',
      'createYourAccount': 'Create your account',
      'signUpSubtitle': 'Shop from local stores and follow your delivery live.',
      'fullName': 'Full name',
      'passwordMin6': 'Password (at least 8 characters)',
      'passTooShort': 'Use a password of at least 8 characters.',
      'fillAllFields': 'Please fill in all fields.',
      'agreeTermsText': 'I accept the Terms of Service and have read the Privacy Policy.',
      'acceptTermsPrompt': 'Please accept the Terms of Service to continue.',
      'alreadyHaveAccount': 'Already have an account?',
      'signIn': 'Sign in',

      // Language and appearance
      'language': 'Language',
      'selectLanguagePrompt': 'Choose language',
      'languagesSubtitle': 'English and Finnish',
      'atomicTranslationSub': 'English and Finnish',
      'instantSwitching': 'English and Finnish',
      'languageSwitchedTo': 'Language: {lang}',
      'activeLanguage': 'Language',
      'displayAppearance': 'Appearance',
      'displayAppearanceSubtitle': 'Light, dark or warm',
      'themeCrispDaylight': 'Light',
      'themeOledMidnight': 'Dark',
      'themeEyeComfort': 'Warm',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'themeAmber': 'Warm',

      // Profile and settings
      'settings': 'Settings',
      'cancel': 'Cancel',
      'liveTracking': 'Follow and reorder',
      'savedLocations': 'Saved on this phone',
      'experienceInterface': 'App',
      'multiChannelAlerts': 'Order updates',
      'multiChannelAlertsSubtitle': 'Your latest order updates',
      'fintechFulfillment': 'Payments and returns',
      'paymentMethods': 'Paying',
      'paymentMethodsSubtitle': 'How paying works',
      'refundsReturns': 'Returns',
      'refundsReturnsSubtitle': '14-day withdrawal for purchases from business sellers',
      'privacyDataRights': 'Privacy',
      'dataRights': 'Your data',
      'dataRightsSubtitle': 'Download or delete your data',
      'legalTerms': 'Terms and policies',
      'legalTermsSubtitle': 'Terms of service, privacy policy',
      'customerSupport': 'Contact us',
      'customerSupportSubtitle': 'Send a message to the Malvoya team',
      'deleteAccountGdpr': 'Delete account',
      'logOutTitle': 'Log out?',
      'logOutMsg': 'You can sign in again at any time.',
      'confirmDelete': 'Delete account',
      'deleteAccountSimpleMsg':
          'Your account and personal data are deleted for good and you are signed out. Order records are kept without your name, as Finnish accounting law requires.',
      'accountAndProfile': 'Account',
      'editAction': 'Edit',
      'editProfile': 'Your name',
      'regionalLocalization': 'Language and appearance',
      'statutoryLegalCompliance': 'Privacy and terms',
      'exportData': 'Download your data',
      'termsOfServiceLaw': 'Terms and policies',
      'fourteenDayWithdrawal': 'Including the 14-day right of withdrawal for purchases from business sellers',
      'deleteAccount': 'Delete account',
      'eraseAccountArt17': 'Delete your account and personal data (GDPR art. 17)',
      'platformLegalFooter': 'Malvoya is a marketplace: items are sold by independent stores. Payments are processed by Stripe.',

      // Privacy
      'privacyPolicy': 'Privacy',
      'euGdprSovereignty': 'Your data, your rights',
      'euGdprSubtitle': 'Malvoya keeps your data on servers in the EU (Frankfurt). You can download or delete it here.',
      'statutoryDataRights': 'Your rights',
      'rightOfAccessArt15': 'Download your data',
      'rightOfAccessArt15Sub': 'A copy of the personal data Malvoya holds about you (GDPR art. 15)',
      'rightToRectificationArt16': 'Correct your details',
      'rightToRectificationArt16Sub': 'Edit your saved addresses here, and your name in Settings',
      'dpoSupervisoryContact': 'Questions and complaints',
      'gdprArchiveReady': 'Your data is ready',
      'gdprArchiveSub': 'Open Malvoya to see it.',
      'gdprArt15ArchiveTitle': 'Your data',
      'portableJsonFormat': 'Machine-readable JSON',
      'copyJson': 'Copy',
      'gdprCopied': 'Copied',
      'emailArchive': 'Email it to me',
      'rightToErasureArt17': 'Delete account',
      'rightToErasureArt17Sub':
          'Deletes your account and personal data permanently. Order records are kept without your name for as long as Finnish accounting law requires.',
      'eraseAccountPersonalData': 'Delete my account',
      'accountErasedNotif': 'Account deleted',
      'accountErasedNotifBody': 'Your account and personal data have been deleted.',

      // Addresses
      'deliveryAddresses': 'Addresses',
      'addDeliveryAddress': 'Add address',
      'addNewAddress': 'New address',
      'editAddress': 'Edit',
      'verifiedCourierZone': 'Saved on this phone',
      'autoFillMapPin': 'Fill in from the map',
      'addressLabel': 'Label',
      'labelHome': 'Home',
      'labelWork': 'Work',
      'labelOther': 'Other',
      'streetAddress': 'Street address',
      'apartmentSuite': 'Apartment',
      'postalCode': 'Postcode',
      'city': 'City',
      'doorBuzzerCode': 'Door code (optional)',
      'doorBuzzerHint': 'e.g. A 1234',
      'doorCodePrefix': 'Door code',
      'enterStreetPostal': 'Enter the street and postcode.',
      'addressUpdated': 'Address updated',
      'newAddressSaved': 'Address saved on this phone',
      'saveChanges': 'Save changes',
      'saveAddress': 'Save address',
      'noSavedAddresses': 'No saved addresses',
      'noSavedAddressesSub': 'Addresses you save are kept on this phone.',
      'defaultAddress': 'Default',
      'defaultPaymentSet': 'set as your default address',
      'addressRemoved': 'Address removed',
      'setAsDefault': 'Set as default',
      'deleteAddress': 'Delete',

      // Contact and help assistant
      'howCanWeAssist': 'How can we help?',
      'howCanWeAssistSub': 'Messages go to the Malvoya team, and we reply by email.',
      'searchTopicsHint': 'Search topics',
      'allTopicsHeader': 'TOPICS',
      'commonInquiries': 'Common questions',
      'describeYourRequest': 'Your message',
      'inquiryHint': 'Tell us what happened. Add your order number if you have one.',
      'yourReplyEmail': 'Your email for the reply',
      'submitSupportRequest': 'Send to Malvoya',
      'pleaseDescribeInquiry': 'Please write your message.',
      'emailDesk': 'Message our team',
      'directEmailSupport': 'Message the Malvoya team',
      'directEmailSupportSub': 'We reply by email.',
      'yourEmailAddress': 'Your email',
      'category': 'Topic',
      'subject': 'Subject',
      'messageDetails': 'Message',
      'sendTicket': 'Send',
      'pleaseEnterSubjectMsg': 'Please fill in the subject and the message.',
      'catExpressDelivery': 'Delivery',
      'catReturns14d': 'Returns and refunds',
      'catCardSepa': 'Payments',
      'catBoutiquePartner': 'Selling on Malvoya',
      'catGeneralInquiry': 'Something else',
      'onlineOfficialSupport': 'Not a person, not AI',
      'justNow': 'now',
      'botInputHint': 'Ask about delivery, returns, sizes…',
      'botDeliverySuggestion': 'Delivery',
      'botReturnsSuggestion': 'Returns',
      'botSizingSuggestion': 'Sizes',
      'botPaymentsSuggestion': 'Payments',
      'botEmailSuggestion': 'Message our team',
      'botWelcomeMsg':
          'Hi! I am Malvoya\'s help assistant. I give ready-made answers to common questions about delivery, returns, sizes and payments. I am not a person and not AI. For anything else, tap "Message our team".',
      'botResponseDelivery':
          'Local couriers deliver orders from stores near you. The delivery fee and the estimated delivery time are shown before you pay and depend on the distance. Once a courier has your order, you can follow it on the map in Orders. Malvoya is just starting, so there may be no stores near you yet.',
      'botResponseReturns':
          'When you buy from a business seller, you can withdraw from the purchase within 14 days of delivery without giving a reason: start it in Profile → Returns. The refund goes back to the payment method you used. Purchases from private sellers have no statutory right of withdrawal, but you can still ask the seller. Each store page says whether the seller is a business or a private person.',
      'botResponseSizing':
          'Sizes vary by brand and store. Check the product description and the size guide on the product page, or ask the store in the comments of its drops.',
      'botResponsePayment':
          'You pay in Stripe\'s secure payment sheet. Malvoya never sees your card details. Your order is confirmed only after the payment is confirmed, and refunds go back to the payment method you used.',
      'botResponseStore':
          'Stores on Malvoya are independent sellers. Each store page shows who the seller is and whether they are a business or a private person. To sell on Malvoya, use the Malvoya store app.',
      'botResponseEmail': 'Tap "Message our team" at the top. Your message goes to the Malvoya team, and we reply by email.',
      'botResponseHello': 'Hi! Ask me about delivery, returns, sizes or payments, or tap "Message our team".',
      'botResponseFallback':
          'Sorry, I only have answers to common questions. Try asking about delivery, returns, sizes or payments, or tap "Message our team".',
    },
    'fi': {
      // Navigation and home
      'home': 'Koti',
      'search': 'Haku',
      'orders': 'Tilaukset',
      'profile': 'Profiili',
      'viewBag': 'Näytä kassi',
      'deliveringTo': 'Toimitus osoitteeseen',
      'categories': 'Kategoriat',
      'storesNearYou': 'Kaupat lähelläsi',
      'couldNotLoadStores': 'Kauppoja ei voitu ladata. Vedä alas päivittääksesi.',
      'launchingCityTitle': 'Täällä ei vielä ole kauppoja',
      'launchingCitySubtitle': 'Malvoya on vasta aloittamassa, eikä mikään kauppa vielä toimita tähän osoitteeseen.',

      // Sign in and sign up
      'login': 'Kirjaudu sisään',
      'logOut': 'Kirjaudu ulos',
      'email': 'Sähköposti',
      'password': 'Salasana',
      'welcomeBack': 'Tervetuloa takaisin',
      'signInToContinue': 'Kirjaudu sisään jatkaaksesi',
      'boutiques': 'Muotia paikallisista kaupoista',
      'or': 'tai',
      'continueWithGoogle': 'Jatka Googlella',
      'continueWithPhone': 'Kirjaudu kertakäyttökoodilla',
      'signInWithPhone': 'Kirjaudu kertakäyttökoodilla',
      'sendVerificationCode': 'Lähetä koodi',
      'verifyPhoneCode': 'Syötä koodi',
      'enterSmsCode': '6-numeroinen koodi',
      'verifyAndSignIn': 'Vahvista ja kirjaudu',
      'changePhone': 'Käytä toista numeroa tai sähköpostia',
      'guestLogin': 'Selaa ilman tiliä',
      'dontHaveAccount': 'Eikö sinulla ole tiliä?',
      'createOne': 'Luo tili',
      'createAccount': 'Luo tili',
      'createYourAccount': 'Luo tilisi',
      'signUpSubtitle': 'Osta paikallisista kaupoista ja seuraa toimitusta reaaliajassa.',
      'fullName': 'Koko nimi',
      'passwordMin6': 'Salasana (vähintään 8 merkkiä)',
      'passTooShort': 'Käytä vähintään 8 merkin salasanaa.',
      'fillAllFields': 'Täytä kaikki kentät.',
      'agreeTermsText': 'Hyväksyn käyttöehdot ja olen lukenut tietosuojaselosteen.',
      'acceptTermsPrompt': 'Hyväksy käyttöehdot jatkaaksesi.',
      'alreadyHaveAccount': 'Onko sinulla jo tili?',
      'signIn': 'Kirjaudu sisään',

      // Language and appearance
      'language': 'Kieli',
      'selectLanguagePrompt': 'Valitse kieli',
      'languagesSubtitle': 'Englanti ja suomi',
      'atomicTranslationSub': 'Englanti ja suomi',
      'instantSwitching': 'Englanti ja suomi',
      'languageSwitchedTo': 'Kieli: {lang}',
      'activeLanguage': 'Kieli',
      'displayAppearance': 'Ulkoasu',
      'displayAppearanceSubtitle': 'Vaalea, tumma tai lämmin',
      'themeCrispDaylight': 'Vaalea',
      'themeOledMidnight': 'Tumma',
      'themeEyeComfort': 'Lämmin',
      'themeLight': 'Vaalea',
      'themeDark': 'Tumma',
      'themeAmber': 'Lämmin',

      // Profile and settings
      'settings': 'Asetukset',
      'cancel': 'Peruuta',
      'liveTracking': 'Seuraa ja tilaa uudelleen',
      'savedLocations': 'Tallennettu tähän puhelimeen',
      'experienceInterface': 'Sovellus',
      'multiChannelAlerts': 'Tilausten tapahtumat',
      'multiChannelAlertsSubtitle': 'Tilaustesi viimeisimmät tapahtumat',
      'fintechFulfillment': 'Maksut ja palautukset',
      'paymentMethods': 'Maksaminen',
      'paymentMethodsSubtitle': 'Näin maksaminen toimii',
      'refundsReturns': 'Palautukset',
      'refundsReturnsSubtitle': '14 päivän peruuttamisoikeus yritysmyyjiltä ostettaessa',
      'privacyDataRights': 'Tietosuoja',
      'dataRights': 'Tietosi',
      'dataRightsSubtitle': 'Lataa tai poista tietosi',
      'legalTerms': 'Ehdot ja käytännöt',
      'legalTermsSubtitle': 'Käyttöehdot, tietosuojaseloste',
      'customerSupport': 'Ota yhteyttä',
      'customerSupportSubtitle': 'Lähetä viesti Malvoyan tiimille',
      'deleteAccountGdpr': 'Poista tili',
      'logOutTitle': 'Kirjaudutaanko ulos?',
      'logOutMsg': 'Voit kirjautua takaisin milloin tahansa.',
      'confirmDelete': 'Poista tili',
      'deleteAccountSimpleMsg':
          'Tilisi ja henkilötietosi poistetaan pysyvästi, ja sinut kirjataan ulos. Tilaustiedot säilytetään ilman nimeäsi, kuten kirjanpitolaki edellyttää.',
      'accountAndProfile': 'Tili',
      'editAction': 'Muokkaa',
      'editProfile': 'Nimesi',
      'regionalLocalization': 'Kieli ja ulkoasu',
      'statutoryLegalCompliance': 'Tietosuoja ja ehdot',
      'exportData': 'Lataa tietosi',
      'termsOfServiceLaw': 'Ehdot ja käytännöt',
      'fourteenDayWithdrawal': 'Sisältää 14 päivän peruuttamisoikeuden yritysmyyjiltä ostettaessa',
      'deleteAccount': 'Poista tili',
      'eraseAccountArt17': 'Poista tilisi ja henkilötietosi (GDPR 17 art.)',
      'platformLegalFooter': 'Malvoya on markkinapaikka: tuotteita myyvät itsenäiset kaupat. Maksut käsittelee Stripe.',

      // Privacy
      'privacyPolicy': 'Tietosuoja',
      'euGdprSovereignty': 'Tietosi, oikeutesi',
      'euGdprSubtitle': 'Malvoya säilyttää tietosi EU:ssa sijaitsevilla palvelimilla (Frankfurt). Voit ladata tai poistaa ne täällä.',
      'statutoryDataRights': 'Oikeutesi',
      'rightOfAccessArt15': 'Lataa tietosi',
      'rightOfAccessArt15Sub': 'Kopio henkilötiedoista, joita Malvoyalla on sinusta (GDPR 15 art.)',
      'rightToRectificationArt16': 'Korjaa tietosi',
      'rightToRectificationArt16Sub': 'Muokkaa tallennettuja osoitteita täällä ja nimeäsi Asetuksissa',
      'dpoSupervisoryContact': 'Kysymykset ja valitukset',
      'gdprArchiveReady': 'Tietosi ovat valmiina',
      'gdprArchiveSub': 'Avaa Malvoya nähdäksesi ne.',
      'gdprArt15ArchiveTitle': 'Tietosi',
      'portableJsonFormat': 'Koneluettava JSON',
      'copyJson': 'Kopioi',
      'gdprCopied': 'Kopioitu',
      'emailArchive': 'Lähetä minulle sähköpostilla',
      'rightToErasureArt17': 'Poista tili',
      'rightToErasureArt17Sub':
          'Poistaa tilisi ja henkilötietosi pysyvästi. Tilaustiedot säilytetään ilman nimeäsi niin kauan kuin kirjanpitolaki edellyttää.',
      'eraseAccountPersonalData': 'Poista tilini',
      'accountErasedNotif': 'Tili poistettu',
      'accountErasedNotifBody': 'Tilisi ja henkilötietosi on poistettu.',

      // Addresses
      'deliveryAddresses': 'Osoitteet',
      'addDeliveryAddress': 'Lisää osoite',
      'addNewAddress': 'Uusi osoite',
      'editAddress': 'Muokkaa',
      'verifiedCourierZone': 'Tallennetaan tähän puhelimeen',
      'autoFillMapPin': 'Täytä kartalta',
      'addressLabel': 'Nimi',
      'labelHome': 'Koti',
      'labelWork': 'Työ',
      'labelOther': 'Muu',
      'streetAddress': 'Katuosoite',
      'apartmentSuite': 'Asunto',
      'postalCode': 'Postinumero',
      'city': 'Kaupunki',
      'doorBuzzerCode': 'Ovikoodi (valinnainen)',
      'doorBuzzerHint': 'esim. A 1234',
      'doorCodePrefix': 'Ovikoodi',
      'enterStreetPostal': 'Kirjoita katuosoite ja postinumero.',
      'addressUpdated': 'Osoite päivitetty',
      'newAddressSaved': 'Osoite tallennettu tähän puhelimeen',
      'saveChanges': 'Tallenna muutokset',
      'saveAddress': 'Tallenna osoite',
      'noSavedAddresses': 'Ei tallennettuja osoitteita',
      'noSavedAddressesSub': 'Tallentamasi osoitteet säilyvät tässä puhelimessa.',
      'defaultAddress': 'Oletus',
      'defaultPaymentSet': 'asetettu oletusosoitteeksi',
      'addressRemoved': 'Osoite poistettu',
      'setAsDefault': 'Aseta oletukseksi',
      'deleteAddress': 'Poista',

      // Contact and help assistant
      'howCanWeAssist': 'Miten voimme auttaa?',
      'howCanWeAssistSub': 'Viestit menevät Malvoyan tiimille, ja vastaamme sähköpostitse.',
      'searchTopicsHint': 'Hae aiheita',
      'allTopicsHeader': 'AIHEET',
      'commonInquiries': 'Yleisiä kysymyksiä',
      'describeYourRequest': 'Viestisi',
      'inquiryHint': 'Kerro mitä tapahtui. Lisää tilausnumero, jos sinulla on sellainen.',
      'yourReplyEmail': 'Sähköpostisi vastausta varten',
      'submitSupportRequest': 'Lähetä Malvoyalle',
      'pleaseDescribeInquiry': 'Kirjoita viestisi.',
      'emailDesk': 'Viesti tiimille',
      'directEmailSupport': 'Viesti Malvoyan tiimille',
      'directEmailSupportSub': 'Vastaamme sähköpostitse.',
      'yourEmailAddress': 'Sähköpostisi',
      'category': 'Aihe',
      'subject': 'Otsikko',
      'messageDetails': 'Viesti',
      'sendTicket': 'Lähetä',
      'pleaseEnterSubjectMsg': 'Täytä otsikko ja viesti.',
      'catExpressDelivery': 'Toimitus',
      'catReturns14d': 'Palautukset ja hyvitykset',
      'catCardSepa': 'Maksut',
      'catBoutiquePartner': 'Myyminen Malvoyassa',
      'catGeneralInquiry': 'Jokin muu',
      'onlineOfficialSupport': 'Ei ihminen, ei tekoäly',
      'justNow': 'nyt',
      'botInputHint': 'Kysy toimituksesta, palautuksista, koosta…',
      'botDeliverySuggestion': 'Toimitus',
      'botReturnsSuggestion': 'Palautukset',
      'botSizingSuggestion': 'Koot',
      'botPaymentsSuggestion': 'Maksut',
      'botEmailSuggestion': 'Viesti tiimille',
      'botWelcomeMsg':
          'Hei! Olen Malvoyan apuri. Annan valmiita vastauksia yleisiin kysymyksiin toimituksesta, palautuksista, koosta ja maksamisesta. En ole ihminen enkä tekoäly. Muissa asioissa napauta "Viesti tiimille".',
      'botResponseDelivery':
          'Paikalliset lähetit toimittavat tilaukset lähelläsi olevista kaupoista. Toimitusmaksu ja arvioitu toimitusaika näytetään ennen maksua, ja ne riippuvat matkasta. Kun lähetillä on tilauksesi, voit seurata sitä kartalla Tilaukset-välilehdellä. Malvoya on vasta aloittamassa, joten lähelläsi ei ehkä vielä ole kauppoja.',
      'botResponseReturns':
          'Kun ostat yritysmyyjältä, voit perua oston 14 päivän kuluessa toimituksesta syytä kertomatta: aloita kohdasta Profiili → Palautukset. Hyvitys palautetaan käyttämällesi maksutavalle. Yksityismyyjiltä tehdyissä ostoissa ei ole lakisääteistä peruuttamisoikeutta, mutta voit silti kysyä myyjältä. Jokaisella kauppasivulla kerrotaan, onko myyjä yritys vai yksityishenkilö.',
      'botResponseSizing':
          'Koot vaihtelevat merkin ja kaupan mukaan. Katso tuotekuvaus ja tuotesivun kokotaulukko, tai kysy kaupalta sen julkaisujen kommenteissa.',
      'botResponsePayment':
          'Maksat Stripen suojatussa maksuikkunassa. Malvoya ei näe korttitietojasi. Tilaus vahvistetaan vasta, kun maksu on vahvistettu, ja hyvitykset palautetaan käyttämällesi maksutavalle.',
      'botResponseStore':
          'Malvoyan kaupat ovat itsenäisiä myyjiä. Jokaisella kauppasivulla näkyy, kuka myyjä on ja onko se yritys vai yksityishenkilö. Myydäksesi Malvoyassa käytä Malvoyan kauppiassovellusta.',
      'botResponseEmail': 'Napauta ylhäältä "Viesti tiimille". Viestisi menee Malvoyan tiimille, ja vastaamme sähköpostitse.',
      'botResponseHello': 'Hei! Kysy toimituksesta, palautuksista, koosta tai maksamisesta, tai napauta "Viesti tiimille".',
      'botResponseFallback':
          'Valitettavasti osaan vastata vain yleisiin kysymyksiin. Kysy toimituksesta, palautuksista, koosta tai maksamisesta, tai napauta "Viesti tiimille".',
    },
  };

  static String _humanizeCamelCase(String key) {
    if (key.isEmpty) return key;
    final buffer = StringBuffer();
    for (int i = 0; i < key.length; i++) {
      final char = key[i];
      if (i > 0 && char.toUpperCase() == char && key[i - 1].toLowerCase() == key[i - 1]) {
        buffer.write(' ');
      }
      buffer.write(char);
    }
    final raw = buffer.toString();
    return raw[0].toUpperCase() + raw.substring(1);
  }

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? _localizedValues['en']?[key] ?? _humanizeCamelCase(key);
  }

  String translateCategory(String name) {
    final key = name.toLowerCase().trim();
    if (locale.languageCode == 'fi') {
      switch (key) {
        case 'clothing':
        case 'vaatteet':
        case 'apparel':
          return 'Vaatteet';
        case 'shoes':
        case 'kengät':
        case 'footwear':
          return 'Kengät';
        case 'bags':
        case 'laukut':
          return 'Laukut';
        case 'accessories':
        case 'asusteet':
          return 'Asusteet';
        case 'jewelry':
        case 'korut':
          return 'Korut';
        case 'vintage':
          return 'Vintage';
        case 'beauty':
        case 'kauneus':
        case 'cosmetics':
          return 'Kauneus';
        case 'home':
        case 'koti':
          return 'Koti & Sisustus';
        case 'returns':
        case 'palautus':
        case 'palautukset':
          return 'Palautus';
        case 'eco-friendly':
        case 'eco friendly':
        case 'ekoystävällinen':
          return 'Ekoystävällinen';
        case 'swipe to swap':
        case 'swap':
        case 'vaihto':
          return 'Koon & mallin vaihto';
        case 'second hand':
        case 'secondhand':
        case 'käytetty':
          return 'Käytetty muoti';
      }
    } else {
      switch (key) {
        case 'vaatteet':
          return 'Clothing';
        case 'kengät':
          return 'Shoes';
        case 'laukut':
          return 'Bags';
        case 'asusteet':
          return 'Accessories';
        case 'korut':
          return 'Jewelry';
        case 'kauneus':
          return 'Beauty';
        case 'koti':
          return 'Home';
        case 'returns':
        case 'palautus':
          return 'Returns';
        case 'eco-friendly':
        case 'eco friendly':
        case 'ekoystävällinen':
          return 'Eco-Friendly';
        case 'swipe to swap':
        case 'swap':
          return 'Swipe to Swap';
        case 'second hand':
        case 'secondhand':
        case 'käytetty':
          return 'Second Hand';
      }
    }
    return _localizedValues[locale.languageCode]?[name] ?? _localizedValues['en']?[name] ?? name;
  }

  String translateSubcategory(String name) => translateCategory(name);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.languages.keys.contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
