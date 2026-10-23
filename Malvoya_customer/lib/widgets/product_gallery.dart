import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import 'app_image.dart';
import 'product_video_player.dart';

/// One slide of a product gallery: a photo URL or a video map from the API.
class GalleryItem {
  final String? image;
  final Map<String, dynamic>? video;
  const GalleryItem.image(String this.image) : video = null;
  const GalleryItem.video(Map<String, dynamic> this.video) : image = null;
  bool get isVideo => video != null;

  /// The product's first video opens the gallery (it shows the fit and movement best), then the photos,
  /// then any further videos.
  static List<GalleryItem> forProduct(Map<String, dynamic> product) {
    final images = ((product['images'] as List?) ?? const []).map((e) => '$e').toList();
    final videos = ((product['videos'] as List?) ?? const []).map((v) => Map<String, dynamic>.from(v as Map)).toList();
    return [
      if (videos.isNotEmpty) GalleryItem.video(videos.first),
      for (final url in images) GalleryItem.image(url),
      for (final v in videos.skip(1)) GalleryItem.video(v),
    ];
  }
}

/// Swipeable photos and videos (with sound) on the product page. Tap opens the full-screen viewer.
class ProductGallery extends StatefulWidget {
  final List<GalleryItem> items;

  /// The tile photo that flew in: the first slide carries the same Hero when it is that photo.
  final String? heroTag;
  final String? heroImage;
  final String? heroPreview;
  const ProductGallery({super.key, required this.items, this.heroTag, this.heroImage, this.heroPreview});

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  late final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _openFullscreen() async {
    Haptics.selection();
    final back = await Navigator.of(context).push<int>(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) => FullscreenGallery(items: widget.items, initialPage: _page),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (back != null && back != _page && mounted && _pages.hasClients) _pages.jumpToPage(back);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return Container(
        color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk),
        child: Icon(Icons.checkroom_outlined, size: 96, color: AppTheme.clayInk.withValues(alpha: 0.8)),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pages,
          itemCount: items.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final item = items[i];
            if (item.isVideo) {
              return Stack(fit: StackFit.expand, children: [
                ProductVideoPlayer(video: item.video!, active: i == _page),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: _chip(context, Icons.open_in_full_rounded, tr(context, 'Full screen', 'Koko näyttö'), _openFullscreen),
                ),
              ]);
            }
            final flewIn = i == 0 && widget.heroTag != null && item.image == widget.heroImage;
            Widget photo = AppImage(item.image!, previewUrl: flewIn ? widget.heroPreview : null);
            if (flewIn) {
              photo = Hero(
                tag: widget.heroTag!,
                flightShuttleBuilder: widget.heroPreview == null ? null : photoShuttle(widget.heroPreview!),
                child: photo,
              );
            }
            return Semantics(
              button: true,
              label: tr(context, 'Photo ${i + 1} of ${items.length}. Open full screen', 'Kuva ${i + 1}/${items.length}. Avaa koko näytölle'),
              child: GestureDetector(onTap: _openFullscreen, child: photo),
            );
          },
        ),
        if (items.length > 1)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  items.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: MPalette.white.withValues(alpha: i == _page ? 1 : 0.6), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _chip(BuildContext context, IconData icon, String label, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: AppTheme.scrim, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppTheme.onMedia, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.onMedia, fontSize: MTextSize.caption, fontWeight: FontWeight.w600)),
        ]),
      ),
    );

/// Full-screen photos (pinch to zoom) and videos (with sound), swiped sideways like the inline gallery.
class FullscreenGallery extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialPage;
  const FullscreenGallery({super.key, required this.items, this.initialPage = 0});

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late final PageController _pages = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;
  bool _zoomed = false;
  final Map<int, TransformationController> _zoom = {};

  TransformationController _zoomFor(int i) => _zoom.putIfAbsent(i, () {
        final c = TransformationController();
        // Swiping to the next photo is only allowed while the current one is not zoomed in
        c.addListener(() {
          final zoomed = c.value.getMaxScaleOnAxis() > 1.01;
          if (i == _page && zoomed != _zoomed) setState(() => _zoomed = zoomed);
        });
        return c;
      });

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_page);
      },
      child: Scaffold(
        backgroundColor: MPalette.night,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() {
                _page = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) {
                final item = widget.items[i];
                if (item.isVideo) return ProductVideoPlayer(video: item.video!, active: i == _page, fit: BoxFit.contain);
                return InteractiveViewer(
                  transformationController: _zoomFor(i),
                  minScale: 1,
                  maxScale: 4,
                  // Sharp enough to zoom in on (the server's own size limit still applies)
                  child: Center(
                    child: AppImage(
                      item.image!,
                      fit: BoxFit.contain,
                      requestWidth: 2000,
                      placeholder: Center(child: CircularProgressIndicator(color: AppTheme.onMedia.withValues(alpha: 0.54), strokeWidth: 2)),
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(MSpace.sm),
                child: Row(children: [
                  IconButton(
                    tooltip: tr(context, 'Close', 'Sulje'),
                    onPressed: () => Navigator.of(context).pop(_page),
                    icon: const CircleAvatar(backgroundColor: AppTheme.scrim, child: Icon(Icons.close_rounded, color: AppTheme.onMedia)),
                  ),
                  const Spacer(),
                  if (widget.items.length > 1)
                    Text('${_page + 1} / ${widget.items.length}', style: const TextStyle(color: AppTheme.onMedia, fontWeight: FontWeight.w600)),
                  const SizedBox(width: MSpace.md),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
