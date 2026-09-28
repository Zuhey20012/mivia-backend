import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/strings.dart';

/// Shows a product's price exactly as the API computed it. A reduction is only shown when the
/// API sends a real reference price: the lowest price of the 30 days before the reduction.
class PriceTag extends StatelessWidget {
  final Map<String, dynamic>? pricing;
  final int? overrideCents; // price of the chosen size/colour
  final double size;
  final Color? color;
  final bool showReferenceLabel;

  const PriceTag({
    super.key,
    required this.pricing,
    this.overrideCents,
    this.size = 16,
    this.color,
    this.showReferenceLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final price = overrideCents ?? asInt(pricing?['priceCents']);
    final previous = asInt(pricing?['previousPriceCents']);
    final pct = asInt(pricing?['discountPct']);
    final main = color ?? AppTheme.primaryText(context);
    if (price == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              euro(context, price),
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: previous != null ? const Color(0xFFC2412D) : main),
            ),
            if (previous != null)
              Text(
                euro(context, previous),
                style: TextStyle(
                  fontSize: size * 0.78,
                  color: AppTheme.secondaryText(context),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            if (pct != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFC2412D), borderRadius: BorderRadius.circular(6)),
                child: Text('−$pct %', style: TextStyle(color: Colors.white, fontSize: size * 0.62, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        if (previous != null && showReferenceLabel)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              tr(context, 'Lowest price in the 30 days before the reduction', 'Alin hinta alennusta edeltäneiden 30 päivän aikana'),
              style: TextStyle(fontSize: 11, color: AppTheme.secondaryText(context)),
            ),
          ),
      ],
    );
  }
}
