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
const String kAppRole = 'VENDOR';

/// Where the signed-in store owner stands, from GET /stores/my.
enum StoreState { unknown, none, inReview, approved, error }

class User {
  final int id;
  final String email;
  final String role;
  final String? name;
  final bool googleLinked;

  User({required this.id, required this.email, required this.role, this.name, this.googleLinked = false});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'] ?? '',
        role: json['role'] ?? kAppRole,
        name: json['name'],
        googleLinked: json['googleLinked'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'name': name, 'googleLinked': googleLinked};
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

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _accessToken != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
  @override
  String? get accessToken => _accessToken;
  bool get isReady => _ready;

  StoreState _storeState = StoreState.unknown;
  String? _storeError;
  bool _checkingStore = false;

  /// Whether this account has a store yet, and whether it is approved. The app's home screen follows it:
  /// no store → setup, a store (in review or approved) → dashboard.
  StoreState get storeState => _storeState;
  String? get storeError => _storeError;

  /// The store exists but Malvoya has not approved it yet (customers cannot see it). The dashboard
  /// still opens, so products and drops can be prepared meanwhile.
  bool get isPendingApproval => _storeState == StoreState.inReview;

  /// Asks the server whether this account has a store (and whether it is approved).
  Future<void> checkStore() async {
    if (_checkingStore || !isAuthenticated) return;
    _checkingStore = true;
    final res = await ApiClient(this).get('/stores/my');
    _checkingStore = false;
    if (!isAuthenticated) return;
    if (res.status == 404) {
      _storeState = StoreState.none;
    } else if (res.ok && res.data['store'] is Map) {
      updateStore(Map<String, dynamic>.from(res.data['store']));
      return;
    } else {
      _storeState = StoreState.error;
      _storeError = res.errorMessage;
    }
    notifyListeners();
  }

  /// Keeps [storeState] in step with a store payload loaded elsewhere (null = the account has no store).
  void updateStore(Map<String, dynamic>? store) {
    final next = store == null
        ? StoreState.none
        : store['isVerified'] == true
            ? StoreState.approved
            : StoreState.inReview;
    if (next == _storeState) return;
    _storeState = next;
    _storeError = null;
    notifyListeners();
  }

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

  /// [signedIn] is false for a token refresh (the same person stays signed in).
  Future<String?> _applySession(Map<String, dynamic> data, {bool signedIn = true}) async {
    // Two-step sign-in is on for this account (API 2.13/2.16): the first step only gives a short-lived
    // challenge; the app's home then asks for the authenticator code (see [completeTwoStep]).
    if (data['mfaRequired'] == true) {
      final token = data['mfaToken'];
      if (token is! String || token.isEmpty) return 'Sign-in failed. Please try again.';
      _mfaToken = token;
      _ageRetry = null;
      notifyListeners();
      return null;
    }
    if (data['user'] is! Map) return 'Sign-in failed. Please try again.';
    final user = User.fromJson(Map<String, dynamic>.from(data['user']));
    if (user.role != kAppRole) {
      return 'This account is not a store account. Please use the matching Malvoya app.';
    }
    _currentUser = user;
    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
    _mfaToken = null;
    _ageRetry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
    await _secureStorage.write(key: 'accessToken', value: _accessToken);
    await _secureStorage.write(key: 'refreshToken', value: _refreshToken);
    _scheduleRefresh();
    notifyListeners();
    if (signedIn) unawaited(syncLocale());
    return null;
  }

  /// Tells the server the app's language, so push notifications and emails come in it
  /// (PATCH /me {locale}). Older servers do not have it; nothing depends on the answer.
  Future<void> syncLocale() async {
    if (!isAuthenticated) return;
    try {
      await ApiClient(this).patch('/me', {'locale': AppLanguage.code});
    } catch (_) {}
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
              headers: ApiClient.baseHeaders, body: jsonEncode({'refreshToken': refresh}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        await _applySession(jsonDecode(res.body), signedIn: false);
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
      if (body['error'] is String) return ServerMessages.localize(body['error']);
      final fieldErrors = body['errors']?['fieldErrors'] as Map<String, dynamic>?;
      if (fieldErrors != null && fieldErrors.isNotEmpty) return ServerMessages.localize((fieldErrors.values.first as List).first.toString());
    } catch (_) {}
    return ServerMessages.localize(fallback);
  }

