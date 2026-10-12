import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../auth_service.dart';
import 'api_client.dart';

/// Push notifications for order, delivery and payout updates (never marketing).
///
/// The phone's push token is sent to Malvoya only while someone is signed in, and it is
/// removed again on sign-out. Permission is asked right after sign-in, not at first launch.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// Called when the user taps a notification. `data` holds e.g. {type: order, orderId: 12}.
  void Function(Map<String, dynamic> data)? onOpen;

  static const _channel = AndroidNotificationChannel(
    'orders', // the backend sends every push on this channel
    'Orders and deliveries',
    description: 'Updates about your orders, deliveries and payouts',
    importance: Importance.high,
  );

  /// Loud channel for new and waiting orders (the server sends those pushes here too).
  static const _newOrders = AndroidNotificationChannel(
    'new_orders',
    'New orders',
    description: 'Rings until you accept or decline a new order',
    importance: Importance.max,
  );
  static const _alarmId = 9001;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ringing = false;
  AuthService? _auth;
  String? _token;
  int? _registeredFor;
  bool _started = false;

  Future<void> attach(AuthService auth) async {
    if (_auth != null) return;
    _auth = auth;
    auth.addListener(_onAuthChanged);
    AuthService.beforeLogout.add(_unregister);
    await _start();
    _onAuthChanged();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload == null) return;
          try {
            onOpen?.call(Map<String, dynamic>.from(jsonDecode(r.payload!)));
          } catch (_) {}
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_newOrders);

      FirebaseMessaging.onMessage.listen(_showWhileOpen);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _registeredFor = null;
        _onAuthChanged();
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        Future.delayed(const Duration(milliseconds: 900), () => onOpen?.call(initial.data));
      }
    } catch (e) {
      debugPrint('Push unavailable: $e');
    }
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;
    final userId = auth.isAuthenticated ? auth.currentUser?.id : null;
    if (userId == null) {
      _registeredFor = null;
      return;
    }
    if (_registeredFor != userId) _register(auth, userId);
  }

  Future<void> _register(AuthService auth, int userId) async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      _token ??= await FirebaseMessaging.instance.getToken();
      if (_token == null) return;
      final res = await ApiClient(auth).post('/me/devices', {
        'token': _token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      if (res.ok) _registeredFor = userId;
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _unregister(AuthService auth) async {
    final token = _token;
    _registeredFor = null;
    if (token == null || !auth.isAuthenticated) return;
    await ApiClient(auth).delete('/me/devices', {'token': token});
  }

  /// Like a shop tablet: keeps ringing (the phone's own notification sound, repeated by Android's
  /// "insistent" flag) until every paid order is accepted or declined, or the alert is tapped.
  Future<void> ringNewOrders(int waiting) async {
    if (waiting <= 0) return stopRinging();
    if (_ringing) return;
    _ringing = true;
    try {
      await _local.show(
        _alarmId,
        waiting == 1 ? 'New order waiting' : '$waiting new orders waiting',
        'Accept or decline in Malvoya Store. / Hyväksy tai hylkää Malvoya Storessa.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _newOrders.id,
            _newOrders.name,
            channelDescription: _newOrders.description,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            icon: '@mipmap/launcher_icon',
            ongoing: true,
            autoCancel: true,
            additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT: repeat the sound
          ),
          iOS: const DarwinNotificationDetails(presentSound: true, interruptionLevel: InterruptionLevel.timeSensitive),
        ),
        payload: jsonEncode({'type': 'orders'}),
      );
    } catch (e) {
      _ringing = false;
      debugPrint('New-order alert failed: $e');
    }
  }

  Future<void> stopRinging() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _local.cancel(_alarmId);
    } catch (_) {}
  }

  /// Android does not show notifications for an app that is open, so show them ourselves.
  void _showWhileOpen(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      m.messageId.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(m.data),
    );
  }
}
