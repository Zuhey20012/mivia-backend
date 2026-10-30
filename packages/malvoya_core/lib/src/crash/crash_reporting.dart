import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/app_language.dart';
import 'crash_backend.dart';
import 'crash_scrubber.dart';

/// A failed API call worth a non-fatal crash report: a 5xx answer, or a 2xx answer whose body was
/// not valid JSON. Holds only the method, a cleaned path and the status: never the query, headers
/// or body.
class ApiFault implements Exception {
  /// A fault for [method] [path] (already cleaned with [CrashScrubber.apiPath]).
  const ApiFault(this.method, this.path, this.status, {this.parseFailed = false});

  /// `GET`, `POST`, ...
  final String method;

  /// The path with ids and query removed, e.g. `/orders/:x`.
  final String path;

  /// The HTTP status.
  final int status;

  /// True when the body could not be read as JSON.
  final bool parseFailed;

  /// Which API answers are reported: every 5xx, and 2xx answers whose non-empty body could not be
  /// parsed. Never 4xx (those are the user's or the session's, not a fault in Malvoya), never
  /// network errors (status 0).
  static bool shouldReport(int status, {bool parseFailed = false}) =>
      status >= 500 || (parseFailed && status >= 200 && status < 300);

  @override
  String toString() => parseFailed ? 'ApiFault: $method $path $status unreadable body' : 'ApiFault: $method $path $status';
}

/// Crash and error reports (Firebase Crashlytics in the apps).
///
/// * Sent only from release builds, and only when the app passes a backend (the apps pass none
///   when Firebase did not start, e.g. an iPhone build without `GoogleService-Info.plist`).
/// * The only user data is the numeric Malvoya user id ([setUser]); the only custom keys are the
///   app version and the app's role. Error messages are scrubbed ([CrashScrubber]); names, emails,
///   phone numbers, tokens and request bodies are never sent.
///
/// Set up in each app's `main()` after Firebase:
/// ```dart
/// await CrashReporting.instance.init(backend: firebaseReady ? firebaseBackend() : null, role: 'customer');
/// FlutterError.onError = CrashReporting.instance.recordFlutterFatalError;
/// PlatformDispatcher.instance.onError = CrashReporting.instance.recordPlatformError;
/// ```
class CrashReporting {
  /// A separate instance (tests); the apps use [instance].
  CrashReporting();

  /// The app-wide instance.
  static CrashReporting instance = CrashReporting();

  /// The only custom keys ever set.
  static const allowedKeys = {'app_version', 'role'};

  CrashBackend? _backend;
  bool _enabled = false;
  int? _userId;

  /// True when reports are sent: a backend was given and collection is on.
  bool get active => _backend != null && _enabled;

  /// Starts crash reporting. Collection is on only when [enabled] (default: release builds) and a
  /// [backend] is given; otherwise reports are only printed in debug builds. [role] is the app
  /// (`customer`, `store`, `courier`); [appVersion] defaults to [AppLanguage.appVersion].
  Future<void> init({CrashBackend? backend, required String role, bool enabled = kReleaseMode, String? appVersion}) async {
    _backend = backend;
    _enabled = enabled && backend != null;
    if (backend == null) return;
    await _guard(() => backend.setCollectionEnabled(_enabled));
    if (!_enabled) return;
    await _setKey('role', role);
    final version = appVersion ?? AppLanguage.appVersion;
    if (version != null) await _setKey('app_version', version);
    final user = _userId;
    if (user != null) await _guard(() => backend.setUserIdentifier('$user'));
  }

  /// Ties later reports to the signed-in account by its numeric Malvoya id (call after sign-in).
  Future<void> setUser(int id) async {
    if (id <= 0 || _userId == id) return;
    _userId = id;
    if (active) await _guard(() => _backend!.setUserIdentifier('$id'));
  }

  /// Removes the account from later reports (call on sign-out).
  Future<void> clear() async {
    if (_userId == null) return;
    _userId = null;
    if (active) await _guard(() => _backend!.setUserIdentifier(''));
  }

  /// Calls [setUser] or [clear] whenever [session] changes, reading the signed-in account's id with
  /// [userId] (null when signed out).
  void followUser(Listenable session, int? Function() userId) {
    void sync() {
      final id = userId();
      unawaited(id == null ? clear() : setUser(id));
    }

    session.addListener(sync);
    sync();
  }

  /// A handled error worth knowing about (the app keeps working).
  Future<void> recordNonFatal(Object error, [StackTrace? stack, String? reason]) => _record(error, stack, reason, fatal: false);

  /// An error that ended what the user was doing.
  Future<void> recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) =>
      _record(error, stack, reason, fatal: fatal);

  /// For `FlutterError.onError`: shows the error as Flutter normally does, then reports it as fatal.
  /// The report keeps the error type, a scrubbed message, the stack and the library, but not the
  /// widget context (it can contain on-screen text).
  void recordFlutterFatalError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (!active) return;
    final clean = FlutterErrorDetails(
      exception: CrashScrubber.error(details.exception),
      stack: details.stack,
      library: details.library,
      silent: details.silent,
    );
    unawaited(_guard(() => _backend!.recordFlutterFatalError(clean)));
  }

  /// For `PlatformDispatcher.instance.onError`: reports an uncaught asynchronous error as fatal.
  /// Returns true (handled) when it was reported, so the engine's own logging still runs otherwise.
  bool recordPlatformError(Object error, StackTrace stack) {
    if (!active) return false;
    unawaited(_record(error, stack, null, fatal: true));
    return true;
  }

  /// Called by the API client for every answer; reports only what [ApiFault.shouldReport] allows.
  void recordApiFault(String method, String path, int status, {bool parseFailed = false}) {
    if (!ApiFault.shouldReport(status, parseFailed: parseFailed)) return;
    final fault = ApiFault(method, CrashScrubber.apiPath(path), status, parseFailed: parseFailed);
    unawaited(recordNonFatal(fault, StackTrace.current));
  }

  Future<void> _record(Object error, StackTrace? stack, String? reason, {required bool fatal}) async {
    final clean = CrashScrubber.error(error);
    final cleanReason = reason == null ? null : CrashScrubber.scrub(reason);
    if (!active) {
      if (kDebugMode) debugPrint('Crash report (not sent${fatal ? ', fatal' : ''}): $clean');
      return;
    }
    await _guard(() => _backend!.recordError(clean, stack, reason: cleanReason, fatal: fatal));
  }

  Future<void> _setKey(String key, String value) async {
    assert(allowedKeys.contains(key), 'Only ${allowedKeys.join(', ')} may be set');
    if (!allowedKeys.contains(key)) return;
    await _guard(() => _backend!.setCustomKey(key, value));
  }

  /// Crash reporting must never become a crash itself.
  static Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      if (kDebugMode) debugPrint('Crash reporting: $e');
    }
  }
}
