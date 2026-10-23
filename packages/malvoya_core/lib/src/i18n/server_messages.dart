import 'package:flutter/widgets.dart';
import 'app_language.dart';

/// Finnish versions of the API's messages, for all three apps.
///
/// The API answers in English and its messages are safe to show. In Finnish the known ones are
/// translated here; anything unknown is shown as the server wrote it. Messages the server already
/// sends in both languages ("Finnish sentence. / English sentence.") are split instead.
///
/// One table for the customer, store and courier apps (merged from the three earlier copies; when
/// they translated the same sentence differently, the clearest wording was kept).
class ServerMessages {
  ServerMessages._();

  /// [message] in [languageCode] (default: the app language).
  static String localize(String message, {String? languageCode}) {
    final fi = (languageCode ?? AppLanguage.code) == 'fi';
    final text = message.trim();
    // Both halves must be whole sentences, so a product name containing " / " is never split
    final halves = text.split(' / ');
    bool sentence(String t) => RegExp(r'[.!?]$').hasMatch(t.trim());
    if (halves.length == 2 && sentence(halves[0]) && sentence(halves[1])) {
      return (fi ? halves[0] : halves[1]).trim();
    }
    if (!fi) return message;
    final exact = _fi[text] ?? _fi[text.replaceAll(RegExp(r'[.!]$'), '')];
    if (exact != null) return exact;
    for (final p in _patterns) {
      final m = p.pattern.firstMatch(text);
      if (m != null) return p.fi(m);
    }
    return message;
  }

  /// True when [message] has a Finnish translation (exact or by pattern).
  static bool isKnown(String message) => localize(message, languageCode: 'fi') != message;

  /// Number of exact translations (used by tests and the design-system docs).
  static int get exactCount => _fi.length;

