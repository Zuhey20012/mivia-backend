import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'config/constants.dart';

const _secureStorage = FlutterSecureStorage();

/// The account role this app is for. Other roles are refused at sign-in.
const String kAppRole = 'CUSTOMER';

class User {
  final int id;
  final String email;
  final String role;
  final String? name;
  final bool googleLinked;
  final String? phone;
  final bool isActive;

  /// The account has a password (signed in with one on this phone, or the server says so).
  /// Unknown counts as no, so password actions are only offered when they can work.
  final bool hasPassword;

  User({required this.id, required this.email, required this.role, this.name, this.phone, this.isActive = true, this.googleLinked = false, this.hasPassword = false});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'] ?? '',
        role: json['role'] ?? kAppRole,
        name: json['name'],
        googleLinked: json['googleLinked'] == true,
        phone: json['phone'],
        isActive: json['isActive'] ?? true,
        hasPassword: json['hasPassword'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'name': name, 'googleLinked': googleLinked, 'phone': phone, 'isActive': isActive, 'hasPassword': hasPassword};
}

/// Handles sign-in, secure token storage and automatic access-token refresh.
/// Access tokens live 15 minutes; they are refreshed a minute before expiry.
class AuthService extends ChangeNotifier implements ApiSession, GoogleLinkAccount {
  // Resolved on first use so the app still opens if Firebase failed to initialise.
  fb_auth.FirebaseAuth get _firebaseAuth => fb_auth.FirebaseAuth.instance;
  String? _verificationId;

  User? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  Timer? _refreshTimer;
  bool _ready = false;
  bool _isGuest = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _accessToken != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
  @override
  String? get accessToken => _accessToken;
  bool get isReady => _ready;

  bool get isPendingApproval => false;
  bool get isLoading => !_ready;

  /// Guests can browse stores and products; checkout and orders require an account.
  bool get isGuest => _isGuest;
  bool get canBrowse => isAuthenticated || _isGuest;

  AuthService() {
    _loadSession();
  }

