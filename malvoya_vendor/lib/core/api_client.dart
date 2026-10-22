import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../locale_provider.dart';
import 'connectivity.dart';
import 'server_errors.dart';

/// Result of an API call. [error] is always a sentence that can be shown to the user.
class ApiResult {
  final int status;
  final Map<String, dynamic> data;
  final String? error;

  /// Something worth telling the user besides the result itself, e.g. "Seller Terms accepted" when the
  /// call was retried after the agreement sheet (see `core/agreements.dart`).
  final String? notice;

  const ApiResult(this.status, this.data, this.error, {this.notice});

  bool get ok => error == null && status >= 200 && status < 300;

  /// 428 AGREEMENT_REQUIRED (API 2.11): the store must accept the version in force of its Seller Terms
  /// before accepting orders or publishing products.
  bool get agreementRequired => status == 428 && data['code'] == 'AGREEMENT_REQUIRED';

  ApiResult withNotice(String? notice) => ApiResult(status, data, error, notice: notice);

  /// The error to show the user, in the app's language; never null.
  String get errorMessage => error ?? trApp('Something went wrong. Please try again.', 'Jokin meni vikaan. Yritä uudelleen.');
}

/// Small JSON client for the Malvoya API: adds the session, retries once after a token
/// refresh, and turns network problems into readable messages.
class ApiClient {
  final AuthService? auth;
  const ApiClient([this.auth]);

  static const _timeout = Duration(seconds: 15);

  /// "1.7.0+9": recorded by the server with every agreement acceptance (X-App-Version).
  static String? appVersion;

  /// Reads the app's version once at start-up; requests made before it is known simply go without it.
  static Future<void> loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {}
  }

  /// Headers for every request to the Malvoya API. `Accept-Language` lets the server answer, and
  /// send push notifications and emails, in the app's language.
  static Map<String, String> get baseHeaders => {
        'Content-Type': 'application/json',
        'Accept-Language': LocaleProvider.currentCode,
        if (appVersion != null) 'X-App-Version': appVersion!,
      };

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
      ...baseHeaders,
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
      return ApiResult(0, const {}, trApp('The server took too long to answer. Please try again.', 'Palvelin vastasi liian hitaasti. Yritä uudelleen.'));
    } catch (_) {
      // Lets the "No internet" strip appear even if the system did not report a network change
      ConnectivityService.instance.verify();
      return ApiResult(0, const {}, trApp('Could not reach Malvoya. Check your connection and try again.', 'Malvoyaan ei saatu yhteyttä. Tarkista yhteys ja yritä uudelleen.'));
    }
  }

  static String _messageFor(int status, Map<String, dynamic> data) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return localizeServerError(error);
    final fieldErrors = data['errors']?['fieldErrors'];
    if (fieldErrors is Map && fieldErrors.isNotEmpty) {
      final first = fieldErrors.values.first;
      if (first is List && first.isNotEmpty) return localizeServerError(first.first.toString());
    }
    if (status == 401) return trApp('Please sign in again.', 'Kirjaudu uudelleen sisään.');
    if (status == 403) return trApp('You do not have access to this.', 'Sinulla ei ole pääsyä tähän.');
    if (status == 404) return trApp('Not found.', 'Ei löytynyt.');
    if (status == 429) return trApp('Too many attempts. Please wait a moment.', 'Liian monta yritystä. Odota hetki.');
    if (status >= 500) return trApp('Something went wrong on our side. Please try again.', 'Jokin meni vikaan meidän päässämme. Yritä uudelleen.');
    return trApp('Something went wrong. Please try again.', 'Jokin meni vikaan. Yritä uudelleen.');
  }
}
