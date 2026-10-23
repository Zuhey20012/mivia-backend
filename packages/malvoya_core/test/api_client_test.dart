import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malvoya_core/malvoya_core.dart';

class FakeSession implements ApiSession {
  FakeSession(this.accessToken);
  @override
  String? accessToken;
  int refreshes = 0;
  bool refreshWorks = true;

  @override
  Future<bool> refreshSession() async {
    refreshes++;
    if (refreshWorks) accessToken = 'fresh';
    return refreshWorks;
  }
}

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late List<http.Request> sent;

  void serve(Future<http.Response> Function(http.Request req, int n) handler) {
    sent = [];
    final mock = MockClient((req) async {
      sent.add(req);
      return handler(req, sent.length);
    });
    ApiConfig.httpClient = () => mock;
  }

  setUp(() {
    ApiConfig.baseUrl = 'https://api.test/api/v1';
    ApiConfig.retryDelay = Duration.zero;
    ApiConfig.onAgreementRequired = null;
    ApiConfig.onNetworkError = null;
    AppLanguage.code = 'en';
    AppLanguage.appVersion = '1.7.0+9';
  });

  test('sends language, app version and session', () async {
    serve((req, _) async => json(200, {'ok': true}));
    final res = await ApiClient(FakeSession('abc')).get('/me', query: {'a': '1'});
    expect(res.ok, isTrue);
    final req = sent.single;
    expect(req.url.toString(), 'https://api.test/api/v1/me?a=1');
    expect(req.headers['Authorization'], 'Bearer abc');
    expect(req.headers['Accept-Language'], 'en');
    expect(req.headers['X-App-Version'], '1.7.0+9');
  });

  group('428 AGREEMENT_REQUIRED', () {
    final required = {'ok': false, 'code': 'AGREEMENT_REQUIRED', 'doc': 'terms', 'version': 'terms@abc', 'error': 'Please accept the Terms.'};

    test('the hook is asked once and the request is sent again after acceptance', () async {
      serve((req, n) async => n == 1 ? json(428, required) : json(201, {'ok': true, 'order': {'id': 7}}));
      var asked = 0;
      ApiConfig.onAgreementRequired = (result, session) async {
        asked++;
        expect(AgreementRequired.from(result)!.version, 'terms@abc');
        return true;
      };
      final res = await ApiClient(FakeSession('t')).post('/orders', {'items': []});
      expect(asked, 1);
      expect(sent.length, 2);
      expect(sent[1].body, sent[0].body);
      expect(res.ok, isTrue);
      expect(res.data['order']['id'], 7);
    });

    test('declining returns the 428 without sending again', () async {
      serve((req, n) async => json(428, required));
      ApiConfig.onAgreementRequired = (result, session) async => false;
      final res = await ApiClient(FakeSession('t')).post('/orders', {});
      expect(sent.length, 1);
      expect(res.agreementRequired, isTrue);
      expect(res.error, 'Please accept the Terms.');
    });

    test('a second 428 after acceptance is returned, never a loop', () async {
      serve((req, n) async => json(428, required));
      var asked = 0;
      ApiConfig.onAgreementRequired = (result, session) async {
        asked++;
        return true;
      };
      final res = await ApiClient(FakeSession('t')).post('/orders', {});
      expect(asked, 1);
      expect(sent.length, 2);
      expect(res.agreementRequired, isTrue);
    });

    test('without a hook the caller sees the 428', () async {
      serve((req, n) async => json(428, required));
      final res = await ApiClient(FakeSession('t')).patch('/courier/status', {'online': true});
      expect(sent.length, 1);
      expect(AgreementRequired.from(res)?.doc, 'terms');
    });
  });

  test('401 refreshes the session once and repeats with the new token', () async {
    serve((req, n) async => n == 1 ? json(401, {'error': 'Invalid or expired token'}) : json(200, {'ok': true}));
    final session = FakeSession('old');
    final res = await ApiClient(session).get('/me');
    expect(session.refreshes, 1);
    expect(sent[1].headers['Authorization'], 'Bearer fresh');
    expect(res.ok, isTrue);
  });

  test('a failed refresh returns the 401', () async {
    serve((req, n) async => json(401, {'error': 'Invalid or expired token'}));
    final session = FakeSession('old')..refreshWorks = false;
    final res = await ApiClient(session).get('/me');
    expect(sent.length, 1);
    expect(res.status, 401);
  });

  test('GETs are repeated after a 503, other methods are not', () async {
    serve((req, n) async => n == 1 ? json(503, {}) : json(200, {'ok': true}));
    expect((await const ApiClient().get('/stores')).ok, isTrue);
    expect(sent.length, 2);

    serve((req, n) async => json(503, {}));
    final post = await const ApiClient().post('/support', {});
    expect(sent.length, 1);
    expect(post.error, 'Something went wrong on our side. Please try again.');
  });

  test('network errors: GET retried, then a readable message and the hook', () async {
    serve((req, n) async => throw http.ClientException('offline'));
    var told = 0;
    ApiConfig.onNetworkError = () => told++;
    final res = await const ApiClient().get('/stores');
    expect(sent.length, 2);
    expect(res.status, 0);
    expect(told, 1);
    expect(res.error, 'Could not reach Malvoya. Check your connection and try again.');
  });

  test('timeouts give a readable message', () async {
    ApiConfig.timeout = const Duration(milliseconds: 20);
    serve((req, n) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return json(200, {});
    });
    final res = await const ApiClient().post('/orders', {});
    expect(res.status, 0);
    expect(res.error, 'The server took too long to answer. Please try again.');
    ApiConfig.timeout = const Duration(seconds: 15);
  });

  test('errors: server sentence, field errors, then status sentences (translated)', () async {
    AppLanguage.code = 'fi';
    serve((req, n) async => json(404, {'error': 'Order not found'}));
    expect((await const ApiClient().get('/orders/1')).error, 'Tilausta ei löytynyt.');
    serve((req, n) async => json(400, {'errors': {'fieldErrors': {'email': ['Enter a valid email address']}}}));
    expect((await const ApiClient().post('/x', {})).error, 'Anna kelvollinen sähköpostiosoite.');
    serve((req, n) async => json(429, {}));
    expect((await const ApiClient().post('/x', {})).error, 'Liian monta yritystä. Odota hetki.');
  });
}
