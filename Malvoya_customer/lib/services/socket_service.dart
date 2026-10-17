import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/constants.dart';

typedef SocketEventListener = void Function(Map<String, dynamic> data);

/// Recent chat messages of an order, from the server's answer to `chat:join` (newer servers).
typedef ChatHistoryListener = void Function(int orderId, List<Map<String, dynamic>> messages);

/// One shared Socket.io connection for the customer app. Several screens can listen at the same
/// time (the Orders tab and an open order, for example): listeners are added and removed, never
/// overwritten, and order rooms are reference-counted so one screen closing does not stop
/// another screen's updates.
class CustomerSocketService extends ChangeNotifier {
  static final CustomerSocketService _instance = CustomerSocketService._internal();
  factory CustomerSocketService() => _instance;
  CustomerSocketService._internal();

  io.Socket? _socket;
  String? _token;
  bool _connected = false;
  bool get isConnected => _connected;

  // Rooms are per connection, so they are joined again after every reconnect
  final Map<int, int> _trackedOrders = {};
  final Map<int, int> _chats = {};

  final List<SocketEventListener> _locationListeners = [];
  final List<SocketEventListener> _statusListeners = [];
  final List<SocketEventListener> _chatListeners = [];
  final List<VoidCallback> _reconnectListeners = [];
  final List<ChatHistoryListener> _historyListeners = [];

  void addChatHistoryListener(ChatHistoryListener l) => _historyListeners.add(l);
  void removeChatHistoryListener(ChatHistoryListener l) => _historyListeners.remove(l);

  /// Joins an order's chat room. Newer servers answer with the recent messages; older ones do
  /// not answer at all, which is fine.
  void _emitJoinChat(io.Socket socket, int orderId) {
    socket.emitWithAck('chat:join', orderId, ack: (dynamic data) {
      final raw = data is List && data.isNotEmpty && data.first is Map ? data.first : data;
      final list = raw is Map ? (raw['messages'] ?? raw['history']) : raw;
      if (list is! List) return;
      final messages = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      for (final l in List<ChatHistoryListener>.of(_historyListeners)) {
        try {
          l(orderId, messages);
        } catch (e) {
          debugPrint('[CustomerSocket] history listener error: $e');
        }
      }
    });
  }

  void addCourierLocationListener(SocketEventListener l) => _locationListeners.add(l);
  void removeCourierLocationListener(SocketEventListener l) => _locationListeners.remove(l);
  void addOrderStatusListener(SocketEventListener l) => _statusListeners.add(l);
  void removeOrderStatusListener(SocketEventListener l) => _statusListeners.remove(l);
  void addChatListener(SocketEventListener l) => _chatListeners.add(l);
  void removeChatListener(SocketEventListener l) => _chatListeners.remove(l);

  /// Called after the connection comes back, so screens can catch up on events they missed.
  void addReconnectListener(VoidCallback l) => _reconnectListeners.add(l);
  void removeReconnectListener(VoidCallback l) => _reconnectListeners.remove(l);

  static void _dispatch(List<SocketEventListener> listeners, dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    for (final l in List<SocketEventListener>.of(listeners)) {
      try {
        l(map);
      } catch (e) {
        debugPrint('[CustomerSocket] listener error: $e');
      }
    }
  }

  /// Connects with the current access token. Safe to call often: an existing connection is
  /// kept, and a dropped one is rebuilt with the fresh token (the old one may have expired).
  void connect(String accessToken) {
    if (accessToken.isEmpty) return;
    if (_socket != null && (_connected || accessToken == _token)) return;
    _closeSocket();
    _token = accessToken;

    final baseUrl = AppConstants.apiBase.replaceAll('/api/v1', '');
    final socket = io.io(
        baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': accessToken})
            .enableForceNew()
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(2000)
            .build());
    _socket = socket;
    var connectedBefore = false;

    socket.onConnect((_) {
      _connected = true;
      for (final id in _trackedOrders.keys) {
        socket.emit('track:order', id);
      }
      for (final id in _chats.keys) {
        _emitJoinChat(socket, id);
      }
      if (connectedBefore) {
        for (final l in List<VoidCallback>.of(_reconnectListeners)) {
          l();
        }
      }
      connectedBefore = true;
      notifyListeners();
    });

    socket.onDisconnect((_) {
      _connected = false;
      debugPrint('[CustomerSocket] Disconnected');
      notifyListeners();
    });

    socket.onConnectError((err) {
      debugPrint('[CustomerSocket] Connection error: $err');
      _connected = false;
    });

    socket.on('courier:location', (data) => _dispatch(_locationListeners, data));
    socket.on('order:status', (data) => _dispatch(_statusListeners, data));
    socket.on('chat:message', (data) => _dispatch(_chatListeners, data));
  }

  /// Order ids must be the numeric id (the server ignores anything else).
  void trackOrder(int orderId) {
    final first = !_trackedOrders.containsKey(orderId);
    _trackedOrders[orderId] = (_trackedOrders[orderId] ?? 0) + 1;
    if (first) _socket?.emit('track:order', orderId);
  }

  void stopTracking(int orderId) {
    final n = (_trackedOrders[orderId] ?? 0) - 1;
    if (n <= 0) {
      _trackedOrders.remove(orderId);
    } else {
      _trackedOrders[orderId] = n;
    }
  }

  void joinChat(int orderId) {
    final first = !_chats.containsKey(orderId);
    _chats[orderId] = (_chats[orderId] ?? 0) + 1;
    final socket = _socket;
    if (first && socket != null) _emitJoinChat(socket, orderId);
  }

  void leaveChat(int orderId) {
    final n = (_chats[orderId] ?? 0) - 1;
    if (n <= 0) {
      _chats.remove(orderId);
    } else {
      _chats[orderId] = n;
    }
  }

  /// Sends over the live connection. Returns false when there is none (then send it over HTTP).
  bool sendChatMessage(int orderId, String message, String senderName) {
    final socket = _socket;
    if (socket == null || !_connected) return false;
    socket.emit('chat:send', {'orderId': orderId, 'text': message, 'sender': senderName});
    return true;
  }

  void _closeSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _token = null;
    _connected = false;
  }

  /// Ends the connection (sign-out). Listeners stay registered: they belong to screens, which
  /// remove them when they close.
  void disconnect() {
    _closeSocket();
    _trackedOrders.clear();
    _chats.clear();
    notifyListeners();
  }
}
