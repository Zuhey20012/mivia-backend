import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
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

  /// Returns false when location is off or permission was refused.
  Future<bool> start({required String accessToken, int? orderId}) async {
    _token = accessToken;
    _orderId = orderId;
    if (_positions != null) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return false;

    // Android: a visible foreground service keeps the position flowing while the phone is in a
    // pocket, and shows the courier at all times that their location is being shared.
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Malvoya Courier is online',
              notificationText: 'Your location is shared while you are online. Go offline to stop.',
              notificationIcon: AndroidResource(name: 'launcher_icon', defType: 'mipmap'),
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
    try {
      await http
          .post(
            Uri.parse('${AppConstants.apiBase}/courier/telemetry'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
            body: jsonEncode({
              'latitude': p.latitude,
              'longitude': p.longitude,
              'bearing': p.heading,
              'speed': p.speed,
              'accuracy': p.accuracy,
              if (_orderId != null) 'orderId': _orderId,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Next tick tries again with a fresher position; old positions are never replayed
    }
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
