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

  // Rooms are per connection, so they are joined again after every reconnect
  final Set<int> _trackedOrders = {};
  final Set<int> _chats = {};

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
      for (final id in _trackedOrders) {
        _socket?.emit('track:order', id);
      }
      for (final id in _chats) {
        _socket?.emit('chat:join', id);
      }
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
      if (data is Map) onCourierLocationUpdate?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('order:status', (data) {
      if (data is Map) onOrderStatusUpdate?.call(Map<String, dynamic>.from(data));
      notifyListeners();
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) onChatMessage?.call(Map<String, dynamic>.from(data));
    });
  }

  /// Order ids must be the numeric id (the server ignores anything else).
  void trackOrder(int orderId) {
    _trackedOrders.add(orderId);
    _socket?.emit('track:order', orderId);
  }

  void joinChat(int orderId) {
    _chats.add(orderId);
    _socket?.emit('chat:join', orderId);
  }

  void sendChatMessage(int orderId, String message, String senderName) {
    _socket?.emit('chat:send', {'orderId': orderId, 'text': message, 'sender': senderName});
  }

  void stopTracking(int orderId) {
    _trackedOrders.remove(orderId);
    _chats.remove(orderId);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _trackedOrders.clear();
    _chats.clear();
    onCourierLocationUpdate = null;
    onOrderStatusUpdate = null;
    onChatMessage = null;
    notifyListeners();
  }
}
