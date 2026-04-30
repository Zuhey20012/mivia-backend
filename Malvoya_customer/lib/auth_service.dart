import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'config/constants.dart';

class User {
  final int id;
  final String email;
  final String role;
  final String? name;
  
  User({required this.id, required this.email, required this.role, this.name});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      role: json['role'],
      name: json['name'],
    );
  }
}

class AuthService extends ChangeNotifier {
  User? _currentUser;
  String? _accessToken;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.role == 'ADMIN';
  String? get accessToken => _accessToken;

  AuthService() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    final token = prefs.getString('accessToken');
    if (userJson != null && token != null) {
      _currentUser = User.fromJson(jsonDecode(userJson));
      _accessToken = token;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Login Error: $e");
      return false;
    }
  }

  Future<bool> register(String name, String email, String password, String role) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Registration Error: $e");
      return false;
    }
  }

  Future<void> _saveSession(Map<String, dynamic> userData, String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    _currentUser = User.fromJson(userData);
    _accessToken = accessToken;
    
    await prefs.setString('user', jsonEncode(userData));
    await prefs.setString('accessToken', accessToken);
    await prefs.setString('refreshToken', refreshToken);
    
    notifyListeners();
  }

  Future<bool> loginWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        final GoogleSignInAuthentication auth = await account.authentication;
        
        final response = await http.post(
          Uri.parse('${AppConstants.apiBase}/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': auth.idToken}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
          return true;
        }
      }
      return false;
    } catch (error) {
      debugPrint("Google Sign In Error: $error");
      return false;
    }
  }

  Future<bool> loginWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/apple'), // Need to implement in backend too
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': credential.identityToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['user'], data['accessToken'], data['refreshToken']);
        return true;
      }
      return false;
    } catch (error) {
      debugPrint("Apple Sign In Error: $error");
      return false;
    }
  }

  Future<void> verifyPhone(String phone, Function(String) onCodeSent) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        // Auto-resolution (Android only)
        if (credential.smsCode != null) {
          await signInWithOtp(credential.verificationId!, credential.smsCode!);
        }
      },
      verificationFailed: (e) => debugPrint("Phone verification failed: $e"),
      codeSent: (id, resendToken) => onCodeSent(id),
      codeAutoRetrievalTimeout: (id) {},
    );
  }

  Future<bool> signInWithOtp(String verificationId, String smsCode) async {
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
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Phone OTP Error: $e");
      return false;
    }
  }
  
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser?.id == 5) await _googleSignIn.signOut();
    
    _currentUser = null;
    _accessToken = null;
    await prefs.clear();
    
    notifyListeners();
  }
}
