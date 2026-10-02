import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../core/strings.dart';
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
  const ProductGallery({super.key, required this.items});

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
    HapticFeedback.selectionClick();
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
      return Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, size: 72, color: AppTheme.primary));
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
            return GestureDetector(
              onTap: _openFullscreen,
              child: CachedNetworkImage(imageUrl: item.image!, fit: BoxFit.cover, width: double.infinity),
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
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _page ? 1 : 0.6), borderRadius: BorderRadius.circular(3)),
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
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
        backgroundColor: Colors.black,
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
                  child: Center(child: CachedNetworkImage(imageUrl: item.image!, fit: BoxFit.contain)),
                );
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  IconButton(
                    tooltip: tr(context, 'Close', 'Sulje'),
                    onPressed: () => Navigator.of(context).pop(_page),
                    icon: const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, color: Colors.white)),
                  ),
                  const Spacer(),
                  if (widget.items.length > 1)
                    Text('${_page + 1} / ${widget.items.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
