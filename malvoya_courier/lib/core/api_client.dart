import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../config/constants.dart';
import 'connectivity.dart';
import 'server_messages.dart';

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
      return ApiResult(0, const {}, ServerMessages.pick('The server took too long to answer. Please try again.', 'Palvelin vastasi liian hitaasti. Yritä uudelleen.'));
    } catch (_) {
      // Lets the "No internet" strip appear even if the system did not report a network change
      ConnectivityService.instance.verify();
      return ApiResult(0, const {}, ServerMessages.pick('Could not reach Malvoya. Check your connection and try again.', 'Malvoyaan ei saatu yhteyttä. Tarkista nettiyhteys ja yritä uudelleen.'));
    }
  }

  /// The server's message (in Finnish when the app is in Finnish and a translation is known),
  /// or a sentence for the status code.
  static String _messageFor(int status, Map<String, dynamic> data) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return ServerMessages.localize(error);
    final fieldErrors = data['errors']?['fieldErrors'];
    if (fieldErrors is Map && fieldErrors.isNotEmpty) {
      final first = fieldErrors.values.first;
      if (first is List && first.isNotEmpty) return ServerMessages.localize(first.first.toString());
    }
    final pick = ServerMessages.pick;
    if (status == 401) return pick('Please sign in again.', 'Kirjaudu uudelleen sisään.');
    if (status == 403) return pick('You do not have access to this.', 'Sinulla ei ole oikeutta tähän.');
    if (status == 404) return pick('Not found.', 'Ei löytynyt.');
    if (status == 429) return pick('Too many attempts. Please wait a moment.', 'Liian monta yritystä. Odota hetki.');
    if (status >= 500) return pick('Something went wrong on our side. Please try again.', 'Jotain meni vikaan meidän päässämme. Yritä uudelleen.');
    return pick('Something went wrong. Please try again.', 'Jotain meni vikaan. Yritä uudelleen.');
  }
}