  // ── Two-step sign-in (authenticator app; API 2.13, offered to stores since 2.16) ──

  String? _mfaToken;

  /// The first sign-in step worked and the account has two-step sign-in on: the app asks for a code.
  bool get twoStepPending => _mfaToken != null;

  /// POST /auth/login/mfa with the code from the authenticator app (or a recovery code).
  /// Returns null when signed in, otherwise a message to show. [twoStepPending] becomes false when
  /// the challenge has expired (the person starts again from the sign-in screen).
  Future<String?> completeTwoStep(String code) async {
    final token = _mfaToken;
    if (token == null) return 'This sign-in has expired. Please start again.';
    final res = await const ApiClient().post('/auth/login/mfa', {'mfaToken': token, 'code': code.replaceAll(' ', '').trim()});
    if (res.ok) {
      final err = await _applySession(res.data);
      if (err != null) cancelTwoStep();
      return err;
    }
    if (res.status == 401) cancelTwoStep();
    return res.errorMessage;
  }

  /// Back to the sign-in screen without finishing the second step.
  void cancelTwoStep() {
    if (_mfaToken == null) return;
    _mfaToken = null;
    notifyListeners();
  }

  /// A session the server issued to the signed-in user (e.g. turning two-step sign-in on ends every
  /// older session and returns a fresh one). Returns an error message when it could not be used.
  Future<String?> adoptSession(Map<String, dynamic> data) async {
    if (data['accessToken'] is! String || data['refreshToken'] is! String || data['user'] is! Map) return null;
    return _applySession(data, signedIn: false);
  }

  // ── Age confirmation for new accounts (API 2.16) ─────────────────────────────

  /// A Google or phone sign-in that would create a new account, waiting for "I am 18 or older".
  _SignInRetry? _ageRetry;

  /// The server needs "I am 18 or older" before it creates the account; the app's home asks for it.
  bool get ageConfirmationNeeded => _ageRetry != null;

  /// Repeats the waiting sign-in with `ageConfirmed: true`. Null when signed in (or a two-step code is
  /// needed next), otherwise a message to show.
  Future<String?> confirmAgeAndContinue() async {
    final retry = _ageRetry;
    if (retry == null) return 'Please start again.';
    String? err;
    try {
      err = await _postSignIn(retry.path, {...retry.body, 'ageConfirmed': true}, retry.fallback);
    } catch (_) {
      // Offline: keep the attempt, so the person can try again
      return ServerMessages.localize('Could not reach Malvoya. Check your connection and try again.');
    }
    // A refusal other than the age question ends the attempt: back to the sign-in screen with it
    if (err != null) {
      _ageRetry = null;
      notifyListeners();
    }
    return err;
  }

  void cancelAgeConfirmation() {
    if (_ageRetry == null) return;
    _ageRetry = null;
    notifyListeners();
  }

  /// 400 for a new account without "I am 18 or older" (the code name is checked first; the
  /// sentence is the fallback for a server that answers without one).
  static bool _isAgeRequired(int status, Map<String, dynamic> data) {
    if (status != 400) return false;
    final code = '${data['code'] ?? ''}'.toUpperCase();
    if (code.contains('AGE')) return true;
    final error = '${data['error'] ?? ''}'.toLowerCase();
    return error.contains('18 or older') || error.contains('ageconfirmed');
  }

  /// Google and phone sign-in: posts [body] to [path] and applies the session. When the server asks
  /// for the age confirmation first, the attempt waits in [ageConfirmationNeeded] and null is returned.
  Future<String?> _postSignIn(String path, Map<String, dynamic> body, String fallback) async {
    final res = await http
        .post(Uri.parse('${AppConstants.apiBase}$path'), headers: ApiClient.baseHeaders, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200 || res.statusCode == 201) return await _applySession(jsonDecode(res.body));
    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (_isAgeRequired(res.statusCode, data) && body['ageConfirmed'] != true) {
      _ageRetry = _SignInRetry(path, body, fallback);
      notifyListeners();
      return null;
    }
    return _errorFrom(res, fallback);
  }

  // ── Email / password ───────────────────────────────────────────────────────

