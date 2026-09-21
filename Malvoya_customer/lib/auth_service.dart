import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'config/constants.dart';

final _secureStorage = const FlutterSecureStorage();

class User {
  final int id;
  final String email;
  final String role;
  final String? name;
  final String? phone;
  final bool isActive;

  User({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.phone,
    this.isActive = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      role: json['role'] ?? 'CUSTOMER',
      name: json['name'],
      phone: json['phone'],
      isActive: json['isActive'] ?? true,
    );
  }
}

class AuthService extends ChangeNotifier {
  User? _currentUser;
  String? _accessToken;
  bool _loading = true;

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
  bool get isLoading => _loading;
  String? get accessToken => _accessToken;

  /// Vendors & Couriers must be approved by admin before accessing dashboards
  bool get isPendingApproval {
    final role = _currentUser?.role;
    if (role == 'VENDOR' || role == 'COURIER') {
      return !(_currentUser?.isActive ?? true);
    }
    return false;
  }

  AuthService() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    final token = await _secureStorage.read(key: 'accessToken');
    if (userJson != null && token != null) {
      _currentUser = User.fromJson(jsonDecode(userJson));
      _accessToken = token;
    }
    _loading = false;
    notifyListeners();
  }

  String _sanitizeEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('@')) return trimmed;
    final cleanDigits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.isNotEmpty) return '$cleanDigits@phone.malvoya.app';
    return trimmed;
  }

  Future<void> loginAsGuest() async {
    final guestUser = {
      'id': 999999,
      'email': 'guest@malvoya.app',
      'name': 'Guest Explorer',
      'role': 'CUSTOMER',
      'isActive': true,
    };
    await _saveSession(guestUser, 'guest_token_${DateTime.now().millisecondsSinceEpoch}', 'guest_refresh_token');
  }

  Future<String?> loginWithPhone(String phone) async {
    final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.length < 5) {
      return 'Please enter a valid mobile phone number.';
    }
    final phoneEmail = '$cleanDigits@phone.malvoya.app';
    final securePassword = base64Encode(utf8.encode('malvoya_${phone.hashCode}_secure'));
    
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': phoneEmail, 'password': securePassword}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return null;
      }
    } catch (_) {}

    try {
      final regRes = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': 'Customer (+$cleanDigits)',
          'email': phoneEmail,
          'password': securePassword,
          'role': 'CUSTOMER',
        }),
      );
      if (regRes.statusCode == 201) {
        final data = jsonDecode(regRes.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return null;
      }
      return 'Failed to authenticate with phone number.';
    } catch (_) {
      return 'Could not connect. Please check your internet connection.';
    }
  }

  Future<String?> login(String email, String password) async {
    final effectiveEmail = _sanitizeEmail(email);
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': effectiveEmail, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return null; // null = success
      }
      if (effectiveEmail.endsWith('@phone.malvoya.app')) {
        return loginWithPhone(email);
      }
      final body = jsonDecode(response.body);
      return body['message'] ?? 'Invalid email or password.';
    } catch (e) {
      debugPrint('Login error: $e');
      if (effectiveEmail.endsWith('@phone.malvoya.app')) {
        return loginWithPhone(email);
      }
      return 'Could not connect. Please check your internet connection.';
    }
  }

  Future<String?> register(String name, String email, String password, String role) async {
    final effectiveEmail = _sanitizeEmail(email);
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': effectiveEmail,
          'password': password,
          'role': role,
        }),
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return null; // success
      }
      if (effectiveEmail.endsWith('@phone.malvoya.app')) {
        return loginWithPhone(email);
      }
      final body = jsonDecode(response.body);
      return body['message'] ?? 'Registration failed. Please try again.';
    } catch (e) {
      if (effectiveEmail.endsWith('@phone.malvoya.app')) {
        return loginWithPhone(email);
      }
      return 'Could not connect. Please check your internet connection.';
    }
  }

  Future<void> _saveSession(Map<String, dynamic> userData, String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    // Guarantee CUSTOMER app users have CUSTOMER role locally
    final userMap = Map<String, dynamic>.from(userData);
    userMap['role'] = 'CUSTOMER';
    userMap['isActive'] = true;
    _currentUser = User.fromJson(userMap);
    _accessToken = accessToken;
    await prefs.setString('user', jsonEncode(userMap));
    await _secureStorage.write(key: 'accessToken', value: accessToken);
    await _secureStorage.write(key: 'refreshToken', value: refreshToken);
    notifyListeners();
  }

  Future<String?> loginWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return null; // Cancelled gracefully
      final GoogleSignInAuthentication gAuth = await account.authentication;
      try {
        final response = await http.post(
          Uri.parse('${AppConstants.apiBase}/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': gAuth.idToken}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
          return null;
        }
        final body = jsonDecode(response.body);
        return body['message'] ?? 'Google sign-in failed.';
      } catch (e) {
        debugPrint('Google auth error: $e');
        return 'Google sign-in failed. Please check your internet connection.';
      }
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      return 'Google sign-in was not completed.';
    }
  }

  Future<void> saveSession(Map<String, dynamic> user, String accessToken, String refreshToken) async {
    await _saveSession(user, accessToken, refreshToken);
  }

  Future<String?> loginWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/apple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': credential.identityToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return null;
      }
      return 'Apple login failed. Please try again.';
    } catch (e) {
      return 'Apple sign-in failed.';
    }
  }

  Future<void> verifyPhone(String phone, Function(String) onCodeSent) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        if (credential.smsCode != null) {
          await signInWithOtp(credential.verificationId!, credential.smsCode!);
        }
      },
      verificationFailed: (e) => debugPrint('Phone verification failed: $e'),
      codeSent: (id, _) => onCodeSent(id),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<String?> signInWithOtp(String verificationId, String smsCode) async {
    try {
      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken != null) {
        final response = await http.post(
          Uri.parse('${AppConstants.apiBase}/auth/phone'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'firebaseToken': idToken}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
          return null;
        }
        final body = jsonDecode(response.body);
        return body['message'] ?? 'Authentication failed.';
      }
      return 'Authentication failed.';
    } catch (e) {
      return 'OTP error: $e';
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    try { await _googleSignIn.signOut(); } catch (_) {}
    _currentUser = null;
    _accessToken = null;
    await prefs.clear();
    await _secureStorage.deleteAll();
    notifyListeners();
  }
}
