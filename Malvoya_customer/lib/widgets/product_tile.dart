import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../core/strings.dart';
import '../screens/product_detail.dart';
import 'price_tag.dart';

/// Grid tile used by search, store pages and favourites.
class ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? storeName;

  const ProductTile({super.key, required this.product, this.storeName});

  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List?)?.cast<String>() ?? const [];
    final inStock = product['inStock'] != false;
    final hasVideo = ((product['videos'] as List?) ?? const []).isNotEmpty;
    final store = storeName ?? product['store']?['name'];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: asInt(product['id'])!)));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk)),
                  if (images.isNotEmpty)
                    CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 180))
                  else
                    Icon(Icons.checkroom_outlined, size: 44, color: AppTheme.clayInk.withValues(alpha: 0.8)),
                  if (hasVideo)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.play_arrow_rounded, color: AppTheme.ink, size: 14),
                          const SizedBox(width: 2),
                          Text(tr(context, 'Video', 'Video'), style: const TextStyle(color: AppTheme.ink, fontSize: 11, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  if (!inStock)
                    Container(
                      color: Colors.white.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.ink, borderRadius: BorderRadius.circular(14)),
                        child: Text(tr(context, 'Sold out', 'Loppuunmyyty'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product['name'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.primaryText(context)),
          ),
          if (store != null && '$store'.isNotEmpty)
            Text(store, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context))),
          const SizedBox(height: 2),
          PriceTag(pricing: product['pricing'] as Map<String, dynamic>?, size: 14),
        ],
      ),
    );
  }
}
