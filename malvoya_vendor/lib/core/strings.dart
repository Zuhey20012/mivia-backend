/// Store-app text helpers. The shared ones (`tr`, `euro`, dates, `asInt`) live in malvoya_core.

/// Malvoya's commission from the store's `commissionRate` (a fraction, e.g. 0.1 → "10 %").
/// Malvoya takes no commission (every store is at 0 since API 2.13), so an unknown rate counts as 0.
String commissionText(num? rate) {
  final pct = ((rate ?? 0) * 100);
  final rounded = (pct * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? rounded.round().toString() : rounded.toStringAsFixed(1);
  return '$text %';
}

/// Whether this store pays any commission (none do today; kept so a future rate shows correctly).
bool hasCommission(num? rate) => (rate ?? 0) > 0;