  static const Map<String, String> _fi = {
    // ── The API client's own messages ──────────────────────────────────────
    'The server took too long to answer. Please try again.': 'Palvelin vastasi liian hitaasti. Yritä uudelleen.',
    'Could not reach Malvoya. Check your connection and try again.': 'Malvoyaan ei saatu yhteyttä. Tarkista yhteys ja yritä uudelleen.',
    'Please sign in again.': 'Kirjaudu uudelleen sisään.',
    'You do not have access to this.': 'Sinulla ei ole pääsyä tähän.',
    'Not found.': 'Ei löytynyt.',
    'Too many attempts. Please wait a moment.': 'Liian monta yritystä. Odota hetki.',
    'Something went wrong on our side. Please try again.': 'Jokin meni vikaan meidän päässämme. Yritä uudelleen.',
    'Something went wrong. Please try again.': 'Jokin meni vikaan. Yritä uudelleen.',

    // ── General ────────────────────────────────────────────────────────────
    'Invalid request': 'Virheellinen pyyntö.',
    'Forbidden': 'Sinulla ei ole oikeutta tähän.',
    'Unauthorized': 'Kirjaudu uudelleen sisään.',
    'Not found': 'Ei löytynyt.',
    'Something went wrong': 'Jokin meni vikaan. Yritä uudelleen.',
    'Internal server error': 'Palvelimella tapahtui virhe. Yritä uudelleen.',
    'Request body too large': 'Tieto on liian suuri lähetettäväksi.',
    'Check the details': 'Tarkista tiedot.',
    'Nothing to change': 'Ei muutettavaa.',
    'Too many requests, please try again later.': 'Liian monta pyyntöä. Yritä hetken päästä uudelleen.',
    'Too many attempts, please try again later.': 'Liian monta yritystä. Yritä hetken päästä uudelleen.',

    // ── Not found / access ─────────────────────────────────────────────────
    'Order not found': 'Tilausta ei löytynyt.',
    'Product not found': 'Tuotetta ei löytynyt.',
    'Store not found': 'Kauppaa ei löytynyt.',
    'Return not found': 'Palautusta ei löytynyt.',
    'Drop not found': 'Julkaisua ei löytynyt.',
    'This drop is not available': 'Tämä julkaisu ei ole saatavilla.',
    'Video not found': 'Videota ei löytynyt.',
    'Payout not found': 'Tilitystä ei löytynyt.',
    'Account not found': 'Tiliä ei löytynyt.',
    'User not found': 'Käyttäjää ei löytynyt.',
    'Review not found': 'Arviota ei löytynyt.',
    'Promo code not found': 'Alennuskoodia ei löytynyt.',
    'Courier profile not found': 'Lähettiprofiilia ei löytynyt.',
    'Create your store first': 'Perusta ensin kauppasi.',
    'This account is disabled': 'Tämä tili on poistettu käytöstä.',

    // ── Account and sign-in ────────────────────────────────────────────────
    'Invalid credentials': 'Sähköposti, puhelinnumero tai salasana on väärin.',
    'Invalid email or password.': 'Väärä sähköposti tai salasana.',
    'Invalid phone number or email address': 'Puhelinnumero tai sähköpostiosoite ei kelpaa.',
    'Enter a valid email address or phone number': 'Anna kelvollinen sähköpostiosoite tai puhelinnumero.',
    'Enter a valid email address': 'Anna kelvollinen sähköpostiosoite.',
    'Invalid verification code': 'Koodi on väärä.',
    'The code has already been used': 'Koodi on jo käytetty.',
    'The code has expired. Please request a new one.': 'Koodi on vanhentunut. Pyydä uusi koodi.',
    'Too many incorrect attempts. Please request a new code.': 'Liian monta väärää yritystä. Pyydä uusi koodi.',
    'Please wait a minute before requesting a new code': 'Odota hetki ennen kuin pyydät uuden koodin.',
    'We could not send a verification code right now. Please try again later.':
        'Vahvistuskoodia ei voitu lähettää juuri nyt. Yritä myöhemmin uudelleen.',
    'An account with this email or phone number already exists. Please sign in with your password.':
        'Tällä sähköpostiosoitteella tai puhelinnumerolla on jo tili. Kirjaudu salasanallasi.',
    'An account with this email or phone already exists. Please sign in.':
        'Tällä sähköpostiosoitteella tai puhelinnumerolla on jo tili. Kirjaudu sisään.',
    'Refresh token expired or invalid': 'Kirjaudu uudelleen sisään.',
    'Invalid or expired token': 'Kirjaudu uudelleen sisään.',
    'Your session has ended. Please sign in again.': 'Istuntosi on päättynyt. Kirjaudu sisään uudelleen.',
    'Registration failed. Please try again.': 'Rekisteröityminen epäonnistui. Yritä uudelleen.',
    'Google sign-in failed.': 'Google-kirjautuminen epäonnistui.',
    'Phone sign-in failed.': 'Puhelinkirjautuminen epäonnistui.',
    'Invalid Google token': 'Google-kirjautuminen epäonnistui. Yritä uudelleen.',
    'Invalid phone token': 'Puhelinkirjautuminen epäonnistui. Yritä uudelleen.',
    'Invalid sign-in token': 'Kirjautuminen epäonnistui. Yritä uudelleen.',
    'Google sign-in is not configured': 'Google-kirjautuminen ei ole käytössä.',
    'This Google account is already linked to another Malvoya account': 'Tämä Google-tili on jo yhdistetty toiseen Malvoya-tiliin.',
    'A different Google account is already linked. Unlink it first.': 'Tiliin on jo yhdistetty toinen Google-tili. Poista se ensin.',
    'Google can only be unlinked from accounts that sign in with a password.':
        'Google-yhteyden voi poistaa vain tililtä, jolle kirjaudutaan salasanalla.',
    'You have orders in progress. Your account can be deleted once they are completed or cancelled.':
        'Sinulla on keskeneräisiä tilauksia. Tilin voi poistaa, kun ne on toimitettu tai peruttu.',
    'Accept the Seller Terms to create a store account': 'Hyväksy myyjän ehdot luodaksesi kauppatilin.',
    'Password must be at least 8 characters': 'Salasanassa on oltava vähintään 8 merkkiä.',
    'Enter a phone number': 'Anna puhelinnumero.',
    'Enter a name between 1 and 80 characters': 'Anna nimi, jossa on 1–80 merkkiä.',

    // ── Forgotten password ─────────────────────────────────────────────────
    'Password reset by email is not available yet. Contact support.':
        'Salasanan vaihto sähköpostilla ei ole vielä käytössä. Ota yhteyttä tukeen.',
    'Enter the 6-digit code from the email': 'Anna sähköpostissa tullut 6-numeroinen koodi.',
    'The code is wrong or has expired. Request a new one.': 'Koodi on väärä tai vanhentunut. Pyydä uusi koodi.',
    'Too many wrong codes. Request a new one.': 'Liian monta väärää koodia. Pyydä uusi koodi.',

    // ── Orders and checkout (customer) ─────────────────────────────────────
    'This store is not taking orders right now.': 'Kauppa ei ota juuri nyt vastaan tilauksia.',
    'This store is not accepting orders': 'Kauppa ei ota juuri nyt vastaan tilauksia.',
    'This store does not offer pickup': 'Tästä kaupasta ei voi noutaa.',
    'Enter a delivery address': 'Kirjoita toimitusosoite.',
    'Tips go to couriers, so a pickup order cannot have a tip': 'Tippi menee kuriirille, joten noutotilaukseen ei voi lisätä tippiä.',
    'The order changed in the meantime, please refresh': 'Tilaus muuttui sillä välin. Päivitä näkymä.',
    'This order is already on its way and can no longer be cancelled': 'Tilaus on jo matkalla, eikä sitä voi enää perua.',
    'The store has already accepted this order. Please contact support or use your 14-day return right after delivery.':
        'Kauppa on jo hyväksynyt tilauksen. Ota yhteyttä tukeen tai käytä 14 päivän palautusoikeutta toimituksen jälkeen.',
    'You can return an order once it has been delivered': 'Voit palauttaa tilauksen, kun se on toimitettu.',
    'You can review an order once it has been delivered': 'Voit arvioida tilauksen, kun se on toimitettu.',
    'Reviews can be left within 30 days of delivery': 'Arvion voi jättää 30 päivän kuluessa toimituksesta.',
    'This delivery time is not offered. Pick one of the times shown.': 'Tätä toimitusaikaa ei ole tarjolla. Valitse jokin näytetyistä ajoista.',
    'Deliveries can be scheduled for today or tomorrow.': 'Toimituksen voi ajastaa tälle päivälle tai huomiselle.',
    'The store is closed at that time. Pick another delivery time.': 'Kauppa on silloin kiinni. Valitse toinen toimitusaika.',
    'Pickup orders have no delivery time': 'Noutotilauksella ei ole toimitusaikaa.',
    'This order has not been paid yet': 'Tilausta ei ole vielä maksettu.',
    'This order has not been paid': 'Tilausta ei ole maksettu.',

    // ── Store: orders, returns, products ───────────────────────────────────
    "The store completes a pickup order by entering the customer's pickup code":
        'Noutotilaus merkitään noudetuksi syöttämällä asiakkaan noutokoodi.',
    'Mark the order ready before handing it over': 'Merkitse tilaus valmiiksi ennen luovutusta.',
    'This order can no longer be handed over': 'Tilausta ei voi enää luovuttaa.',
    'This return has already been refunded': 'Tämä palautus on jo hyvitetty.',
    'Order has no captured payment to refund': 'Tilauksella ei ole veloitettua maksua, jonka voisi hyvittää.',
    'Explain the deduction in the condition note': 'Perustele vähennys kuntohuomiossa.',
    "Add store pictures with the app's photo picker": 'Lisää kaupan kuvat sovelluksen kuvavalitsimella.',
    "Add photos with the app's photo picker": 'Lisää kuvat sovelluksen kuvavalitsimella.',
    'The upload was not found. Please try again.': 'Ladattua tiedostoa ei löytynyt. Yritä uudelleen.',
    'Upload could not be verified': 'Latausta ei voitu varmistaa. Yritä uudelleen.',
    'That upload does not belong to you': 'Ladattu tiedosto ei kuulu sinulle.',
    'Photo and video uploads are not switched on yet': 'Kuvien ja videoiden lataus ei ole vielä käytössä.',
    'Choose one of your own products': 'Valitse jokin omista tuotteistasi.',
    'That product is not for sale right now': 'Tuote ei ole nyt myynnissä.',
    'That video is already posted': 'Tämä video on jo julkaistu.',
    'That video is already added': 'Tämä video on jo lisätty.',
    'You can import your catalogue once Malvoya has approved your store': 'Voit tuoda tuotteesi, kun Malvoya on hyväksynyt kauppasi.',
    'An import is already running for your store. Wait for it to finish.': 'Kauppasi tuonti on jo käynnissä. Odota, että se valmistuu.',
    'Business sellers must give their Y-tunnus': 'Yritysmyyjän on annettava Y-tunnus.',
    'Y-tunnus format is 1234567-8': 'Y-tunnuksen muoto on 1234567-8.',
    'This Y-tunnus is not valid: check the last digit': 'Y-tunnus ei kelpaa: tarkista viimeinen numero.',

    // ── Store: tax information (DAC7) ──────────────────────────────────────
    'A Finnish postal code has 5 digits': 'Suomalaisessa postinumerossa on 5 numeroa.',
    'Enter your date of birth as YYYY-MM-DD': 'Anna syntymäaikasi muodossa VVVV-KK-PP.',
    'Sellers must be at least 18 years old': 'Myyjän on oltava vähintään 18-vuotias.',
    'This is not a valid Finnish personal identity code (henkilötunnus)': 'Tämä ei ole kelvollinen suomalainen henkilötunnus.',
    'The personal identity code does not match the date of birth': 'Henkilötunnus ei vastaa syntymäaikaa.',
    'Enter the tax identification number of your country of residence': 'Anna asuinmaasi verotunniste.',
    'Enter your tax identification number (henkilötunnus for Finnish residents)': 'Anna verotunnisteesi (Suomessa asuville henkilötunnus).',
    'Tax IDs cannot be saved right now because secure storage is not set up on the server. Please try again later.':
        'Verotunnistetta ei voi juuri nyt tallentaa, koska palvelimen suojattu tallennus ei ole käytössä. Yritä myöhemmin uudelleen.',
    'Add your business ID (Y-tunnus) to the store first': 'Lisää ensin Y-tunnus kaupan tietoihin.',
    'Enter the VAT number with its country prefix, e.g. SE123456789001': 'Anna ALV-numero maatunnuksen kanssa, esim. SE123456789001.',
    'Use a two-letter country code, e.g. FI': 'Käytä kaksikirjaimista maatunnusta, esim. FI.',
    'Use the month as YYYY-MM': 'Anna kuukausi muodossa VVVV-KK.',

    // ── Courier: jobs and deliveries ───────────────────────────────────────
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
    'Confirm the handover in the app to complete this delivery': 'Vahvista luovutus sovelluksessa, niin toimitus merkitään valmiiksi.',
    'Your courier account is awaiting approval': 'Lähettitilisi odottaa vielä hyväksyntää.',
    'You are offline': 'Olet poissa linjoilta.',
    'You can only add a photo to a delivery you are carrying': 'Voit lisätä kuvan vain toimitukseen, joka on sinulla.',
    'Only couriers can upload delivery photos': 'Vain lähetit voivat ladata toimituskuvia.',
    'locationDisclosure: true is required': 'Sijaintitiedotteen hyväksyntä puuttuu.',

    // ── Payouts ────────────────────────────────────────────────────────────
    'You can set up payouts once your account is approved': 'Voit ottaa tilitykset käyttöön, kun tilisi on hyväksytty.',
    'Set up payouts first': 'Ota ensin tilitykset käyttöön.',
    'Only failed payouts can be retried': 'Vain epäonnistuneen tilityksen voi yrittää uudelleen.',

    // ── Agreements (API 2.11) ──────────────────────────────────────────────
    'That is not the current or the announced version of this document. Reload and try again.':
        'Tämä ei ole voimassa oleva eikä ilmoitettu versio. Päivitä näkymä ja yritä uudelleen.',
    'Agreement copy not found': 'Sopimuksen kopiota ei löytynyt.',
    'This document is not one your account accepts': 'Tätä asiakirjaa ei hyväksytä tällä tilillä.',
    'doc and version are required': 'Asiakirja ja versio puuttuvat. Yritä uudelleen.',

    // ── Drops, comments, safety ────────────────────────────────────────────
    'You are commenting very fast. Please wait a few minutes.': 'Kommentoit hyvin nopeasti. Odota muutama minuutti.',
    'Write a comment first': 'Kirjoita ensin kommentti.',
    'You cannot block yourself': 'Et voi estää itseäsi.',
    'You cannot report your own review': 'Et voi ilmoittaa omasta arviostasi.',
    'Choose or write a reason': 'Valitse tai kirjoita syy.',

    // ── Support ────────────────────────────────────────────────────────────
    'Give an email address we can reply to': 'Anna sähköpostiosoite, johon voimme vastata.',
    'Write a short description of what you need help with': 'Kirjoita lyhyesti, missä tarvitset apua.',
    'You have sent several requests already. We will reply to them by email.':
        'Olet jo lähettänyt useita viestejä. Vastaamme niihin sähköpostitse.',
  };

