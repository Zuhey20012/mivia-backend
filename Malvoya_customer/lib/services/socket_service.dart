import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

class CustomerSocketService extends ChangeNotifier {
  static final CustomerSocketService _instance = CustomerSocketService._internal();
  factory CustomerSocketService() => _instance;
  CustomerSocketService._internal();

  io.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  // Callbacks for real-time events
  Function(Map<String, dynamic>)? onCourierLocationUpdate;
  Function(Map<String, dynamic>)? onOrderStatusUpdate;
  Function(Map<String, dynamic>)? onChatMessage;

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
      debugPrint('[CustomerSocket] Connected');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('[CustomerSocket] Disconnected');
      notifyListeners();
    });

    _socket!.onConnectError((err) {
      debugPrint('[CustomerSocket] Connection error: $err');
      _connected = false;
    });

    // Listen for live courier GPS
    _socket!.on('courier:location', (data) {
      debugPrint('[CustomerSocket] Courier location: $data');
      if (data is Map<String, dynamic>) {
        onCourierLocationUpdate?.call(data);
      }
      notifyListeners();
    });

    // Listen for order status changes
    _socket!.on('order:status', (data) {
      debugPrint('[CustomerSocket] Order status: $data');
      if (data is Map<String, dynamic>) {
        onOrderStatusUpdate?.call(data);
      }
      notifyListeners();
    });

    // Listen for chat messages
    _socket!.on('chat:message', (data) {
      debugPrint('[CustomerSocket] Chat message: $data');
      if (data is Map<String, dynamic>) {
        onChatMessage?.call(data);
      }
      notifyListeners();
    });
  }

  void trackOrder(dynamic orderId) {
    _socket?.emit('track:order', orderId);
    debugPrint('[CustomerSocket] Tracking order: $orderId');
  }

  void joinChat(dynamic orderId) {
    _socket?.emit('chat:join', orderId);
    debugPrint('[CustomerSocket] Joined chat for order: $orderId');
  }

  void sendChatMessage(dynamic orderId, String message, String senderRole) {
    _socket?.emit('chat:send', {
      'orderId': orderId,
      'message': message,
      'sender': senderRole,
    });
  }

  void stopTracking() {
    // Socket.io rooms are automatically left on disconnect
    debugPrint('[CustomerSocket] Stopped tracking');
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    onCourierLocationUpdate = null;
    onOrderStatusUpdate = null;
    onChatMessage = null;
    notifyListeners();
  }
}
