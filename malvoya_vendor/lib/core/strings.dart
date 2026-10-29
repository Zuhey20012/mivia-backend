/// Store-app text helpers. The shared ones (`tr`, `euro`, dates, `asInt`) live in malvoya_core.

/// Malvoya's commission from the store's `commissionRate` (a fraction, e.g. 0.15 → "15 %").
/// New stores get the platform's default rate (15 % since API 2.16); admins may agree another rate
/// per store. Callers show [commissionKnown] first: a null rate means the store is not loaded yet.
String commissionText(num? rate) {
  final pct = ((rate ?? 0) * 100);
  final rounded = (pct * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? rounded.round().toString() : rounded.toStringAsFixed(1);
  return '$text %';
}

/// Whether this store pays a commission (its rate is above 0).
bool hasCommission(num? rate) => (rate ?? 0) > 0;

/// Whether the store's rate is known (a store payload was loaded). Without it the apps never say
/// "no commission", only that the rate is in the Seller Terms.
bool commissionKnown(num? rate) => rate != null;