  static final List<({RegExp pattern, String Function(RegExpMatch m) fi})> _patterns = [
    (pattern: RegExp(r'^Insufficient stock for (.+)$'), fi: (m) => 'Tuotetta ”${m[1]}” ei ole riittävästi varastossa.'),
    (pattern: RegExp(r'^(.+) is not available for purchase$'), fi: (m) => '”${m[1]}” ei ole enää myynnissä.'),
    (pattern: RegExp(r'^The minimum order is (.+)$'), fi: (m) => 'Vähimmäistilaus on ${m[1]}.'),
    (
      pattern: RegExp(r'^This store is closed right now\.(?: It opens again at (\S+)\.)?$'),
      fi: (m) => m[1] == null ? 'Kauppa on nyt suljettu.' : 'Kauppa on nyt suljettu. Se aukeaa taas klo ${m[1]!.replaceAll(':', '.')}.',
    ),
    (
      pattern: RegExp(r'^This delivery time is too soon\. Pick a time that starts at least (\d+) minutes from now\.$'),
      fi: (m) => 'Tämä toimitusaika on liian pian. Valitse aika, joka alkaa aikaisintaan ${m[1]} minuutin päästä.',
    ),
    (pattern: RegExp(r'^Refund must be between 0\.01 and ([\d.]+) €$'), fi: (m) => 'Hyvityksen on oltava 0,01–${m[1]!.replaceAll('.', ',')} €.'),
    (pattern: RegExp(r'^Cannot change order from \w+ to \w+$'), fi: (_) => 'Tilauksen tila on jo muuttunut. Päivitä näkymä.'),
    (
      pattern: RegExp(r'^A Finnish VAT number is FI followed by the Y-tunnus without the dash \((FI\d+)\)$'),
      fi: (m) => 'Suomalainen ALV-numero on FI ja Y-tunnus ilman väliviivaa (${m[1]}).',
    ),
    (pattern: RegExp(r'^Videos can be up to (\d+) seconds$'), fi: (m) => 'Video voi olla enintään ${m[1]} sekuntia.'),
  ];
}

/// A server message in the widget's language. See [ServerMessages.localize].
String localizeServerMessage(BuildContext context, String message) =>
    ServerMessages.localize(message, languageCode: isFinnish(context) ? 'fi' : 'en');
