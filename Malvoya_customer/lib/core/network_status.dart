import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone has a network connection. Screens listen to it to retry automatically when
/// the connection comes back; [OfflineBanner] shows a small notice while it is gone.
///
/// It only knows whether a network interface is up (Wi-Fi, mobile data, ...), not whether
/// Malvoya's server answers; screens still handle their own request errors.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._();
  static final NetworkStatus instance = NetworkStatus._();

  bool _online = true;
  bool get online => _online;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _offlineDelay;

  /// Starts listening. Safe to call more than once.
  Future<void> start() async {
    if (_sub != null) return;
    try {
      final connectivity = Connectivity();
      _sub = connectivity.onConnectivityChanged.listen(_apply, onError: (_) {});
      _apply(await connectivity.checkConnectivity());
    } catch (_) {
      // Plugin unavailable (tests, unsupported platform): assume online and never block anything.
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final up = results.any((r) => r != ConnectivityResult.none);
    if (up) {
      _offlineDelay?.cancel();
      _offlineDelay = null;
      _set(true);
    } else if (_online && _offlineDelay == null) {
      // Switching between Wi-Fi and mobile data briefly reports "none"; don't flash the banner.
      _offlineDelay = Timer(const Duration(milliseconds: 1500), () {
        _offlineDelay = null;
        _set(false);
      });
    }
  }

  void _set(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }
}
