import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../cart.dart';
import '../config/theme.dart';
import '../core/strings.dart';
import '../models.dart';
import 'price_tag.dart';

String variantLabel(Map v) => [v['size'], v['color']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

/// Choose a size/colour and add the product to the bag. Returns true when something was added.
Future<bool> showAddToBagSheet(BuildContext context, Map<String, dynamic> product, {Map<String, dynamic>? store}) async {
  HapticFeedback.selectionClick();
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToBagSheet(product: product, store: store ?? (product['store'] as Map?)?.cast<String, dynamic>()),
  );
  return added == true;
}

class _AddToBagSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? store;
  const _AddToBagSheet({required this.product, this.store});

  @override
  State<_AddToBagSheet> createState() => _AddToBagSheetState();
}

class _AddToBagSheetState extends State<_AddToBagSheet> {
  int? _variantId;

  List<Map<String, dynamic>> get _variants =>
      ((widget.product['variants'] as List?) ?? []).map((v) => Map<String, dynamic>.from(v)).toList();

  Map<String, dynamic>? get _selected {
    for (final v in _variants) {
      if (asInt(v['id']) == _variantId) return v;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final inStock = _variants.where((v) => v['inStock'] == true).toList();
    if (inStock.length == 1) _variantId = asInt(inStock.first['id']);
  }

  void _add() {
    final cart = Provider.of<CartService>(context, listen: false);
    final storeId = asInt(widget.store?['id'] ?? widget.product['storeId']);
    final storeName = (widget.store?['name'] ?? '').toString();
    final chosen = _selected;
    final price = asInt(chosen?['priceCents']) ?? asInt(widget.product['pricing']?['priceCents']) ?? 0;
    final images = (widget.product['images'] as List?)?.cast<String>() ?? const [];

    void doAdd({bool clear = false}) {
      HapticFeedback.mediumImpact();
      cart.add(
        CartItem(
          productId: asInt(widget.product['id'])!,
          variantId: asInt(chosen?['id']),
          storeId: storeId,
          storeName: storeName,
          name: widget.product['name'] ?? '',
          variantLabel: chosen == null ? null : variantLabel(chosen),
          imageUrl: images.isNotEmpty ? images.first : null,
          price: price / 100.0,
        ),
        forceClear: clear,
      );
      Navigator.pop(context, true);
    }

    if (cart.canAddDirectly(storeId)) return doAdd();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Start a new bag?', 'Aloitetaanko uusi ostoskassi?')),
        content: Text(tr(
          context,
          'Your bag has items from ${cart.storeName ?? 'another store'}. One order comes from one store, so starting a new bag removes them.',
          'Kassissasi on tuotteita kaupasta ${cart.storeName ?? 'toinen kauppa'}. Yksi tilaus tulee yhdestä kaupasta, joten uusi kassi poistaa ne.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Keep my bag', 'Pidä kassi'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              doAdd(clear: true);
            },
            child: Text(tr(context, 'New bag', 'Uusi kassi')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final images = (p['images'] as List?)?.cast<String>() ?? const [];
    final variants = _variants;
    final needsChoice = variants.isNotEmpty;
    final chosen = _selected;
    final inStock = p['inStock'] != false && (!needsChoice || variants.any((v) => v['inStock'] == true));
    final canAdd = inStock && (!needsChoice || (chosen != null && chosen['inStock'] == true));
    final isPrivate = (widget.store?['sellerType'] ?? p['store']?['sellerType']) == 'PRIVATE';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.cardBorder(context), borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 80,
                  child: images.isEmpty
                      ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary))
                      : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] ?? '', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                    if (widget.store?['name'] != null)
                      Text(widget.store!['name'], style: TextStyle(fontSize: 13, color: AppTheme.secondaryText(context))),
                    const SizedBox(height: 4),
                    PriceTag(pricing: p['pricing'] as Map<String, dynamic>?, overrideCents: asInt(chosen?['priceCents']), size: 16),
                  ],
                ),
              ),
            ],
          ),
          if (needsChoice) ...[
            const SizedBox(height: 20),
            Text(tr(context, 'Choose size / colour', 'Valitse koko / väri'),
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: variants.map((v) {
                final id = asInt(v['id']);
                final available = v['inStock'] == true;
                final selected = id == _variantId;
                return ChoiceChip(
                  label: Text(variantLabel(v)),
                  selected: selected,
                  onSelected: available ? (_) => setState(() => _variantId = id) : null,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : (available ? AppTheme.primaryText(context) : AppTheme.secondaryText(context)),
                    decoration: available ? null : TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: AppTheme.primary,
                  showCheckmark: false,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isPrivate ? Icons.person_outline_rounded : Icons.verified_outlined, size: 18, color: AppTheme.secondaryText(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPrivate
                      ? tr(context, 'Sold by a private person. The 14-day consumer right of withdrawal applies to purchases from businesses only.',
                          'Myyjä on yksityishenkilö. Kuluttajan 14 päivän peruuttamisoikeus koskee vain yrityksiltä ostettuja tuotteita.')
                      : tr(context, 'Sold by a business. You can return it within 14 days of delivery.',
                          'Myyjä on yritys. Voit palauttaa tuotteen 14 päivän kuluessa toimituksesta.'),
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: AppTheme.secondaryText(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: canAdd ? _add : null,
              child: Text(
                !inStock
                    ? tr(context, 'Sold out', 'Loppuunmyyty')
                    : (needsChoice && chosen == null)
                        ? tr(context, 'Choose a size', 'Valitse koko')
                        : tr(context, 'Add to bag', 'Lisää kassiin'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
