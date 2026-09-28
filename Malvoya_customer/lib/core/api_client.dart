import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../config/constants.dart';

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
        if (await auth!.refreshSession()) return _send(method, path, body: body, query: query, retried: true);
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
