import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

/// Live connection for job offers, order updates and chat with the customer.
class CourierSocketService extends ChangeNotifier {
  static final CourierSocketService _instance = CourierSocketService._internal();
  factory CourierSocketService() => _instance;
  CourierSocketService._internal();

  io.Socket? _socket;
  bool _connected = false;
  bool get isConnected => _connected;

  // Rooms are per connection, so they are joined again after every reconnect
  final Set<int> _orders = {};

  void Function(Map<String, dynamic>)? onDispatchOffer;
  void Function(Map<String, dynamic>)? onOrderStatus;
  void Function(Map<String, dynamic>)? onChatMessage;

  void connect(String accessToken) {
    if (_socket != null) return;
    final baseUrl = AppConstants.apiBase.replaceAll('/api/v1', '');
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .build(),
    );
    _socket!.onConnect((_) {
      _connected = true;
      for (final id in _orders) {
        _socket?.emit('track:order', id);
        _socket?.emit('chat:join', id);
      }
      notifyListeners();
    });
    _socket!.onDisconnect((_) {
      _connected = false;
      notifyListeners();
    });
    _socket!.on('courier:dispatch_offer', (data) {
      if (data is Map) onDispatchOffer?.call(Map<String, dynamic>.from(data));
      notifyListeners();
    });
    _socket!.on('order:status', (data) {
      if (data is Map) onOrderStatus?.call(Map<String, dynamic>.from(data));
      notifyListeners();
    });
    _socket!.on('chat:message', (data) {
      if (data is Map) onChatMessage?.call(Map<String, dynamic>.from(data));
    });
  }

  void emitTelemetry(Map<String, dynamic> data) => _socket?.emit('courier:telemetry', data);

  /// Follow an order the courier is carrying (status updates and chat).
  void trackOrder(int orderId) {
    _orders.add(orderId);
    _socket?.emit('track:order', orderId);
    _socket?.emit('chat:join', orderId);
  }

  void sendChat(int orderId, String text, String senderName) =>
      _socket?.emit('chat:send', {'orderId': orderId, 'text': text, 'sender': senderName});

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _orders.clear();
    notifyListeners();
  }
}
