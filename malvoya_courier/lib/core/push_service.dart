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

  /// Called for every push that arrives while the app is open (e.g. to re-check the approval state).
  void Function(Map<String, dynamic> data)? onReceive;

  static const _channel = AndroidNotificationChannel(
    'orders', // the backend sends every push on this channel
    'Orders and deliveries',
    description: 'Updates about your orders, deliveries and payouts',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
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
          android: AndroidInitializationSettings('@drawable/ic_stat_malvoya'),
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

  /// Android does not show notifications for an app that is open, so show them ourselves.
  /// A job offer is announced once, whether the push or the live connection brings it first.
  void _showWhileOpen(RemoteMessage m) {
    try {
      onReceive?.call(Map<String, dynamic>.from(m.data));
    } catch (_) {}
    final n = m.notification;
    if (n == null) return;
    if (m.data['type'] == 'offer') {
      final id = int.tryParse('${m.data['orderId'] ?? ''}');
      if (id != null) {
        alertOffer(orderId: id, title: n.title ?? '', body: n.body ?? '');
        return;
      }
    }
    _local.show(m.messageId.hashCode, n.title, n.body, _details(), payload: jsonEncode(m.data));
  }

  NotificationDetails _details({bool onlyAlertOnce = false}) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_malvoya',
          onlyAlertOnce: onlyAlertOnce,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  // Offers already announced in this session (order ids)
  final Set<int> _announcedOffers = {};

  static int _offerNotificationId(int orderId) => 700000 + orderId % 1000000;

  /// A new job offer while the app is open: the phone's own notification sound, once per offer.
  /// Returns false if this offer was already announced (by the push or the live connection).
  Future<bool> alertOffer({required int orderId, required String title, required String body}) async {
    if (!_announcedOffers.add(orderId)) return false;
    try {
      await _local.show(_offerNotificationId(orderId), title, body, _details(onlyAlertOnce: true),
          payload: jsonEncode({'type': 'offer', 'orderId': '$orderId'}));
    } catch (e) {
      debugPrint('Offer notification failed: $e');
    }
    return true;
  }

  /// The offer was taken, accepted or withdrawn: remove its notification.
  void clearOffer(int orderId) {
    try {
      _local.cancel(_offerNotificationId(orderId));
    } catch (_) {}
  }
}
