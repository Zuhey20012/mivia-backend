import 'dart:async';
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

  /// A customer asked to return something (socket `return:new`, API 2.10). The payload is whatever the
  /// server sends (e.g. returnId, orderId); listeners refresh from the API rather than trusting it.
  final StreamController<Map<String, dynamic>> _returnsNew = StreamController.broadcast();
  Stream<Map<String, dynamic>> get returnsNew => _returnsNew.stream;

  /// Live shopping events (API 2.15): `live:viewers`, `live:likes`, `live:message`, `live:message_hidden`,
  /// `live:pinned` and `live:ended`, for the live screen. Kept apart from [notifyListeners], which the
  /// dashboard treats as "orders may have changed".
  final StreamController<LiveSocketEvent> _live = StreamController.broadcast();
  Stream<LiveSocketEvent> get liveEvents => _live.stream;

  static const _liveEventNames = ['live:viewers', 'live:likes', 'live:message', 'live:message_hidden', 'live:pinned', 'live:ended'];

  final List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> get pendingOrders => List.unmodifiable(_pendingOrders);

  void connect(String accessToken) {
    if (_socket != null && _connected) return;

    final baseUrl = AppConstants.apiBase.replaceAll('/api/v1', '');
    _socket = io.io(baseUrl, io.OptionBuilder()
        .setTransports(['websocket'])
        // A fresh manager each time, so a new sign-in token is really used (the client caches sockets per host)
        .enableForceNew()
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

    _socket!.on('return:new', (data) {
      debugPrint('[VendorSocket] New return request');
      _returnsNew.add(data is Map ? Map<String, dynamic>.from(data) : const {});
    });

    for (final name in _liveEventNames) {
      _socket!.on(name, (data) => _live.add(LiveSocketEvent(name, data is Map ? Map<String, dynamic>.from(data) : const {})));
    }

    // Listen for order status changes
    _socket!.on('order:status', (data) {
      debugPrint('[VendorSocket] Order status update: $data');
      notifyListeners();
    });
  }

  /// After the internet comes back: reconnect with the current token if the live connection is down
  /// (automatic reconnection gives up after 10 tries and would reuse an expired token).
  void ensureConnected(String accessToken) {
    if (_socket != null && _connected) return;
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }
    connect(accessToken);
  }

  void joinStoreRoom(dynamic storeId) {
    _socket?.emit('track:store', storeId);
    debugPrint('[VendorSocket] Joined store room: store:$storeId');
  }

  /// Sends [event] and waits for the server's answer (its first argument, as a map). Null when the
  /// connection is down or no answer came within [timeout], so callers never assume it worked.
  Future<Map<String, dynamic>?> emitWithAck(String event, Object data, {Duration timeout = const Duration(seconds: 8)}) {
    final socket = _socket;
    if (socket == null || !_connected) return Future.value(null);
    final done = Completer<Map<String, dynamic>?>();
    socket.emitWithAck(event, data, ack: (dynamic answer, [dynamic _]) {
      if (done.isCompleted) return;
      done.complete(answer is Map ? Map<String, dynamic>.from(answer) : <String, dynamic>{});
    });
    return done.future.timeout(timeout, onTimeout: () => null);
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

/// One live-shopping socket event: its [name] (e.g. `live:viewers`) and payload.
class LiveSocketEvent {
  final String name;
  final Map<String, dynamic> data;
  const LiveSocketEvent(this.name, this.data);
}
