import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'config/constants.dart';

const _secureStorage = FlutterSecureStorage();

/// The account role this app is for. Other roles are refused at sign-in.
const String kAppRole = 'COURIER';

class User {
  final int id;
  final String email;
  final String role;
  final String? name;

  User({required this.id, required this.email, required this.role, this.name});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        email: json['email'] ?? '',
        role: json['role'] ?? kAppRole,
        name: json['name'],
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'name': name};
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
  bool _isApproved = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _accessToken != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
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

  Future<String?> _applySession(Map<String, dynamic> data) async {
    final user = User.fromJson(data['user']);
    if (user.role != kAppRole) {
      return 'This account is not a courier account. Please use the matching Malvoya app.';
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
  Future<bool> refreshSession() async {
    final refresh = _refreshToken;
    if (refresh == null) return false;
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/refresh'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': refresh}))
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

  // ── Email / password ───────────────────────────────────────────────────────

  Future<String?> login(String emailOrPhone, String password) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'email': emailOrPhone.trim(), 'password': password}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Invalid email or password.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  Future<String?> register(String name, String email, String password, [String? _]) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/register'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name.trim(), 'email': email.trim(), 'password': password, 'role': kAppRole}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) return _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Registration failed. Please try again.');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Google ────────────────────────────────────────────────────────────────

  Future<String?> loginWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return 'Google sign-in cancelled';
      final idToken = (await googleUser.authentication).idToken;
      if (idToken == null) return 'Google did not return a sign-in token';
      final res = await http
          .post(Uri.parse('${AppConstants.apiBase}/auth/google'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'idToken': idToken, 'role': kAppRole}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Google sign-in failed.');
    } catch (_) {
      return 'Google sign-in failed. Please check your internet connection.';
    }
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
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'firebaseToken': firebaseToken, 'role': kAppRole}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return _applySession(jsonDecode(res.body));
      return _errorFrom(res, 'Phone sign-in failed.');
    } on fb_auth.FirebaseAuthException catch (e) {
      return e.code == 'invalid-verification-code' ? 'The code is incorrect.' : (e.message ?? 'Phone verification failed');
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  // ── Courier approval ──────────────────────────────────────────────────────

  /// Reads the approval state from the server (the only source of truth).
  Future<bool> refreshApprovalStatus() async {
    final token = _accessToken;
    if (token == null) return false;
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/courier/me'), headers: {'Authorization': 'Bearer $token'})
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

  Future<void> logout() async {
    final refresh = _refreshToken;
    if (refresh != null) {
      try {
        await http
            .post(Uri.parse('${AppConstants.apiBase}/auth/logout'),
                headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': refresh}))
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
