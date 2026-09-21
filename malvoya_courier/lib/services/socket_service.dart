import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

class CourierSocketService extends ChangeNotifier {
  static final CourierSocketService _instance = CourierSocketService._internal();
  factory CourierSocketService() => _instance;
  CourierSocketService._internal();

  io.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  final List<Map<String, dynamic>> _dispatchOffers = [];
  List<Map<String, dynamic>> get dispatchOffers => List.unmodifiable(_dispatchOffers);

  Function(Map<String, dynamic>)? onNewDispatchOffer;

  void connect(String accessToken) {
    if (_socket != null && _connected) return;

    final baseUrl = AppConstants.apiBase.replaceAll('/api/v1', '');
    _socket = io.io(baseUrl, io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': accessToken})
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(10)
        .setReconnectionDelay(2000)
        .build());

    _socket!.onConnect((_) {
      _connected = true;
      debugPrint('[CourierSocket] Connected');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('[CourierSocket] Disconnected');
      notifyListeners();
    });

    _socket!.onConnectError((err) {
      debugPrint('[CourierSocket] Connection error: $err');
      _connected = false;
    });

    // Listen for dispatch offers
    _socket!.on('courier:dispatch_offer', (data) {
      debugPrint('[CourierSocket] Dispatch offer: $data');
      if (data is Map<String, dynamic>) {
        _dispatchOffers.insert(0, data);
        onNewDispatchOffer?.call(data);
      }
      notifyListeners();
    });

    // Listen for order status changes on active deliveries
    _socket!.on('order:status', (data) {
      debugPrint('[CourierSocket] Order status update: $data');
      notifyListeners();
    });
  }

  void emitTelemetry(Map<String, dynamic> telemetryData) {
    _socket?.emit('courier:telemetry', telemetryData);
  }

  void trackOrder(dynamic orderId) {
    _socket?.emit('track:order', orderId);
    debugPrint('[CourierSocket] Tracking order: $orderId');
  }

  void clearOffer(int index) {
    if (index >= 0 && index < _dispatchOffers.length) {
      _dispatchOffers.removeAt(index);
      notifyListeners();
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _dispatchOffers.clear();
    notifyListeners();
  }
}
