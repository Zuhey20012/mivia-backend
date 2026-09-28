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
    final store = storeName ?? product['store']?['name'];

    return GestureDetector(
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
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppTheme.primary.withValues(alpha: 0.06)),
                  if (images.isNotEmpty)
                    CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 180))
                  else
                    const Icon(Icons.checkroom_rounded, size: 40, color: AppTheme.primary),
                  if (!inStock)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Text(tr(context, 'Sold out', 'Loppuunmyyty'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
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
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryText(context)),
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
