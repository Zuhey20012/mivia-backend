import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// Records everything that would have gone to Firebase Crashlytics.
class FakeBackend implements CrashBackend {
  final calls = <String>[];
  final errors = <({Object error, String? reason, bool fatal})>[];
  final flutterErrors = <FlutterErrorDetails>[];
  final keys = <String, Object>{};
  final userIds = <String>[];
  bool? collection;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    calls.add('collection:$enabled');
    collection = enabled;
  }

  @override
  Future<void> setUserIdentifier(String id) async => userIds.add(id);

  @override
  Future<void> setCustomKey(String key, Object value) async => keys[key] = value;

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) async =>
      errors.add((error: error, reason: reason, fatal: fatal));

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async => flutterErrors.add(details);

  /// Everything sent, as one string, to search for personal data.
  String get everything => [
        ...errors.map((e) => '${e.error} ${e.reason}'),
        ...flutterErrors.map((d) => '${d.exception} ${d.context} ${d.library}'),
        ...keys.entries.map((e) => '${e.key}=${e.value}'),
        ...userIds,
      ].join('\n');
}

class FakeSession extends ChangeNotifier {
  int? userId;
  void signIn(int id) {
    userId = id;
    notifyListeners();
  }

  void signOut() {
    userId = null;
    notifyListeners();
  }
}

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const email = 'anna.virtanen@example.com';
const phone = '+358 40 123 4567';
const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOjQyfQ.c2lnbmF0dXJl';

