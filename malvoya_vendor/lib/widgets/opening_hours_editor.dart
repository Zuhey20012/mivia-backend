import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

class OpeningDay {
  bool open;
  TimeOfDay from;
  TimeOfDay to;
  OpeningDay(this.open, this.from, this.to);
}

/// Weekly opening hours being edited, in the API's shape: `{ mon: [["10:00","18:00"]], … }`
/// (Finnish time), or null for "always open while orders are switched on".
class OpeningHoursDraft {
  static const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _from = TimeOfDay(hour: 10, minute: 0);
  static const _to = TimeOfDay(hour: 18, minute: 0);

  bool useHours;
  final List<OpeningDay> days;

  OpeningHoursDraft._(this.useHours, this.days);

  /// From the store's saved hours. Without saved hours the days start as Mon–Sat 10–18, Sunday closed,
  /// and [useHours] is [defaultOn].
  factory OpeningHoursDraft.fromJson(Map<String, dynamic>? hours, {bool defaultOn = false}) {
    final days = keys.map((k) {
      final ranges = (hours?[k] as List?) ?? const [];
      if (hours == null || ranges.isEmpty || ranges.first is! List || (ranges.first as List).length < 2) {
        return OpeningDay(hours == null && k != 'sun', _from, _to);
      }
      final r = ranges.first as List;
      return OpeningDay(true, _parse('${r[0]}') ?? _from, _parse('${r[1]}') ?? _to);
    }).toList();
    return OpeningHoursDraft._(hours != null || defaultOn, days);
  }

  static TimeOfDay? _parse(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    return h < 24 && min < 60 ? TimeOfDay(hour: h, minute: min) : null;
  }

  static String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// What the API stores; null = no opening hours.
  Map<String, List<List<String>>>? toJson() => useHours
      ? {for (var i = 0; i < 7; i++) keys[i]: days[i].open ? [[fmt(days[i].from), fmt(days[i].to)]] : <List<String>>[]}
      : null;

  /// A problem to show before saving, or null.
  String? validate(BuildContext context) {
    if (!useHours) return null;
    for (final d in days) {
      if (d.open && fmt(d.from) == fmt(d.to)) {
        return tr(context, 'Opening and closing time cannot be the same.', 'Avaamis- ja sulkemisaika eivät voi olla samat.');
      }
    }
    if (days.every((d) => !d.open)) {
      return tr(context, 'Open at least one day, or switch opening hours off.', 'Ole auki vähintään yhtenä päivänä tai kytke aukioloajat pois.');
    }
    return null;
  }
}

/// The "Use opening hours" switch and one row per weekday. Shared by the opening-hours screen and
/// the store setup.
class OpeningHoursEditor extends StatelessWidget {
  final OpeningHoursDraft draft;
  final VoidCallback onChanged;
  const OpeningHoursEditor({super.key, required this.draft, required this.onChanged});

  List<String> _names(BuildContext context) => isFinnish(context)
      ? ['Maanantai', 'Tiistai', 'Keskiviikko', 'Torstai', 'Perjantai', 'Lauantai', 'Sunnuntai']
      : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  Future<void> _pick(BuildContext context, OpeningDay d, bool from) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: from ? d.from : d.to,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    from ? d.from = picked : d.to = picked;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final names = _names(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'Use opening hours', 'Käytä aukioloaikoja'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(draft.useHours
              ? tr(context, 'Closed automatically outside these hours', 'Suljettu automaattisesti näiden ulkopuolella')
              : tr(context, 'Open whenever orders are switched on', 'Auki aina, kun tilaukset ovat päällä')),
          value: draft.useHours,
          onChanged: (v) {
            draft.useHours = v;
            onChanged();
          },
        ),
        if (draft.useHours)
          for (var i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.only(top: MSpace.sm),
              padding: const EdgeInsets.fromLTRB(14, 6, MSpace.sm, 6),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(draft.days[i].open ? tr(context, 'Open', 'Auki') : tr(context, 'Closed', 'Suljettu'),
                            style: TextStyle(fontSize: MTextSize.caption, color: draft.days[i].open ? AppTheme.primary : AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  if (draft.days[i].open) ...[
                    _timeButton(OpeningHoursDraft.fmt(draft.days[i].from), () => _pick(context, draft.days[i], true)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: MSpace.xs), child: Text('–')),
                    _timeButton(OpeningHoursDraft.fmt(draft.days[i].to), () => _pick(context, draft.days[i], false)),
                  ],
                  Switch(
                    value: draft.days[i].open,
                    onChanged: (v) {
                      draft.days[i].open = v;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _timeButton(String label, VoidCallback onTap) => Material(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(MRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(MRadius.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(widthFactor: 1, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL))),
            ),
          ),
        ),
      );
}
