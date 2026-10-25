import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../cart.dart';
import '../checkout.dart';
import '../models.dart';
import 'app_image.dart';
import 'product_info.dart';

String _amount(dynamic n) => n is num ? (n == n.roundToDouble() ? '${n.toInt()}' : '$n') : '';

/// "M · Black", "02 Sand", "50 ml": the option as the customer chose it (also on the bag line).
String variantLabel(Map v) {
  final unit = v['contentUnit'];
  final content = v['contentAmount'] is num && (unit == 'ml' || unit == 'g') ? '${_amount(v['contentAmount'])} $unit' : null;
  return <String>{
    for (final x in [v['size'], v['color'], v['shadeName'], content])
      if (x != null && '$x'.trim().isNotEmpty) '$x'.trim(),
  }.join(' · ');
}

List<Map<String, dynamic>> productVariants(Map<String, dynamic> product) =>
    ((product['variants'] as List?) ?? const []).whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();

/// Shade products: every option has a swatch colour (API 2.12 `shadeHex`).
bool isShadeProduct(List<Map<String, dynamic>> variants) => variants.isNotEmpty && variants.every((v) => MSwatchOption.fromVariant(v) != null);

/// The option picker: swatches for shades ([MSwatchPicker]), size tiles otherwise ([MSizeSelector])
/// with sold-out options crossed out and an optional "Size guide" link.
Widget optionPicker(
  BuildContext context, {
  required List<Map<String, dynamic>> variants,
  required int? selectedId,
  required ValueChanged<int> onChanged,
  VoidCallback? onSizeGuide,
}) {
  if (isShadeProduct(variants)) {
    return MSwatchPicker(
      options: [for (final v in variants) MSwatchOption.fromVariant(v)!],
      selectedId: selectedId?.toString(),
      onChanged: (id) => onChanged(int.parse(id)),
    );
  }
  final onlySizes = variants.every((v) => '${v['size'] ?? ''}'.isNotEmpty && '${v['color'] ?? ''}'.isEmpty && '${v['shadeName'] ?? ''}'.isEmpty);
  final onlyColours = variants.every((v) => '${v['color'] ?? ''}'.isNotEmpty && '${v['size'] ?? ''}'.isEmpty);
  final onlyContent = variants.every((v) => v['contentAmount'] is num && '${v['size'] ?? ''}'.isEmpty && '${v['color'] ?? ''}'.isEmpty);
  return MSizeSelector(
    label: onlySizes || onlyContent ? tr(context, 'Size', 'Koko') : (onlyColours ? tr(context, 'Colour', 'Väri') : tr(context, 'Option', 'Vaihtoehto')),
    options: [
      for (final v in variants)
        if (asInt(v['id']) != null) MSizeOption(id: '${asInt(v['id'])}', label: variantLabel(v), soldOut: v['inStock'] != true),
    ],
    selectedId: selectedId?.toString(),
    onChanged: (id) => onChanged(int.parse(id)),
    onSizeGuide: onSizeGuide,
  );
}

/// The price of the product or the chosen option, with the unit price of that option. The
/// Omnibus reference price belongs to the product's own price, so it is shown only when the
/// option costs the same.
Widget productPrice(Map<String, dynamic> product, Map<String, dynamic>? variant, {MPriceSize size = MPriceSize.md, bool showReferenceLabel = false}) {
  final pricing = product['pricing'] is Map ? Map<String, dynamic>.from(product['pricing']) : const <String, dynamic>{};
  final base = asInt(pricing['priceCents']);
  final chosen = asInt(variant?['priceCents']);
  final cents = chosen ?? base;
  if (cents == null) return const SizedBox.shrink();
  final same = chosen == null || chosen == base;
  return MPrice(
    cents: cents,
    previousCents: same ? asInt(pricing['previousPriceCents']) : null,
    discountPct: same ? asInt(pricing['discountPct']) : null,
    size: size,
    showReferenceLabel: showReferenceLabel,
    unitPrice: UnitPrice.fromJson(variant != null ? variant['unitPrice'] : product['unitPrice']),
  );
}

