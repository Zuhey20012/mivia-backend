import 'package:flutter/widgets.dart';
import 'strings.dart';

/// "Closed · opens tomorrow 10:00" or "Not taking orders right now" for a store the API says is
/// not open; null when it is open (or the API did not say).
String? closedLabel(BuildContext context, Map<String, dynamic>? store) {
  if (store == null || store['openNow'] != false) return null;
  if (store['closedReason'] == 'paused') return tr(context, 'Not taking orders right now', 'Ei ota tilauksia juuri nyt');
  final opens = store['opensAt'];
  if (opens is! Map) return tr(context, 'Closed', 'Suljettu');
  final days = isFinnish(context)
      ? {'mon': 'ma', 'tue': 'ti', 'wed': 'ke', 'thu': 'to', 'fri': 'pe', 'sat': 'la', 'sun': 'su'}
      : {'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun'};
  final inDays = asInt(opens['inDays']) ?? 0;
  final when = inDays == 0 ? '' : inDays == 1 ? tr(context, 'tomorrow ', 'huomenna ') : '${days[opens['day']] ?? ''} ';
  return tr(context, 'Closed · opens $when${opens['time']}', 'Suljettu · aukeaa $when${opens['time']}');
}
