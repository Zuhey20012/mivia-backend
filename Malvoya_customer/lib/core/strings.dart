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

/// A server text sent in both languages (`{en, fi}`), or a plain string.
String? localized(BuildContext context, dynamic value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) {
    final text = (isFinnish(context) ? value['fi'] : value['en']) ?? value['en'] ?? value['fi'];
    return text is String && text.isNotEmpty ? text : null;
  }
  return null;
}

/// A scheduled delivery window from an order's `scheduledStart`/`scheduledEnd`: "Tonight 17:00–19:00",
/// "Huomenna 17.00–19.00". Null when the order is not scheduled (or the times are missing).
String? scheduledWindow(BuildContext context, dynamic start, dynamic end) {
  final s = start == null ? null : DateTime.tryParse(start.toString())?.toLocal();
  final e = end == null ? null : DateTime.tryParse(end.toString())?.toLocal();
  if (s == null || e == null) return null;
  final fi = isFinnish(context);
  String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}${fi ? '.' : ':'}${t.minute.toString().padLeft(2, '0')}';
  final span = '${clock(s)}–${clock(e)}';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(s.year, s.month, s.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) {
    return s.hour >= 17 ? (fi ? 'Tänä iltana $span' : 'Tonight $span') : (fi ? 'Tänään $span' : 'Today $span');
  }
  if (diff == 1) return fi ? 'Huomenna $span' : 'Tomorrow $span';
  return fi ? '${s.day}.${s.month}. $span' : '${s.day}/${s.month} $span';
}