/// Choose a size/colour/shade and add the product to the bag. Returns true when something was
/// added. A product without options is added straight away (no sheet) unless it is hygiene-sealed,
/// which always shows the seal notice first.
Future<bool> showAddToBagSheet(BuildContext context, Map<String, dynamic> product, {Map<String, dynamic>? store}) async {
  Haptics.selection();
  final shop = store ?? (product['store'] as Map?)?.cast<String, dynamic>();
  final variants = product['variants'];
  // Only when the payload says so: a product sent without its options still gets the sheet
  if (variants is List && variants.isEmpty && product['inStock'] != false && product['hygieneSealed'] != true && product['recall'] == null && asInt(product['id']) != null) {
    return addProductToBag(context, product, store: shop);
  }
  final added = await showMSheet<bool>(context, builder: (_) => _AddToBagSheet(product: product, store: shop), transparent: true, isScrollControlled: true, useSafeArea: false);
  return added == true;
}

/// One order comes from one store: asks before a bag from another store is replaced.
/// Returns null when the customer keeps their bag, otherwise whether the bag must be cleared.
Future<bool?> confirmBagStore(BuildContext context, int? storeId) async {
  final cart = Provider.of<CartService>(context, listen: false);
  if (cart.canAddDirectly(storeId)) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(context, 'Start a new bag?', 'Aloitetaanko uusi ostoskassi?')),
      content: Text(tr(
        context,
        'Your bag has items from ${cart.storeName ?? 'another store'}. One order comes from one store, so starting a new bag removes them.',
        'Kassissasi on tuotteita kaupasta ${cart.storeName ?? 'toinen kauppa'}. Yksi tilaus tulee yhdestä kaupasta, joten uusi kassi poistaa ne.',
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep my bag', 'Pidä kassi'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'New bag', 'Uusi kassi'))),
      ],
    ),
  );
  return ok == true ? true : null;
}

/// Adds a product (and the chosen option) to the bag, asking first if the bag is from another store.
Future<bool> addProductToBag(BuildContext context, Map<String, dynamic> product, {Map<String, dynamic>? store, Map<String, dynamic>? variant}) async {
  final storeId = asInt(store?['id'] ?? product['storeId'] ?? product['store']?['id']);
  final clear = await confirmBagStore(context, storeId);
  if (clear == null || !context.mounted) return false;
  final price = asInt(variant?['priceCents']) ?? asInt(product['pricing']?['priceCents']) ?? 0;
  final images = (product['images'] as List?)?.cast<String>() ?? const [];
  Haptics.light();
  Provider.of<CartService>(context, listen: false).add(
    CartItem(
      productId: asInt(product['id'])!,
      variantId: asInt(variant?['id']),
      storeId: storeId,
      storeName: (store?['name'] ?? product['store']?['name'] ?? '').toString(),
      name: '${product['name'] ?? ''}',
      variantLabel: variant == null ? null : variantLabel(variant),
      imageUrl: images.isNotEmpty ? images.first : null,
      price: price / 100.0,
    ),
    forceClear: clear,
  );
  return true;
}

