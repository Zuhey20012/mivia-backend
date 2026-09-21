import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'socket_service.dart';

class TelemetryPoint {
  final double latitude;
  final double longitude;
  final double bearing;
  final double speed;
  final double accuracy;
  final DateTime timestamp;
  final dynamic orderId;

  TelemetryPoint({
    required this.latitude,
    required this.longitude,
    this.bearing = 0,
    this.speed = 0,
    this.accuracy = 0,
    DateTime? timestamp,
    this.orderId,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'bearing': bearing,
    'speed': speed,
    'accuracy': accuracy,
    'timestamp': timestamp.toIso8601String(),
    'orderId': orderId,
  };
}

class CourierTelemetryService extends ChangeNotifier {
  static final CourierTelemetryService _instance = CourierTelemetryService._internal();
  factory CourierTelemetryService() => _instance;
  CourierTelemetryService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _httpTransmitTimer;
  bool _isBroadcasting = false;
  bool get isBroadcasting => _isBroadcasting;

  TelemetryPoint? _lastPoint;
  TelemetryPoint? get lastPoint => _lastPoint;

  dynamic _activeOrderId;
  String? _accessToken;

  final List<TelemetryPoint> _offlineBuffer = [];

  Future<bool> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[Telemetry] Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[Telemetry] Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[Telemetry] Location permission permanently denied');
      return false;
    }

    return true;
  }

  Future<void> startLiveBroadcast({dynamic orderId, String? accessToken}) async {
    if (_isBroadcasting) return;

    final hasPermission = await _checkPermissions();
    if (!hasPermission) return;

    _activeOrderId = orderId;
    _accessToken = accessToken ?? _accessToken;
    _isBroadcasting = true;
    notifyListeners();

    // Stream real GPS positions
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // meters - only update when moved 5m
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _lastPoint = TelemetryPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        bearing: position.heading,
        speed: position.speed,
        accuracy: position.accuracy,
        orderId: _activeOrderId,
      );

      // Emit via Socket.io for real-time customer tracking
      CourierSocketService().emitTelemetry(_lastPoint!.toJson());
      notifyListeners();
    }, onError: (e) {
      debugPrint('[Telemetry] GPS stream error: $e');
    });

    // Also transmit via HTTP every 5 seconds as backup
    _httpTransmitTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _transmitViaHttp();
    });

    debugPrint('[Telemetry] Live broadcast started (real GPS)');
  }

  Future<void> _transmitViaHttp() async {
    if (_lastPoint == null || _accessToken == null) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/courier/telemetry'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode(_lastPoint!.toJson()),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Flush any offline buffer
        if (_offlineBuffer.isNotEmpty) {
          _flushOfflineBuffer();
        }
      }
    } catch (e) {
      // Buffer for offline resilience
      if (_lastPoint != null && _offlineBuffer.length < 50) {
        _offlineBuffer.add(_lastPoint!);
      }
      debugPrint('[Telemetry] HTTP transmit failed, buffered: $e');
    }
  }

  Future<void> _flushOfflineBuffer() async {
    if (_offlineBuffer.isEmpty || _accessToken == null) return;
    final batch = List<TelemetryPoint>.from(_offlineBuffer);
    _offlineBuffer.clear();

    for (final point in batch) {
      try {
        await http.post(
          Uri.parse('${AppConstants.apiBase}/courier/telemetry'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_accessToken',
          },
          body: jsonEncode(point.toJson()),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    debugPrint('[Telemetry] Flushed ${batch.length} buffered points');
  }

  void stopBroadcast() {
    _positionStream?.cancel();
    _positionStream = null;
    _httpTransmitTimer?.cancel();
    _httpTransmitTimer = null;
    _isBroadcasting = false;
    _activeOrderId = null;
    _lastPoint = null;
    notifyListeners();
    debugPrint('[Telemetry] Broadcast stopped');
  }

  @override
  void dispose() {
    stopBroadcast();
    super.dispose();
  }
}
