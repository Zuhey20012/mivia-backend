import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Store → Signed-in devices (API 2.16, `GET/DELETE /me/sessions`): every phone or browser signed in
/// to this account, with sign-out per device or for all others. This phone stays signed in.
class SignedInDevicesScreen extends StatefulWidget {
  const SignedInDevicesScreen({super.key});

  @override
  State<SignedInDevicesScreen> createState() => _SignedInDevicesScreenState();
}

class _SignedInDevicesScreenState extends State<SignedInDevicesScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.get('/me/sessions');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.errorMessage;
      if (res.ok) {
        final list = res.data['sessions'] ?? res.data['devices'];
        _sessions = list is List ? list.whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList() : [];
        // This device first, then the most recently used
        _sessions.sort((a, b) {
          if (_isCurrent(a) != _isCurrent(b)) return _isCurrent(a) ? -1 : 1;
          final la = _lastUsed(a) ?? DateTime(2000);
          final lb = _lastUsed(b) ?? DateTime(2000);
          return lb.compareTo(la);
        });
      }
    });
  }

  static bool _isCurrent(Map<String, dynamic> s) => s['current'] == true || s['isCurrent'] == true;
  static DateTime? _lastUsed(Map<String, dynamic> s) => parseApiDate(s['lastUsedAt'] ?? s['lastUsed'] ?? s['createdAt']);

  String _deviceName(Map<String, dynamic> s) {
    for (final key in ['device', 'deviceName', 'userAgentFamily', 'uaFamily', 'userAgent']) {
      final v = s[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return tr(context, 'Unknown device', 'Tuntematon laite');
  }

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.contains('android') || n.contains('iphone') || n.contains('ios') || n.contains('malvoya')) return Icons.smartphone_rounded;
    if (n.contains('chrome') || n.contains('firefox') || n.contains('safari') || n.contains('edge') || n.contains('browser')) return Icons.language_rounded;
    return Icons.devices_other_rounded;
  }

  Future<void> _signOut(Map<String, dynamic> s) async {
    final id = s['id'];
    if (id == null) return;
    final confirmed = await _confirm(
      tr(context, 'Sign out this device?', 'Kirjataanko tämä laite ulos?'),
      tr(context, '${_deviceName(s)} needs to sign in again.', '${_deviceName(s)} joutuu kirjautumaan uudelleen.'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.delete('/me/sessions/${Uri.encodeComponent('$id')}');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    MSnack.success(context, tr(context, 'Device signed out', 'Laite kirjattu ulos'));
    _load();
  }

  Future<void> _signOutOthers() async {
    final confirmed = await _confirm(
      tr(context, 'Sign out all other devices?', 'Kirjataanko kaikki muut laitteet ulos?'),
      tr(context, 'Every other phone or browser signed in to this account needs to sign in again. This phone stays signed in.',
          'Kaikkien muiden tähän tiliin kirjautuneiden puhelinten ja selainten on kirjauduttava uudelleen. Tämä puhelin pysyy kirjautuneena.'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.delete('/me/sessions');
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    MSnack.success(context, tr(context, 'Other devices signed out', 'Muut laitteet kirjattu ulos'));
    _load();
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Sign out', 'Kirjaa ulos'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final others = _sessions.where((s) => !_isCurrent(s)).length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Signed-in devices', 'Kirjautuneet laitteet'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const MSkeletonList(count: 3, lines: 2)
            : _error != null
                ? MStateMessage.error(message: _error, onRetry: () {
                    setState(() => _loading = true);
                    _load();
                  })
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(MSpace.lg),
                    children: [
                      Text(
                        tr(context, 'Where your store account is signed in. If you do not recognise a device, sign it out and turn on two-step sign-in.',
                            'Missä kauppatilisi on kirjautuneena. Jos et tunnista laitetta, kirjaa se ulos ja ota kaksivaiheinen kirjautuminen käyttöön.'),
                        style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: MTextSize.bodyM),
                      ),
                      const SizedBox(height: MSpace.lg),
                      if (_sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: MSpace.xxl),
                          child: Text(tr(context, 'No devices listed.', 'Ei laitteita.'), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
                          child: Column(children: [
                            for (var i = 0; i < _sessions.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _tile(_sessions[i]),
                            ],
                          ]),
                        ),
                      if (others > 0) ...[
                        const SizedBox(height: MSpace.lg),
                        MButton(
                          label: tr(context, 'Sign out all other devices', 'Kirjaa kaikki muut laitteet ulos'),
                          variant: MButtonVariant.outline,
                          icon: Icons.logout_rounded,
                          expand: true,
                          loading: _busy,
                          onPressed: _busy ? null : _signOutOthers,
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final name = _deviceName(s);
    final current = _isCurrent(s);
    final created = parseApiDate(s['createdAt']);
    final used = parseApiDate(s['lastUsedAt'] ?? s['lastUsed']);
    final lines = [
      if (current) tr(context, 'This phone', 'Tämä puhelin'),
      if (used != null) tr(context, 'Last used ${dateTimeText(context, used)}', 'Käytetty viimeksi ${dateTimeText(context, used)}'),
      if (created != null) tr(context, 'Signed in ${dateText(context, created)}', 'Kirjautunut ${dateText(context, created)}'),
    ];
    return ListTile(
      leading: CircleAvatar(backgroundColor: current ? AppTheme.primaryLight : AppTheme.sand, child: Icon(_icon(name), color: current ? AppTheme.primary : AppTheme.textPrimary)),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: lines.isEmpty ? null : Text(lines.join(' · ')),
      trailing: current || s['id'] == null
          ? null
          : TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy ? null : () => _signOut(s),
              child: Text(tr(context, 'Sign out', 'Kirjaa ulos')),
            ),
    );
  }
}
