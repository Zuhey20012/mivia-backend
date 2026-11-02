import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// "Free delivery from €80 · add €12.50 more", straight from the server's quote
/// (`freeDeliveryThresholdCents`, `amountToFreeDeliveryCents`). Nothing is computed here; without
/// those fields (free delivery off, or an older server) nothing is shown.
class FreeDeliveryHint extends StatelessWidget {
  final Map<String, dynamic> quote;
  const FreeDeliveryHint({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    final threshold = asInt(quote['freeDeliveryThresholdCents']);
    if (threshold == null || threshold <= 0) return const SizedBox.shrink();
    final missing = asInt(quote['amountToFreeDeliveryCents']);
    final reached = missing != null && missing <= 0;
    final String text;
    if (reached) {
      text = tr(context, 'Free delivery: your items are over ${euro(context, threshold)}.',
          'Ilmainen toimitus: tuotteesi ylittävät ${euro(context, threshold)}.');
    } else if (missing != null) {
      text = tr(context, 'Free delivery from ${euro(context, threshold)} · add ${euro(context, missing)} more',
          'Ilmainen toimitus yli ${euro(context, threshold)} ostoksiin · lisää vielä ${euro(context, missing)}');
    } else {
      text = tr(context, 'Free delivery from ${euro(context, threshold)}', 'Ilmainen toimitus yli ${euro(context, threshold)} ostoksiin');
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(reached ? Icons.check_circle_rounded : Icons.local_shipping_outlined,
              size: 15, color: reached ? AppTheme.success : AppTheme.secondaryText(context)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: MTextSize.caption,
                fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                color: reached ? AppTheme.success : AppTheme.secondaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Free delivery from €80" on a store page, when the store payload carries the threshold.
String? freeDeliveryFromLabel(BuildContext context, Map<String, dynamic> store) {
  final threshold = asInt(store['freeDeliveryThresholdCents']);
  if (threshold == null || threshold <= 0) return null;
  return tr(context, 'Free delivery from ${euro(context, threshold)}', 'Ilmainen toimitus yli ${euro(context, threshold)}');
}
