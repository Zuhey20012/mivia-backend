import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../crash/crash_reporting.dart';
import '../i18n/app_language.dart';
import '../i18n/server_messages.dart';

/// What the API client needs from an app's sign-in state. Each app's `AuthService` implements it.
abstract interface class ApiSession {
  /// The current access token, or null when signed out.
  String? get accessToken;

  /// Exchanges the refresh token for a new session. True when it worked.
  Future<bool> refreshSession();
}

/// Called when the server answers 428 `AGREEMENT_REQUIRED`. Shows the agreement and returns true
/// once it was accepted; the request is then sent once more (the server refuses such a request
/// before doing anything, so repeating it is safe).
typedef AgreementRequiredHandler = Future<bool> Function(ApiResult result, ApiSession? session);

/// App-wide settings of [ApiClient], set once in `main()`.
class ApiConfig {
  ApiConfig._();

  /// "https://malvoya-api-eu.onrender.com/api/v1" (each app's `AppConstants.apiBase`).
  static String baseUrl = '';

  /// How long one request may take before it fails with a "took too long" message.
  static Duration timeout = const Duration(seconds: 15);

  /// How many times a GET is sent again after a network error or a 502/503/504 answer. GETs never
  /// change anything, so repeating them is safe; other methods are never repeated automatically.
  static int getRetries = 1;

  /// Pause before a GET is repeated.
  static Duration retryDelay = const Duration(milliseconds: 400);

  /// Optional 428 handler (the customer app shows its agreement sheet here). Without one, callers
  /// see the 428 in [ApiResult.agreementRequired] and handle it themselves.
  static AgreementRequiredHandler? onAgreementRequired;

  /// Called when the API could not be reached at all (e.g. to show a "No internet" strip).
  static void Function()? onNetworkError;

  /// The HTTP client. Tests replace it with a `MockClient`.
  static http.Client Function() httpClient = http.Client.new;
}

/// Result of an API call.
class ApiResult {
  /// Creates a result. [rawError] is the message as the server (or the client) wrote it, in
  /// English; [error] is the same message in the app language.
  ApiResult(this.status, this.data, this.rawError, {this.notice})
      : error = rawError == null ? null : ServerMessages.localize(rawError);

  /// HTTP status; 0 when the server could not be reached or did not answer in time.
  final int status;

  /// The decoded JSON object (empty when the body was not an object).
  final Map<String, dynamic> data;

  /// The error in the app language at the time of the call; null when the call worked.
  final String? error;

  /// The error exactly as the server (or the client) wrote it, in English.
  final String? rawError;

  /// Something worth telling the user besides the result itself, e.g. "Seller Terms accepted" when
  /// the call was repeated after the agreement sheet.
  final String? notice;

  /// True for a 2xx answer.
  bool get ok => error == null && status >= 200 && status < 300;

  /// 428 AGREEMENT_REQUIRED (API 2.11): an agreement in force must be accepted first.
  bool get agreementRequired => status == 428 && data['code'] == 'AGREEMENT_REQUIRED';

  /// The same result with a [notice].
  ApiResult withNotice(String? notice) => ApiResult(status, data, rawError, notice: notice);

  /// The error to show; never null (a generic sentence when the call worked or gave no reason).
  String get errorMessage => error ?? ServerMessages.localize('Something went wrong. Please try again.');

  /// [error] in the widget's language (it can differ from the language at the time of the call).
  String? errorText(BuildContext context) => rawError == null ? null : localizeServerMessage(context, rawError!);
}

/// Small JSON client for the Malvoya API.
///
/// * adds the session, `Accept-Language` and `X-App-Version`;
/// * refreshes the session once on 401 and repeats the request;
/// * on 428 `AGREEMENT_REQUIRED` asks [ApiConfig.onAgreementRequired] and repeats once;
/// * repeats GETs after network errors and 502/503/504 ([ApiConfig.getRetries]);
/// * turns failures into sentences that can be shown to the user ([ApiResult.error]).
class ApiClient {
  /// A client for [auth] (signed out when null).
  const ApiClient([this.auth]);

  /// The session sent with each request.
  final ApiSession? auth;

  /// Headers for every request to the Malvoya API (merge into raw `http` calls too).
  static Map<String, String> get baseHeaders => {'Content-Type': 'application/json', ...AppLanguage.headers};

  /// GET [path] (relative to [ApiConfig.baseUrl]) with optional [query].
  Future<ApiResult> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  /// POST [body] as JSON.
  Future<ApiResult> post(String path, [Object? body]) => _send('POST', path, body: body);

  /// PUT [body] as JSON.
  Future<ApiResult> put(String path, [Object? body]) => _send('PUT', path, body: body);

  /// PATCH [body] as JSON.
  Future<ApiResult> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  /// DELETE, optionally with a JSON [body].
  Future<ApiResult> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  Future<ApiResult> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool refreshed = false,
    bool agreementAsked = false,
    int attempt = 0,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final token = auth?.accessToken;
    final headers = <String, String>{...baseHeaders, if (token != null) 'Authorization': 'Bearer $token'};
    final retryable = method == 'GET' && attempt < ApiConfig.getRetries;
    final client = ApiConfig.httpClient();
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await client.send(req).timeout(ApiConfig.timeout);
      res = await http.Response.fromStream(streamed).timeout(ApiConfig.timeout);
    } on TimeoutException {
      return ApiResult(0, const {}, 'The server took too long to answer. Please try again.');
    } catch (_) {
      if (retryable) {
        await Future<void>.delayed(ApiConfig.retryDelay);
        return _send(method, path, body: body, query: query, refreshed: refreshed, agreementAsked: agreementAsked, attempt: attempt + 1);
      }
      ApiConfig.onNetworkError?.call();
      return ApiResult(0, const {}, 'Could not reach Malvoya. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (retryable && (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504)) {
      await Future<void>.delayed(ApiConfig.retryDelay);
      return _send(method, path, body: body, query: query, refreshed: refreshed, agreementAsked: agreementAsked, attempt: attempt + 1);
    }

    if (res.statusCode == 401 && !refreshed && token != null && auth != null) {
      if (await auth!.refreshSession()) {
        return _send(method, path, body: body, query: query, refreshed: true, agreementAsked: agreementAsked, attempt: attempt);
      }
    }

    Map<String, dynamic> data = {};
    var parseFailed = false;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      parseFailed = res.bodyBytes.isNotEmpty;
    }
    // Non-fatal crash report for 5xx answers and unreadable 2xx bodies only (never 4xx, no body)
    CrashReporting.instance.recordApiFault(method, path, res.statusCode, parseFailed: parseFailed);

    if (res.statusCode >= 200 && res.statusCode < 300) return ApiResult(res.statusCode, data, null);
    final result = ApiResult(res.statusCode, data, messageFor(res.statusCode, data));

    final ask = ApiConfig.onAgreementRequired;
    if (result.agreementRequired && !agreementAsked && ask != null) {
      if (await ask(result, auth)) {
        return _send(method, path, body: body, query: query, refreshed: refreshed, agreementAsked: true, attempt: attempt);
      }
    }
    return result;
  }

  /// The server's own message from an error body, or a sentence for the status code (English;
  /// [ApiResult] translates it).
  static String messageFor(int status, Map<String, dynamic> data) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;
    final fieldErrors = data['errors'] is Map ? (data['errors'] as Map)['fieldErrors'] : null;
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
