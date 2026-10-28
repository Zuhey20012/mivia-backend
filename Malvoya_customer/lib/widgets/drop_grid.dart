import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
import 'app_image.dart';

/// The still picture of a drop: a video's poster, or a photo drop's first photo.
String? dropPosterUrl(Map<String, dynamic> drop) {
  final media = drop['media'];
  if (media is! Map) return null;
  if (media['poster'] is String) return media['poster'] as String;
  final images = media['images'];
  if (images is List && images.isNotEmpty && images.first is String) return images.first as String;
  return media['image'] is String ? media['image'] as String : null;
}

/// One drop in a 3-column grid (a sound's drops, saved drops): its picture in 9:16 with the like count.
class DropPosterTile extends StatelessWidget {
  final Map<String, dynamic> drop;
  final VoidCallback onTap;
  const DropPosterTile({super.key, required this.drop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = dropPosterUrl(drop);
    final store = drop['store'] is Map ? (drop['store'] as Map)['name']?.toString() : null;
    final product = drop['product'] is Map ? (drop['product'] as Map)['name']?.toString() : null;
    final likes = asInt(drop['likeCount']) ?? 0;
    return Semantics(
      button: true,
      label: [
        drop['kind'] == 'VIDEO' ? tr(context, 'Video', 'Video') : tr(context, 'Photos', 'Kuvat'),
        if (product != null && product.isNotEmpty) product,
        if (store != null && store.isNotEmpty) store,
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MRadius.sm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: MPalette.night.withValues(alpha: 0.12)),
              if (poster != null) AppImage(poster),
              if (drop['kind'] == 'VIDEO')
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_arrow_rounded, color: AppTheme.onMedia, size: 22, shadows: [Shadow(blurRadius: 8, color: MPalette.scrim)]),
                ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Row(children: [
                  const Icon(Icons.favorite_rounded, color: AppTheme.onMedia, size: 14, shadows: [Shadow(blurRadius: 8, color: MPalette.scrim)]),
                  const SizedBox(width: 3),
                  Text('$likes',
                      style: const TextStyle(
                          color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 8, color: MPalette.scrim)])),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A paged 3-column grid of drops from one API list (`{drops, nextCursor}`), under optional header slivers.
/// Tapping a drop calls [onOpen] with everything loaded so far, so the reel can continue the same list.
class PagedDropGrid extends StatefulWidget {
  final String path;
  final List<Widget> header;
  final Widget empty;

  /// Opens the reel; when the returned future completes the grid loads again if [reloadOnReturn].
  final Future<void> Function(List<Map<String, dynamic>> drops, String? cursor, int dropId) onOpen;
  final bool reloadOnReturn;

  /// Also called on pull-to-refresh (e.g. to reload a header).
  final Future<void> Function()? onRefresh;

  const PagedDropGrid({
    super.key,
    required this.path,
    required this.empty,
    required this.onOpen,
    this.header = const [],
    this.reloadOnReturn = false,
    this.onRefresh,
  });

  @override
  State<PagedDropGrid> createState() => _PagedDropGridState();
}

class _PagedDropGridState extends State<PagedDropGrid> {
  final List<Map<String, dynamic>> _drops = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || _cursor == null)) return;
    if (reset) {
      setState(() {
        _error = null;
        if (_drops.isEmpty) _loading = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final auth = Provider.of<AuthService>(context, listen: false);
    final res = await ApiClient(auth).get(widget.path, query: {
      'limit': '24',
      if (!reset && _cursor != null) 'cursor': _cursor!,
      ...DeliveryLocation.instance.query,
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (!res.ok) {
        if (reset) _error = res.errorText(context);
        return;
      }
      final incoming = ((res.data['drops'] as List?) ?? []).whereType<Map>().map((d) => Map<String, dynamic>.from(d)).toList();
      if (reset) _drops.clear();
      incoming.removeWhere((d) => _drops.any((x) => asInt(x['id']) == asInt(d['id'])));
      _drops.addAll(incoming);
      _cursor = res.data['nextCursor']?.toString();
    });
  }

  Future<void> _open(int dropId) async {
    await widget.onOpen(List.of(_drops), _cursor, dropId);
    if (mounted && widget.reloadOnReturn) _load(reset: true);
  }

  Future<void> _refresh() async {
    await Future.wait([_load(reset: true), if (widget.onRefresh != null) widget.onRefresh!()]);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
    } else if (_error != null && _drops.isEmpty) {
      body = SliverFillRemaining(hasScrollBody: false, child: MStateMessage.error(message: _error!, scrollable: false, onRetry: () => _load(reset: true)));
    } else if (_drops.isEmpty) {
      body = SliverFillRemaining(hasScrollBody: false, child: widget.empty);
    } else {
      body = SliverPadding(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.x4l),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 9 / 16),
          delegate: SliverChildBuilderDelegate(
            (_, i) => DropPosterTile(drop: _drops[i], onTap: () => _open(asInt(_drops[i]['id'])!)),
            childCount: _drops.length,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _load();
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ...widget.header,
            body,
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.only(bottom: MSpace.x4l), child: Center(child: CircularProgressIndicator())),
              ),
          ],
        ),
      ),
    );
  }
}
