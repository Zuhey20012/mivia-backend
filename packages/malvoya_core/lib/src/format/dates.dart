import 'package:flutter/widgets.dart';
import '../i18n/app_language.dart';

const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// A date from the API (ISO string or DateTime) in local time, or null.
DateTime? parseApiDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value == null) return null;
  return DateTime.tryParse('$value')?.toLocal();
}

/// "3.11.2026" (fi) or "3 November 2026" (en), local time. [short] gives "3 Nov 2026" in English.
String formatDate(DateTime d, {String? languageCode, bool short = false}) {
  final t = d.toLocal();
  if ((languageCode ?? AppLanguage.code) == 'fi') return '${t.day}.${t.month}.${t.year}';
  final month = _enMonths[t.month - 1];
  return '${t.day} ${short ? month.substring(0, 3) : month} ${t.year}';
}

/// "14.05" (fi) or "14:05" (en).
String formatClock(DateTime d, {String? languageCode}) {
  final t = d.toLocal();
  final fi = (languageCode ?? AppLanguage.code) == 'fi';
  return '${t.hour.toString().padLeft(2, '0')}${fi ? '.' : ':'}${t.minute.toString().padLeft(2, '0')}';
}

/// [formatDate] in the widget's language.
String dateText(BuildContext context, DateTime d, {bool short = false}) =>
    formatDate(d, languageCode: isFinnish(context) ? 'fi' : 'en', short: short);

/// "3.11.2026 klo 14.05" (fi) or "3 November 2026, 14:05" (en).
String dateTimeText(BuildContext context, DateTime d) {
  final lang = isFinnish(context) ? 'fi' : 'en';
  final t = d.toLocal();
  final mm = t.minute.toString().padLeft(2, '0');
  return lang == 'fi'
      ? '${formatDate(t, languageCode: lang)} klo ${t.hour}.$mm'
      : '${formatDate(t, languageCode: lang)}, ${t.hour.toString().padLeft(2, '0')}:$mm';
}

/// A scheduled delivery window from an order's `scheduledStart`/`scheduledEnd`: "Tonight 17:00–19:00",
/// "Huomenna 17.00–19.00". Null when the order is not scheduled (or the times are missing).
String? scheduledWindow(BuildContext context, dynamic start, dynamic end, {DateTime? now}) =>
    scheduledWindowText(start, end, languageCode: isFinnish(context) ? 'fi' : 'en', now: now);

/// [scheduledWindow] without a widget.
String? scheduledWindowText(dynamic start, dynamic end, {String? languageCode, DateTime? now}) {
  final s = parseApiDate(start);
  final e = parseApiDate(end);
  if (s == null || e == null) return null;
  final fi = (languageCode ?? AppLanguage.code) == 'fi';
  final span = '${formatClock(s, languageCode: fi ? 'fi' : 'en')}–${formatClock(e, languageCode: fi ? 'fi' : 'en')}';
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(s.year, s.month, s.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) {
    return s.hour >= 17 ? (fi ? 'Tänä iltana $span' : 'Tonight $span') : (fi ? 'Tänään $span' : 'Today $span');
  }
  if (diff == 1) return fi ? 'Huomenna $span' : 'Tomorrow $span';
  return fi ? '${s.day}.${s.month}. $span' : '${s.day}/${s.month} $span';
}

/// "25–35 min" delivery window from a store's `etaMinutes`/`etaMaxMinutes`.
String? etaWindow(Map<String, dynamic>? store) {
  final min = store?['etaMinutes'];
  final max = store?['etaMaxMinutes'];
  if (min is! num) return null;
  return max is num ? '${min.round()}–${max.round()} min' : '${min.round()} min';
}
