import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import '../i18n/app_language.dart';

/// Euro amount from integer cents, as Finnish and English readers expect it:
/// "1 249,90 €" (fi) and "€1,249.90" (en). Money in Malvoya is always integer cents in EUR.
String formatEuro(num? cents, {String? languageCode, bool showCents = true}) {
  final value = (cents ?? 0) / 100;
  final fi = (languageCode ?? AppLanguage.code) == 'fi';
  final digits = showCents ? 2 : 0;
  return fi
      ? NumberFormat.currency(locale: 'fi_FI', symbol: '€', decimalDigits: digits).format(value)
      : NumberFormat.currency(locale: 'en_IE', symbol: '€', decimalDigits: digits).format(value);
}

/// [formatEuro] in the widget's language.
String euro(BuildContext context, num? cents) => formatEuro(cents, languageCode: isFinnish(context) ? 'fi' : 'en');

/// A unit price (Price Indication Directive 98/6/EC, Finnish decree 553/2013): goods sold by volume
/// or weight show the price per litre or per kilogram (never per 100 ml / 100 g in Finland).
@immutable
class UnitPrice {
  /// A price of [cents] per [per] ("l" or "kg").
  const UnitPrice(this.cents, this.per);

  /// Cents per litre or kilogram.
  final int cents;

  /// "l" or "kg".
  final String per;

  /// Contents below this many ml or g need no unit price (§10(2) of the decree).
  static const minContent = 50;

  /// The unit price of an item that costs [priceCents] for [amount] [unit] ("ml", "g" or "pcs"),
  /// computed exactly like the API (`catalog/unitPrice.ts`). Null when none is needed: sold by the
  /// piece, no content given, or less than 50 ml / 50 g.
  static UnitPrice? compute(int? priceCents, num? amount, String? unit) {
    if (priceCents == null || amount == null || amount <= 0) return null;
    if (unit != 'ml' && unit != 'g') return null;
    if (amount < minContent) return null;
    return UnitPrice(((priceCents * 1000) / amount).round(), unit == 'ml' ? 'l' : 'kg');
  }

  /// The API's `unitPrice` object (`{cents, per}`), or null.
  static UnitPrice? fromJson(dynamic json) {
    if (json is! Map) return null;
    final cents = asInt(json['cents']);
    final per = json['per'];
    if (cents == null || (per != 'l' && per != 'kg')) return null;
    return UnitPrice(cents, per as String);
  }

  /// "17,80 €/l" (fi) or "€17.80/l" (en).
  String format({String? languageCode}) => '${formatEuro(cents, languageCode: languageCode)}/$per';

  @override
  bool operator ==(Object other) => other is UnitPrice && other.cents == cents && other.per == per;

  @override
  int get hashCode => Object.hash(cents, per);

  @override
  String toString() => 'UnitPrice($cents/$per)';
}
