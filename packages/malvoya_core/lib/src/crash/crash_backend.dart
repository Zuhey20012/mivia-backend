import 'package:flutter/foundation.dart';

/// Where [CrashReporting] sends crash reports. The apps pass one built on Firebase Crashlytics;
/// tests pass a fake, so nothing here needs Firebase.
///
/// [CrashReporting] cleans everything before it reaches a backend (see `CrashScrubber`), so a
/// backend only forwards what it is given.
abstract interface class CrashBackend {
  /// Switches sending on or off (Crashlytics remembers the choice on the device).
  Future<void> setCollectionEnabled(bool enabled);

  /// The numeric Malvoya user id as text, or '' to clear it.
  Future<void> setUserIdentifier(String id);

  /// One custom key on every later report.
  Future<void> setCustomKey(String key, Object value);

  /// A Dart error. [reason] is a short, already cleaned sentence.
  Future<void> recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false});

  /// An error caught by the Flutter framework, which ends the app's current frame.
  Future<void> recordFlutterFatalError(FlutterErrorDetails details);
}

/// A [CrashBackend] made of functions, so an app can build one from `FirebaseCrashlytics.instance`
/// tear-offs without a class of its own:
///
/// ```dart
/// final c = FirebaseCrashlytics.instance;
/// CallbackCrashBackend(
///   setCollectionEnabled: c.setCrashlyticsCollectionEnabled,
///   setUserIdentifier: c.setUserIdentifier,
///   setCustomKey: c.setCustomKey,
///   recordError: (e, s, {reason, fatal = false}) => c.recordError(e, s, reason: reason, fatal: fatal),
///   recordFlutterFatalError: c.recordFlutterFatalError,
/// );
/// ```
class CallbackCrashBackend implements CrashBackend {
  /// Builds a backend from the given functions.
  const CallbackCrashBackend({
    required Future<void> Function(bool enabled) setCollectionEnabled,
    required Future<void> Function(String id) setUserIdentifier,
    required Future<void> Function(String key, Object value) setCustomKey,
    required Future<void> Function(Object error, StackTrace? stack, {String? reason, bool fatal}) recordError,
    required Future<void> Function(FlutterErrorDetails details) recordFlutterFatalError,
  })  : _setCollectionEnabled = setCollectionEnabled,
        _setUserIdentifier = setUserIdentifier,
        _setCustomKey = setCustomKey,
        _recordError = recordError,
        _recordFlutterFatalError = recordFlutterFatalError;

  final Future<void> Function(bool enabled) _setCollectionEnabled;
  final Future<void> Function(String id) _setUserIdentifier;
  final Future<void> Function(String key, Object value) _setCustomKey;
  final Future<void> Function(Object error, StackTrace? stack, {String? reason, bool fatal}) _recordError;
  final Future<void> Function(FlutterErrorDetails details) _recordFlutterFatalError;

  @override
  Future<void> setCollectionEnabled(bool enabled) => _setCollectionEnabled(enabled);

  @override
  Future<void> setUserIdentifier(String id) => _setUserIdentifier(id);

  @override
  Future<void> setCustomKey(String key, Object value) => _setCustomKey(key, value);

  @override
  Future<void> recordError(Object error, StackTrace? stack, {String? reason, bool fatal = false}) =>
      _recordError(error, stack, reason: reason, fatal: fatal);

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) => _recordFlutterFatalError(details);
}
