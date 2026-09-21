import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'local_notification_service.dart';

class RealtimeNotificationService {
  static const String _historyKey = 'malvoya_notification_history';

  /// Dispatches multi-channel alerts (SMS to phone + Security email) when a customer joins or signs in
  static Future<void> notifyCustomerJoined(
    BuildContext context, {
    required String email,
    String? phone,
    required String name,
  }) async {
    final effectivePhone = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : 'Registered Mobile';
    final now = DateTime.now();

    // 1. Log to history
    await _recordNotification(
      type: 'AUTH',
      channel: 'SMS & Email',
      title: 'Welcome to Malvoya',
      message: 'Account verified. Security credentials established for $name ($email).',
      timestamp: now,
    );

    // 2. Dispatch async to backend notification endpoint
    _sendBackendNotification({
      'event': 'CUSTOMER_JOINED',
      'email': email,
      'phone': effectivePhone,
      'name': name,
      'timestamp': now.toIso8601String(),
    });

    if (!context.mounted) return;

    // 3. Trigger native on-device notification
    LocalNotificationService.showNotification(
      id: 10,
      title: '👋 Welcome to Malvoya',
      body: 'Account verified. Security credentials established for $name.',
      payload: 'auth_welcome',
    );

    // 4. Trigger heavy haptic feedback
    HapticFeedback.mediumImpact();

    // 5. Show Phone SMS Dispatch Banner
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sms_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💬 SMS to $effectivePhone',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                  ),
                  Text(
                    'Malvoya: Welcome $name! Security verification code verified. Live account active.',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        action: SnackBarAction(
          label: 'OPEN SMS',
          textColor: const Color(0xFFA78BFA),
          onPressed: () {
            LocalNotificationService.openSmsApp(
              phone: effectivePhone,
              body: 'Malvoya: Welcome $name! Security verification confirmed. Account is active.',
            );
          },
        ),
      ),
    );

