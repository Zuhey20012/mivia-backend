import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../screens/product_detail.dart';
import 'app_image.dart';

/// Grid tile used by search, store pages and favourites.
class ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? storeName;

  /// Called when the tile is opened (search remembers the query that found it).
  final VoidCallback? onOpen;

  const ProductTile({super.key, required this.product, this.storeName, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List?)?.cast<String>() ?? const [];
    final inStock = product['inStock'] != false;
    final hasVideo = ((product['videos'] as List?) ?? const []).isNotEmpty;
    final store = storeName ?? product['store']?['name'];

    // One tag per tile on screen, so the same item shown twice never confuses the photo flight
    final heroTag = 'product-${product['id']}-${identityHashCode(context)}';
    final image = images.isNotEmpty ? images.first : null;
    // The exact photo URL this tile drew (set during layout, read when tapped)
    String? preview;

    return Pressable(
      onTap: () {
        Haptics.selection();
        onOpen?.call();
        // The tile's own copy of the photo is shown while the product page loads its sharper one
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              productId: asInt(product['id'])!,
              heroTag: image == null ? null : heroTag,
              heroImage: image,
              heroPreview: preview,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The photo takes what the text leaves, so large phone text sizes never overflow the tile
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk)),
                  if (image != null)
                    LayoutBuilder(builder: (context, box) {
                      final url = sizedUrlFor(context, image, box.biggest);
                      preview = url;
                      return Hero(
                        tag: heroTag,
                        flightShuttleBuilder: photoShuttle(url),
                        child: AppImage(image),
                      );
                    })
                  else
                    Icon(Icons.checkroom_outlined, size: 44, color: AppTheme.clayInk.withValues(alpha: 0.8)),
                  if (hasVideo)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.xs),
                        decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(MRadius.sm)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_arrow_rounded, color: AppTheme.ink, size: 14),
                          const SizedBox(width: 2),
                          Text(tr(context, 'Video', 'Video'), style: const TextStyle(color: AppTheme.ink, fontSize: MTextSize.caption, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  if (!inStock)
                    Container(
                      color: MPalette.white.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.ink, borderRadius: BorderRadius.circular(14)),
                        child: Text(tr(context, 'Sold out', 'Loppuunmyyty'),
                            style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w800, fontSize: MTextSize.caption)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MSpace.sm),
          Text(
            product['name'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: AppTheme.primaryText(context)),
          ),
          if (store != null && '$store'.isNotEmpty)
            Text(store, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context))),
          const SizedBox(height: 2),
          MPrice.fromPricing(product['pricing'] as Map<String, dynamic>?, size: MPriceSize.sm),
        ],
      ),
    );
  }
}
