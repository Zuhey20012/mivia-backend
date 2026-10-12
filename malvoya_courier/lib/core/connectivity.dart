import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import 'strings.dart';

/// Knows whether the phone can reach the internet right now.
///
/// The system tells us when the network changes; a quick DNS lookup of the API host then confirms
/// that the network really reaches the internet (a Wi-Fi without internet counts as offline).
/// While offline it checks again every few seconds. [onRestored] fires each time the connection
/// comes back, so screens can refresh what they show.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  bool _online = true;
  bool _started = false;
  int _check = 0;
  Timer? _retry;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _restored = StreamController<void>.broadcast();

  bool get isOnline => _online;

  /// Fires when the connection comes back after being lost.
  Stream<void> get onRestored => _restored.stream;

  void start() {
    if (_started) return;
    _started = true;
    _sub = Connectivity().onConnectivityChanged.listen(_onNetwork, onError: (_) {});
    Connectivity().checkConnectivity().then(_onNetwork, onError: (_) {});
  }

  void _onNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      _check++; // a check still running must not flip us back online
      _set(false);
    } else {
      verify();
    }
  }

  /// Confirms whether the internet is reachable. Also called when a request fails to connect.
  Future<void> verify() async {
    final check = ++_check;
    final ok = await _reachable();
    if (check == _check) _set(ok);
  }

  static Future<bool> _reachable() async {
    try {
      final host = Uri.parse(AppConstants.apiBase).host;
      final found = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      return found.isNotEmpty && found.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _set(bool online) {
    _retry?.cancel();
    if (!online) _retry = Timer(const Duration(seconds: 8), verify);
    if (online == _online) return;
    _online = online;
    notifyListeners();
    if (online) _restored.add(null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    _restored.close();
    super.dispose();
  }
}

/// A slim "No internet" strip above the whole app; it slides away when the connection is back.
class OfflineBanner extends StatelessWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final service = ConnectivityService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final offline = !service.isOnline;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: offline
                  ? Material(
                      color: const Color(0xFF17131C),
                      child: SafeArea(
                        bottom: false,
                        child: Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(children: [
                              const Icon(Icons.wifi_off_rounded, size: 18, color: AppTheme.sunshine),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  tr(context, 'No internet. We will update as soon as you are back online.',
                                      'Ei internetyhteyttä. Päivitämme heti, kun yhteys palaa.'),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // The strip already covers the status bar, so the app below must not pad for it again
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: offline, child: child)),
          ],
        );
      },
    );
  }
}
