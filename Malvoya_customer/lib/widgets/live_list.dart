import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
import '../core/network_status.dart';
import 'app_image.dart';

/// The red "LIVE" pill shown on live streams (list tiles, the live screen, the store avatar in Drops).
class LiveBadge extends StatelessWidget {
  final bool small;
  const LiveBadge({super.key, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 5 : MSpace.sm, vertical: small ? 1 : 3),
        decoration: BoxDecoration(color: MPalette.red, borderRadius: BorderRadius.circular(MRadius.xs)),
        child: Text(
          tr(context, 'LIVE', 'LIVE'),
          style: TextStyle(
            color: AppTheme.onMedia,
            fontWeight: FontWeight.w800,
            fontSize: small ? 9 : MTextSize.caption,
            letterSpacing: 0.6,
          ),
        ),
      );
}

/// "1.2 k" style counts for viewers and hearts.
String compactCount(dynamic n) {
  final v = asInt(n) ?? 0;
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} k';
  return '$v';
}

/// Fetches the stores that are live now near the delivery address (`GET /live`). Null when it failed.
Future<List<Map<String, dynamic>>?> fetchLives(BuildContext context) async {
  final auth = Provider.of<AuthService>(context, listen: false);
  final res = await ApiClient(auth).get('/live', query: DeliveryLocation.instance.query);
  if (!res.ok) return null;
  return ((res.data['lives'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}

/// The Live mode of the Drops tab: the stores streaming right now near the delivery address, most viewers
/// first. Refreshes every 30 seconds while [active].
class LiveList extends StatefulWidget {
  final bool active;

  /// Space for the Drops top bar and for the tab bar under the list.
  final double topInset;
  final double bottomInset;
  final ValueChanged<Map<String, dynamic>> onOpen;

  /// Every successful refresh, so Drops can mark live stores in the reel.
  final ValueChanged<List<Map<String, dynamic>>>? onLoaded;

  const LiveList({
    super.key,
    required this.active,
    required this.onOpen,
    this.topInset = 0,
    this.bottomInset = 0,
    this.onLoaded,
  });

  @override
  State<LiveList> createState() => _LiveListState();
}

class _LiveListState extends State<LiveList> {
  static const _refreshEvery = Duration(seconds: 30);
  List<Map<String, dynamic>>? _lives;
  String? _error;
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    NetworkStatus.instance.addListener(_onNetwork);
    DeliveryLocation.instance.addListener(_onLocation);
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveList old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    NetworkStatus.instance.removeListener(_onNetwork);
    DeliveryLocation.instance.removeListener(_onLocation);
    super.dispose();
  }

  void _onNetwork() {
    if (mounted && widget.active && NetworkStatus.instance.online && _error != null) _refresh();
  }

  void _onLocation() {
    if (mounted && widget.active) _refresh();
  }

  /// Refreshes at once when the list becomes visible, then every 30 s; stops while hidden.
  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active) return;
    _refresh();
    _timer = Timer.periodic(_refreshEvery, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    final lives = await fetchLives(context);
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (lives != null) {
        _lives = lives;
        _error = null;
      } else if (_lives == null) {
        // Keep showing the last list when a background refresh fails
        _error = tr(context, 'Could not load live streams. Check your connection.', 'Livelähetyksiä ei voitu ladata. Tarkista yhteys.');
      }
    });
    if (lives != null) widget.onLoaded?.call(lives);
  }

  @override
  Widget build(BuildContext context) {
    final lives = _lives;
    if (lives == null && _error == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.onMedia));
    }
    if (lives == null || lives.isEmpty) {
      return _message(
        lives == null ? Icons.wifi_off_rounded : Icons.videocam_off_outlined,
        _error ??
            tr(context, 'No stores are live right now. When a store near you goes live, it shows up here.',
                'Yksikään kauppa ei ole nyt livenä. Kun lähellä oleva kauppa aloittaa liven, se näkyy täällä.'),
        lives == null ? tr(context, 'Try again', 'Yritä uudelleen') : tr(context, 'Refresh', 'Päivitä'),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(MSpace.md, widget.topInset, MSpace.md, widget.bottomInset),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: MSpace.md,
          crossAxisSpacing: MSpace.md,
          childAspectRatio: 0.62,
        ),
        itemCount: lives.length,
        itemBuilder: (_, i) => _LiveTile(live: lives[i], onTap: () => widget.onOpen(lives[i])),
      ),
    );
  }

  Widget _message(IconData icon, String text, String action) => ListView(
        // Scrollable, so pull-to-refresh is not needed but the layout matches the reel's messages
        padding: EdgeInsets.fromLTRB(MSpace.x3l, widget.topInset + MSpace.x3l, MSpace.x3l, widget.bottomInset),
        children: [
          Icon(icon, color: AppTheme.onMedia.withValues(alpha: 0.54), size: 56),
          const SizedBox(height: MSpace.lg),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.onMedia.withValues(alpha: 0.7), fontSize: MTextSize.bodyL, height: 1.4)),
          const SizedBox(height: MSpace.lg),
          Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.onMedia, side: BorderSide(color: MPalette.white.withValues(alpha: 0.38))),
              onPressed: () {
                setState(() {
                  if (_lives == null) _error = null;
                });
                _refresh();
              },
              child: Text(action),
            ),
          ),
        ],
      );
}

class _LiveTile extends StatelessWidget {
  final Map<String, dynamic> live;
  final VoidCallback onTap;
  const _LiveTile({required this.live, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final store = (live['store'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cover = live['cover'] is String ? live['cover'] as String : null;
    final viewers = asInt(live['viewers']) ?? 0;
    final storeName = (store['name'] ?? '').toString();
    final title = (live['title'] ?? '').toString();
    const shadow = [Shadow(blurRadius: 8, color: MPalette.ink)];
    return Semantics(
      button: true,
      label: tr(context, '$storeName is live: $title. $viewers watching', '$storeName on livenä: $title. $viewers katsojaa'),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover != null
                  ? AppImage(cover)
                  : Container(color: MPalette.nightSurface, child: Icon(Icons.videocam_rounded, color: AppTheme.onMedia.withValues(alpha: 0.5), size: 40)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.3, 0.55, 1],
                    colors: [MPalette.mediaScrimSoft, Colors.transparent, Colors.transparent, MPalette.mediaScrim],
                  ),
                ),
              ),
              Positioned(
                left: MSpace.sm,
                top: MSpace.sm,
                right: MSpace.sm,
                child: Row(
                  children: [
                    const LiveBadge(),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: MPalette.night.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(MRadius.xs)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_outlined, size: 13, color: AppTheme.onMedia),
                          const SizedBox(width: 3),
                          Text(compactCount(viewers), style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: MSpace.sm,
                right: MSpace.sm,
                bottom: MSpace.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, height: 1.25, shadows: shadow)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: AppTheme.primaryLight,
                          backgroundImage: store['logoUrl'] is String ? sizedImageProvider(context, store['logoUrl'] as String, 22) : null,
                          child: store['logoUrl'] is String ? null : const Icon(Icons.storefront_rounded, size: 13, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(storeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w600, shadows: shadow)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
