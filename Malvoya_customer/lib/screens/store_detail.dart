import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import '../config/constants.dart';
import '../cart.dart';
import '../models.dart';
import '../checkout.dart';
import '../config/theme.dart';
import '../l10n.dart';

class StoreDetailScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreDetailScreen({super.key, required this.store});

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  List products = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/stores/${widget.store['id']}/products'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          products = data['products'] ?? [];
          loading = false;
        });
      } else {
        if (mounted) setState(() => loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onProductTapped(Map<String, dynamic> product) {
    HapticFeedback.lightImpact();
    final variants = (product['variants'] as List?) ?? [];
    if (variants.isNotEmpty) {
      _showProductVariantSheet(product, variants);
    } else {
      _confirmAndAddToCart(
        product: product,
        variantId: null,
        variantLabel: null,
        priceCents: product['salePriceCents'] ?? product['rentalDayCents'] ?? 0,
      );
    }
  }

  void _showProductVariantSheet(Map<String, dynamic> product, List variants) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int selectedIndex = 0;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final cardBg = AppTheme.cardBackground(context);
            final textPrimary = AppTheme.primaryText(context);
            final borderColor = AppTheme.cardBorder(context);
            final l10n = AppLocalizations.of(context);

            final activeVariant = variants[selectedIndex];
            final priceAdjust = (activeVariant['priceAdjustCents'] ?? 0) as int;
            final basePrice = (product['salePriceCents'] ?? product['rentalDayCents'] ?? 0) as int;
            final currentTotalCents = basePrice + priceAdjust;
            final stock = (activeVariant['stock'] ?? product['stockQuantity'] ?? 1) as int;
            final isOutOfStock = stock <= 0;

            return Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: borderColor, width: 1.5)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.store['name'] ?? 'Boutique',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                product['name'] ?? 'Artisan Piece',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '€${(currentTotalCents / 100.0).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.translate('selectSizeAndFit'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(variants.length, (i) {
                        final v = variants[i];
                        final isSelected = selectedIndex == i;
                        final vStock = (v['stock'] ?? 1) as int;
                        final vOutOfStock = vStock <= 0;
                        final label = v['size'] ?? v['color'] ?? 'Standard';

                        return GestureDetector(
                          onTap: vOutOfStock
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => selectedIndex = i);
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary
                                  : (vOutOfStock
                                      ? Colors.grey.withValues(alpha: 0.1)
                                      : cardBg),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : (vOutOfStock
                                        ? Colors.grey.shade300
                                        : borderColor),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (vOutOfStock
                                        ? Colors.grey.shade400
                                        : textPrimary),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                decoration: vOutOfStock ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    // Live Stock Indicator
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOutOfStock
                                ? Colors.red
                                : (stock <= 3 ? const Color(0xFFE08A00) : const Color(0xFF248A52)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOutOfStock
                              ? l10n.translate('outOfStockSize')
                              : (stock <= 3
                                  ? '${l10n.translate('onlyLeft')} $stock ${l10n.translate('leftInStock')}'
                                  : l10n.translate('inStockReady')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isOutOfStock
                                ? Colors.red
                                : (stock <= 3 ? const Color(0xFFE08A00) : const Color(0xFF248A52)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: isOutOfStock ? Colors.grey.shade400 : AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: isOutOfStock
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                final chosenVariant = variants[selectedIndex];
                                final sizeStr = chosenVariant['size'] ?? chosenVariant['color'] ?? 'Standard';
                                _confirmAndAddToCart(
                                  product: product,
                                  variantId: chosenVariant['id'],
                                  variantLabel: 'Size $sizeStr',
                                  priceCents: currentTotalCents,
                                );
                              },
                        child: Text(
                          isOutOfStock ? l10n.translate('soldOut') : '${l10n.translate('addToBag')} • €${(currentTotalCents / 100.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmAndAddToCart({
    required Map<String, dynamic> product,
    required int? variantId,
    required String? variantLabel,
    required int priceCents,
  }) {
    final cart = Provider.of<CartService>(context, listen: false);
    final storeId = widget.store['id'] as int?;
    final storeName = widget.store['name'] ?? 'Boutique';

    // Malvoya Single-Merchant Basket Protection Check
    if (!cart.canAddDirectly(storeId)) {
      HapticFeedback.heavyImpact();
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(AppLocalizations.of(context).translate('startNewBasket'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: Text(
            AppLocalizations.of(context).translate('differentBoutiqueWarning'),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(AppLocalizations.of(context).translate('cancel'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _executeAddToCart(
                  cart: cart,
                  product: product,
                  variantId: variantId,
                  variantLabel: variantLabel,
                  priceCents: priceCents,
                  storeId: storeId,
                  storeName: storeName,
                  forceClear: true,
                );
              },
              child: Text(AppLocalizations.of(context).translate('startNewBag'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      return;
    }

    _executeAddToCart(
      cart: cart,
      product: product,
      variantId: variantId,
      variantLabel: variantLabel,
      priceCents: priceCents,
      storeId: storeId,
      storeName: storeName,
      forceClear: false,
    );
  }

  void _executeAddToCart({
    required CartService cart,
    required Map<String, dynamic> product,
    required int? variantId,
    required String? variantLabel,
    required int priceCents,
    required int? storeId,
    required String storeName,
    required bool forceClear,
  }) {
    HapticFeedback.mediumImpact();
    cart.add(
      CartItem(
        productId: product['id'],
        variantId: variantId,
        storeId: storeId,
        storeName: storeName,
        name: product['name'],
        variantLabel: variantLabel,
        price: priceCents / 100.0,
      ),
      forceClear: forceClear,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']}${variantLabel != null ? ' ($variantLabel)' : ''} added to bag'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'VIEW BAG',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
          },
        ),
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final priceCents = product['salePriceCents'] ?? product['rentalDayCents'] ?? 0;
    final price = priceCents / 100.0;
    final cardBg = AppTheme.cardBackground(context);
    final borderColor = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    
    return GestureDetector(
      onTap: () => _onProductTapped(product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(19)),
              ),
              child: const Icon(Icons.checkroom_rounded, size: 44, color: AppTheme.primary),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Product',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product['description'] ?? product['category'] ?? '',
                      style: TextStyle(color: textSecondary, fontSize: 12, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '€${price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primary, fontSize: 16),
                        ),
                        ElevatedButton(
                          onPressed: () => _onProductTapped(product),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.primaryText(context);

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 220.0,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.store['name'] ?? 'Store',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
                  ),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF6366F1), AppTheme.primary],
                      ),
                    ),
                    child: const Center(child: Icon(Icons.storefront_rounded, size: 72, color: Colors.white24)),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Collections & Drops',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                      Text(
                        '${products.length} Items',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.secondaryText(context)),
                      ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (products.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        const Text('No drops listed yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Check back soon for new studio collections.', style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildProductItem(products[index]),
                      childCount: products.length,
                    ),
                  ),
                ),
            ],
          ),

          // Malvoya Reactive Floating Bag Bar
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Consumer<CartService>(
              builder: (ctx, cart, _) {
                if (cart.items.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: AppTheme.irisFuchsiaGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${cart.itemCount}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '€${cart.total.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context).translate('viewBag'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
