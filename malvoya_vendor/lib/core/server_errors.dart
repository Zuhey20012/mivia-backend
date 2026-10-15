import '../locale_provider.dart';

/// The app's language outside a widget (the API client has no BuildContext).
bool get appIsFinnish => LocaleProvider.currentCode == 'fi';

/// English or Finnish by the app's language, for messages made outside a widget.
String trApp(String en, String fi) => appIsFinnish ? fi : en;

/// The Malvoya API answers in English. These are the messages a store owner is most likely to see,
/// in Finnish; anything else is shown as the server wrote it.
const Map<String, String> _finnish = {
  // Not found / access
  'Order not found': 'Tilausta ei löytynyt.',
  'Product not found': 'Tuotetta ei löytynyt.',
  'Store not found': 'Kauppaa ei löytynyt.',
  'Return not found': 'Palautusta ei löytynyt.',
  'Drop not found': 'Julkaisua ei löytynyt.',
  'Video not found': 'Videota ei löytynyt.',
  'Payout not found': 'Tilitystä ei löytynyt.',
  'Account not found': 'Tiliä ei löytynyt.',
  'Forbidden': 'Sinulla ei ole oikeutta tähän.',
  'Create your store first': 'Perusta ensin kauppasi.',
  'This account is disabled': 'Tämä tili on poistettu käytöstä.',
  // Orders
  'The order changed in the meantime, please refresh': 'Tilaus muuttui sillä välin. Päivitä näkymä.',
  'This order is already on its way and can no longer be cancelled': 'Tilaus on jo matkalla, eikä sitä voi enää perua.',
  'This order has not been paid yet': 'Tilausta ei ole vielä maksettu.',
  'This order has not been paid': 'Tilausta ei ole maksettu.',
  'The store completes a pickup order by entering the customer\'s pickup code':
      'Noutotilaus merkitään noudetuksi syöttämällä asiakkaan noutokoodi.',
  'Mark the order ready before handing it over': 'Merkitse tilaus valmiiksi ennen luovutusta.',
  'This order can no longer be handed over': 'Tilausta ei voi enää luovuttaa.',
  // Returns
  'This return has already been refunded': 'Tämä palautus on jo hyvitetty.',
  'Order has no captured payment to refund': 'Tilauksella ei ole veloitettua maksua, jonka voisi hyvittää.',
  'Explain the deduction in the condition note': 'Perustele vähennys kuntohuomiossa.',
  // Products, media, drops, imports
  'Add store pictures with the app\'s photo picker': 'Lisää kaupan kuvat sovelluksen kuvavalitsimella.',
  'Add photos with the app\'s photo picker': 'Lisää kuvat sovelluksen kuvavalitsimella.',
  'The upload was not found. Please try again.': 'Ladattua tiedostoa ei löytynyt. Yritä uudelleen.',
  'Upload could not be verified': 'Latausta ei voitu varmistaa.',
  'That upload does not belong to you': 'Ladattu tiedosto ei kuulu sinulle.',
  'Photo and video uploads are not switched on yet': 'Kuvien ja videoiden lataus ei ole vielä käytössä.',
  'Choose one of your own products': 'Valitse jokin omista tuotteistasi.',
  'That product is not for sale right now': 'Tuote ei ole nyt myynnissä.',
  'That video is already posted': 'Tämä video on jo julkaistu.',
  'That video is already added': 'Tämä video on jo lisätty.',
  'You can import your catalogue once Malvoya has approved your store': 'Voit tuoda tuotteesi, kun Malvoya on hyväksynyt kauppasi.',
  'An import is already running for your store. Wait for it to finish.': 'Kauppasi tuonti on jo käynnissä. Odota, että se valmistuu.',
  // Store details
  'Business sellers must give their Y-tunnus': 'Yritysmyyjän on annettava Y-tunnus.',
  'Y-tunnus format is 1234567-8': 'Y-tunnuksen muoto on 1234567-8.',
  // Payouts
  'You can set up payouts once your account is approved': 'Voit ottaa tilitykset käyttöön, kun tilisi on hyväksytty.',
  'Set up payouts first': 'Ota ensin tilitykset käyttöön.',
  // Tax information (DAC7)
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
  // Account and sign-in
  'Invalid credentials': 'Väärä sähköposti, puhelinnumero tai salasana.',
  'Invalid email or password.': 'Väärä sähköposti tai salasana.',
  'Invalid phone number or email address': 'Virheellinen puhelinnumero tai sähköpostiosoite.',
  'Enter a valid email address or phone number': 'Anna kelvollinen sähköpostiosoite tai puhelinnumero.',
  'Refresh token expired or invalid': 'Kirjaudu uudelleen sisään.',
  'Registration failed. Please try again.': 'Rekisteröityminen epäonnistui. Yritä uudelleen.',
  'Google sign-in failed.': 'Google-kirjautuminen epäonnistui.',
  'Phone sign-in failed.': 'Puhelinkirjautuminen epäonnistui.',
  'An account with this email or phone number already exists. Please sign in with your password.':
      'Tällä sähköpostiosoitteella tai puhelinnumerolla on jo tili. Kirjaudu salasanallasi.',
  'An account with this email or phone already exists. Please sign in.':
      'Tällä sähköpostiosoitteella tai puhelinnumerolla on jo tili. Kirjaudu sisään.',
  'This Google account is already linked to another Malvoya account': 'Tämä Google-tili on jo yhdistetty toiseen Malvoya-tiliin.',
  'A different Google account is already linked. Unlink it first.': 'Tiliin on jo yhdistetty toinen Google-tili. Poista se ensin.',
  'Google can only be unlinked from accounts that sign in with a password.': 'Google-yhteyden voi poistaa vain tileiltä, joille kirjaudutaan salasanalla.',
  'You have orders in progress. Your account can be deleted once they are completed or cancelled.':
      'Sinulla on keskeneräisiä tilauksia. Tilin voi poistaa, kun ne on toimitettu tai peruttu.',
  // Support and limits
  'Give an email address we can reply to': 'Anna sähköpostiosoite, johon voimme vastata.',
  'Write a short description of what you need help with': 'Kirjoita lyhyesti, missä tarvitset apua.',
  'You have sent several requests already. We will reply to them by email.': 'Olet jo lähettänyt useita viestejä. Vastaamme niihin sähköpostitse.',
  'Too many requests, please try again later.': 'Liian monta pyyntöä. Yritä hetken päästä uudelleen.',
  'Too many attempts, please try again later.': 'Liian monta yritystä. Yritä hetken päästä uudelleen.',
};

final _refundRange = RegExp(r'^Refund must be between 0\.01 and ([\d.]+) €$');
final _transition = RegExp(r'^Cannot change order from \w+ to \w+$');
final _finnishVat = RegExp(r'^A Finnish VAT number is FI followed by the Y-tunnus without the dash \((FI\d+)\)$');
final _videoLength = RegExp(r'^Videos can be up to (\d+) seconds$');

/// The server's message in the app's language (Finnish when the app is in Finnish and the message is known).
String localizeServerError(String message) {
  if (!appIsFinnish) return message;
  final known = _finnish[message.trim()];
  if (known != null) return known;
  final refund = _refundRange.firstMatch(message);
  if (refund != null) return 'Hyvityksen on oltava 0,01–${refund.group(1)!.replaceAll('.', ',')} €.';
  if (_transition.hasMatch(message)) return 'Tilauksen tila on jo muuttunut. Päivitä näkymä.';
  final vat = _finnishVat.firstMatch(message);
  if (vat != null) return 'Suomalainen ALV-numero on FI ja Y-tunnus ilman väliviivaa (${vat.group(1)}).';
  final video = _videoLength.firstMatch(message);
  if (video != null) return 'Video voi olla enintään ${video.group(1)} sekuntia.';
  return message;
}
