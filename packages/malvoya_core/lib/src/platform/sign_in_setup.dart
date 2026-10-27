import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which sign-in options can work in this build, so the apps hide the ones that cannot.
///
/// On iOS some options stop the app (a native exception, not a Dart error) when their setup is
/// missing: Google sign-in without its client ID and URL scheme, Firebase phone sign-in without
/// its callback URL scheme. The owner adds `GoogleService-Info.plist` and fills
/// `ios/Flutter/Malvoya.xcconfig` on the Mac; until then those buttons are hidden or fall back.
///
/// Android is unchanged: every check below is true there.
///
/// Set up in each app's `main()`:
/// ```dart
/// await SignInSetup.loadIos();
/// final app = await Firebase.initializeApp();
/// SignInSetup.firebaseInitialised(appId: app.options.appId, iosClientId: app.options.iosClientId);
/// ```
abstract final class SignInSetup {
  /// Answered by `ios/Runner/AppDelegate.swift` in each app.
  static const _channel = MethodChannel('malvoya/ios_setup');

  static bool _firebaseReady = false;
  static String? _firebaseAppId;
  static String? _firebaseIosClientId;

  static bool _iosFirebasePlist = false;
  static List<String> _iosUrlSchemes = const [];
  static String? _iosGoogleClientId;
  static String? _iosGoogleServerClientId;

  /// True on iPhone builds.
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Firebase started (on iOS: `GoogleService-Info.plist` is in the build).
  static bool get firebaseReady => _firebaseReady;

  /// Reads what the iOS build contains (URL schemes, Google client IDs). Does nothing elsewhere,
  /// and never throws: a build without the channel counts as "nothing set up".
  static Future<void> loadIos() async {
    if (!isIOS) return;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('read');
      if (info == null) return;
      _iosFirebasePlist = info['firebasePlist'] == true;
      _iosUrlSchemes = [
        for (final s in (info['urlSchemes'] as List?) ?? const []) if (s is String) s.toLowerCase(),
      ];
      _iosGoogleClientId = _nonEmpty(info['googleClientId']);
      _iosGoogleServerClientId = _nonEmpty(info['googleServerClientId']);
    } catch (e) {
      debugPrint('iOS setup not readable: $e');
    }
  }

  /// Call after `Firebase.initializeApp()` succeeded, with the app's options.
  static void firebaseInitialised({required String appId, String? iosClientId}) {
    _firebaseReady = true;
    _firebaseAppId = appId;
    _firebaseIosClientId = _nonEmpty(iosClientId);
  }

  /// Firebase phone verification can be started. On iOS Firebase Auth stops the app unless the
  /// reCAPTCHA callback scheme is registered: the reversed client ID or the encoded app ID
  /// (`app-1-…-ios-…`), both from `GoogleService-Info.plist`.
  static bool get firebasePhone {
    if (!isIOS) return true;
    if (!_firebaseReady || !_iosFirebasePlist) return false;
    final client = _firebaseIosClientId;
    final appId = _firebaseAppId;
    return (client != null && _hasScheme(reversedClientId(client))) ||
        (appId != null && _hasScheme('app-${appId.replaceAll(':', '-')}'));
  }

  /// "Sign in with Google" can be offered. On iOS it needs the iOS OAuth client ID (Info.plist
  /// `GIDClientID`, or `CLIENT_ID` from `GoogleService-Info.plist`) and its reversed form as a URL
  /// scheme; without them the Google SDK stops the app.
  /// App Store guideline 4.8: on iPhone, Google is offered only together with Sign in with Apple, so a build
  /// that has the Google settings but no Firebase (no Apple sign-in) shows neither.
  static bool get google {
    if (!isIOS) return true;
    final client = googleIosClientId;
    return apple && client != null && _hasScheme(reversedClientId(client));
  }

  /// The iOS OAuth client ID to pass to `GoogleSignIn(clientId:)` (null on Android).
  static String? get googleIosClientId => isIOS ? (_iosGoogleClientId ?? _firebaseIosClientId) : null;

  /// The web client ID the API verifies Google tokens against (`GIDServerClientID`), so the ID
  /// token's audience is the one the server expects. Null on Android and when not set.
  static String? get googleIosServerClientId => isIOS ? _iosGoogleServerClientId : null;

  /// "Sign in with Apple" can be offered: iOS only, through Firebase (the API verifies Firebase
  /// ID tokens).
  static bool get apple => isIOS && _firebaseReady;

  /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`.
  static String reversedClientId(String clientId) => clientId.split('.').reversed.join('.');

  static bool _hasScheme(String scheme) => _iosUrlSchemes.contains(scheme.toLowerCase());

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final v = value.trim();
    return v.isEmpty ? null : v;
  }
}