/// "Added to your bag" with a shortcut to the bag.
void showAddedToBag(BuildContext context) {
  final navigator = Navigator.of(context);
  MSnack.show(
    context,
    tr(context, 'Added to your bag', 'Lisätty ostoskassiin'),
    kind: MSnackKind.success,
    actionLabel: tr(context, 'View bag', 'Näytä ostoskassi'),
    onAction: () => navigator.push(MaterialPageRoute(builder: (_) => const CheckoutPage())),
  );
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

  List<Map<String, dynamic>> get _variants => productVariants(widget.product);

  Map<String, dynamic>? get _selected => _variants.where((v) => asInt(v['id']) == _variantId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final inStock = _variants.where((v) => v['inStock'] == true).toList();
    if (inStock.length == 1) _variantId = asInt(inStock.first['id']);
  }

  Future<void> _add() async {
    final added = await addProductToBag(context, widget.product, store: widget.store, variant: _selected);
    if (added && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final p = widget.product;
    final images = (p['images'] as List?)?.cast<String>() ?? const [];
    final variants = _variants;
    final needsChoice = variants.isNotEmpty;
    final chosen = _selected;
    final recalled = p['recall'] != null;
    final inStock = !recalled && p['inStock'] != false && (!needsChoice || variants.any((v) => v['inStock'] == true));
    final canAdd = inStock && (!needsChoice || (chosen != null && chosen['inStock'] == true));
    final isPrivate = (widget.store?['sellerType'] ?? p['store']?['sellerType']) == 'PRIVATE';
    final shades = isShadeProduct(variants);

    return MSheet(
      handle: true,
      padding: EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.xl + MediaQuery.of(context).viewPadding.bottom),
      actions: [
        MButton(
          expand: true,
          size: MButtonSize.lg,
          icon: Icons.shopping_bag_outlined,
          onPressed: canAdd ? _add : null,
          label: !inStock
              ? tr(context, 'Sold out', 'Loppuunmyyty')
              : (needsChoice && chosen == null)
                  ? (shades ? tr(context, 'Choose a shade', 'Valitse sävy') : tr(context, 'Choose an option', 'Valitse vaihtoehto'))
                  : tr(context, 'Add to bag', 'Lisää kassiin'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: MSpace.sm),
          Row(
            children: [
              ClipRRect(
                borderRadius: MRadius.brMd,
                child: SizedBox(
                  width: 64,
                  height: 80,
                  child: images.isEmpty
                      ? Container(color: context.mPastels.clay, child: Icon(Icons.checkroom_outlined, color: context.mPastels.clayInk))
                      : AppImage(images.first),
                ),
              ),
              const SizedBox(width: MSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] ?? '', style: MType.title.copyWith(color: c.onSurface)),
                    if (widget.store?['name'] != null) Text(widget.store!['name'], style: MType.label.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    const SizedBox(height: MSpace.xs),
                    productPrice(p, chosen),
                  ],
                ),
              ),
            ],
          ),
          if (needsChoice) ...[
            const SizedBox(height: MSpace.xl),
            optionPicker(
              context,
              variants: variants,
              selectedId: _variantId,
              onChanged: (id) => setState(() => _variantId = id),
              onSizeGuide: hasSizeGuide(p) ? () => showSizeGuideSheet(context, p) : null,
            ),
            if (shades)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.xs),
                child: Text(tr(context, 'Colours vary by screen.', 'Näytön värit voivat poiketa.'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
              ),
          ],
          if (p['hygieneSealed'] == true) ...[
            const SizedBox(height: MSpace.lg),
            HygieneSealNotice(product: p),
          ],
          const SizedBox(height: MSpace.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isPrivate ? Icons.person_outline_rounded : Icons.verified_outlined, size: 18, color: c.onSurfaceVariant),
              const SizedBox(width: MSpace.sm),
              Expanded(
                child: Text(
                  isPrivate
                      ? tr(context, 'Sold by a private person. The 14-day consumer right of withdrawal applies to purchases from businesses only.',
                          'Myyjä on yksityishenkilö. Kuluttajan 14 päivän peruuttamisoikeus koskee vain yrityksiltä ostettuja tuotteita.')
                      : p['hygieneSealed'] == true
                          ? tr(context, 'Sold by a business. Unopened, you can return it within 14 days of delivery.', 'Myyjä on yritys. Avaamattoman tuotteen voit palauttaa 14 päivän kuluessa toimituksesta.')
                          : tr(context, 'Sold by a business. You can return it within 14 days of delivery.', 'Myyjä on yritys. Voit palauttaa tuotteen 14 päivän kuluessa toimituksesta.'),
                  style: MType.caption.copyWith(color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
