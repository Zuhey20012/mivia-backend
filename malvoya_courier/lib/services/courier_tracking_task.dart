import 'dart:async';
import 'package:flutter/foundation.dart';
import 'courier_telemetry_service.dart';

/// Android Background Courier Telemetry Task Handler
/// Manages background execution, velocity-dependent transmission throttles,
/// and integration with the real GPS telemetry service.
class CourierTelemetryHandler {
  static final CourierTelemetryHandler _instance = CourierTelemetryHandler._internal();
  factory CourierTelemetryHandler() => _instance;
  CourierTelemetryHandler._internal();

  Timer? _periodicTimer;
  dynamic _activeOrderId;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  dynamic get activeOrderId => _activeOrderId;

  /// Dynamic transmission frequency calculated from speed (m/s)
  /// Fast movement (> 20 km/h) = 1.5s interval; urban transit = 3.0s interval; idle = 8.0s
  Duration calculateDynamicInterval(double speedMps) {
    if (speedMps > 5.5) {
      return const Duration(milliseconds: 1500);
    } else if (speedMps > 1.0) {
      return const Duration(seconds: 3);
    } else {
      return const Duration(seconds: 8);
    }
  }

  /// Starts background telemetry task with order context
  Future<void> onStart({required dynamic orderId, required String authToken}) async {
    _activeOrderId = orderId;
    _isRunning = true;

    final service = CourierTelemetryService();
    await service.startLiveBroadcast(orderId: orderId, accessToken: authToken);

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      onRepeatEvent();
    });

    if (kDebugMode) {
      print('⚡ CourierTelemetryHandler: Started background tracking for order #$orderId');
    }
  }

  /// Periodic telemetry tick event
  Future<void> onRepeatEvent() async {
    if (!_isRunning) return;

    final service = CourierTelemetryService();
    final lastPoint = service.lastPoint;
    if (lastPoint != null) {
      final interval = calculateDynamicInterval(lastPoint.speed);
      if (_periodicTimer?.tick != null && _periodicTimer!.tick % 10 == 0) {
        if (kDebugMode) {
          print(
            '📍 CourierTelemetryHandler Ping: Lat ${lastPoint.latitude.toStringAsFixed(4)}, '
            'Lng ${lastPoint.longitude.toStringAsFixed(4)}, Heading ${lastPoint.bearing.toStringAsFixed(1)}°, '
            'Interval ${interval.inMilliseconds}ms',
          );
        }
      }
    }
  }

  /// Clean teardown on delivery completion or courier going offline
  Future<void> onDestroy() async {
    _isRunning = false;
    _activeOrderId = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;

    final service = CourierTelemetryService();
    service.stopBroadcast();

    if (kDebugMode) {
      print('🛑 CourierTelemetryHandler: Terminated background tracking task');
    }
  }
}
