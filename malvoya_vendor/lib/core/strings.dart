/// Store-app text helpers. The shared ones (`tr`, `euro`, dates, `asInt`) live in malvoya_core.

/// Malvoya's commission from the store's `commissionRate` (a fraction, e.g. 0.1 → "10 %").
/// Falls back to the default 10 % when the rate is not known.
String commissionText(num? rate) {
  final pct = ((rate ?? 0.10) * 100);
  final rounded = (pct * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? rounded.round().toString() : rounded.toStringAsFixed(1);
  return '$text %';
}