void main() {
  late FakeBackend backend;
  late CrashReporting crash;

  setUp(() async {
    backend = FakeBackend();
    crash = CrashReporting();
    await crash.init(backend: backend, role: 'customer', enabled: true, appVersion: '1.8.0+10');
  });

  group('collection', () {
    test('release builds: on, with only the app version and role as custom keys', () {
      expect(backend.collection, isTrue);
      expect(crash.active, isTrue);
      expect(backend.keys, {'app_version': '1.8.0+10', 'role': 'customer'});
      expect(backend.keys.keys.toSet(), CrashReporting.allowedKeys);
    });

    test('debug builds: switched off and nothing is sent', () async {
      final b = FakeBackend();
      final c = CrashReporting();
      await c.init(backend: b, role: 'store', enabled: false);
      expect(b.collection, isFalse);
      expect(c.active, isFalse);
      await c.recordNonFatal(StateError('x'));
      await c.setUser(7);
      c.recordApiFault('GET', '/orders', 500);
      expect(c.recordPlatformError(StateError('y'), StackTrace.current), isFalse);
      await pumpEventQueue();
      expect(b.errors, isEmpty);
      expect(b.userIds, isEmpty);
      expect(b.keys, isEmpty);
    });

    test('no backend (Firebase did not start, e.g. iPhone without GoogleService-Info.plist): nothing happens', () async {
      final c = CrashReporting();
      await c.init(role: 'courier', enabled: true);
      expect(c.active, isFalse);
      await c.recordError(StateError('x'), StackTrace.current, fatal: true);
      expect(c.recordPlatformError(StateError('y'), StackTrace.current), isFalse);
    });

    test('a failing backend never throws into the app', () async {
      final c = CrashReporting();
      await c.init(
        backend: CallbackCrashBackend(
          setCollectionEnabled: (_) async {},
          setUserIdentifier: (_) => Future.error(StateError('down')),
          setCustomKey: (_, __) async {},
          recordError: (e, s, {reason, fatal = false}) => Future.error(StateError('down')),
          recordFlutterFatalError: (_) => Future.error(StateError('down')),
        ),
        role: 'customer',
        enabled: true,
      );
      await c.setUser(1);
      await c.recordNonFatal(StateError('x'));
    });
  });

  group('user', () {
    test('only the numeric id is set after sign-in, and cleared on sign-out', () async {
      final session = FakeSession();
      crash.followUser(session, () => session.userId);
      expect(backend.userIds, isEmpty);
      session.signIn(42);
      await pumpEventQueue();
      expect(backend.userIds, ['42']);
      session.signIn(42); // unchanged: not sent again
      await pumpEventQueue();
      expect(backend.userIds, ['42']);
      session.signOut();
      await pumpEventQueue();
      expect(backend.userIds, ['42', '']);
      for (final id in backend.userIds) {
        expect(RegExp(r'^\d*$').hasMatch(id), isTrue);
      }
    });

    test('a user signed in before init is set once collection starts', () async {
      final b = FakeBackend();
      final c = CrashReporting();
      await c.setUser(9);
      await c.init(backend: b, role: 'store', enabled: true);
      expect(b.userIds, ['9']);
    });
  });

  group('fatal hooks', () {
    test('PlatformDispatcher errors are reported as fatal', () async {
      expect(crash.recordPlatformError(StateError('boom'), StackTrace.current), isTrue);
      await pumpEventQueue();
      expect(backend.errors.single.fatal, isTrue);
      expect(backend.errors.single.error.toString(), contains('Bad state: boom'));
    });

    test('Flutter errors are reported as fatal without the widget context', () async {
      final original = FlutterError.presentError;
      FlutterError.presentError = (_) {};
      addTearDown(() => FlutterError.presentError = original);
      crash.recordFlutterFatalError(FlutterErrorDetails(
        exception: StateError('layout for anna@example.com'),
        stack: StackTrace.current,
        library: 'rendering library',
        context: ErrorDescription('while building Text("Anna Virtanen +358 40 123 4567")'),
      ));
      await pumpEventQueue();
      final sent = backend.flutterErrors.single;
      expect(sent.exception, isA<ScrubbedError>());
      expect(sent.exception.toString(), 'StateError: Bad state: layout for <email>');
      expect(sent.context, isNull);
      expect(sent.library, 'rendering library');
      expect(backend.everything, isNot(contains('Anna')));
    });
  });

  group('no personal data', () {
    test('emails, phone numbers, tokens and secrets are scrubbed from errors and reasons', () async {
      await crash.recordNonFatal(
        Exception('login failed for $email, phone $phone, Authorization: Bearer $jwt, password=hunter2'),
        StackTrace.current,
        'while signing in $email',
      );
      final sent = backend.everything;
      expect(sent, isNot(contains(email)));
      expect(sent, isNot(contains('123 4567')));
      expect(sent, isNot(contains(jwt)));
      expect(sent, isNot(contains('hunter2')));
      expect(sent, contains('<email>'));
    });

    test('a FormatException never carries the body it failed on', () async {
      try {
        jsonDecode('{"email": "$email", "name": "Anna Virtanen", "card');
      } catch (e, s) {
        await crash.recordNonFatal(e, s);
      }
      final sent = backend.everything;
      expect(sent, startsWith('FormatException: '));
      expect(sent, isNot(contains('Anna')));
      expect(sent, isNot(contains(email)));
    });

    test('scrubber', () {
      expect(CrashScrubber.scrub('mail $email now'), 'mail <email> now');
      expect(CrashScrubber.scrub('call 0401234567'), 'call <number>');
      expect(CrashScrubber.scrub('hetu 131052-308T'), 'hetu <id-code>');
      expect(CrashScrubber.scrub('iban FI21 1234 5600 0007 85'), 'iban <iban>');
      expect(CrashScrubber.scrub('GET https://api.test/x?email=a%40b.fi&code=123456'), 'GET https://api.test/x?<query>');
      expect(CrashScrubber.scrub('{"token": "abc", "ok": true}'), '{token=<redacted>, "ok": true}');
      expect(CrashScrubber.scrub('pi_3Mtw_secret_YrKJUKribcBjcG8HVhfZluoGH'), '<token>');
      expect(CrashScrubber.scrub("type 'Null' is not a subtype of type 'String?'"), "type 'Null' is not a subtype of type 'String?'");
      expect(CrashScrubber.scrub('x y ' * 100).length, CrashScrubber.maxLength + 1);
    });

    test('API paths lose ids, codes and query strings', () {
      expect(CrashScrubber.apiPath('/orders/123'), '/orders/:x');
      expect(CrashScrubber.apiPath('/auth/check?email=$email'), '/auth/check');
      expect(CrashScrubber.apiPath('/legal/terms/v/terms@abc'), '/legal/terms/v/:x');
      expect(CrashScrubber.apiPath('/statements/link/$jwt'), '/statements/link/:x');
      expect(CrashScrubber.apiPath('/stores/my/live'), '/stores/my/live');
    });
  });

  group('API faults', () {
    test('only 5xx and unreadable 2xx bodies are reported, never 4xx or network errors', () {
      for (final s in [500, 502, 503, 504]) {
        expect(ApiFault.shouldReport(s), isTrue, reason: '$s');
      }
      for (final s in [0, 200, 201, 204, 301, 400, 401, 403, 404, 409, 422, 428, 429]) {
        expect(ApiFault.shouldReport(s), isFalse, reason: '$s');
      }
      expect(ApiFault.shouldReport(200, parseFailed: true), isTrue);
      expect(ApiFault.shouldReport(404, parseFailed: true), isFalse);
      expect(ApiFault.shouldReport(400, parseFailed: true), isFalse);
    });

    group('through ApiClient', () {
      late CrashReporting saved;
      late List<http.Request> sent;

      void serve(http.Response Function(http.Request req, int n) handler) {
        sent = [];
        final mock = MockClient((req) async {
          sent.add(req);
          return handler(req, sent.length);
        });
        ApiConfig.httpClient = () => mock;
      }

      setUp(() {
        saved = CrashReporting.instance;
        CrashReporting.instance = crash;
        ApiConfig.baseUrl = 'https://api.test/api/v1';
        ApiConfig.retryDelay = Duration.zero;
        ApiConfig.onAgreementRequired = null;
        ApiConfig.onNetworkError = null;
      });
      tearDown(() => CrashReporting.instance = saved);

      test('a 500 is reported once, without body, query or headers', () async {
        serve((_, __) => json(500, {'error': 'Internal error for $email'}));
        await const ApiClient().post('/orders/77/cancel?email=$email', {'note': 'call me $email'});
        await pumpEventQueue();
        final fault = backend.errors.single;
        expect(fault.fatal, isFalse);
        expect(fault.error.toString(), 'ApiFault: POST /orders/:x/cancel 500');
        expect(backend.everything, isNot(contains(email)));
      });

      test('a GET 503 is reported once, after its retry', () async {
        serve((_, __) => json(503, {}));
        await const ApiClient().get('/drops');
        await pumpEventQueue();
        expect(sent, hasLength(2));
        expect(backend.errors.single.error.toString(), 'ApiFault: GET /drops 503');
      });

      test('4xx answers are never reported', () async {
        for (final s in [400, 401, 403, 404, 409, 422, 429]) {
          serve((_, __) => json(s, {'error': 'No'}));
          await const ApiClient().post('/x');
        }
        serve((_, __) => http.Response('<html>Not found</html>', 404));
        await const ApiClient().get('/missing');
        await pumpEventQueue();
        expect(backend.errors, isEmpty);
      });

      test('a 200 with a broken body is reported; an empty 204 is not', () async {
        serve((_, __) => http.Response('<html>proxy error</html>', 200));
        await const ApiClient().get('/me');
        serve((_, __) => http.Response('', 204));
        await const ApiClient().delete('/me/saves/3');
        await pumpEventQueue();
        expect(backend.errors.single.error.toString(), 'ApiFault: GET /me 200 unreadable body');
      });
    });
  });
}
