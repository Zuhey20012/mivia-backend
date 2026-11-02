import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../services/courier_telemetry_service.dart';
import 'help_screen.dart';

/// Safety help while online (API 2.16): call 112, report an incident to Malvoya
/// (`POST /courier/incident`, a person is alerted at once) and the status of the courier's reports.
class SafetyScreen extends StatefulWidget {
  /// The order being carried, attached to a report.
  final int? orderId;

  const SafetyScreen({super.key, this.orderId});

  /// Reports sent from this phone in this session, shown when the server has no list to give.
  static final List<Map<String, dynamic>> _sentHere = [];

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

const _types = ['ACCIDENT', 'THREAT', 'DAMAGED', 'THEFT', 'OTHER'];

class _SafetyScreenState extends State<SafetyScreen> {
  final _note = TextEditingController();
  String? _type;
  bool _sending = false;
  String? _error;
  String? _sent;
  List<Map<String, dynamic>>? _incidents;
  bool _loadingList = true;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _loadIncidents();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _typeLabel(String t) => switch (t) {
        'ACCIDENT' => tr(context, 'Accident', 'Onnettomuus'),
        'THREAT' => tr(context, 'Threat or harassment', 'Uhkaus tai häirintä'),
        'DAMAGED' => tr(context, 'Order damaged', 'Tilaus vaurioitui'),
        'THEFT' => tr(context, 'Theft or robbery', 'Varkaus tai ryöstö'),
        _ => tr(context, 'Something else', 'Jotain muuta'),
      };

  IconData _typeIcon(String t) => switch (t) {
        'ACCIDENT' => Icons.car_crash_rounded,
        'THREAT' => Icons.report_rounded,
        'DAMAGED' => Icons.inventory_2_outlined,
        'THEFT' => Icons.no_backpack_rounded,
        _ => Icons.more_horiz_rounded,
      };

