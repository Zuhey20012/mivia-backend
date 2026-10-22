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

const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "3.11.2026" in Finnish, "3 November 2026" otherwise (local time).
String dateText(BuildContext context, DateTime d) {
  final t = d.toLocal();
  return isFinnish(context) ? '${t.day}.${t.month}.${t.year}' : '${t.day} ${_enMonths[t.month - 1]} ${t.year}';
}

/// [dateText] with the time: "3.11.2026 klo 14.05" / "3 November 2026, 14:05".
String dateTimeText(BuildContext context, DateTime d) {
  final t = d.toLocal();
  final mm = t.minute.toString().padLeft(2, '0');
  return isFinnish(context) ? '${dateText(context, t)} klo ${t.hour}.$mm' : '${dateText(context, t)}, ${t.hour.toString().padLeft(2, '0')}:$mm';
}

/// The app-language text of a server `{en, fi}` object, or null.
String? localizedText(BuildContext context, dynamic v) {
  if (v is! Map) return v is String && v.isNotEmpty ? v : null;
  final text = isFinnish(context) ? (v['fi'] ?? v['en']) : (v['en'] ?? v['fi']);
  return text is String && text.trim().isNotEmpty ? text : null;
}
