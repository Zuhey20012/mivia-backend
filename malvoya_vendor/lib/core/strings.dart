import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Finnish when the app language is Finnish, English otherwise (for screens added after the
/// original translation tables).
String tr(BuildContext context, String en, String fi) =>
    Localizations.localeOf(context).languageCode == 'fi' ? fi : en;

bool isFinnish(BuildContext context) => Localizations.localeOf(context).languageCode == 'fi';

/// Euro amount from cents: "49,90 €" in Finnish, "€49.90" otherwise.
String euro(BuildContext context, num? cents) {
  final value = (cents ?? 0) / 100;
  return isFinnish(context)
      ? NumberFormat.currency(locale: 'fi_FI', symbol: '€', decimalDigits: 2).format(value)
      : NumberFormat.currency(locale: 'en_IE', symbol: '€', decimalDigits: 2).format(value);
}

/// "25–35 min" delivery window from the API's estimate.
String? etaWindow(Map<String, dynamic>? store) {
  final min = store?['etaMinutes'];
  final max = store?['etaMaxMinutes'];
  if (min is! num) return null;
  return max is num ? '${min.round()}–${max.round()} min' : '${min.round()} min';
}

int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

/// Malvoya's commission from the store's `commissionRate` (a fraction, e.g. 0.1 → "10 %").
/// Falls back to the default 10 % when the rate is not known.
String commissionText(num? rate) {
  final pct = ((rate ?? 0.10) * 100);
  final rounded = (pct * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? rounded.round().toString() : rounded.toStringAsFixed(1);
  return '$text %';
}
