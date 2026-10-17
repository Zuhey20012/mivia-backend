import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../config/constants.dart';
import 'app_language.dart';
import 'strings.dart';

/// Result of an API call. [error] is always a sentence that can be shown to the user.
class ApiResult {
  final int status;
  final Map<String, dynamic> data;
  final String? error;

  const ApiResult(this.status, this.data, this.error);

  bool get ok => error == null && status >= 200 && status < 300;
}

/// Small JSON client for the Malvoya API: adds the session, retries once after a token
/// refresh, and turns network problems into readable messages.
class ApiClient {
  final AuthService? auth;
  const ApiClient([this.auth]);

  static const _timeout = Duration(seconds: 15);

  Future<ApiResult> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<ApiResult> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<ApiResult> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<ApiResult> patch(String path, [Object? body]) => _send('PATCH', path, body: body);
  Future<ApiResult> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  Future<ApiResult> _send(String method, String path, {Object? body, Map<String, String>? query, bool retried = false}) async {
    final uri = Uri.parse('${AppConstants.apiBase}$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...AppLanguage.header,
      if (auth?.accessToken != null) 'Authorization': 'Bearer ${auth!.accessToken}',
    };
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed).timeout(_timeout);

      if (res.statusCode == 401 && !retried && auth?.accessToken != null) {
        if (await auth!.refreshSession()) return await _send(method, path, body: body, query: query, retried: true);
      }

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}

      if (res.statusCode >= 200 && res.statusCode < 300) return ApiResult(res.statusCode, data, null);
      return ApiResult(res.statusCode, data, _messageFor(res.statusCode, data));
    } on TimeoutException {
      return const ApiResult(0, {}, 'The server took too long to answer. Please try again.');
    } catch (_) {
      return const ApiResult(0, {}, 'Could not reach Malvoya. Check your connection and try again.');
    }
  }

  static String _messageFor(int status, Map<String, dynamic> data) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;
    final fieldErrors = data['errors']?['fieldErrors'];
    if (fieldErrors is Map && fieldErrors.isNotEmpty) {
      final first = fieldErrors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    if (status == 401) return 'Please sign in again.';
    if (status == 403) return 'You do not have access to this.';
    if (status == 404) return 'Not found.';
    if (status == 429) return 'Too many attempts. Please wait a moment.';
    if (status >= 500) return 'Something went wrong on our side. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}

/// The client's own fixed messages, and the server's most common ones, in Finnish. Other server
/// messages are shown as they come.
const _fiMessages = {
  'The server took too long to answer. Please try again.': 'Palvelin ei vastannut ajoissa. Yritä uudelleen.',
  'Could not reach Malvoya. Check your connection and try again.': 'Malvoyaan ei saatu yhteyttä. Tarkista yhteys ja yritä uudelleen.',
  'Please sign in again.': 'Kirjaudu sisään uudelleen.',
  'You do not have access to this.': 'Sinulla ei ole pääsyä tähän.',
  'Not found.': 'Ei löytynyt.',
  'Too many attempts. Please wait a moment.': 'Liian monta yritystä. Odota hetki.',
  'Something went wrong on our side. Please try again.': 'Jotain meni vikaan meidän päässämme. Yritä uudelleen.',
  'Something went wrong. Please try again.': 'Jotain meni vikaan. Yritä uudelleen.',
  // Server (backend/src) messages customers meet most often
  'Invalid request': 'Virheellinen pyyntö.',
  'Forbidden': 'Sinulla ei ole oikeutta tähän.',
  'Order not found': 'Tilausta ei löytynyt.',
  'Product not found': 'Tuotetta ei löytynyt.',
  'Store not found': 'Kauppaa ei löytynyt.',
  'Return not found': 'Palautusta ei löytynyt.',
  'Drop not found': 'Droppia ei löytynyt.',
  'This drop is not available': 'Tämä droppi ei ole saatavilla.',
  'Promo code not found': 'Alennuskoodia ei löytynyt.',
  'Invalid credentials': 'Väärä sähköpostiosoite tai salasana.',
  'Invalid verification code': 'Koodi on väärä.',
  'The code has already been used': 'Koodi on jo käytetty.',
  'The code has expired. Please request a new one.': 'Koodi on vanhentunut. Pyydä uusi koodi.',
  'Too many incorrect attempts. Please request a new code.': 'Liian monta väärää yritystä. Pyydä uusi koodi.',
  'Please wait a minute before requesting a new code': 'Odota hetki ennen kuin pyydät uuden koodin.',
  'We could not send a verification code right now. Please try again later.': 'Vahvistuskoodia ei voitu lähettää juuri nyt. Yritä myöhemmin uudelleen.',
  'Enter a valid email address or phone number': 'Kirjoita kelvollinen sähköpostiosoite tai puhelinnumero.',
  'An account with this email or phone already exists. Please sign in.': 'Tällä sähköpostilla tai puhelinnumerolla on jo tili. Kirjaudu sisään.',
  'This account is disabled': 'Tämä tili on poistettu käytöstä.',
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
  'This return has already been refunded': 'Tämä palautus on jo hyvitetty.',
  'You have orders in progress. Your account can be deleted once they are completed or cancelled.':
      'Sinulla on keskeneräisiä tilauksia. Tilin voi poistaa, kun ne on toimitettu tai peruttu.',
  'You are commenting very fast. Please wait a few minutes.': 'Kommentoit hyvin nopeasti. Odota muutama minuutti.',
  'Write a comment first': 'Kirjoita ensin kommentti.',
  'This delivery time is not offered. Pick one of the times shown.': 'Tätä toimitusaikaa ei ole tarjolla. Valitse jokin näytetyistä ajoista.',
  'Deliveries can be scheduled for today or tomorrow.': 'Toimituksen voi ajastaa tälle päivälle tai huomiselle.',
  'The store is closed at that time. Pick another delivery time.': 'Kauppa on silloin kiinni. Valitse toinen toimitusaika.',
  'Pickup orders have no delivery time': 'Noutotilauksella ei ole toimitusaikaa.',
  // Password reset, blocking and reports
  'Enter a valid email address': 'Kirjoita kelvollinen sähköpostiosoite.',
  'Password reset by email is not available yet. Contact support.': 'Salasanan palautus sähköpostilla ei ole vielä käytössä. Ota yhteyttä tukeen.',
  'The code is wrong or has expired. Request a new one.': 'Koodi on väärä tai vanhentunut. Pyydä uusi koodi.',
  'Too many wrong codes. Request a new one.': 'Liian monta väärää koodia. Pyydä uusi koodi.',
  'Enter the 6-digit code from the email': 'Kirjoita sähköpostissa tullut 6-numeroinen koodi.',
  'Password must be at least 8 characters': 'Salasanassa on oltava vähintään 8 merkkiä.',
  'Your session has ended. Please sign in again.': 'Istuntosi on päättynyt. Kirjaudu sisään uudelleen.',
  'You cannot block yourself': 'Et voi estää itseäsi.',
  'User not found': 'Käyttäjää ei löytynyt.',
  'Review not found': 'Arviota ei löytynyt.',
  'You cannot report your own review': 'Et voi ilmoittaa omasta arviostasi.',
  'Choose or write a reason': 'Valitse tai kirjoita syy.',
};

/// Server messages with a changing part (a product name, an amount, a time).
final _fiPatterns = <RegExp, String Function(Match)>{
  RegExp(r'^Insufficient stock for (.+)$'): (m) => 'Tuotetta ”${m[1]}” ei ole riittävästi varastossa.',
  RegExp(r'^(.+) is not available for purchase$'): (m) => '”${m[1]}” ei ole enää myynnissä.',
  RegExp(r'^The minimum order is (.+)$'): (m) => 'Vähimmäistilaus on ${m[1]}.',
  RegExp(r'^This store is closed right now\.(?: It opens again at (\S+)\.)?$'): (m) =>
      m[1] == null ? 'Kauppa on nyt suljettu.' : 'Kauppa on nyt suljettu. Se aukeaa taas klo ${m[1]!.replaceAll(':', '.')}.',
  RegExp(r'^This delivery time is too soon\. Pick a time that starts at least (\d+) minutes from now\.$'): (m) =>
      'Tämä toimitusaika on liian pian. Valitse aika, joka alkaa aikaisintaan ${m[1]} minuutin päästä.',
};

/// A message from the server in the app's language: known English messages are translated to
/// Finnish, and messages the server sends in both languages ("Finnish / English") are split.
String localizeServerMessage(BuildContext context, String message) {
  final fi = isFinnish(context);
  final halves = message.split(' / ');
  // (both halves are whole sentences, so a product name containing " / " is never split)
  bool sentence(String t) => RegExp(r'[.!?]$').hasMatch(t.trim());
  if (halves.length == 2 && sentence(halves[0]) && sentence(halves[1])) {
    return (fi ? halves[0] : halves[1]).trim();
  }
  if (!fi) return message;
  final exact = _fiMessages[message] ?? _fiMessages[message.trim().replaceAll(RegExp(r'\.$'), '')];
  if (exact != null) return exact;
  for (final entry in _fiPatterns.entries) {
    final m = entry.key.firstMatch(message.trim());
    if (m != null) return entry.value(m);
  }
  return message;
}

extension ApiResultText on ApiResult {
  /// [error] in the app's language (the client's own messages and the common server ones).
  String? errorText(BuildContext context) {
    final e = error;
    if (e == null) return null;
    return localizeServerMessage(context, e);
  }
}
