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

/// Messages from this file follow the app language (no BuildContext here).
String _t(String en, String fi) => AppLanguage.pick(en, fi);

/// Every request names the app language, so the server can send notifications and emails in it.
Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json', 'Accept-Language': AppLanguage.code, if (AppLanguage.appVersion != null) 'X-App-Version': AppLanguage.appVersion!};

/// The account role this app is for. Other roles are refused at sign-in.
const String kAppRole = 'COURIER';

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

/// Answer to a password-reset step. [unavailable] = the server cannot reset passwords by email
/// (503: email not set up, or 404: an older server without the feature).
class PasswordResetResult {
  final bool ok;
  final String? error;
  final bool unavailable;
  final bool tooMany;
  /// 404: the server has no password reset at all (older version).
  final bool notSupported;
  /// The code was refused (wrong, expired or used up), so a new one is needed or it must be re-typed.
  final bool codeProblem;
  /// Set when the password was changed but signing in with it afterwards failed.
  final String? signInError;

  const PasswordResetResult({
    required this.ok,
    this.error,
    this.unavailable = false,
    this.tooMany = false,
    this.notSupported = false,
    this.codeProblem = false,
    this.signInError,
  });

  factory PasswordResetResult.from(ApiResult res) {
    final raw = '${res.data['error'] ?? ''}'.toLowerCase();
    return PasswordResetResult(
      ok: res.ok,
      error: res.ok ? null : res.error,
      unavailable: res.status == 503 || res.status == 404,
      tooMany: res.status == 429,
      notSupported: res.status == 404,
      codeProblem: res.status == 400 && (raw.contains('code') || raw.contains('expired')),
    );
  }
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
  bool _isApproved = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _accessToken != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
  @override
  String? get accessToken => _accessToken;
  bool get isReady => _ready;

