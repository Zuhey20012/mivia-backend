import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUser = null;
    _accessToken = null;
    await prefs.clear();
    notifyListeners();
  }
}
