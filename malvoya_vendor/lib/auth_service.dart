import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'config/constants.dart';
import 'core/api_client.dart';
import 'core/server_errors.dart';
import 'locale_provider.dart';

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
class AuthService extends ChangeNotifier {
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
    final user = User.fromJson(data['user']);
    if (user.role != kAppRole) {
      return 'This account is not a store account. Please use the matching Malvoya app.';
    }
    _currentUser = user;
    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
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
      await ApiClient(this).patch('/me', {'locale': LocaleProvider.currentCode});
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
      if (body['error'] is String) return localizeServerError(body['error']);
      final fieldErrors = body['errors']?['fieldErrors'] as Map<String, dynamic>?;
      if (fieldErrors != null && fieldErrors.isNotEmpty) return localizeServerError((fieldErrors.values.first as List).first.toString());
    } catch (_) {}
    return localizeServerError(fallback);
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
  Future<String?> register(String name, String email, String password, {bool acceptTerms = false}) async {
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
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return 'Google did not return a sign-in token';
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/google'),
              headers: ApiClient.baseHeaders, body: jsonEncode({'idToken': idToken, 'role': kAppRole}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Google sign-in failed.');
    } catch (_) {
      return 'Google sign-in failed. Please check your internet connection.';
    }
  }

  // ── Linking Google to the signed-in account ──────────────────────────────

  bool get googleLinked => _currentUser?.googleLinked ?? false;

  /// Links a Google account to this account, so "Sign in with Google" opens it from now on.
  Future<String?> linkGoogle() async {
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
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/phone'),
              headers: ApiClient.baseHeaders,
              body: jsonEncode({'firebaseToken': firebaseToken, 'role': kAppRole}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Phone sign-in failed.');
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
    try { await GoogleSignIn().signOut(); } catch (_) {}
    try { await _firebaseAuth.signOut(); } catch (_) {}
    await _clearSession();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