  /// Couriers can take jobs only after an admin has verified them.
  bool get isPendingApproval => !_isApproved;

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
      await refreshApprovalStatus();
    }
    _ready = true;
    notifyListeners();
  }

  // ── Two-step sign-in and age confirmation (API 2.16) ─────────────────────

  /// Shows the "code from your authenticator app" step when an account has two-step sign-in on.
  /// Set once in `main()` (it needs the app's navigator). Returns null when the second step
  /// signed in, otherwise the message to show (e.g. cancelled).
  static Future<String?> Function(AuthService auth, String mfaToken)? askTwoStepCode;

  /// Asks "I am 18 or older" when the server needs it for a new account created by a social
  /// sign-in. True = confirmed, so the sign-in is sent once more with `ageConfirmed: true`.
  static Future<bool> Function()? confirmAge;

  /// The server refused to create a new account because the age was not confirmed (400).
  static bool _needsAgeConfirmation(http.Response res) {
    if (res.statusCode != 400) return false;
    try {
      final body = jsonDecode(res.body);
      if (body is! Map) return false;
      final code = '${body['code'] ?? ''}'.toUpperCase();
      if (code.contains('AGE')) return true;
      final text = jsonEncode(body).toLowerCase();
      return text.contains('ageconfirmed') || text.contains('18 or older');
    } catch (_) {
      return false;
    }
  }

  /// POST /auth/login/mfa: the challenge from the first step plus an authenticator or recovery
  /// code. Null when signed in, otherwise the server's message.
  Future<String?> completeTwoStep(String mfaToken, String code) async {
    final res = await const ApiClient().post('/auth/login/mfa', {'mfaToken': mfaToken, 'code': code.replaceAll(' ', '').trim()});
    if (!res.ok) return res.errorMessage;
    final err = await _applySession(res.data, signIn: true);
    if (err != null) return err;
    final left = asInt(res.data['recoveryCodesLeft']);
    if (left != null) {
      lastSignInNotice = _t('You used a recovery code. $left left. You can make new ones under Account → Two-step sign-in.',
          'Käytit varakoodin. Jäljellä $left. Voit tehdä uudet kohdassa Tili → Kaksivaiheinen kirjautuminen.');
    }
    return null;
  }

  /// Something to tell the courier after signing in (e.g. a recovery code was used).
  String? lastSignInNotice;

  /// Applies a session the server returned to a signed-in action (e.g. turning two-step sign-in
  /// on, which ends every older session and returns a fresh one).
  Future<String?> applyFreshSession(Map<String, dynamic> data) async {
    if (data['accessToken'] is! String || data['refreshToken'] is! String || data['user'] is! Map) return null;
    return _applySession(data);
  }

  Future<String?> _applySession(Map<String, dynamic> data, {bool signIn = false}) async {
    // Two-step sign-in: no tokens yet, only a 5-minute challenge for the authenticator code
    if (data['mfaRequired'] == true && data['mfaToken'] is String) {
      final ask = askTwoStepCode;
      if (ask == null) return _t('Enter the code from your authenticator app to sign in.', 'Kirjaudu antamalla todennussovelluksen koodi.');
      return ask(this, data['mfaToken'] as String);
    }
    final user = User.fromJson(data['user']);
    if (user.role != kAppRole) {
      return _t('This account is not a courier account. Please use the matching Malvoya app.', 'Tämä ei ole lähettitili. Käytä oikeaa Malvoya-sovellusta.');
    }
    _currentUser = user;
    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user.toJson()));
    await _secureStorage.write(key: 'accessToken', value: _accessToken);
    await _secureStorage.write(key: 'refreshToken', value: _refreshToken);
    _scheduleRefresh();
    unawaited(refreshApprovalStatus());
    // A new sign-in tells the server which language this phone uses (a token refresh does not)
    if (signIn) unawaited(syncLocale());
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
              headers: _jsonHeaders, body: jsonEncode({'refreshToken': refresh}))
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
      if (body['error'] is String) return ServerMessages.localize(body['error']);
      final fieldErrors = body['errors']?['fieldErrors'] as Map<String, dynamic>?;
      if (fieldErrors != null && fieldErrors.isNotEmpty) return ServerMessages.localize((fieldErrors.values.first as List).first.toString());
    } catch (_) {}
    return fallback;
  }

  // ── Email / password ───────────────────────────────────────────────────────

  /// True when the last [login] was refused for its credentials (not for the connection), so the
  /// sign-in screen can offer "Forgot password?".
  bool lastLoginRejected = false;

  Future<String?> login(String emailOrPhone, String password) async {
    lastLoginRejected = false;
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/login'),
              headers: _jsonHeaders,
              body: jsonEncode({'email': emailOrPhone.trim(), 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body), signIn: true);
      lastLoginRejected = res.statusCode == 400 || res.statusCode == 401;
      return _errorFrom(res, _t('Invalid email or password.', 'Sähköposti tai salasana on väärin.'));
    } catch (_) {
      return _t('Could not connect. Please check your internet connection.', 'Yhteyttä ei saatu. Tarkista nettiyhteys.');
    }
  }

  /// Creates a courier account. [acceptTerms] records that the courier accepted the courier agreement.
  /// [ageConfirmed]: the courier ticked "I am 18 or older" (required for new accounts, API 2.16).
  Future<String?> register(String name, String email, String password, {required bool acceptTerms, required bool ageConfirmed}) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/register'),
              headers: _jsonHeaders,
              body: jsonEncode({
                'name': name.trim(),
                'email': email.trim(),
                'password': password,
                'role': kAppRole,
                if (acceptTerms) 'acceptTerms': true,
                if (ageConfirmed) 'ageConfirmed': true,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) return await _applySession(jsonDecode(res.body), signIn: true);
      return _errorFrom(res, _t('Registration failed. Please try again.', 'Rekisteröinti epäonnistui. Yritä uudelleen.'));
    } catch (_) {
      return _t('Could not connect. Please check your internet connection.', 'Yhteyttä ei saatu. Tarkista nettiyhteys.');
    }
  }

  // ── Forgotten password (a code by email, API 2.10) ────────────────────────

  /// Asks the server to email a 6-digit code. The server answers the same whether or not an
  /// account exists, so this never reveals who has an account.
  Future<PasswordResetResult> requestPasswordReset(String email) async {
    final res = await const ApiClient().post('/auth/password/forgot', {'email': email.trim()});
    return PasswordResetResult.from(res);
  }

  /// Sets the new password with the emailed code, then signs in with it.
  Future<PasswordResetResult> resetPassword(String email, String code, String password) async {
    final res = await const ApiClient().post('/auth/password/reset', {'email': email.trim(), 'code': code.trim(), 'password': password});
    final result = PasswordResetResult.from(res);
    if (!result.ok) return result;
    // The reset ends every session, so a fresh one is opened with the new password
    final err = await login(email, password);
    return PasswordResetResult(ok: true, signInError: err);
  }

  // ── Language ──────────────────────────────────────────────────────────────

  String? _localeSynced;

  /// Stores the app language on the server (`PATCH /me {locale}`), so push notifications and
  /// emails come in it. Sent after sign-in and when the language is changed; an older server
  /// without the field simply ignores it.
  Future<void> syncLocale() async {
    final user = _currentUser;
    if (user == null || _accessToken == null) return;
    final code = AppLanguage.code;
    final key = '${user.id}:$code';
    if (_localeSynced == key) return;
    _localeSynced = key;
    final res = await ApiClient(this).patch('/me', {'locale': code});
    // Network trouble: try again next time; a refusal (old server) is not retried
    if (res.status == 0) _localeSynced = null;
  }

  // ── Google ────────────────────────────────────────────────────────────────

  Future<String?> loginWithGoogle() async {
    // Not offered on iPhone (App Review 4.8, see screens/login.dart); the iOS build has no Google setup
    if (SignInSetup.isIOS) return 'Google sign-in is not available on iPhone.';
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return _t('Google sign-in cancelled', 'Google-kirjautuminen peruttiin');
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return _t('Google did not return a sign-in token', 'Google ei palauttanut kirjautumistunnistetta');
      Future<http.Response> send({bool age = false}) => http
          .post(Uri.parse('${AppConstants.apiBase}/auth/google'),
              headers: _jsonHeaders, body: jsonEncode({'idToken': idToken, 'role': kAppRole, if (age) 'ageConfirmed': true}))
          .timeout(const Duration(seconds: 15));
      var res = await send();
      // A new account: the server needs "I am 18 or older" first
      if (_needsAgeConfirmation(res)) {
        final confirm = confirmAge;
        if (confirm == null || !await confirm()) return _t('Confirm that you are 18 or older to create an account.', 'Vahvista, että olet vähintään 18-vuotias luodaksesi tilin.');
        res = await send(age: true);
      }
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body), signIn: true);
      return _errorFrom(res, _t('Google sign-in failed.', 'Google-kirjautuminen epäonnistui.'));
    } catch (_) {
      return _t('Google sign-in failed. Please check your internet connection.', 'Google-kirjautuminen epäonnistui. Tarkista nettiyhteys.');
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
      if (googleUser == null) return _t('Google sign-in cancelled', 'Google-kirjautuminen peruttiin');
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return _t('Google did not return a sign-in token', 'Google ei palauttanut kirjautumistunnistetta');
      final res = await ApiClient(this).post('/auth/google/link', {'idToken': idToken});
      if (!res.ok) return res.error;
      await _setGoogleLinked(true);
      return null;
    } catch (_) {
      return _t('Google sign-in failed. Please check your internet connection.', 'Google-kirjautuminen epäonnistui. Tarkista nettiyhteys.');
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
      onError(_t('Phone sign-in is not available in this version of the app.', 'Puhelimella kirjautuminen ei ole käytettävissä tässä sovellusversiossa.'));
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
        verificationFailed: (e) => onError(e.message ?? _t('Phone verification failed', 'Puhelinnumeron vahvistus epäonnistui')),
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) => _verificationId = verificationId,
      );
    } catch (e) {
      onError(_t('Could not send the verification code. Please try again.', 'Vahvistuskoodia ei voitu lähettää. Yritä uudelleen.'));
    }
  }

  Future<String?> signInWithSmsCode(String smsCode) async {
    if (_verificationId == null) return _t('Request a new code first', 'Pyydä ensin uusi koodi');
    final credential = fb_auth.PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: smsCode.trim());
    return _signInWithCredential(credential);
  }

  Future<String?> _signInWithCredential(fb_auth.PhoneAuthCredential credential) async {
    try {
      final result = await _firebaseAuth.signInWithCredential(credential);
      final firebaseToken = await result.user?.getIdToken();
      if (firebaseToken == null) return _t('Phone verification failed', 'Puhelinnumeron vahvistus epäonnistui');
      Future<http.Response> send({bool age = false}) => http
          .post(Uri.parse('${AppConstants.apiBase}/auth/phone'),
              headers: _jsonHeaders,
              body: jsonEncode({'firebaseToken': firebaseToken, 'role': kAppRole, if (age) 'ageConfirmed': true}))
          .timeout(const Duration(seconds: 15));
      var res = await send();
      if (_needsAgeConfirmation(res)) {
        final confirm = confirmAge;
        if (confirm == null || !await confirm()) return _t('Confirm that you are 18 or older to create an account.', 'Vahvista, että olet vähintään 18-vuotias luodaksesi tilin.');
        res = await send(age: true);
      }
      if (res.statusCode == 200) return await _applySession(jsonDecode(res.body), signIn: true);
      return _errorFrom(res, _t('Phone sign-in failed.', 'Puhelinkirjautuminen epäonnistui.'));
    } on fb_auth.FirebaseAuthException catch (e) {
      return e.code == 'invalid-verification-code'
          ? _t('The code is incorrect.', 'Koodi on väärin.')
          : (e.message ?? _t('Phone verification failed', 'Puhelinnumeron vahvistus epäonnistui'));
    } catch (_) {
      return _t('Could not connect. Please check your internet connection.', 'Yhteyttä ei saatu. Tarkista nettiyhteys.');
    }
  }

  /// After `PATCH /me/profile` succeeded: shows the new name everywhere without signing in again.
  Future<void> updateLocalName(String name) async {
    final user = _currentUser;
    if (user == null) return;
    _currentUser = User.fromJson({...user.toJson(), 'name': name});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    notifyListeners();
  }

  // ── Courier approval ──────────────────────────────────────────────────────

  /// Reads the approval state from the server (the only source of truth).
  Future<bool> refreshApprovalStatus() async {
    final token = _accessToken;
    if (token == null) return false;
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/courier/me'), headers: {'Authorization': 'Bearer $token', 'Accept-Language': AppLanguage.code, if (AppLanguage.appVersion != null) 'X-App-Version': AppLanguage.appVersion!})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _isApproved = jsonDecode(res.body)['courier']?['isApproved'] == true;
        notifyListeners();
      }
    } catch (_) {}
    return _isApproved;
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> _clearSession() async {
    _refreshTimer?.cancel();
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
                headers: _jsonHeaders, body: jsonEncode({'refreshToken': refresh}))
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