  List<Map<String, dynamic>> _listOf(dynamic v) =>
      (v is List ? v : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> _loadIncidents() async {
    final res = await ApiClient(_auth).get('/courier/incidents');
    if (!mounted) return;
    setState(() {
      _loadingList = false;
      if (res.ok) {
        final list = res.data['incidents'] ?? res.data['items'];
        _incidents = _listOf(list);
      } else {
        // An older server without the list: what this phone sent (each one the server accepted)
        _incidents = null;
      }
    });
  }

  Future<void> _call112() async {
    HapticFeedback.heavyImpact();
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: '112'));
    } catch (_) {}
    if (!ok && mounted) {
      MSnack.show(context, tr(context, 'Could not open the phone app. Dial 112 yourself.', 'Puhelinsovellusta ei voitu avata. Soita itse numeroon 112.'));
    }
  }

  Future<Position?> _position() async {
    final last = CourierTelemetryService().lastPosition;
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) return last;
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      return last;
    }
  }

  Future<void> _send() async {
    final type = _type;
    if (type == null) {
      setState(() => _error = tr(context, 'Choose what happened.', 'Valitse, mitä tapahtui.'));
      return;
    }
    if (type == 'OTHER' && _note.text.trim().length < 3) {
      setState(() => _error = tr(context, 'Write a few words about what happened.', 'Kirjoita muutama sana siitä, mitä tapahtui.'));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _sending = true;
      _error = null;
    });
    final pos = await _position();
    final note = _note.text.trim();
    final res = await ApiClient(_auth).post('/courier/incident', {
      'type': type,
      if (widget.orderId != null) 'orderId': widget.orderId,
      if (note.isNotEmpty) 'note': note,
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lng': pos.longitude,
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _sending = false;
        _error = res.errorMessage;
      });
      return;
    }
    final stored = res.data['incident'] is Map ? Map<String, dynamic>.from(res.data['incident'] as Map) : <String, dynamic>{};
    final incident = <String, dynamic>{
      'type': type,
      'status': 'OPEN',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      if (widget.orderId != null) 'orderId': widget.orderId,
      if (note.isNotEmpty) 'note': note,
      if (res.data['id'] != null) 'id': res.data['id'],
      ...stored,
    };
    SafetyScreen._sentHere.insert(0, incident);
    setState(() {
      _sending = false;
      _type = null;
      _note.clear();
      _sent = tr(context, 'Sent. A person at Malvoya has been alerted and will contact you. In danger, call 112 first.',
          'Lähetetty. Malvoyan työntekijä on saanut hälytyksen ja ottaa sinuun yhteyttä. Vaaratilanteessa soita ensin 112.');
    });
    await _loadIncidents();
  }

  bool _isOpen(Map i) {
    final s = '${i['status'] ?? ''}'.toUpperCase();
    return i['resolvedAt'] == null && s != 'RESOLVED' && s != 'CLOSED';
  }

  String _statusText(Map i) {
    if (!_isOpen(i)) return tr(context, 'Resolved', 'Ratkaistu');
    final s = '${i['status'] ?? ''}'.toUpperCase();
    if (s == 'IN_PROGRESS' || s == 'ACKNOWLEDGED' || i['acknowledgedAt'] != null) {
      return tr(context, 'Being handled by Malvoya', 'Malvoya käsittelee');
    }
    return tr(context, 'Open: Malvoya has been alerted', 'Avoin: Malvoya on saanut hälytyksen');
  }

  String? _when(dynamic v) {
    final t = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (t == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day}.${t.month}. ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _incidentTile(Map<String, dynamic> i) {
    final open = _isOpen(i);
    final type = '${i['type'] ?? 'OTHER'}';
    final when = _when(i['createdAt']);
    final orderId = asInt(i['orderId']);
    final resolution = i['resolutionNote'] ?? i['resolution'] ?? i['adminNote'];
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: open ? AppTheme.sunshineLight : AppTheme.surface,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: open ? AppTheme.sunshineLight : AppTheme.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_typeIcon(type), color: open ? AppTheme.amberInk : AppTheme.textSecondary),
        const SizedBox(width: MSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [_typeLabel(type), if (orderId != null) '${tr(context, 'order', 'tilaus')} #$orderId'].join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              [_statusText(i), if (when != null) when].join(' · '),
              style: TextStyle(fontWeight: FontWeight.w600, color: open ? AppTheme.amberInk : AppTheme.successDark, fontSize: MTextSize.label),
            ),
            if (resolution is String && resolution.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(resolution.trim(), style: const TextStyle(color: AppTheme.textSecondary, height: 1.35)),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incidents = _incidents ?? SafetyScreen._sentHere;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Help and safety', 'Apu ja turvallisuus'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.x3l),
        children: [
          // Emergency first
          Container(
            padding: const EdgeInsets.all(MSpace.lg),
            decoration: BoxDecoration(color: AppTheme.dangerLight, borderRadius: BorderRadius.circular(MRadius.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'In danger or injured?', 'Vaarassa tai loukkaantunut?'), style: AppTheme.display(size: 20, color: AppTheme.dangerInk)),
              const SizedBox(height: 4),
              Text(
                tr(context, 'Call the emergency number 112 first. Your safety matters more than any order.',
                    'Soita ensin hätänumeroon 112. Turvallisuutesi on tärkeämpi kuin mikään tilaus.'),
                style: const TextStyle(color: AppTheme.dangerInk, height: 1.4),
              ),
              const SizedBox(height: MSpace.md),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: AppTheme.onPrimary),
                  onPressed: _call112,
                  icon: const Icon(Icons.call_rounded),
                  label: Text(tr(context, 'Call 112', 'Soita 112'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: MSpace.xl),
          Text(tr(context, 'Report an incident to Malvoya', 'Ilmoita tapahtumasta Malvoyalle'), style: AppTheme.display(size: 20)),
          const SizedBox(height: 6),
          Text(
            widget.orderId == null
                ? tr(context, 'A person at Malvoya is alerted straight away. Your current position is attached so we know where you are.',
                    'Malvoyan työntekijä saa hälytyksen heti. Nykyinen sijaintisi liitetään mukaan, jotta tiedämme, missä olet.')
                : tr(context, 'A person at Malvoya is alerted straight away. Order #${widget.orderId} and your current position are attached.',
                    'Malvoyan työntekijä saa hälytyksen heti. Tilaus #${widget.orderId} ja nykyinen sijaintisi liitetään mukaan.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: MSpace.md),
          if (_sent != null)
            Container(
              margin: const EdgeInsets.only(bottom: MSpace.md),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.mint, borderRadius: BorderRadius.circular(MRadius.md)),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(child: Text(_sent!, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
              ]),
            ),
          Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
            for (final t in _types)
              ChoiceChip(
                avatar: Icon(_typeIcon(t), size: 18),
                label: Text(_typeLabel(t)),
                selected: _type == t,
                onSelected: _sending
                    ? null
                    : (_) => setState(() {
                          _type = t;
                          _error = null;
                          _sent = null;
                        }),
              ),
          ]),
          const SizedBox(height: MSpace.md),
          TextField(
            controller: _note,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            enabled: !_sending,
            decoration: InputDecoration(
              labelText: tr(context, 'What happened? (optional)', 'Mitä tapahtui? (valinnainen)'),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MSpace.sm),
              child: Text(_error!, style: const TextStyle(color: AppTheme.dangerInk, fontWeight: FontWeight.w600)),
            ),
          MButton(
            label: tr(context, 'Send the report', 'Lähetä ilmoitus'),
            icon: Icons.campaign_rounded,
            expand: true,
            loading: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: MSpace.xl),
          Text(tr(context, 'Your reports', 'Ilmoituksesi'), style: AppTheme.display(size: 18)),
          const SizedBox(height: MSpace.sm),
          if (_loadingList && incidents.isEmpty)
            const Padding(padding: EdgeInsets.all(MSpace.lg), child: Center(child: CircularProgressIndicator()))
          else if (incidents.isEmpty)
            Text(tr(context, 'No reports.', 'Ei ilmoituksia.'), style: const TextStyle(color: AppTheme.textSecondary))
          else
            for (final i in incidents.take(20)) _incidentTile(i),
          const SizedBox(height: MSpace.lg),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HelpScreen(orderId: widget.orderId))),
            icon: const Icon(Icons.support_agent_rounded),
            label: Text(tr(context, 'Something else? Message the Malvoya team', 'Muuta asiaa? Lähetä viesti Malvoyan tiimille')),
          ),
        ],
      ),
    );
  }
}