  /// The last password sign-in was refused because the email/phone or password was wrong (401):
  /// the sign-in screen then offers "Forgot password?" right next to the error.
  bool lastLoginRejected = false;

  Future<String?> login(String emailOrPhone, String password) async {
    lastLoginRejected = false;
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/login'),
              headers: ApiClient.baseHeaders,
              body: jsonEncode({'email': emailOrPhone.trim(), 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body));
      if (res.statusCode == 401) lastLoginRejected = true;
      return _errorFrom(res, 'Invalid email or password.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  /// [acceptTerms]: the person ticked "I accept the Seller Terms" (the server records when and which version).
  /// [ageConfirmed]: the person ticked "I am 18 or older" (API 2.16; required for new accounts).
  Future<String?> register(String name, String email, String password, {bool acceptTerms = false, bool ageConfirmed = false}) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/register'),
              headers: ApiClient.baseHeaders,
              body: jsonEncode({
                'name': name.trim(),
                'email': email.trim(),
                'password': password,
                'role': kAppRole,
                if (acceptTerms) 'acceptTerms': true,
                if (ageConfirmed) 'ageConfirmed': true,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) return await _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Registration failed. Please try again.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Forgotten password (a 6-digit code by email) ────────────────────────────

  /// POST /auth/password/forgot. The server answers 200 for any well-formed address (it never says
  /// whether an account exists), 429 when asked too often and 503 when it cannot send email.
  Future<ApiResult> requestPasswordReset(String email) =>
      const ApiClient().post('/auth/password/forgot', {'email': email.trim()});

  /// POST /auth/password/reset. On success every earlier session of the account is signed out.
  Future<ApiResult> resetPassword(String email, String code, String password) =>
      const ApiClient().post('/auth/password/reset', {'email': email.trim(), 'code': code.trim(), 'password': password});

  // ── Google ────────────────────────────────────────────────────────────────

  Future<String?> loginWithGoogle() async {
    // Not offered on iPhone (App Review 4.8, see screens/login.dart); the iOS build has no Google setup
    if (SignInSetup.isIOS) return 'Google sign-in is not available on iPhone.';
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return 'Google did not return a sign-in token';
      return await _postSignIn('/auth/google', {'idToken': idToken, 'role': kAppRole}, 'Google sign-in failed.');
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
    if (SignInSetup.isIOS) return 'Google sign-in is not available on iPhone.';
    try {
      final google = GoogleSignIn();
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

  /// Deletes the account on the server (GDPR Art. 17), then signs out on this phone.
  Future<String?> deleteAccount() async {
    final res = await ApiClient(this).delete('/auth/me');
    if (!res.ok) return res.error;
    await logout();
    return null;
  }

  @override
  Future<String?> unlinkGoogle() async {
    final res = await ApiClient(this).delete('/auth/google/link');
    if (!res.ok) return res.error;
    await _setGoogleLinked(false);
    return null;
  }

  Future<void> _setGoogleLinked(bool linked) async {
    final user = _currentUser;
    if (user == null) return;
    _currentUser = User.fromJson({...user.toJson(), 'googleLinked': linked});
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
    // On iOS Firebase stops the app if GoogleService-Info.plist or its callback URL scheme is missing
    if (!SignInSetup.firebasePhone) {
      onError('Phone sign-in is not available in this version of the app.');
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
      return await _postSignIn('/auth/phone', {'firebaseToken': firebaseToken, 'role': kAppRole}, 'Phone sign-in failed.');
    } on fb_auth.FirebaseAuthException catch (e) {
      return e.code == 'invalid-verification-code' ? 'The code is incorrect.' : (e.message ?? 'Phone verification failed');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> _clearSession() async {
    _refreshTimer?.cancel();
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _mfaToken = null;
    _ageRetry = null;
    _storeState = StoreState.unknown;
    _storeError = null;
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
                headers: ApiClient.baseHeaders, body: jsonEncode({'refreshToken': refresh}))
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (!SignInSetup.isIOS) {
      try { await GoogleSignIn().signOut(); } catch (_) {}
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

/// A sign-in request kept for one repeat (with `ageConfirmed: true`).
class _SignInRetry {
  final String path;
  final Map<String, dynamic> body;
  final String fallback;
  const _SignInRetry(this.path, this.body, this.fallback);
}
