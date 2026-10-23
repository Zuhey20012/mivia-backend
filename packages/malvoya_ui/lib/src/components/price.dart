import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// Price sizes.
enum MPriceSize {
  /// 14: list rows, bag lines.
  sm,

  /// 16: product tiles.
  md,

  /// 20: product detail.
  lg,
}

/// A price exactly as the API computed it. A reduction is shown only with a real reference price
/// ([previousCents]: the lowest price of the 30 days before the reduction, Omnibus); the app never
/// computes discounts itself.
///
/// Finnish: "49,90 €", English: "€49.90". Screen readers hear "49,90 €, before 59,90 €".
class MPrice extends StatelessWidget {
  /// Creates a price.
  const MPrice({
    super.key,
    required this.cents,
    this.previousCents,
    this.discountPct,
    this.size = MPriceSize.md,
    this.color,
    this.showReferenceLabel = false,
    this.unitPrice,
    this.prefix,
  });

  /// From an API `pricing` object (`priceCents`, `previousPriceCents`, `discountPct`, `unitPrice`).
  /// [overrideCents] is the price of the chosen option. Null pricing draws nothing.
  static Widget fromPricing(Map<String, dynamic>? pricing, {Key? key, int? overrideCents, MPriceSize size = MPriceSize.md, Color? color, bool showReferenceLabel = false}) {
    final cents = overrideCents ?? asInt(pricing?['priceCents']);
    if (cents == null) return const SizedBox.shrink();
    return MPrice(
      key: key,
      cents: cents,
      previousCents: asInt(pricing?['previousPriceCents']),
      discountPct: asInt(pricing?['discountPct']),
      size: size,
      color: color,
      showReferenceLabel: showReferenceLabel,
      unitPrice: overrideCents == null ? UnitPrice.fromJson(pricing?['unitPrice']) : null,
    );
  }

  /// The price to pay, in cents.
  final int cents;

  /// The Omnibus reference price, when the API sent one.
  final int? previousCents;

  /// The API's discount percentage (shown in a sunshine badge).
  final int? discountPct;

  /// Size.
  final MPriceSize size;

  /// Text colour (defaults to body ink; reductions use the sale colour).
  final Color? color;

  /// Explain the reference price under it.
  final bool showReferenceLabel;

  /// Shown under the price ([MUnitPrice]).
  final UnitPrice? unitPrice;

  /// Text before the amount ("from ").
  final String? prefix;

  double get _fontSize => switch (size) {
        MPriceSize.sm => 14,
        MPriceSize.md => 16,
        MPriceSize.lg => 20,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final reduced = previousCents != null;
    final now = '${prefix ?? ''}${euro(context, cents)}';
    final before = reduced ? euro(context, previousCents) : null;
    final fs = _fontSize;
    final main = size == MPriceSize.lg
        ? MType.displayS.copyWith(fontSize: fs, color: reduced ? c.sale : (color ?? c.onSurface))
        : MType.bodyL.copyWith(fontSize: fs, fontWeight: FontWeight.w800, height: 1.25, color: reduced ? c.sale : (color ?? c.onSurface));
    final spoken = before == null ? now : tr(context, '$now, before $before', '$now, ennen $before');

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(now, style: main),
              if (before != null)
                Text(before, style: MType.bodyM.copyWith(fontSize: fs * 0.78, color: c.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
              if (discountPct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: c.sunshine, borderRadius: MRadius.brXs),
                  child: Text('−$discountPct %', style: MType.label.copyWith(fontSize: fs * 0.64 < 11 ? 11 : fs * 0.64, color: c.onSunshine, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          if (reduced && showReferenceLabel)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr(context, 'Lowest price in the 30 days before the reduction', 'Alin hinta alennusta edeltäneiden 30 päivän aikana'),
                style: MType.caption.copyWith(fontSize: 11, color: c.onSurfaceVariant),
              ),
            ),
          if (unitPrice != null) MUnitPrice(unitPrice!),
        ],
      ),
    );
  }
}

/// The unit price under a price: "178,00 €/l" / "€18.00/kg" (Price Indication Directive). Always
/// computed from the price actually charged; show it whenever the API sends one.
class MUnitPrice extends StatelessWidget {
  /// Shows [unitPrice].
  const MUnitPrice(this.unitPrice, {super.key});

  /// Computes the unit price for [priceCents] and the content ([amount] [unit]: ml, g or pcs);
  /// draws nothing when none is needed.
  static Widget forContent(int? priceCents, num? amount, String? unit, {Key? key}) {
    final u = UnitPrice.compute(priceCents, amount, unit);
    return u == null ? const SizedBox.shrink() : MUnitPrice(u, key: key);
  }

  /// The value.
  final UnitPrice unitPrice;

  @override
  Widget build(BuildContext context) {
    final text = unitPrice.format(languageCode: isFinnish(context) ? 'fi' : 'en');
    final spoken = unitPrice.per == 'l'
        ? tr(context, '${euro(context, unitPrice.cents)} per litre', '${euro(context, unitPrice.cents)} litralta')
        : tr(context, '${euro(context, unitPrice.cents)} per kilogram', '${euro(context, unitPrice.cents)} kilolta');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Semantics(
        label: spoken,
        excludeSemantics: true,
        child: Text(text, style: MType.caption.copyWith(color: context.mColors.onSurfaceVariant)),
      ),
    );
  }
}