    // 5. Follow-up Google Security Email Alert
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA4335),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📧 Email Security Alert to $email',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                    ),
                    const Text(
                      'Account Security: New sign-in detected from Helsinki, Finland (Android device).',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1438),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          action: SnackBarAction(
            label: 'OPEN EMAIL',
            textColor: const Color(0xFF60A5FA),
            onPressed: () {
              LocalNotificationService.openEmailApp(
                email: email,
                subject: 'Malvoya Account Security Alert',
                body: 'Malvoya Security Notice\n\nNew verified sign-in detected on your Android device.\nIf this was you, no action is needed.',
              );
            },
          ),
        ),
      );
    });
  }

  /// Dispatches multi-channel alerts when a user adds a credit/debit card
  static Future<void> notifyBankCardAdded(
    BuildContext context, {
    required String last4,
    required String brand,
    required String email,
    String? phone,
  }) async {
    final effectivePhone = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : 'Registered Mobile';
    final now = DateTime.now();

    // 1. Log to history
    await _recordNotification(
      type: 'CARD_ADDED',
      channel: 'SMS & Email',
      title: 'Payment Card Added',
      message: '$brand card ending in •••• $last4 verified via Luhn checksum and secured.',
      timestamp: now,
    );

    // 2. Dispatch async to backend
    _sendBackendNotification({
      'event': 'BANK_CARD_ADDED',
      'brand': brand,
      'last4': last4,
      'email': email,
      'phone': effectivePhone,
      'timestamp': now.toIso8601String(),
    });

    if (!context.mounted) return;

    LocalNotificationService.showNotification(
      id: 20,
      title: '💳 Payment Card Linked',
      body: '$brand card ending in •••• $last4 secured and verified.',
      payload: 'card_linked',
    );

    HapticFeedback.heavyImpact();

    // 3. Immediate SMS Notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lock_person_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💬 SMS to $effectivePhone',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                  ),
                  Text(
                    'Malvoya Security: $brand (•••• $last4) was successfully linked to your phone. Luhn algorithm check passed.',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );

    // 4. Email Security Alert
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📧 Security Notification to $email',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                    ),
                    Text(
                      'New payment method added ($brand •••• $last4). If this was not you, lock your account immediately in Settings.',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1438),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    });
  }

  /// Dispatches multi-channel alerts when a user links a European SEPA IBAN
  static Future<void> notifySepaBankLinked(
    BuildContext context, {
    required String ibanMasked,
    required String holderName,
    required String email,
    String? phone,
  }) async {
    final effectivePhone = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : 'Registered Mobile';
    final now = DateTime.now();

    // 1. Log to history
    await _recordNotification(
      type: 'BANK_IBAN_LINKED',
      channel: 'SMS & Email',
      title: 'SEPA Bank Account Linked',
      message: 'European IBAN ($ibanMasked) validated via Modulo-97 algorithm for $holderName.',
      timestamp: now,
    );

    // 2. Dispatch async to backend
    _sendBackendNotification({
      'event': 'SEPA_IBAN_LINKED',
      'ibanMasked': ibanMasked,
      'holderName': holderName,
      'email': email,
      'phone': effectivePhone,
      'timestamp': now.toIso8601String(),
    });

    if (!context.mounted) return;

    LocalNotificationService.showNotification(
      id: 30,
      title: '🏦 European SEPA IBAN Verified',
      body: 'Account ($ibanMasked) linked for $holderName. Direct debit active.',
      payload: 'sepa_linked',
    );

    HapticFeedback.heavyImpact();

    // 3. Immediate SMS Notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💬 SMS to $effectivePhone',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                  ),
                  Text(
                    'Malvoya Bank Link: European IBAN ($ibanMasked) verified via Modulo-97. Direct debit & statutory refunds active.',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );

    // 4. Email Security Alert
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📧 Banking Alert to $email',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                    ),
                    Text(
                      'SEPA Bank account registration confirmed for $holderName. Authorized from Helsinki, Finland.',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1438),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    });
  }

  /// Dispatches multi-channel alerts for orders & payments
  static Future<void> notifyOrderPlaced(
    BuildContext context, {
    required String orderId,
    required double total,
    required String paymentMethod,
    required String email,
    String? phone,
  }) async {
    final effectivePhone = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : 'Registered Mobile';
    final now = DateTime.now();

    await _recordNotification(
      type: 'ORDER_PLACED',
      channel: 'SMS & Email',
      title: 'Order $orderId Confirmed',
      message: 'Payment of €${total.toStringAsFixed(2)} authorized via $paymentMethod.',
      timestamp: now,
    );

    _sendBackendNotification({
      'event': 'ORDER_PLACED',
      'orderId': orderId,
      'amount': total,
      'paymentMethod': paymentMethod,
      'email': email,
      'phone': effectivePhone,
      'timestamp': now.toIso8601String(),
    });

    if (!context.mounted) return;

    LocalNotificationService.showNotification(
      id: 40,
      title: '🛍️ Order Confirmed ($orderId)',
      body: '€${total.toStringAsFixed(2)} authorized via ${paymentMethod.replaceAll("_", " ").toUpperCase()}. Courier dispatch active.',
      payload: 'order_$orderId',
    );

    HapticFeedback.heavyImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.sms_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '💬 SMS to $effectivePhone: Malvoya payment of €${total.toStringAsFixed(2)} authorized via ${paymentMethod.replaceAll("_", " ").toUpperCase()}. Order $orderId confirmed!',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        action: SnackBarAction(
          label: 'OPEN SMS',
          textColor: const Color(0xFFA78BFA),
          onPressed: () {
            LocalNotificationService.openSmsApp(
              phone: effectivePhone,
              body: 'Malvoya Payment Authorized: €${total.toStringAsFixed(2)} for Order #$orderId. Dispatch active.',
            );
          },
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!context.mounted) return;

      LocalNotificationService.showNotification(
        id: 41,
        title: '🧾 VAT Tax Invoice & Receipt',
        body: 'Official ALV 25.5% receipt for $orderId (€${total.toStringAsFixed(2)}) sent to $email.',
        payload: 'invoice_$orderId',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.mark_email_read_rounded, color: Colors.amberAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '📧 Official VAT invoice & tracking dispatched to $email.',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1438),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          action: SnackBarAction(
            label: 'OPEN EMAIL',
            textColor: const Color(0xFF60A5FA),
            onPressed: () {
              LocalNotificationService.openEmailApp(
                email: email,
                subject: 'Malvoya Official VAT 25.5% Tax Receipt - Order #$orderId',
                body: 'Malvoya Official Order Confirmation & Tax Receipt\n\n'
                    'Order ID: #$orderId\n'
                    'Total Paid: €${total.toStringAsFixed(2)} (incl. 25.5% Finnish VAT)\n'
                    'Status: Boutique Dispatch Confirmed\n'
                    'Payment Method: ${paymentMethod.replaceAll("_", " ").toUpperCase()}\n\n'
                    'Thank you for shopping with Malvoya!',
              );
            },
          ),
        ),
      );
    });
  }

  // ── Helpers ──
  static Future<void> _recordNotification({
    required String type,
    required String channel,
    required String title,
    required String message,
    required DateTime timestamp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyRaw = prefs.getString(_historyKey);
      final List<dynamic> list = historyRaw != null ? jsonDecode(historyRaw) : [];
      list.insert(0, {
        'type': type,
        'channel': channel,
        'title': title,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
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

  static void _sendBackendNotification(Map<String, dynamic> payload) {
    try {
      http.post(
        Uri.parse('${AppConstants.apiBase}/notifications/dispatch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
    } catch (_) {}
  }

  static Future<void> dispatchOtpSms({
    required String phone,
    required String code,
  }) async {
    _sendBackendNotification({
      'event': 'VERIFICATION_CODE',
      'channel': 'SMS',
      'phone': phone,
      'code': code,
    });
  }

  static Future<Map<String, dynamic>> sendRealOtp({
    required String destination,
    String? channel,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/otp/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'target': destination,
          'channel': channel ?? (destination.contains('@') ? 'email' : 'sms'),
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final errData = jsonDecode(res.body);
      return {'ok': false, 'error': errData['error'] ?? 'Could not send verification code.'};
    } catch (e) {
      return {'ok': false, 'error': 'Connection error: Could not reach verification server.'};
    }
  }

  static Future<Map<String, dynamic>> verifyRealOtp({
    required String destination,
    required String code,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBase}/auth/otp/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'target': destination,
          'code': code.trim(),
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final errData = jsonDecode(res.body);
      return {'ok': false, 'error': errData['error'] ?? 'Invalid or expired verification code.'};
    } catch (e) {
      return {'ok': false, 'error': 'Connection error: Verification failed.'};
    }
  }
}
