import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    try {
      await _notificationsPlugin.initialize(initSettings);
      
      // Create high importance notification channel for Android 8+
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'malvoya_dispatch',
        'Malvoya Orders & Dispatch Alerts',
        description: 'Instant status alerts for orders, SMS notifications, and receipts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(channel);
        await androidPlugin.requestNotificationsPermission();
      }
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_initialized) await initialize();
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'malvoya_dispatch',
        'Malvoya Orders & Dispatch Alerts',
        channelDescription: 'Instant status alerts for orders, SMS notifications, and receipts',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/launcher_icon',
      );

      const NotificationDetails details = NotificationDetails(android: androidDetails);
      await _notificationsPlugin.show(id, title, body, details, payload: payload);
    } catch (_) {}
  }

  /// Launches phone SMS app with pre-filled message using robust multi-stage platform intent fallbacks
  static Future<bool> openSmsApp({required String phone, required String body}) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    
    // Attempt 1: Standard Uri with query parameters
    final uri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: body.isNotEmpty ? <String, String>{'body': body} : null,
    );
    try {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // Attempt 2: Direct launch (bypasses Android 11+ package visibility checks if canLaunchUrl returned false)
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    // Attempt 3: iOS '&body=' delimiter format
    if (body.isNotEmpty) {
      try {
        final iosUri = Uri.parse('sms:$cleanPhone&body=${Uri.encodeComponent(body)}');
        final ok = await launchUrl(iosUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {}
    }

    // Attempt 4: Android '?sms_body=' format
    if (body.isNotEmpty) {
      try {
        final androidSmsBodyUri = Uri.parse('sms:$cleanPhone?sms_body=${Uri.encodeComponent(body)}');
        final ok = await launchUrl(androidSmsBodyUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {}
    }

    // Attempt 5: Fallback to blank SMS to recipient
    try {
      final plainUri = Uri(scheme: 'sms', path: cleanPhone);
      return await launchUrl(plainUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    return false;
  }

  /// Launches phone Email app with pre-filled subject and body with multi-stage platform fallback
  static Future<bool> openEmailApp({required String email, required String subject, required String body}) async {
    final cleanEmail = email.trim();
    final queryParts = <String>[];
    if (subject.isNotEmpty) {
      queryParts.add('subject=${Uri.encodeComponent(subject)}');
    }
    if (body.isNotEmpty) {
      queryParts.add('body=${Uri.encodeComponent(body)}');
    }
    final queryString = queryParts.isNotEmpty ? '?${queryParts.join('&')}' : '';
    final uri = Uri.parse('mailto:$cleanEmail$queryString');

    // Attempt 1: canLaunchUrl check followed by externalApplication launch
    try {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    // Attempt 2: Direct launch (bypasses Android package visibility restrictions)
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    // Attempt 3: Plain mailto: without query parameters if client fails on params
    try {
      final plainUri = Uri.parse('mailto:$cleanEmail');
      return await launchUrl(plainUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    return false;
  }

  /// Launches Google Maps app with 3D buildings, Satellite, and turn-by-turn navigation
  static Future<bool> openGoogleMaps({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final encodedLabel = Uri.encodeComponent(label ?? 'Malvoya Delivery Pin');
    // 1. Try native Google Maps intent URI
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedLabel)&z=18');
    try {
      if (await canLaunchUrl(geoUri)) {
        return await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 2. Fallback to Google Maps Universal Web Link
    final webMapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(webMapsUri)) {
        return await launchUrl(webMapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  /// Launches phone dialer
  static Future<bool> callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }
}
