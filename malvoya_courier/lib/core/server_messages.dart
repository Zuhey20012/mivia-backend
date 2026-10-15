/// Finnish versions of the server's most common error messages.
///
/// The API answers in English. Its messages are safe to show, so in Finnish the known ones are
/// translated here and anything unknown is shown as the server sent it. [languageCode] follows
/// the app language (set by `LocaleProvider`), because the API client has no BuildContext.
class ServerMessages {
  ServerMessages._();

  static String languageCode = 'fi';

  static bool get _finnish => languageCode == 'fi';

  /// [message] in the app language when a translation is known, otherwise unchanged.
  static String localize(String message) {
    if (!_finnish) return message;
    final text = message.trim();
    final exact = _fi[text] ?? _fi[text.replaceAll(RegExp(r'[.!]$'), '')];
    if (exact != null) return exact;
    for (final p in _patterns) {
      final m = p.pattern.firstMatch(text);
      if (m != null) return p.fi(m);
    }
    return message;
  }

  /// Picks the Finnish or English text of something the app itself says.
  static String pick(String en, String fi) => _finnish ? fi : en;

  static const Map<String, String> _fi = {
    // Jobs and deliveries
    'This delivery is no longer available': 'Tämä keikka ei ole enää saatavilla.',
    'Go online before accepting deliveries': 'Mene linjoille ennen kuin otat keikkoja.',
    'Finish your current delivery first': 'Tee nykyinen toimitus ensin loppuun.',
    'You are too far from the shop to take this job': 'Olet liian kaukana kaupasta ottaaksesi tämän keikan.',
    'This delivery is scheduled for later and is not open to couriers yet':
        'Tämä toimitus on ajastettu myöhemmäksi, eikä se ole vielä avoinna läheteille.',
    'Check in when you are at the shop: your current position is not within 300 m of it. Keep location sharing on.':
        'Ilmoittaudu vasta kaupalla: sijaintisi ei ole 300 metrin säteellä kaupasta. Pidä sijainnin jakaminen päällä.',
    'You can only check in at the shop before pickup': 'Voit ilmoittautua kaupalle vain ennen noutoa.',
    'Pick the order up before completing the delivery': 'Nouda tilaus ennen kuin merkitset sen toimitetuksi.',
    'Take a photo of where you left the order': 'Ota kuva paikasta, johon jätit tilauksen.',
    'This order can no longer be handed over': 'Tätä tilausta ei voi enää luovuttaa.',
    'Confirm the handover in the app to complete this delivery': 'Vahvista luovutus sovelluksessa, niin toimitus merkitään valmiiksi.',
    'The order changed in the meantime, please refresh': 'Tilaus muuttui välillä. Päivitä näkymä.',
    'Your courier account is awaiting approval': 'Lähettitilisi odottaa vielä hyväksyntää.',
    'Courier profile not found': 'Lähettiprofiilia ei löytynyt.',
    'Order not found': 'Tilausta ei löytynyt.',
    'You are offline': 'Olet poissa linjoilta.',
    // Delivery photos
    'You can only add a photo to a delivery you are carrying': 'Voit lisätä kuvan vain toimitukseen, joka on sinulla.',
    'Only couriers can upload delivery photos': 'Vain lähetit voivat ladata toimituskuvia.',
    'The upload was not found. Please try again.': 'Ladattua kuvaa ei löytynyt. Yritä uudelleen.',
    'Upload could not be verified': 'Ladattua kuvaa ei voitu vahvistaa. Yritä uudelleen.',
    'Photo and video uploads are not switched on yet': 'Kuvien lataus ei ole vielä käytössä.',
    // Payouts
    'You can set up payouts once your account is approved': 'Voit ottaa tilitykset käyttöön, kun tilisi on hyväksytty.',
    'Set up payouts first': 'Ota tilitykset ensin käyttöön.',
    'Payout not found': 'Tilitystä ei löytynyt.',
    'Only failed payouts can be retried': 'Vain epäonnistuneen tilityksen voi yrittää uudelleen.',
    // Account and sign-in
    'Invalid credentials': 'Sähköposti, puhelinnumero tai salasana on väärin.',
    'This account is disabled': 'Tämä tili on poistettu käytöstä.',
    'An account with this email or phone number already exists. Please sign in with your password.':
        'Tällä sähköpostilla tai puhelinnumerolla on jo tili. Kirjaudu salasanallasi.',
    'An account with this email or phone already exists. Please sign in.':
        'Tällä sähköpostilla tai puhelinnumerolla on jo tili. Kirjaudu sisään.',
    'Enter a valid email address or phone number': 'Anna kelvollinen sähköpostiosoite tai puhelinnumero.',
    'Invalid phone number or email address': 'Puhelinnumero tai sähköpostiosoite ei kelpaa.',
    'Password must be at least 8 characters': 'Salasanassa on oltava vähintään 8 merkkiä.',
    'Invalid Google token': 'Google-kirjautuminen epäonnistui. Yritä uudelleen.',
    'Invalid phone token': 'Puhelinkirjautuminen epäonnistui. Yritä uudelleen.',
    'Invalid sign-in token': 'Kirjautuminen epäonnistui. Yritä uudelleen.',
    'Google sign-in is not configured': 'Google-kirjautuminen ei ole käytössä.',
    'This Google account is already linked to another Malvoya account': 'Tämä Google-tili on jo yhdistetty toiseen Malvoya-tiliin.',
    'A different Google account is already linked. Unlink it first.': 'Tiliin on jo yhdistetty toinen Google-tili. Poista se ensin.',
    'Google can only be unlinked from accounts that sign in with a password.':
        'Google-yhteyden voi poistaa vain tililtä, jolle kirjaudutaan salasanalla.',
    'You have orders in progress. Your account can be deleted once they are completed or cancelled.':
        'Sinulla on keskeneräisiä tilauksia. Tilisi voidaan poistaa, kun ne on toimitettu tai peruttu.',
    'Account not found': 'Tiliä ei löytynyt.',
    'Refresh token expired or invalid': 'Kirjaudu uudelleen sisään.',
    'Invalid or expired token': 'Kirjaudu uudelleen sisään.',
    'Unauthorized': 'Kirjaudu uudelleen sisään.',
    'Forbidden': 'Sinulla ei ole oikeutta tähän.',
    // Help
    'Write a short description of what you need help with': 'Kirjoita lyhyesti, missä tarvitset apua.',
    'Give an email address we can reply to': 'Anna sähköpostiosoite, johon voimme vastata.',
    'You have sent several requests already. We will reply to them by email.':
        'Olet lähettänyt jo useita viestejä. Vastaamme niihin sähköpostilla.',
    // General
    'Too many requests, please try again later.': 'Liian monta pyyntöä. Yritä hetken päästä uudelleen.',
    'Too many attempts, please try again later.': 'Liian monta yritystä. Yritä hetken päästä uudelleen.',
    'Not found': 'Ei löytynyt.',
    'Something went wrong': 'Jotain meni vikaan. Yritä uudelleen.',
    'Internal server error': 'Palvelimella tapahtui virhe. Yritä uudelleen.',
    'Request body too large': 'Tieto on liian suuri lähetettäväksi.',
  };

  static final List<({RegExp pattern, String Function(RegExpMatch) fi})> _patterns = [
    (pattern: RegExp(r'^Cannot change order from \w+ to \w+$'), fi: (_) => 'Tilauksen tilaa ei voi enää muuttaa näin. Päivitä näkymä.'),
  ];
}
