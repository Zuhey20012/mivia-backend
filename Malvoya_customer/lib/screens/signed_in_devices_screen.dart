import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Settings → Signed-in devices (API 2.16, `GET /me/sessions`): where this account is signed in,
/// with "Sign out" for one device and "Sign out all other devices". This phone stays signed in.
class SignedInDevicesScreen extends StatefulWidget {
  const SignedInDevicesScreen({super.key});

  @override
  State<SignedInDevicesScreen> createState() => _SignedInDevicesScreenState();
}

class _SignedInDevicesScreenState extends State<SignedInDevicesScreen> {
  bool _loading = true;
  String? _error;

  /// False when this server cannot list sessions yet (404).
  bool _available = true;
  List<Map<String, dynamic>> _sessions = const [];
  final Set<String> _busy = {};
  bool _busyAll = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.get('/me/sessions');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.status == 404) {
        _available = false;
        return;
      }
      if (!res.ok) {
        _error = res.errorText(context);
        return;
      }
      _available = true;
      final list = res.data['sessions'];
      _sessions = list is List
          ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) => m['id'] != null).toList()
          : const [];
      // This device first, then the most recently used
      _sessions.sort((a, b) {
        if ((a['current'] == true) != (b['current'] == true)) return a['current'] == true ? -1 : 1;
        final ta = parseApiDate(a['lastUsedAt'] ?? a['createdAt']);
        final tb = parseApiDate(b['lastUsedAt'] ?? b['createdAt']);
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta);
      });
    });
  }

  String _deviceName(Map<String, dynamic> s) {
    for (final key in ['device', 'deviceName', 'userAgent', 'family', 'client']) {
      final v = s[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return tr(context, 'Unknown device', 'Tuntematon laite');
  }

  Future<void> _signOut(Map<String, dynamic> session) async {
    final id = '${session['id']}';
    final ok = await _confirm(
      tr(context, 'Sign out this device?', 'Kirjataanko tämä laite ulos?'),
      tr(context, '${_deviceName(session)} will need to sign in again.', '${_deviceName(session)} joutuu kirjautumaan uudelleen.'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(id));
    final res = await _api.delete('/me/sessions/${Uri.encodeComponent(id)}');
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (!res.ok) {
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not sign it out. Try again.', 'Uloskirjaus ei onnistunut. Yritä uudelleen.'));
      return;
    }
    MSnack.show(context, tr(context, 'Signed out', 'Kirjattu ulos'), kind: MSnackKind.success);
    _load();
  }

  Future<void> _signOutOthers() async {
    final ok = await _confirm(
      tr(context, 'Sign out all other devices?', 'Kirjataanko kaikki muut laitteet ulos?'),
      tr(context, 'Every other phone or browser will need to sign in again. This phone stays signed in.',
          'Kaikkien muiden puhelinten ja selainten täytyy kirjautua uudelleen. Tämä puhelin pysyy kirjautuneena.'),
    );
    if (!ok || !mounted) return;
    setState(() => _busyAll = true);
    final res = await _api.delete('/me/sessions');
    if (!mounted) return;
    setState(() => _busyAll = false);
    if (!res.ok) {
      MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not sign them out. Try again.', 'Uloskirjaus ei onnistunut. Yritä uudelleen.'));
      return;
    }
    MSnack.show(context, tr(context, 'All other devices are signed out', 'Kaikki muut laitteet on kirjattu ulos'), kind: MSnackKind.success);
    _load();
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Sign out', 'Kirjaa ulos'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryText(context);
    final others = _sessions.where((s) => s['current'] != true).length;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Signed-in devices', 'Kirjautuneet laitteet'))),
      body: _loading
          ? const MSkeletonList()
          : _error != null
              ? MStateMessage.error(message: _error!, onRetry: _load)
              : !_available
                  ? MStateMessage(
                      icon: Icons.devices_other_rounded,
                      message: tr(context, 'The list of devices is not available yet. It will appear here after an update.',
                          'Laitelista ei ole vielä käytössä. Se tulee tähän päivityksen jälkeen.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(MSpace.lg),
                        children: [
                          Text(
                            tr(context, 'If you see a device you do not recognise, sign it out and change your password.',
                                'Jos näet laitteen, jota et tunnista, kirjaa se ulos ja vaihda salasanasi.'),
                            style: TextStyle(fontSize: MTextSize.label, color: muted, height: 1.4),
                          ),
                          const SizedBox(height: MSpace.lg),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.cardBackground(context),
                              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                              border: Border.all(color: AppTheme.cardBorder(context)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [for (final s in _sessions) _tile(s)]),
                          ),
                          if (others > 0) ...[
                            const SizedBox(height: MSpace.xl),
                            MButton(
                              label: tr(context, 'Sign out all other devices', 'Kirjaa ulos kaikki muut laitteet'),
                              expand: true,
                              loading: _busyAll,
                              variant: MButtonVariant.secondary,
                              onPressed: _busyAll ? null : _signOutOthers,
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _tile(Map<String, dynamic> s) {
    final id = '${s['id']}';
    final current = s['current'] == true;
    final created = parseApiDate(s['createdAt']);
    final used = parseApiDate(s['lastUsedAt']);
    final details = [
      if (current) tr(context, 'This device', 'Tämä laite'),
      if (used != null) '${tr(context, 'Last used', 'Käytetty viimeksi')} ${dateTimeText(context, used.toLocal())}',
      if (created != null) '${tr(context, 'Signed in', 'Kirjautunut')} ${dateText(context, created.toLocal())}',
    ].join('\n');
    final name = _deviceName(s);
    return ListTile(
      leading: Icon(current ? Icons.smartphone_rounded : Icons.devices_rounded, color: current ? AppTheme.primary : AppTheme.secondaryText(context)),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: details.isEmpty ? null : Text(details, style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context), height: 1.35)),
      isThreeLine: details.contains('\n'),
      trailing: current
          ? null
          : _busy.contains(id)
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _signOut(s),
                  child: Text(tr(context, 'Sign out', 'Kirjaa ulos'), semanticsLabel: tr(context, 'Sign out $name', 'Kirjaa ulos $name')),
                ),
    );
  }
}
