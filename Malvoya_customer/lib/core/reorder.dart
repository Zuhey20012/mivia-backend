import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../cart.dart';
import '../checkout.dart';
import '../models.dart';
import '../widgets/add_to_bag_sheet.dart' show variantLabel;
import 'api_client.dart';
import 'strings.dart';

/// "Order again": puts the items of a past order back in the bag at today's prices, skipping
/// anything sold out or no longer sold, then opens checkout. Nothing is bought without the
/// customer confirming the price there.
Future<void> reorder(BuildContext context, Map<String, dynamic> order) async {
  final api = ApiClient(Provider.of<AuthService>(context, listen: false));
  final cart = Provider.of<CartService>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final storeId = asInt(order['storeId'] ?? order['store']?['id']);
  final storeName = (order['store']?['name'] ?? '').toString();
  final items = ((order['items'] as List?) ?? []).map((i) => Map<String, dynamic>.from(i)).toList();
  if (storeId == null || items.isEmpty) return;

  final ready = <CartItem>[];
  final missing = <String>[];
  var priceChanged = false;
  for (final i in items) {
    final productId = asInt(i['productId'] ?? i['product']?['id']);
    final name = (i['product']?['name'] ?? '').toString();
    if (productId == null) continue;
    final res = await api.get('/products/$productId');
    final p = res.ok ? Map<String, dynamic>.from(res.data['product']) : null;
    if (p == null || p['inStock'] == false) {
      missing.add(name);
      continue;
    }
    final variantId = asInt(i['variantId'] ?? i['variant']?['id']);
    Map<String, dynamic>? variant;
    if (variantId != null) {
      for (final v in (p['variants'] as List? ?? const [])) {
        if (asInt(v['id']) == variantId) variant = Map<String, dynamic>.from(v);
      }
      if (variant == null || variant['inStock'] != true) {
        missing.add(name);
        continue;
      }
    }
    final priceCents = asInt(variant?['priceCents']) ?? asInt(p['pricing']?['priceCents']) ?? 0;
    if (priceCents != asInt(i['unitCents'])) priceChanged = true;
    final images = (p['images'] as List?)?.cast<String>() ?? const [];
    ready.add(CartItem(
      productId: productId,
      variantId: variantId,
      storeId: storeId,
      storeName: storeName,
      name: (p['name'] ?? name).toString(),
      variantLabel: variant == null ? null : variantLabel(variant),
      imageUrl: images.isNotEmpty ? images.first : null,
      price: priceCents / 100.0,
      quantity: asInt(i['quantity']) ?? 1,
    ));
  }

  if (!context.mounted) return;
  if (ready.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(tr(context, 'None of these items are available any more.', 'Mikään näistä tuotteista ei ole enää saatavilla.'))));
    return;
  }
  // One order comes from one store: a bag from another store is replaced (the customer chose this)
  final replace = !cart.canAddDirectly(storeId);
  for (var k = 0; k < ready.length; k++) {
    cart.add(ready[k], forceClear: replace && k == 0);
  }
  final notes = [
    if (missing.isNotEmpty) tr(context, 'Not available any more: ${missing.join(', ')}.', 'Ei enää saatavilla: ${missing.join(', ')}.'),
    if (priceChanged) tr(context, 'Some prices have changed since your last order.', 'Joidenkin tuotteiden hinnat ovat muuttuneet.'),
  ];
  if (notes.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(notes.join(' '))));
  navigator.push(MaterialPageRoute(builder: (_) => const CheckoutPage()));
}
