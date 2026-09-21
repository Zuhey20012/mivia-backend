import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

class VendorSocketService extends ChangeNotifier {
  static final VendorSocketService _instance = VendorSocketService._internal();
  factory VendorSocketService() => _instance;
  VendorSocketService._internal();

  io.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  final List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> get pendingOrders => List.unmodifiable(_pendingOrders);

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
      debugPrint('[VendorSocket] Connected');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('[VendorSocket] Disconnected');
      notifyListeners();
    });

    _socket!.onConnectError((err) {
      debugPrint('[VendorSocket] Connection error: $err');
      _connected = false;
    });

    // Listen for new orders
    _socket!.on('order:new', (data) {
      debugPrint('[VendorSocket] New order received: $data');
      if (data is Map<String, dynamic>) {
        _pendingOrders.insert(0, data);
      }
      notifyListeners();
    });

    // Listen for order status changes
    _socket!.on('order:status', (data) {
      debugPrint('[VendorSocket] Order status update: $data');
      notifyListeners();
    });
  }

  void joinStoreRoom(dynamic storeId) {
    _socket?.emit('track:store', storeId);
    debugPrint('[VendorSocket] Joined store room: store:$storeId');
  }

  void clearPendingOrder(int index) {
    if (index >= 0 && index < _pendingOrders.length) {
      _pendingOrders.removeAt(index);
      notifyListeners();
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _pendingOrders.clear();
    notifyListeners();
  }
}