  // ── Session storage ────────────────────────────────────────────────────────

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    final token = await _secureStorage.read(key: 'accessToken');
    final refresh = await _secureStorage.read(key: 'refreshToken');
    if (userJson != null && token != null && refresh != null) {
      _currentUser = User.fromJson(jsonDecode(userJson));
      _accessToken = token;
      _refreshToken = refresh;
      if (_secondsUntilExpiry(token) < 60) {
        await refreshSession();
      } else {
        _scheduleRefresh();
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<String?> _applySession(Map<String, dynamic> data, {bool withPassword = false}) async {
    final raw = Map<String, dynamic>.from(data['user'] as Map);
    // A refresh does not say whether the account has a password: keep what this phone knows
    if (withPassword) {
      raw['hasPassword'] = true;
    } else if (!raw.containsKey('hasPassword') && _currentUser?.id == raw['id']) {
      raw['hasPassword'] = _currentUser?.hasPassword ?? false;
    }
    final user = User.fromJson(raw);
    if (user.role != kAppRole) {
      return 'This account is not a customer account. Please use the matching Malvoya app.';
    }
    _currentUser = user;
    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
    await _secureStorage.write(key: 'accessToken', value: _accessToken);
    await _secureStorage.write(key: 'refreshToken', value: _refreshToken);
    _scheduleRefresh();
    _isGuest = false;
    notifyListeners();
    return null;
  }

  int _secondsUntilExpiry(String jwt) {
    try {
      final payload = jwt.split('.')[1];
      final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))));
      final exp = decoded['exp'] as int;
      return exp - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_accessToken == null) return;
    final seconds = _secondsUntilExpiry(_accessToken!) - 60;
    _refreshTimer = Timer(Duration(seconds: seconds < 5 ? 5 : seconds), refreshSession);
  }

  /// Exchanges the refresh token for a new pair. Signs out if the session is no longer valid.
  @override
  Future<bool> refreshSession() async {
    final refresh = _refreshToken;
    if (refresh == null) return false;
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/refresh'),
              headers: {'Content-Type': 'application/json', ...AppLanguage.headers}, body: jsonEncode({'refreshToken': refresh}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        await _applySession(jsonDecode(res.body));
        return true;
      }
      if (res.statusCode == 401) await _clearSession();
    } catch (_) {
      // Offline: try again shortly, keep the user signed in
      _refreshTimer = Timer(const Duration(seconds: 30), refreshSession);
    }
    return false;
  }

  String _errorFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body['error'] is String) return body['error'];
      final fieldErrors = body['errors']?['fieldErrors'] as Map<String, dynamic>?;
      if (fieldErrors != null && fieldErrors.isNotEmpty) return (fieldErrors.values.first as List).first.toString();
    } catch (_) {}
    return fallback;
  }

  // ── Age (18+) for new accounts ────────────────────────────────────────────

  /// Returned by the social sign-in methods instead of an error when the server needs the
  /// "I am 18 or older" confirmation before it creates a new account (400 AGE_CONFIRMATION_REQUIRED).
  /// Ask the person (core/age_gate.dart), then call [retryWithAgeConfirmed].
  static const ageConfirmationRequired = 'AGE_CONFIRMATION_REQUIRED';

  /// The sign-in request that was refused for the missing age confirmation (path + body).
  ({String path, Map<String, dynamic> body, String fallback})? _pendingAgeRetry;

  /// True when a JSON error body says the age confirmation is missing.
  static bool isAgeConfirmationError(int status, Object? body) {
    if (status != 400 || body is! Map) return false;
    return body['code'] == ageConfirmationRequired || body['error'] == ageConfirmationRequired;
  }

  /// Posts a sign-in request; a session answer signs in. When the server needs the age
  /// confirmation for a new account, the request is kept and [ageConfirmationRequired] returned.
  Future<String?> _signInRequest(String path, Map<String, dynamic> body, String fallback) async {
    final res = await http
        .post(Uri.parse('${AppConstants.apiBase}$path'),
            headers: {'Content-Type': 'application/json', ...AppLanguage.headers}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 || res.statusCode == 201) {
      _pendingAgeRetry = null;
      return await _applySession(jsonDecode(res.body));
    }
    Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {}
    if (isAgeConfirmationError(res.statusCode, decoded)) {
      _pendingAgeRetry = (path: path, body: body, fallback: fallback);
      return ageConfirmationRequired;
    }
    _pendingAgeRetry = null;
    return _errorFrom(res, fallback);
  }

  /// Sends the sign-in refused for the missing age confirmation again, now with `ageConfirmed: true`.
  Future<String?> retryWithAgeConfirmed() async {
    final pending = _pendingAgeRetry;
    _pendingAgeRetry = null;
    if (pending == null) return 'Please sign in again.';
    try {
      final err = await _signInRequest(pending.path, {...pending.body, 'ageConfirmed': true}, pending.fallback);
      // The server asked again although it was confirmed: do not loop
      return err == ageConfirmationRequired ? pending.fallback : err;
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  /// The person said they are not 18 or older: forget the kept request.
  void cancelAgeRetry() => _pendingAgeRetry = null;

  // ── Email / password ───────────────────────────────────────────────────────

  Future<String?> login(String emailOrPhone, String password) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/login'),
              headers: {'Content-Type': 'application/json', ...AppLanguage.headers},
              body: jsonEncode({'email': emailOrPhone.trim(), 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body), withPassword: true);
      return _errorFrom(res, 'Invalid email or password.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  /// Creates an account. The screen asks "I am 18 or older" first ([ageConfirmed]).
  Future<String?> register(String name, String email, String password, {bool ageConfirmed = true}) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/register'),
              headers: {'Content-Type': 'application/json', ...AppLanguage.headers},
              body: jsonEncode({
                'name': name.trim(),
                'email': email.trim(),
                'password': password,
                'role': kAppRole,
                'acceptTerms': true,
                if (ageConfirmed) 'ageConfirmed': true,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) return await _applySession(jsonDecode(res.body), withPassword: true);
      return _errorFrom(res, 'Registration failed. Please try again.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Forgotten password (a 6-digit code by email, then a new password) ───────

  /// Asks the server to email a reset code. The server answers 200 for any well-formed address
  /// (it never says whether an account exists); 503 when email sending is not set up.
  Future<ApiResult> requestPasswordReset(String email) =>
      const ApiClient().post('/auth/password/forgot', {'email': email.trim()});

  /// Sets a new password with the emailed code. The server signs the account out everywhere.
  Future<ApiResult> resetPassword(String email, String code, String password) =>
      const ApiClient().post('/auth/password/reset', {'email': email.trim(), 'code': code.trim(), 'password': password});

  // ── Google ────────────────────────────────────────────────────────────────

  /// Android reads the client IDs from google-services.json. On iOS they come from the build
  /// (`ios/Flutter/Malvoya.xcconfig` / GoogleService-Info.plist), and the server client ID makes the
  /// ID token's audience the one the API checks.
  GoogleSignIn _googleSignIn() => SignInSetup.isIOS
      ? GoogleSignIn(clientId: SignInSetup.googleIosClientId, serverClientId: SignInSetup.googleIosServerClientId)
      : GoogleSignIn();

  static const _googleUnavailable = 'Google sign-in is not available in this version of the app.';

  Future<String?> loginWithGoogle() async {
    // Without its iOS setup the Google SDK would stop the app; the button is hidden then too
    if (!SignInSetup.google) return _googleUnavailable;
    try {
      final googleUser = await _googleSignIn().signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return 'Google did not return a sign-in token';
      return await _signInRequest('/auth/google', {'idToken': idToken, 'role': kAppRole}, 'Google sign-in failed.');
    } catch (_) {
      return 'Google sign-in failed. Please check your internet connection.';
    }
  }

  // ── Linking Google to the signed-in account ──────────────────────────────

  @override
  bool get googleLinked => _currentUser?.googleLinked ?? false;

  /// Links a Google account to this account, so "Sign in with Google" opens it from now on.
  @override
  Future<String?> linkGoogle() async {
    if (!SignInSetup.google) return _googleUnavailable;
    try {
      final google = _googleSignIn();
      // Show the account picker even if Google was used before, so the right account gets linked
      await google.signOut();
      final googleUser = await google.signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return 'Google did not return a sign-in token';
      final res = await ApiClient(this).post('/auth/google/link', {'idToken': idToken});
      if (!res.ok) return res.error;
      await _setGoogleLinked(true);
      return null;
    } catch (_) {
      return 'Google sign-in failed. Please check your internet connection.';
    }
  }

  @override
  Future<String?> unlinkGoogle() async {
    final res = await ApiClient(this).delete('/auth/google/link');
    if (!res.ok) return res.error;
    await _setGoogleLinked(false);
    return null;
  }

  Future<void> _setGoogleLinked(bool linked) => _patchUser({'googleLinked': linked});

  /// Saves a new display name on the server, then on this phone.
  Future<String?> updateName(String name) async {
    final res = await ApiClient(this).patch('/me/profile', {'name': name});
    if (!res.ok) return res.error;
    await _patchUser({'name': res.data['user']?['name'] ?? name});
    return null;
  }

  Future<void> _patchUser(Map<String, dynamic> changes) async {
    final user = _currentUser;
    if (user == null) return;
    _currentUser = User.fromJson({...user.toJson(), ...changes});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    notifyListeners();
  }

  // ── Phone (Firebase verifies the SMS code, the API trusts only Firebase's token) ──

  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    Function()? onAutoVerified,
  }) async {
    // On iOS Firebase stops the app if its callback URL scheme is missing (SignInSetup)
    if (!SignInSetup.firebasePhone) {
      onError('Could not send the verification code. Please try again.');
      return;
    }
    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          final err = await _signInWithCredential(credential);
          if (err == null) {
            onAutoVerified?.call();
          } else {
            onError(err);
          }
        },
        verificationFailed: (e) => onError(e.message ?? 'Phone verification failed'),
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) => _verificationId = verificationId,
      );
    } catch (e) {
      onError('Could not send the verification code. Please try again.');
    }
  }

  Future<String?> signInWithSmsCode(String smsCode) async {
    if (_verificationId == null) return 'Request a new code first';
    final credential = fb_auth.PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: smsCode.trim());
    return _signInWithCredential(credential);
  }

  Future<String?> _signInWithCredential(fb_auth.PhoneAuthCredential credential) async {
    try {
      final result = await _firebaseAuth.signInWithCredential(credential);
      final firebaseToken = await result.user?.getIdToken();
      if (firebaseToken == null) return 'Phone verification failed';
      return await _signInRequest('/auth/phone', {'firebaseToken': firebaseToken, 'role': kAppRole}, 'Phone sign-in failed.');
    } on fb_auth.FirebaseAuthException catch (e) {
      return e.code == 'invalid-verification-code' ? 'The code is incorrect.' : (e.message ?? 'Phone verification failed');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Customer-only sign-in options ─────────────────────────────────────────

  /// Browse without an account. No token is created; the API is used anonymously.
  Future<void> loginAsGuest() async {
    _isGuest = true;
    notifyListeners();
  }

  /// Stores a session returned by the API (e.g. from /auth/otp/verify).
  Future<String?> saveSession(Map<String, dynamic> user, String accessToken, String refreshToken) {
    return _applySession({'user': user, 'accessToken': accessToken, 'refreshToken': refreshToken});
  }

  /// Used by the OTP screen: confirm the Firebase SMS code, then sign in to Malvoya.
  Future<String?> signInWithOtp(String verificationId, String smsCode) {
    _verificationId = verificationId;
    return signInWithSmsCode(smsCode);
  }

  /// After Firebase has verified the phone number, exchange its ID token for a Malvoya session.
  Future<String?> exchangeFirebasePhoneToken(String firebaseIdToken) async {
    try {
      return await _signInRequest('/auth/phone', {'firebaseToken': firebaseIdToken, 'role': kAppRole}, 'Phone sign-in failed.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  /// Sign in with Apple (iOS only): Firebase runs Apple's sheet (and its nonce), then the API
  /// exchanges the Firebase ID token for a Malvoya session. Apple shares the name only on the first
  /// sign-in; Firebase keeps it as the display name, and it is sent along for new accounts.
  Future<String?> loginWithApple() async {
    if (!SignInSetup.apple) return 'Sign in with Apple is not available in this version of the app.';
    try {
      final provider = fb_auth.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final result = await _firebaseAuth.signInWithProvider(provider);
      final firebaseToken = await result.user?.getIdToken();
      if (firebaseToken == null) return 'Apple sign-in failed.';
      final name = result.user?.displayName?.trim();
      return await _signInRequest(
          '/auth/apple', {'idToken': firebaseToken, 'role': kAppRole, if (name != null && name.isNotEmpty) 'name': name}, 'Apple sign-in failed.');
    } on fb_auth.FirebaseAuthException catch (e) {
      // Closing Apple's sheet is not an error
      return e.code == 'canceled' || e.code == 'web-context-canceled' ? null : 'Apple sign-in failed.';
    } catch (_) {
      return 'Apple sign-in failed. Please try again.';
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> _clearSession() async {
    _refreshTimer?.cancel();
    _isGuest = false;
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    await _secureStorage.delete(key: 'accessToken');
    await _secureStorage.delete(key: 'refreshToken');
    notifyListeners();
  }

  /// Work that needs the session one last time before signing out (e.g. forgetting this
  /// phone's push token). Each hook gets a few seconds; failures never block signing out.
  static final List<Future<void> Function(AuthService)> beforeLogout = [];

  Future<void> logout() async {
    for (final hook in beforeLogout) {
      try {
        await hook(this).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    final refresh = _refreshToken;
    if (refresh != null) {
      try {
        await http
            .post(Uri.parse('${AppConstants.apiBase}/auth/logout'),
                headers: {'Content-Type': 'application/json', ...AppLanguage.headers}, body: jsonEncode({'refreshToken': refresh}))
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (SignInSetup.google) {
      try { await _googleSignIn().signOut(); } catch (_) {}
    }
    try { await _firebaseAuth.signOut(); } catch (_) {}
    await _clearSession();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
