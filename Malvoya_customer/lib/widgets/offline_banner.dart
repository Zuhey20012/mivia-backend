import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/network_status.dart';

/// A slim notice at the top of every screen while the phone is offline, and a short "back online"
/// when the connection returns. It pushes the app down a little instead of covering it, and
/// never blocks taps.
class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final _net = NetworkStatus.instance;
  bool _offline = false;
  bool _backOnline = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _offline = !_net.online;
    _net.addListener(_onChange);
  }

  @override
  void dispose() {
    _net.removeListener(_onChange);
    _hide?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final offline = !_net.online;
    if (offline == _offline) return;
    _hide?.cancel();
    setState(() {
      _backOnline = _offline && !offline;
      _offline = offline;
    });
    if (_backOnline) {
      _hide = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _backOnline = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _offline || _backOnline;
    final topInset = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: visible ? _bar(context, topInset) : const SizedBox(width: double.infinity),
        ),
        Expanded(
          // While the banner is showing it already covers the status bar area
          child: MediaQuery.removePadding(context: context, removeTop: visible, child: widget.child),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, double topInset) {
    final color = _offline ? AppTheme.sunshine : AppTheme.mint;
    final ink = _offline ? AppTheme.ink : AppTheme.moss;
    final text = _offline
        ? tr(context, 'No internet connection. We will reconnect automatically.', 'Ei internetyhteyttä. Yhdistämme automaattisesti, kun yhteys palaa.')
        : tr(context, 'Back online', 'Yhteys palasi');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: color,
          child: Padding(
            padding: EdgeInsets.fromLTRB(MSpace.lg, topInset + 6, MSpace.lg, MSpace.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_offline ? Icons.wifi_off_rounded : Icons.wifi_rounded, size: 16, color: ink),
                const SizedBox(width: MSpace.sm),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: ink, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
