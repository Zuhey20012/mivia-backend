import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../core/server_messages.dart';
import 'socket_service.dart';

/// Shares the courier's position while they are online, and only then.
///
/// While carrying an order the position goes live to that order's customer (socket, with an
/// HTTP fallback every 10 s). Between jobs it is sent every 30 s so nearby offers can be
/// ranked. Going offline stops it and the server deletes the stored position.
class CourierTelemetryService extends ChangeNotifier {
  static final CourierTelemetryService _instance = CourierTelemetryService._internal();
  factory CourierTelemetryService() => _instance;
  CourierTelemetryService._internal();

  StreamSubscription<Position>? _positions;
  Timer? _httpTimer;
  Position? _last;
  int? _orderId;
  String? _token;
  DateTime _lastHttp = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isBroadcasting => _positions != null;
  Position? get lastPosition => _last;

  /// Returns false when location is off or permission is missing. It never asks for permission
  /// itself: the dashboard asks only right after the location disclosure (`LocationDisclosure`).
  Future<bool> start({required String accessToken, int? orderId}) async {
    _token = accessToken;
    _orderId = orderId;
    if (_positions != null) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return false;

    // Android: a visible foreground service keeps the position flowing while the phone is in a
    // pocket, and shows the courier at all times that their location is being shared.
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 5),
            // In the app language at the moment sharing starts
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: ServerMessages.pick('Malvoya Courier is online', 'Malvoya Courier on linjoilla'),
              notificationText: ServerMessages.pick('Your location is shared while you are online. Go offline to stop.',
                  'Sijaintisi jaetaan, kun olet linjoilla. Lopeta poistumalla linjoilta.'),
              notificationIcon: const AndroidResource(name: 'ic_stat_malvoya', defType: 'drawable'),
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _positions = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) => debugPrint('GPS error: $e'));
    _httpTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendHttp());
    notifyListeners();
    return true;
  }

  /// The order being carried right now (null between jobs).
  void setActiveOrder(int? orderId) {
    if (_orderId == orderId) return;
    _orderId = orderId;
    if (orderId != null) {
      CourierSocketService().trackOrder(orderId);
      if (_last != null) _onPosition(_last!);
    }
  }

  void updateToken(String? token) => _token = token ?? _token;

  /// The internet is back: send the latest position right away instead of waiting for the next
  /// tick, so the customer sees the courier again within seconds. GPS itself keeps running offline.
  void resume(String? token) {
    updateToken(token);
    if (_positions == null) return;
    _lastHttp = DateTime.fromMillisecondsSinceEpoch(0);
    if (_last != null) _onPosition(_last!);
    _sendHttp();
  }

  void _onPosition(Position p) {
    _last = p;
    if (_orderId != null) {
      CourierSocketService().emitTelemetry({
        'orderId': _orderId,
        'lat': p.latitude,
        'lng': p.longitude,
        'bearing': p.heading,
        'speed': p.speed,
        'accuracy': p.accuracy,
      });
    }
    notifyListeners();
  }

  Future<void> _sendHttp() async {
    final p = _last;
    if (p == null || _token == null) return;
    // Between jobs a position every 30 s is enough; during a delivery every 10 s
    final every = _orderId != null ? const Duration(seconds: 10) : const Duration(seconds: 30);
    if (DateTime.now().difference(_lastHttp) < every) return;
    _lastHttp = DateTime.now();
    await _post(_body(p));
  }

  Map<String, dynamic> _body(Position p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'bearing': p.heading,
        'speed': p.speed,
        'accuracy': p.accuracy,
        if (_orderId != null) 'orderId': _orderId,
      };

  Future<bool> _post(Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AppConstants.apiBase}/courier/telemetry'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 6));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      // Next tick tries again with a fresher position; old positions are never replayed
      return false;
    }
  }

  /// Takes a fresh GPS fix and sends it to the server straight away, waiting for the answer.
  /// Used before actions the server checks against where the courier is (accepting a job,
  /// "I'm at the shop"). [post] lets the caller send it through its session-aware API client.
  /// Only while sharing is on; returns false when no position could be sent.
  Future<bool> sendNow({Future<bool> Function(Map<String, dynamic> body)? post}) async {
    if (_positions == null) return false;
    Position? p;
    try {
      p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      p = _last;
    }
    if (p == null) return false;
    _onPosition(p);
    _lastHttp = DateTime.now();
    final body = _body(p);
    if (post != null) return post(body);
    if (_token == null) return false;
    return _post(body);
  }

  void stop() {
    _positions?.cancel();
    _positions = null;
    _httpTimer?.cancel();
    _httpTimer = null;
    _orderId = null;
    _last = null;
    notifyListeners();
  }
}
