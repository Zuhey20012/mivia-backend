import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'store_detail.dart';

/// Settings → Notifications (API 2.16, `GET/PATCH /me/notification-settings`): which optional
/// notifications this account gets. Messages about your orders, deliveries, payments and recalls
/// are always sent. Each switch is saved on the server; a switch the server refuses goes back.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  /// The optional kinds, in the order shown. Only those the server reports are shown.
  static const _keys = ['followedDrops', 'lives', 'referralRewards', 'launchAlerts'];

  bool _loading = true;
  String? _error;

  /// False when this server has no notification settings yet (404).
  bool _available = true;
  final Map<String, bool> _settings = {};
  final Set<String> _saving = {};

  /// Followed stores, when the server lists them with the settings (`followedStores`).
  List<Map<String, dynamic>> _stores = const [];
  final Set<int> _savingStores = {};

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Map<String, dynamic> _settingsOf(Map<String, dynamic> data) {
    for (final key in ['settings', 'notificationSettings']) {
      if (data[key] is Map) return Map<String, dynamic>.from(data[key] as Map);
    }
    return data;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.get('/me/notification-settings');
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
      _applySettings(res.data);
    });
  }

  void _applySettings(Map<String, dynamic> data) {
    final settings = _settingsOf(data);
    for (final key in _keys) {
      final v = settings[key];
      if (v is bool) _settings[key] = v;
    }
    final stores = data['followedStores'] ?? settings['followedStores'];
    if (stores is List) {
      _stores = stores.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) => _storeId(m) != null).toList();
    }
  }

  static int? _storeId(Map<String, dynamic> m) => asInt(m['storeId'] ?? m['id'] ?? (m['store'] is Map ? m['store']['id'] : null));

  static String _storeName(Map<String, dynamic> m) => (m['name'] ?? (m['store'] is Map ? m['store']['name'] : null) ?? '').toString();

  Future<void> _set(String key, bool value) async {
    final before = _settings[key];
    Haptics.selection();
    setState(() {
      _settings[key] = value;
      _saving.add(key);
    });
    final res = await _api.patch('/me/notification-settings', {key: value});
    if (!mounted) return;
    setState(() {
      _saving.remove(key);
      if (res.ok) {
        final saved = _settingsOf(res.data)[key];
        if (saved is bool) _settings[key] = saved;
      } else if (before != null) {
        _settings[key] = before;
      }
    });
    if (!res.ok) MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not save. Try again.', 'Tallennus ei onnistunut. Yritä uudelleen.'));
  }

  Future<void> _muteStore(Map<String, dynamic> store, bool muted) async {
    final id = _storeId(store)!;
    final before = store['muted'] == true;
    Haptics.selection();
    setState(() {
      store['muted'] = muted;
      _savingStores.add(id);
    });
    final res = await _api.patch('/stores/$id/follow', {'muted': muted});
    if (!mounted) return;
    setState(() {
      _savingStores.remove(id);
      if (res.ok) {
        final saved = res.data['muted'];
        if (saved is bool) store['muted'] = saved;
      } else {
        store['muted'] = before;
      }
    });
    if (!res.ok) MSnack.error(context, res.errorText(context) ?? tr(context, 'Could not save. Try again.', 'Tallennus ei onnistunut. Yritä uudelleen.'));
  }

  (String, String, IconData) _label(String key) => switch (key) {
        'followedDrops' => (
            tr(context, 'New drops from stores you follow', 'Uudet dropit seuraamiltasi kaupoilta'),
            tr(context, 'A notification when a store you follow posts a drop.', 'Ilmoitus, kun seuraamasi kauppa julkaisee dropin.'),
            Icons.play_circle_outline_rounded,
          ),
        'lives' => (
            tr(context, 'Lives from stores you follow', 'Seuraamiesi kauppojen livet'),
            tr(context, 'A notification when a store you follow goes live.', 'Ilmoitus, kun seuraamasi kauppa aloittaa liven.'),
            Icons.sensors_rounded,
          ),
        'referralRewards' => (
            tr(context, 'Invite rewards', 'Kutsupalkinnot'),
            tr(context, 'When a friend you invited makes their first order.', 'Kun kutsumasi ystävä tekee ensimmäisen tilauksensa.'),
            Icons.card_giftcard_rounded,
          ),
        _ => (
            tr(context, 'Malvoya opens near you', 'Malvoya aukeaa lähelläsi'),
            tr(context, 'The one-time message when the first store opens in your area.', 'Kertaviesti, kun alueellesi avautuu ensimmäinen kauppa.'),
            Icons.near_me_outlined,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryText(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Notifications', 'Ilmoitukset'))),
      body: _loading
          ? const MSkeletonList()
          : _error != null
              ? MStateMessage.error(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(MSpace.lg),
                    children: [
                      _card([
                        ListTile(
                          leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
                          title: Text(tr(context, 'Orders, deliveries and payments', 'Tilaukset, toimitukset ja maksut'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            tr(context, 'Always on. These are messages about your own orders, refunds and product recalls.',
                                'Aina päällä. Nämä ovat viestejä omista tilauksistasi, hyvityksistä ja tuotteiden takaisinvedoista.'),
                            style: TextStyle(fontSize: MTextSize.caption, color: muted),
                          ),
                        ),
                      ]),
                      if (!_available)
                        _note(tr(context, 'Choosing other notifications is not available yet. It will appear here after an update.',
                            'Muiden ilmoitusten valinta ei ole vielä käytössä. Se tulee tähän päivityksen jälkeen.'))
                      else if (_settings.isNotEmpty)
                        _card([
                          for (final key in _keys)
                            if (_settings.containsKey(key)) _switchTile(key),
                        ]),
                      if (_stores.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(MSpace.xs, MSpace.sm, MSpace.xs, MSpace.sm),
                          child: Text(tr(context, 'Stores you follow', 'Seuraamasi kaupat'), style: AppTheme.display(context, size: 18)),
                        ),
                        _card([for (final store in _stores) _storeTile(store)]),
                      ],
                      _note(tr(context, 'You can mute a store you follow on its page: you keep following it, without notifications. Your phone’s own settings can also turn Malvoya notifications off.',
                          'Voit mykistää seuraamasi kaupan sen sivulla: seuraat sitä edelleen, mutta ilman ilmoituksia. Myös puhelimen omista asetuksista voit poistaa Malvoyan ilmoitukset käytöstä.')),
                    ],
                  ),
                ),
    );
  }

  Widget _switchTile(String key) {
    final (title, subtitle, icon) = _label(key);
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context))),
      value: _settings[key] ?? false,
      onChanged: _saving.contains(key) ? null : (v) => _set(key, v),
    );
  }

  Widget _storeTile(Map<String, dynamic> store) {
    final id = _storeId(store)!;
    final name = _storeName(store);
    final isMuted = store['muted'] == true;
    return ListTile(
      leading: const Icon(Icons.storefront_rounded, color: AppTheme.primary),
      title: Text(name.isEmpty ? tr(context, 'Store', 'Kauppa') : name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(isMuted ? tr(context, 'Muted', 'Mykistetty') : tr(context, 'Notifications on', 'Ilmoitukset päällä'),
          style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context))),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: {'id': id, 'name': name}))),
      trailing: IconButton(
        tooltip: isMuted ? tr(context, 'Unmute $name', 'Poista mykistys: $name') : tr(context, 'Mute $name', 'Mykistä $name'),
        onPressed: _savingStores.contains(id) ? null : () => _muteStore(store, !isMuted),
        icon: Icon(isMuted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
            color: isMuted ? AppTheme.secondaryText(context) : AppTheme.primary),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: MSpace.lg),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.xs, 0, MSpace.xs, MSpace.lg),
        child: Text(text, style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context), height: 1.4)),
      );
}
