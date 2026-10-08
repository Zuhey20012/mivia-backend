import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';

/// Weekly opening hours in Finnish time. Outside them customers see "Closed" and cannot order,
/// so no order waits for a store that is not there.
class OpeningHoursScreen extends StatefulWidget {
  final int storeId;
  final Map<String, dynamic>? initial;
  const OpeningHoursScreen({super.key, required this.storeId, this.initial});

  @override
  State<OpeningHoursScreen> createState() => _OpeningHoursScreenState();
}

class _Day {
  bool open;
  TimeOfDay from;
  TimeOfDay to;
  _Day(this.open, this.from, this.to);
}

class _OpeningHoursScreenState extends State<OpeningHoursScreen> {
  static const _keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  late bool _useHours;
  late List<_Day> _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    _useHours = h != null;
    _days = _keys.map((k) {
      final ranges = (h?[k] as List?) ?? const [];
      if (ranges.isEmpty) return _Day(h == null && k != 'sun', const TimeOfDay(hour: 10, minute: 0), const TimeOfDay(hour: 18, minute: 0));
      final r = (ranges.first as List).cast<String>();
      return _Day(true, _parse(r[0]), _parse(r[1]));
    }).toList();
  }

  TimeOfDay _parse(String hhmm) => TimeOfDay(hour: int.parse(hhmm.substring(0, 2)), minute: int.parse(hhmm.substring(3, 5)));
  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  List<String> _names(BuildContext context) => isFinnish(context)
      ? ['Maanantai', 'Tiistai', 'Keskiviikko', 'Torstai', 'Perjantai', 'Lauantai', 'Sunnuntai']
      : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  Future<void> _pick(_Day d, bool from) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: from ? d.from : d.to,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked != null) setState(() => from ? d.from = picked : d.to = picked);
  }

  Future<void> _save() async {
    for (final d in _days) {
      if (_useHours && d.open && _fmt(d.from) == _fmt(d.to)) {
        _snack(tr(context, 'Opening and closing time cannot be the same.', 'Avaamis- ja sulkemisaika eivät voi olla samat.'));
        return;
      }
    }
    setState(() => _saving = true);
    final hours = _useHours
        ? {for (var i = 0; i < 7; i++) _keys[i]: _days[i].open ? [[_fmt(_days[i].from), _fmt(_days[i].to)]] : <List<String>>[]}
        : null;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).patch('/stores/${widget.storeId}', {'openingHours': hours});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      _snack(res.error ?? tr(context, 'Could not save', 'Tallennus epäonnistui'));
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final names = _names(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Opening hours', 'Aukioloajat'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Text(
              tr(context,
                  'Customers can only order while you are open. Times are Finnish time. Closing after midnight works too, e.g. 18:00–02:00.',
                  'Asiakkaat voivat tilata vain aukioloaikoina. Ajat ovat Suomen aikaa. Myös puolenyön yli toimii, esim. 18:00–02:00.'),
              style: const TextStyle(color: Color(0xFF6A4500), height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Use opening hours', 'Käytä aukioloaikoja'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_useHours
                ? tr(context, 'Closed automatically outside these hours', 'Suljettu automaattisesti näiden ulkopuolella')
                : tr(context, 'Open whenever orders are switched on', 'Auki aina, kun tilaukset ovat päällä')),
            value: _useHours,
            onChanged: (v) => setState(() => _useHours = v),
          ),
          if (_useHours)
            for (var i = 0; i < 7; i++)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(names[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(_days[i].open ? tr(context, 'Open', 'Auki') : tr(context, 'Closed', 'Suljettu'),
                              style: TextStyle(fontSize: 12.5, color: _days[i].open ? AppTheme.primary : AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    if (_days[i].open) ...[
                      _timeButton(_fmt(_days[i].from), () => _pick(_days[i], true)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
                      _timeButton(_fmt(_days[i].to), () => _pick(_days[i], false)),
                    ],
                    Switch(value: _days[i].open, onChanged: (v) => setState(() => _days[i].open = v)),
                  ],
                ),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(tr(context, 'Save', 'Tallenna')),
          ),
        ),
      ),
    );
  }

  Widget _timeButton(String label, VoidCallback onTap) => Material(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      );
}
