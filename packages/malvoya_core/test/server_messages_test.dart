import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_core/malvoya_core.dart';

void main() {
  test('known messages are translated in Finnish and kept in English', () {
    expect(ServerMessages.localize('Order not found', languageCode: 'fi'), 'Tilausta ei löytynyt.');
    expect(ServerMessages.localize('Order not found', languageCode: 'en'), 'Order not found');
  });

  test('messages from all three apps are in the one table', () {
    // customer
    expect(ServerMessages.isKnown('Enter a delivery address'), isTrue);
    // store
    expect(ServerMessages.isKnown('Y-tunnus format is 1234567-8'), isTrue);
    // courier
    expect(ServerMessages.isKnown('Go online before accepting deliveries'), isTrue);
    // the client's own messages
    expect(ServerMessages.isKnown('Could not reach Malvoya. Check your connection and try again.'), isTrue);
    expect(ServerMessages.exactCount, greaterThan(130));
  });

  test('a trailing full stop does not matter, spaces around do not either', () {
    expect(ServerMessages.localize('Order not found.', languageCode: 'fi'), 'Tilausta ei löytynyt.');
    expect(ServerMessages.localize('  Forbidden ', languageCode: 'fi'), 'Sinulla ei ole oikeutta tähän.');
  });

  test('patterns keep the changing part', () {
    expect(ServerMessages.localize('Insufficient stock for Linen shirt', languageCode: 'fi'), 'Tuotetta ”Linen shirt” ei ole riittävästi varastossa.');
    expect(ServerMessages.localize('This store is closed right now. It opens again at 09:30.', languageCode: 'fi'),
        'Kauppa on nyt suljettu. Se aukeaa taas klo 09.30.');
    expect(ServerMessages.localize('Refund must be between 0.01 and 42.50 €', languageCode: 'fi'), 'Hyvityksen on oltava 0,01–42,50 €.');
    expect(ServerMessages.localize('Videos can be up to 60 seconds', languageCode: 'fi'), 'Video voi olla enintään 60 sekuntia.');
  });

  test('bilingual server sentences are split by language', () {
    const both = 'Hyväksy ehdot ensin. / Accept the terms first.';
    expect(ServerMessages.localize(both, languageCode: 'fi'), 'Hyväksy ehdot ensin.');
    expect(ServerMessages.localize(both, languageCode: 'en'), 'Accept the terms first.');
    // A product name with a slash is not a translation pair
    expect(ServerMessages.localize('Insufficient stock for Top / skirt set', languageCode: 'en'), 'Insufficient stock for Top / skirt set');
  });

  test('unknown messages are shown as the server wrote them', () {
    expect(ServerMessages.localize('Some brand new message', languageCode: 'fi'), 'Some brand new message');
  });

  test('ApiResult keeps the raw message and translates it for the app language', () {
    AppLanguage.code = 'fi';
    final r = ApiResult(404, const {}, 'Order not found');
    expect(r.rawError, 'Order not found');
    expect(r.error, 'Tilausta ei löytynyt.');
    expect(r.ok, isFalse);
    AppLanguage.code = 'en';
    expect(ApiResult(404, const {}, 'Order not found').error, 'Order not found');
  });
}
