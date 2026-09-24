import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config/constants.dart';

/// In-app notification history + the OTP calls used by the login screen.
/// Emails and SMS are sent by the server when something really happens (e.g. a payment succeeds);
/// the app never asks the server to send messages on its behalf.
class RealtimeNotificationService {
  static const String _historyKey = 'malvoya_notification_history';

  static Future<void> notifyCustomerJoined(
    BuildContext context, {
    required String email,
    String? phone,
    required String name,
  }) async {
    await _recordNotification(
      type: 'AUTH',
      title: 'Tervetuloa Malvoyaan / Welcome to Malvoya',
      message: 'Signed in as $name.',
    );
  }

  /// Called after the payment sheet completes. The order is confirmed only when the server
  /// receives Stripe's confirmation, so the wording reflects that.
  static Future<void> notifyOrderPlaced(
    BuildContext context, {
    required String orderId,
    required double total,
    required String paymentMethod,
    required String email,
    String? phone,
  }) async {
    await _recordNotification(
      type: 'ORDER_PLACED',
      title: 'Tilaus #$orderId / Order #$orderId',
      message: 'Payment of €${total.toStringAsFixed(2)} submitted. You will get a confirmation email once the payment is confirmed.',
    );
  }

  // ── History ──
  static Future<void> _recordNotification({
    required String type,
    required String title,
    required String message,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyRaw = prefs.getString(_historyKey);
      final List<dynamic> list = historyRaw != null ? jsonDecode(historyRaw) : [];
      list.insert(0, {
        'type': type,
        'channel': 'In-app',
        'title': title,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (list.length > 50) list.removeRange(50, list.length);
      await prefs.setString(_historyKey, jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyRaw = prefs.getString(_historyKey);
      if (historyRaw == null) return [];
      final list = jsonDecode(historyRaw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── One-time codes (server generates, sends and verifies them) ──
  static Future<Map<String, dynamic>> sendRealOtp({
    required String destination,
    String? channel,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AppConstants.apiBase}/auth/otp/send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'target': destination,
              'channel': channel ?? (destination.contains('@') ? 'email' : 'sms'),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final errData = jsonDecode(res.body);
      return {'ok': false, 'error': errData['error'] ?? 'Could not send verification code.'};
    } catch (e) {
      return {'ok': false, 'error': 'Could not reach the server. Please check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> verifyRealOtp({
    required String destination,
    required String code,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AppConstants.apiBase}/auth/otp/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'target': destination, 'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
      final errData = jsonDecode(res.body);
      return {'ok': false, 'error': errData['error'] ?? 'Invalid or expired verification code.'};
    } catch (e) {
      return {'ok': false, 'error': 'Could not reach the server. Please check your connection.'};
    }
  }
}
