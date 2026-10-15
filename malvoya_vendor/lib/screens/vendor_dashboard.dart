import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
import '../core/delete_account_tile.dart';
import '../services/socket_service.dart';
import '../core/push_service.dart';
import '../widgets/loading_states.dart';
import 'chatbot.dart';
import 'drops_manager.dart';
import 'import_products_screen.dart';
import 'payouts_screen.dart';
import 'pickup_code_sheet.dart';
import 'product_editor.dart';
import 'returns_manager.dart';
import 'statements_screen.dart';
import 'store_setup.dart';
import 'opening_hours_screen.dart';
import 'tax_info_screen.dart';

/// The store owner's home: incoming orders, products, drops and the store itself.
class VendorDashboard extends StatefulWidget {
  const VendorDashboard({super.key});

  @override
  State<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends State<VendorDashboard> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
  final _dropsKey = GlobalKey<DropsManagerState>();

  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  bool _ordersLoaded = false;
  String? _ordersError;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VendorSocketService().connect(Provider.of<AuthService>(context, listen: false).accessToken ?? '');
      _load();
      PushService.instance.refreshPermission();
    });
    VendorSocketService().addListener(_onSocket);
    WidgetsBinding.instance.addObserver(this);
    // Safety net if the live connection drops: look for new orders every 30 s while open
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _loadOrders());
    // Keeps "Waiting 4 min" on new orders current, even while offline
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _orders.any(_isWaiting)) setState(() {});
    });
    // Back online: reconnect the live connection with a fresh token and catch up on orders
    _restored = ConnectivityService.instance.onRestored.listen((_) {
      if (!mounted) return;
      VendorSocketService().ensureConnected(Provider.of<AuthService>(context, listen: false).accessToken ?? '');
      _load();
    });
  }

  Timer? _poll;
  Timer? _tick;
  StreamSubscription<void>? _restored;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadOrders();
      _loadReturns();
      // Back from the phone's settings: hide the red bar once notifications are on
      PushService.instance.refreshPermission();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _restored?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.stopRinging();
    VendorSocketService().removeListener(_onSocket);
    _tabs.dispose();
    _productSearch.dispose();
    super.dispose();
  }

  void _onSocket() {
    HapticFeedback.mediumImpact();
    _loadOrders();
  }

  Future<void> _load() async {
    final res = await _api.get('/stores/my');
    if (!mounted) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (res.status == 404) {
      // No store (e.g. removed by an admin): the app's home shows the store setup instead
      auth.updateStore(null);
      return;
    }
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok && res.data['store'] is Map) _store = Map<String, dynamic>.from(res.data['store']);
    });
    if (res.ok && _store != null) {
      auth.updateStore(_store);
      _loadNormalPrep();
      _loadImports();
      _loadReturns();
    }
    await _loadOrders();
  }

  // ── Open returns (badge on the Store tab) ───────────────────────────────
  // Returns have no push of their own yet, so the count is refreshed on load, on resume and with
  // pull to refresh.

  static const _openReturnStatuses = {'REQUESTED', 'APPROVED', 'IN_TRANSIT', 'RECEIVED'};
  int _openReturns = 0;

  Future<void> _loadReturns() async {
    final res = await _api.get('/returns');
    if (!mounted || !res.ok) return;
    final open = ((res.data['returns'] as List?) ?? const []).whereType<Map>().where((r) => _openReturnStatuses.contains(r['status'])).length;
    if (open != _openReturns) setState(() => _openReturns = open);
  }

  Widget _countBadge(int n) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(10)),
        child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
      );

  // ── Notifications off: the store would miss new orders ─────────────────

  bool _enablingPush = false;

  Future<void> _turnOnNotifications() async {
    HapticFeedback.selectionClick();
    setState(() => _enablingPush = true);
    final ok = await PushService.instance.enableNotifications();
    if (!mounted) return;
    setState(() => _enablingPush = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Open your phone\'s Settings → Apps → Malvoya Store → Notifications and switch them on.',
            'Avaa puhelimen Asetukset → Sovellukset → Malvoya Store → Ilmoitukset ja kytke ne päälle.')),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  Widget _notificationsOffBar() => ValueListenableBuilder<bool?>(
        valueListenable: PushService.instance.notificationsAllowed,
        builder: (context, allowed, _) {
          if (allowed != false) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(color: const Color(0xFFD93025), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Row(children: [
              const Icon(Icons.notifications_off_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr(context, 'Notifications are off — you will miss orders.', 'Ilmoitukset ovat pois päältä — menetät tilauksia.'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.3)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFD93025),
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: _enablingPush ? null : _turnOnNotifications,
                child: Text(tr(context, 'Turn on', 'Ota käyttöön')),
              ),
            ]),
          );
        },
      );

  // ── Tax information (DAC7) ──────────────────────────────────────────────

  Future<void> _openTaxInfo() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxInfoScreen()));
    if (mounted) _load();
  }

  /// Shown only when the server says the tax details are missing (older servers do not send the flag).
  Widget _taxInfoBanner() {
    if (_store?['taxInfoComplete'] != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: AppTheme.lilac, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: _openTaxInfo,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: AppTheme.malva),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'Add your tax information', 'Lisää verotietosi'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(tr(context, 'EU law (DAC7) requires it from every seller. It takes about two minutes.', 'EU-laki (DAC7) edellyttää sitä jokaiselta myyjältä. Se vie noin kaksi minuuttia.'),
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
          ]),
        ),
      ),
    );
  }

  bool _switching = false;

  /// The store's "online" switch: off means customers see the store as paused and cannot order.
  Future<void> _setAccepting(bool value) async {
    final id = asInt(_store?['id']);
    if (id == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _switching = true);
    final res = await _api.patch('/stores/$id', {'acceptingOrders': value});
    if (!mounted) return;
    setState(() => _switching = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? tr(context, 'Could not change it', 'Muutos epäonnistui'))));
      return;
    }
    await _load();
  }

  // ── Busy mode: preparation time ──────────────────────────────────────────
  // Customers' delivery estimates include the store's preparation time. "+10 min" remembers the
  // usual time on this phone so "Back to normal" can restore it.

  bool _savingPrep = false;
  int? _normalPrep;

  int get _prep => asInt(_store?['prepMinutes']) ?? 10;
  String get _prepKey => 'prep_normal_${_store?['id']}';

  Future<void> _loadNormalPrep() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var normal = prefs.getInt(_prepKey);
      // Changed elsewhere (e.g. in store details) to the usual time or less: not busy any more
      if (normal != null && _prep <= normal) {
        await prefs.remove(_prepKey);
        normal = null;
      }
      if (mounted) setState(() => _normalPrep = normal);
    } catch (_) {}
  }

  Future<void> _setPrep(int minutes, {required bool busy}) async {
    final id = asInt(_store?['id']);
    if (id == null || _savingPrep) return;
    HapticFeedback.selectionClick();
    final before = _prep;
    final normalBefore = _normalPrep;
    setState(() {
      _savingPrep = true;
      _store!['prepMinutes'] = minutes;
      _normalPrep = busy ? (normalBefore ?? before) : null;
    });
    final res = await _api.patch('/stores/$id', {'prepMinutes': minutes});
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _savingPrep = false;
        _store!['prepMinutes'] = before;
        _normalPrep = normalBefore;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? tr(context, 'Could not change it', 'Muutos epäonnistui'))));
      return;
    }
    setState(() => _savingPrep = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_normalPrep == null) {
        await prefs.remove(_prepKey);
      } else {
        await prefs.setInt(_prepKey, _normalPrep!);
      }
    } catch (_) {}
  }

  Widget _prepRow(Color fg) {
    final busy = _normalPrep != null && _prep > _normalPrep!;
    final pill = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(busy ? Icons.local_fire_department_rounded : Icons.timer_outlined, size: 18, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              busy
                  ? tr(context, 'Busy — preparation time $_prep min', 'Kiire — valmisteluaika $_prep min')
                  : tr(context, 'Preparation time $_prep min', 'Valmisteluaika $_prep min'),
              style: TextStyle(fontWeight: FontWeight.w700, color: fg),
            ),
          ),
          if (_savingPrep) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonal(
            style: pill,
            onPressed: _savingPrep || _prep >= 120 ? null : () => _setPrep((_prep + 10).clamp(0, 120), busy: true),
            child: const Text('+10 min'),
          ),
          if (busy)
            OutlinedButton(
              style: pill,
              onPressed: _savingPrep ? null : () => _setPrep(_normalPrep!, busy: false),
              child: Text(tr(context, 'Back to normal (${_normalPrep!} min)', 'Takaisin normaaliin (${_normalPrep!} min)')),
            ),
        ]),
        if (busy)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr(context, 'Customers see longer delivery times while you are busy.', 'Asiakkaat näkevät pidemmät toimitusajat kiireen aikana.'),
                style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.85))),
          ),
      ]),
    );
  }

  String _opensText(Map? opensAt) {
    if (opensAt == null) return '';
    final days = isFinnish(context)
        ? {'mon': 'ma', 'tue': 'ti', 'wed': 'ke', 'thu': 'to', 'fri': 'pe', 'sat': 'la', 'sun': 'su'}
        : {'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun'};
    final inDays = asInt(opensAt['inDays']) ?? 0;
    final when = inDays == 0 ? '' : inDays == 1 ? tr(context, 'tomorrow ', 'huomenna ') : '${days[opensAt['day']] ?? ''} ';
    return ' · ${tr(context, 'opens', 'aukeaa')} $when${opensAt['time']}';
  }

  Widget _availabilityCard() {
    final accepting = _store?['acceptingOrders'] != false;
    final openNow = _store?['openNow'] != false;
    final (title, subtitle, bg, fg) = !accepting
        ? (tr(context, 'Paused', 'Tauolla'), tr(context, 'Customers cannot order right now', 'Asiakkaat eivät voi tilata nyt'), AppTheme.sand, AppTheme.textPrimary)
        : !openNow
            ? (tr(context, 'Closed now', 'Suljettu nyt') + _opensText(_store?['opensAt'] as Map?),
                tr(context, 'Outside your opening hours', 'Aukioloaikojen ulkopuolella'), AppTheme.sunshineLight, const Color(0xFF6A4500))
            : (tr(context, 'Open — taking orders', 'Auki — otetaan tilauksia'),
                tr(context, 'Answer new orders within 10 minutes', 'Vastaa uusiin tilauksiin 10 minuutissa'), AppTheme.primaryLight, AppTheme.primary);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.display(size: 18, color: fg)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85))),
            ]),
          ),
          _switching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
              : Semantics(
                  label: tr(context, 'Take new orders', 'Ota vastaan tilauksia'),
                  child: Switch(value: accepting, onChanged: _setAccepting),
                ),
        ]),
        // Preparation time only matters while the store takes orders
        if (accepting) _prepRow(fg),
      ]),
    );
  }

  Future<void> _loadOrders() async {
    final res = await _api.get('/orders');
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _ordersError = res.error);
      return;
    }
    setState(() {
      _orders = ((res.data['orders'] as List?) ?? []).map((o) => Map<String, dynamic>.from(o)).toList();
      _ordersLoaded = true;
      _ordersError = null;
    });
    // Ring while any paid order is waiting for an answer; stop as soon as none is
    final waiting = _orders.where((o) => o['status'] == 'PENDING' && o['paymentStatus'] == 'SUCCEEDED').length;
    PushService.instance.ringNewOrders(waiting);
  }

  Future<void> _setStatus(Map<String, dynamic> order, String status) async {
    if (status == 'CANCELLED') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(context, 'Decline this order?', 'Hylätäänkö tilaus?')),
          content: Text(tr(context, 'The customer gets a full refund automatically.', 'Asiakas saa automaattisesti täyden hyvityksen.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Back', 'Takaisin'))),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5), minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(context, 'Decline', 'Hylkää')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    HapticFeedback.mediumImpact();
    final res = await _api.patch('/orders/${order['id']}/status', {'status': status});
    if (!mounted) return;
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorMessage)));
    _loadOrders();
  }

  static const _red = Color(0xFFD93025);

  // ── "Can't fulfil": cancel an accepted order with a full refund ─────────
  // The API lets the store cancel CONFIRMED and PROCESSING orders (not once the courier has it);
  // cancelOrderInternal restocks and refunds the whole payment.

  bool _canCancelAccepted(Map<String, dynamic> o) => ['CONFIRMED', 'PROCESSING'].contains(o['status']) && !_isCollected(o);

  Future<void> _cancelAccepted(Map<String, dynamic> o) async {
    final reasons = {
      'DAMAGED': tr(context, 'Item damaged', 'Tuote on vaurioitunut'),
      'OUT_OF_STOCK': tr(context, 'Out of stock', 'Tuote on loppu'),
      'OTHER': tr(context, 'Other', 'Muu syy'),
    };
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(tr(ctx, 'Why can\'t you fulfil order #${o['id']}?', 'Miksi et voi toimittaa tilausta #${o['id']}?'), style: AppTheme.display(size: 19)),
          ),
          for (final e in reasons.entries)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              minTileHeight: 56,
              title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (reason == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: _red, size: 32),
        title: Text(tr(ctx, 'Cancel order #${o['id']}?', 'Perutaanko tilaus #${o['id']}?')),
        content: Text(tr(ctx,
            'The customer is refunded in full automatically, and the items go back into your stock. This cannot be undone.',
            'Asiakkaalle palautetaan koko summa automaattisesti, ja tuotteet palautetaan varastoosi. Tätä ei voi perua.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Keep the order', 'Pidä tilaus'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'Cancel and refund', 'Peru ja palauta rahat')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    // `reason` is sent for the server's records; servers that do not store it yet ignore it
    final res = await _api.patch('/orders/${o['id']}/status', {'status': 'CANCELLED', 'reason': reason});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok
          ? tr(context, 'Order #${o['id']} cancelled. The customer gets a full refund.', 'Tilaus #${o['id']} peruttu. Asiakas saa täyden hyvityksen.')
          : res.errorMessage),
    ));
    _loadOrders();
  }

  Future<void> _editProduct([Map<String, dynamic>? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductEditorScreen(product: p)));
    if (saved == true) _load();
  }

  Future<void> _importProducts() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ImportProductsScreen(storeApproved: _store?['isVerified'] == true)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final newOrders = _orders.where((o) => o['status'] == 'PENDING').length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 16,
        toolbarHeight: 64,
        title: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primaryLight,
            backgroundImage: _store?['logoUrl'] != null ? CachedNetworkImageProvider(_store!['logoUrl']) : null,
            child: _store?['logoUrl'] == null ? const Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 20) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_store?['name'] ?? 'Malvoya Store', style: AppTheme.display(size: 18), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _store?['isVerified'] == true ? AppTheme.primaryLight : AppTheme.sunshineLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _store?['isVerified'] == true ? tr(context, 'Approved — visible to shoppers', 'Hyväksytty — näkyy asiakkaille') : tr(context, 'In review — not visible yet', 'Tarkistuksessa — ei vielä näkyvissä'),
                  style: TextStyle(fontSize: 11.5, color: _store?['isVerified'] == true ? AppTheme.primary : const Color(0xFF8A5A00), fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppTheme.primary, width: 3),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr(context, 'Orders', 'Tilaukset')),
              if (newOrders > 0) ...[
                const SizedBox(width: 6),
                CircleAvatar(radius: 10, backgroundColor: AppTheme.sunshine, child: Text('$newOrders', style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary, fontWeight: FontWeight.w800))),
              ],
            ])),
            Tab(text: tr(context, 'Products', 'Tuotteet')),
            Tab(text: tr(context, 'Drops', 'Julkaisut')),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr(context, 'Store', 'Kauppa')),
              if (_openReturns > 0 || _store?['taxInfoComplete'] == false) ...[
                const SizedBox(width: 6),
                _openReturns > 0
                    ? Semantics(label: tr(context, '$_openReturns open returns', '$_openReturns avointa palautusta'), child: _countBadge(_openReturns))
                    : const CircleAvatar(radius: 4, backgroundColor: AppTheme.sunshine),
              ],
            ])),
          ],
        ),
      ),
      floatingActionButton: switch (_tabs.index) {
        1 => Row(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.extended(
              heroTag: 'import-products',
              onPressed: _importProducts,
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              elevation: 2,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(tr(context, 'Import', 'Tuo')),
            ),
            const SizedBox(width: 10),
            FloatingActionButton.extended(
              heroTag: 'add-product',
              onPressed: () => _editProduct(),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(context, 'Product', 'Tuote')),
            ),
          ]),
        2 => FloatingActionButton.extended(heroTag: 'new-drop', onPressed: () => _dropsKey.currentState?.create(), icon: const Icon(Icons.videocam_rounded), label: Text(tr(context, 'New drop', 'Uusi julkaisu'))),
        _ => null,
      },
      body: _loading
          ? const SkeletonList(button: true)
          : _error != null
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [ErrorState(message: _error, onRetry: _retryLoad)]),
                )
              : TabBarView(controller: _tabs, children: [_ordersTab(), _productsTab(), DropsManager(key: _dropsKey), _storeTab()]),
    );
  }

  void _retryLoad() {
    HapticFeedback.selectionClick();
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  // ── Orders ──────────────────────────────────────────────────────────────

  void _retryOrders() {
    HapticFeedback.selectionClick();
    setState(() => _ordersError = null);
    _loadOrders();
  }

  Widget _ordersTab() {
    final active = _orders.where((o) => ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])).toList();
    final done = _orders.where((o) => !active.contains(o)).take(30).toList();
    return RefreshIndicator(
      onRefresh: () => Future.wait([_loadOrders(), _loadReturns(), PushService.instance.refreshPermission()]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _notificationsOffBar(),
          _availabilityCard(),
          _taxInfoBanner(),
          // First load: placeholders, or what went wrong. Later failures keep the list and show a strip.
          if (!_ordersLoaded && _ordersError != null) ErrorState(message: _ordersError, onRetry: _retryOrders, top: 24),
          if (!_ordersLoaded && _ordersError == null) ...[for (var i = 0; i < 3; i++) SkeletonCard(lines: 4, button: i == 0)],
          if (_ordersLoaded && _ordersError != null) ErrorBanner(message: _ordersError!, onRetry: _retryOrders),
          if (_ordersLoaded && _orders.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              top: 48,
              message: _store?['isVerified'] == true
                  ? tr(context, 'No orders yet. New orders appear here as soon as they are paid, with a sound and a notification. Malvoya is just starting, so the first orders may take a while.',
                      'Ei vielä tilauksia. Uudet tilaukset näkyvät täällä heti maksun jälkeen äänimerkin ja ilmoituksen kera. Malvoya on vasta aloittamassa, joten ensimmäisiä tilauksia voi joutua odottamaan.')
                  : tr(context, 'Your store is in review. Add products and drops meanwhile — they go live when you are approved.', 'Kauppasi on tarkistuksessa. Lisää sillä välin tuotteita ja julkaisuja — ne julkaistaan hyväksynnän jälkeen.'),
            ),
          for (final o in active) _orderCard(o),
          if (done.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(tr(context, 'Earlier', 'Aiemmat'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
          for (final o in done) _orderCard(o, earlier: true),
        ],
      ),
    );
  }

  /// Paid and not answered yet: the store has 10 minutes before the order is refunded automatically.
  bool _isWaiting(Map<String, dynamic> o) => o['status'] == 'PENDING' && o['paymentStatus'] == 'SUCCEEDED';

  Widget _waitingNote(Map<String, dynamic> o) {
    // The 10-minute limit counts from payment (the server's order watchdog)
    final since = DateTime.tryParse('${o['paidAt'] ?? o['createdAt']}')?.toLocal();
    final waited = since == null ? 0 : DateTime.now().difference(since).inMinutes.clamp(0, 999);
    final left = 10 - waited;
    final urgent = left <= 3;
    final fg = urgent ? const Color(0xFFD93025) : const Color(0xFF6A4500);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: urgent ? const Color(0xFFFDECEA) : AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.hourglass_bottom_rounded, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              waited < 1 ? tr(context, 'Just came in', 'Tuli juuri') : tr(context, 'Waiting $waited min', 'Odottanut $waited min'),
              style: TextStyle(fontWeight: FontWeight.w800, color: fg),
            ),
            Text(
              left > 0
                  ? tr(context, 'Unanswered orders are refunded automatically after 10 minutes ($left min left).',
                      'Vastaamattomat tilaukset hyvitetään automaattisesti 10 minuutin jälkeen ($left min jäljellä).')
                  : tr(context, 'Unanswered orders are refunded automatically after 10 minutes. Answer now.',
                      'Vastaamattomat tilaukset hyvitetään automaattisesti 10 minuutin jälkeen. Vastaa nyt.'),
              style: TextStyle(fontSize: 12.5, color: fg, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _itemLine(Map i) {
    final variant = i['variant'] as Map?;
    final options = [
      if ((variant?['size'] ?? '').toString().isNotEmpty) '${tr(context, 'Size', 'Koko')} ${variant!['size']}',
      if ((variant?['color'] ?? '').toString().isNotEmpty) '${tr(context, 'Colour', 'Väri')} ${variant!['color']}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
          child: Text('${i['quantity']}×', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i['product']?['name'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final opt in options)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(8)),
                      child: Text(opt, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  // ── Pickup orders ("Collect in shop") ───────────────────────────────────
  // No courier: accept → "Ready for pickup" (PROCESSING, the customer gets a message) → the customer
  // comes in and the store types the customer's 6-digit code (POST /orders/:id/collect). Orders not
  // collected within 72 h of being marked ready are refunded automatically by the server.

  /// Orders without `fulfilment` (older server) are deliveries.
  bool _isPickup(Map<String, dynamic> o) => '${o['fulfilment'] ?? ''}'.toUpperCase() == 'PICKUP';

  bool _isCollected(Map<String, dynamic> o) => o['collectedAt'] != null || ['DELIVERED', 'COLLECTED'].contains(o['status']);

  /// "14.05", or "3.6. 14.05" when it is not today.
  String _when(DateTime d) {
    final now = DateTime.now();
    final time = '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    final today = d.year == now.year && d.month == now.month && d.day == now.day;
    return today ? time : '${d.day}.${d.month}. $time';
  }

  Widget _pickupBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.storefront_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(tr(context, 'Collect in shop', 'Nouto kaupasta'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      );

  /// Ready and waiting: since when, until when, and the big "Customer is here" button.
  Widget _pickupWaiting(Map<String, dynamic> o) {
    final readyAt = DateTime.tryParse('${o['readyAt'] ?? ''}')?.toLocal();
    final deadline = readyAt?.add(const Duration(hours: 72));
    const fg = Color(0xFF6A4500);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.schedule_rounded, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                readyAt != null
                    ? tr(context, 'Waiting for the customer · ready since ${_when(readyAt)}', 'Odottaa asiakasta · valmiina ${_when(readyAt)} alkaen')
                    : tr(context, 'Waiting for the customer', 'Odottaa asiakasta'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                deadline != null
                    ? tr(context, 'If it is not collected by ${_when(deadline)} (72 h after you marked it ready), the order is refunded automatically.',
                        'Jos tilausta ei noudeta ${_when(deadline)} mennessä (72 h valmiiksi merkitsemisestä), se hyvitetään automaattisesti.')
                    : tr(context, 'Orders not collected within 72 h of being marked ready are refunded automatically.',
                        'Tilaukset, joita ei noudeta 72 tunnin kuluessa valmiiksi merkitsemisestä, hyvitetään automaattisesti.'),
                style: const TextStyle(fontSize: 12.5, color: fg, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 60), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          onPressed: () => _collect(o),
          icon: const Icon(Icons.how_to_reg_rounded),
          label: Text(tr(context, 'Customer is here', 'Asiakas on paikalla')),
        ),
      ),
    ]);
  }

  Future<void> _collect(Map<String, dynamic> o) async {
    HapticFeedback.selectionClick();
    final updated = await showPickupCodeSheet(context, o);
    if (updated == null || !mounted) return;
    setState(() {
      o.addAll(updated);
      if (updated['status'] == null) o['status'] = 'DELIVERED';
      if (o['deliveredAt'] == null) o['collectedAt'] ??= DateTime.now().toIso8601String();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr(context, 'Order #${o['id']} collected. Thank you!', 'Tilaus #${o['id']} noudettu. Kiitos!'))));
    _loadOrders();
  }

  /// The courier checked in at the shop (POST /orders/:id/arrived-at-store) and waits for this order.
  Widget _courierAtCounter(Map<String, dynamic> o, DateTime since) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.directions_bike_rounded, color: AppTheme.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(context, 'Courier at the counter since ${_hhmm(since)}', 'Lähetti tiskillä klo ${_hhmm(since)}'),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          // The number the courier asks for
          Text('#${o['id']}', style: AppTheme.display(size: 26)),
        ]),
      );

  String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

  Widget _orderCard(Map<String, dynamic> o, {bool earlier = false}) {
    final status = o['status'];
    final items = (o['items'] as List?) ?? [];
    final created = DateTime.tryParse('${o['createdAt']}')?.toLocal();
    final pickup = _isPickup(o);
    final collectedAt = DateTime.tryParse('${o['collectedAt'] ?? o['deliveredAt'] ?? ''}')?.toLocal();
    final courierArrived = DateTime.tryParse('${o['courierArrivedAt'] ?? ''}')?.toLocal();
    // Status as a soft pill: new orders are sunny so they stand out, active ones green, finished grey
    final (label, bg, fg) = switch (status) {
      'PENDING' => (tr(context, 'New — accept or decline', 'Uusi — hyväksy tai hylkää'), AppTheme.sunshine, AppTheme.textPrimary),
      'CONFIRMED' when pickup => (tr(context, 'Accepted — get it ready', 'Hyväksytty — valmistele'), AppTheme.primaryLight, AppTheme.primary),
      'CONFIRMED' => (tr(context, 'Accepted — pack it', 'Hyväksytty — pakkaa'), AppTheme.primaryLight, AppTheme.primary),
      'PROCESSING' when pickup => (tr(context, 'Ready for pickup', 'Valmis noudettavaksi'), AppTheme.primaryLight, AppTheme.primary),
      'PROCESSING' => (tr(context, 'Ready — waiting for courier', 'Valmis — odottaa kuriiria'), AppTheme.primaryLight, AppTheme.primary),
      'SHIPPED' => (tr(context, 'With the courier', 'Kuriirilla'), AppTheme.peach, AppTheme.accent),
      _ when pickup && _isCollected(o) => (
          collectedAt != null ? '${tr(context, 'Collected', 'Noudettu')} ${_when(collectedAt)}' : tr(context, 'Collected', 'Noudettu'),
          AppTheme.sand,
          AppTheme.textSecondary
        ),
      'DELIVERED' => (tr(context, 'Delivered', 'Toimitettu'), AppTheme.sand, AppTheme.textSecondary),
      _ => (tr(context, 'Cancelled / refunded', 'Peruttu / hyvitetty'), AppTheme.sand, AppTheme.textSecondary),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
        border: Border.all(color: status == 'PENDING' ? AppTheme.primary : AppTheme.divider, width: status == 'PENDING' ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Large, so it is easy to match with the courier's or customer's order number
            Text('#${o['id']}', style: AppTheme.display(size: 24)),
            if (created != null)
              Flexible(
                child: Text(
                  '  ${earlier ? '${created.day}.${created.month}.${created.year == DateTime.now().year ? '' : created.year} ${_hhmm(created)}' : _when(created)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            const Spacer(),
            Text(euro(context, o['subtotalCents']), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (_canCancelAccepted(o))
              PopupMenuButton<String>(
                tooltip: tr(context, 'More', 'Lisää'),
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (_) => _cancelAccepted(o),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'cancel',
                    height: 52,
                    child: Row(children: [
                      const Icon(Icons.cancel_outlined, color: _red),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(tr(ctx, 'Can\'t fulfil — cancel and refund', 'En voi toimittaa — peru ja palauta rahat'),
                            style: const TextStyle(color: _red, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ],
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (pickup) _pickupBadge(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          ]),
          if (_isWaiting(o)) _waitingNote(o),
          if (courierArrived != null && !pickup && ['CONFIRMED', 'PROCESSING'].contains(status)) _courierAtCounter(o, courierArrived),
          const Divider(height: 20),
          for (final i in items) _itemLine(i as Map),
          if ((asInt(o['tipCents']) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(Icons.volunteer_activism_outlined, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text('${tr(context, 'Tip for the courier', 'Tippi kuriirille')} ${euro(context, o['tipCents'])}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
          if (o['courier'] != null && courierArrived == null && ['CONFIRMED', 'PROCESSING'].contains(status))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${tr(context, 'Courier', 'Kuriiri')} ${(o['courier']['name'] ?? '').toString().split(' ').first} ${tr(context, 'is on the way to you', 'on matkalla luoksesi')}',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ),
          if (status == 'PENDING') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5)),
                  onPressed: () => _setStatus(o, 'CANCELLED'),
                  child: Text(tr(context, 'Decline', 'Hylkää')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => _setStatus(o, 'CONFIRMED'), child: Text(tr(context, 'Accept', 'Hyväksy')))),
            ]),
          ],
          if (status == 'CONFIRMED' && !pickup) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _setStatus(o, 'PROCESSING'), child: Text(tr(context, 'Packed — ready for courier', 'Pakattu — valmis kuriirille')))),
          ],
          if (status == 'CONFIRMED' && pickup) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _setStatus(o, 'PROCESSING'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(tr(context, 'Ready for pickup', 'Valmis noudettavaksi')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr(context, 'The customer gets a message to come and collect it. Orders not collected within 72 h of being marked ready are refunded automatically.',
                    'Asiakas saa viestin, että tilauksen voi noutaa. Tilaukset, joita ei noudeta 72 tunnin kuluessa valmiiksi merkitsemisestä, hyvitetään automaattisesti.'),
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35),
              ),
            ),
          ],
          if (status == 'PROCESSING' && pickup && !_isCollected(o)) _pickupWaiting(o),
        ],
      ),
    );
  }

  // ── Products ────────────────────────────────────────────────────────────

  final Set<dynamic> _savingProducts = {};

  /// Quick "sold out" switch: hides the product from shoppers at once (optimistic), and puts it
  /// back if the server refuses.
  Future<void> _setProductAvailable(Map<String, dynamic> p, bool value) async {
    final id = p['id'];
    final stored = ((_store?['products'] as List?) ?? []).whereType<Map>().where((x) => x['id'] == id).firstOrNull;
    if (stored == null || _savingProducts.contains(id)) return;
    HapticFeedback.selectionClick();
    final before = stored['isAvailable'] != false;
    final wasDraft = _isDraft(p);
    setState(() {
      stored['isAvailable'] = value;
      _savingProducts.add(id);
    });
    final res = await _api.patch('/products/$id', {'isAvailable': value});
    if (!mounted) return;
    setState(() {
      _savingProducts.remove(id);
      if (!res.ok) stored['isAvailable'] = before;
    });
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(!res.ok
          ? (res.error ?? tr(context, 'Could not change it', 'Muutos epäonnistui'))
          : value && wasDraft
              ? tr(context, '${p['name']} is published', '${p['name']} on julkaistu')
          : value
              ? tr(context, '${p['name']} is available again', '${p['name']} on taas saatavilla')
              : tr(context, '${p['name']} is sold out and hidden from shoppers', '${p['name']} on loppu ja piilotettu asiakkailta')),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Ids of the product imports the store has published (null = not known, e.g. older server).
  Set<String>? _publishedImports;

  Future<void> _loadImports() async {
    final res = await _api.get('/products/import');
    if (!mounted) return;
    final jobs = res.ok ? ((res.data['jobs'] as List?) ?? []).whereType<Map>() : null;
    setState(() => _publishedImports = jobs?.where((j) => j['publishedAt'] != null).map((j) => '${j['id']}').toSet());
  }

  /// An imported product that has not been published. Imports arrive hidden (isAvailable=false)
  /// with importJobId set. A hidden product from a published import is still a draft while it lacks
  /// a photo or a price (publishing skips those); otherwise the store switched it off itself.
  bool _isDraft(Map p) {
    if (p['isAvailable'] != false || p['importJobId'] == null) return false;
    final published = _publishedImports;
    if (published == null || !published.contains('${p['importJobId']}')) return true;
    return p['salePriceCents'] == null || ((p['images'] as List?) ?? const []).isEmpty;
  }

  // Search and filters work on the list /stores/my returns (all of the store's products; paging would need
  // a paged product endpoint for owners).
  final _productSearch = TextEditingController();
  String _productFilter = 'all';

  int _stockOf(Map p) {
    final variants = (p['variants'] as List?) ?? const [];
    return variants.isEmpty ? (asInt(p['stockQuantity']) ?? 0) : variants.whereType<Map>().fold<int>(0, (s, v) => s + (asInt(v['stock']) ?? 0));
  }

  bool _matchesFilter(Map<String, dynamic> p) {
    final q = _productSearch.text.trim().toLowerCase();
    if (q.isNotEmpty && !'${p['name'] ?? ''}'.toLowerCase().contains(q)) return false;
    return switch (_productFilter) {
      'visible' => p['isAvailable'] != false,
      'drafts' => _isDraft(p),
      'soldout' => !_isDraft(p) && (p['isAvailable'] == false || _stockOf(p) == 0),
      _ => true,
    };
  }

  Widget _productFilters(int shown, int total) {
    final filters = {
      'all': tr(context, 'All', 'Kaikki'),
      'visible': tr(context, 'Visible', 'Näkyvillä'),
      'drafts': tr(context, 'Drafts', 'Luonnokset'),
      'soldout': tr(context, 'Sold out', 'Loppuneet'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _productSearch,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: tr(context, 'Search your products', 'Hae tuotteistasi'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _productSearch.text.isEmpty
              ? null
              : IconButton(
                  tooltip: tr(context, 'Clear', 'Tyhjennä'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(_productSearch.clear),
                ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final f in filters.entries)
          ChoiceChip(
            label: Text(f.value),
            selected: _productFilter == f.key,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => setState(() => _productFilter = f.key),
          ),
      ]),
      if (shown != total)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(tr(context, '$shown of $total products', '$shown/$total tuotetta'), style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _productsTab() {
    final all = ((_store?['products'] as List?) ?? []).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    final products = all.where(_matchesFilter).toList();
    if (all.isEmpty) {
      // Pull to refresh works here too (e.g. after importing on another phone)
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            EmptyState(
              icon: Icons.checkroom_rounded,
              top: 40,
              message: tr(context, 'Add your first product with photos, price and sizes.', 'Lisää ensimmäinen tuotteesi kuvineen, hintoineen ja kokoineen.'),
              actions: [
                FilledButton.icon(onPressed: () => _editProduct(), icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Add product', 'Lisää tuote'))),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                  child: Column(children: [
                    Text(
                      tr(context, 'Have a Shopify shop or a spreadsheet? Import everything at once.', 'Onko sinulla Shopify-kauppa tai taulukko? Tuo kaikki kerralla.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6A4500), height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _importProducts,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(tr(context, 'Import products', 'Tuo tuotteita')),
                    ),
                  ]),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: products.length + 1 + (products.isEmpty ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == 0) return _productFilters(products.length, all.length);
          if (products.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(tr(context, 'No products match.', 'Ei osuvia tuotteita.'), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            );
          }
          final p = products[index - 1];
          final images = ((p['images'] as List?) ?? const []).map((e) => '$e').toList();
          final variants = (p['variants'] as List?) ?? [];
          final stock = _stockOf(p);
          final available = p['isAvailable'] != false;
          final draft = _isDraft(p);
          final noPrice = p['salePriceCents'] == null;
          final saving = _savingProducts.contains(p['id']);
          return InkWell(
            onTap: () => _editProduct(p),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
              child: Row(children: [
                Opacity(
                  opacity: available ? 1 : 0.45,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 64,
                      height: 78,
                      child: images.isEmpty ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.image_outlined, color: AppTheme.primary)) : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover, placeholder: (_, __) => const Shimmering(child: SkeletonBox(height: double.infinity, radius: 0))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (draft)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(8)),
                        child: Text(tr(context, 'Draft — not published yet', 'Luonnos — ei vielä julkaistu'),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF6A4500))),
                      ),
                    Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(noPrice ? tr(context, 'No price yet', 'Ei vielä hintaa') : euro(context, p['salePriceCents']),
                        style: TextStyle(fontWeight: FontWeight.w600, color: noPrice ? AppTheme.accent : AppTheme.textPrimary)),
                    Text(
                      [
                        stock == 0 ? tr(context, 'Out of stock', 'Ei varastossa') : '$stock ${tr(context, 'in stock', 'varastossa')}',
                        if (variants.isNotEmpty) '${variants.length} ${tr(context, 'options', 'vaihtoehtoa')}',
                        if (images.isEmpty) tr(context, 'No photo', 'Ei kuvaa'),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: stock == 0 || images.isEmpty ? AppTheme.accent : AppTheme.textSecondary),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                // Wolt-style quick switch: off = sold out, hidden from shoppers until switched back on
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                    label: tr(context, 'Available to shoppers', 'Saatavilla asiakkaille'),
                    child: Switch(value: available, onChanged: saving ? null : (v) => _setProductAvailable(p, v)),
                  ),
                  Text(
                    available
                        ? tr(context, 'Available', 'Saatavilla')
                        : draft
                            ? tr(context, 'Hidden', 'Piilossa')
                            : tr(context, 'Sold out', 'Loppu'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: available ? AppTheme.primary : draft ? const Color(0xFF6A4500) : AppTheme.accent),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Store ───────────────────────────────────────────────────────────────

  Widget _storeTab() {
    final paid = _orders.where((o) => o['paymentStatus'] == 'SUCCEEDED' && o['status'] != 'CANCELLED').toList();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    // Both numbers cover the same 7 days (the order list is limited to the latest 200 orders)
    final week = paid.where((o) => (DateTime.tryParse('${o['createdAt']}') ?? DateTime(2000)).isAfter(weekAgo)).toList();
    final weekSales = week.fold<int>(0, (s, o) => s + (asInt(o['subtotalCents']) ?? 0));
    final reviews = asInt(_store?['totalReviews']) ?? 0;
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Widget? badge}) => ListTile(
          leading: CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(icon, color: AppTheme.primary)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: badge == null
              ? const Icon(Icons.chevron_right_rounded)
              : Row(mainAxisSize: MainAxisSize.min, children: [badge, const Icon(Icons.chevron_right_rounded)]),
          onTap: onTap,
        );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _stat(tr(context, 'Sales, 7 days', 'Myynti, 7 pv'), euro(context, weekSales)),
          const SizedBox(width: 10),
          _stat(tr(context, 'Orders, 7 days', 'Tilaukset, 7 pv'), '${week.length}'),
          const SizedBox(width: 10),
          _stat(tr(context, 'Rating', 'Arvio'), reviews > 0 ? '★ ${_store?['rating']}' : '—'),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            tile(Icons.account_balance_outlined, tr(context, 'Payouts', 'Tilitykset'),
                tr(context, 'Through Stripe · commission ${commissionText(_store?['commissionRate'] as num?)}', 'Stripen kautta · provisio ${commissionText(_store?['commissionRate'] as num?)}'),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayoutsScreen(commissionRate: _store?['commissionRate'] as num?)))),
            const Divider(height: 1),
            tile(
              Icons.assignment_return_outlined,
              tr(context, 'Returns', 'Palautukset'),
              _openReturns > 0
                  ? tr(context, '$_openReturns open — answer them in the app', '$_openReturns avointa — käsittele ne sovelluksessa')
                  : tr(context, 'Approve and refund returns', 'Hyväksy ja hyvitä palautukset'),
              () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsManager()));
                if (mounted) _loadReturns();
              },
              badge: _openReturns > 0 ? _countBadge(_openReturns) : null,
            ),
            const Divider(height: 1),
            tile(Icons.calendar_month_outlined, tr(context, 'Monthly statements', 'Kuukausiraportit'),
                tr(context, 'Sales, commission, refunds and payouts per month', 'Myynti, provisio, hyvitykset ja tilitykset kuukausittain'),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatementsScreen()))),
            const Divider(height: 1),
            tile(
              Icons.receipt_long_outlined,
              tr(context, 'Tax information', 'Verotiedot'),
              _store?['taxInfoComplete'] == false
                  ? tr(context, 'Missing — required by EU law (DAC7)', 'Puuttuu — EU-laki (DAC7) edellyttää')
                  : tr(context, 'Reported to the Finnish Tax Administration (DAC7)', 'Ilmoitetaan Verohallinnolle (DAC7)'),
              _openTaxInfo,
              badge: _store?['taxInfoComplete'] == false ? const CircleAvatar(radius: 5, backgroundColor: AppTheme.sunshine) : null,
            ),
            const Divider(height: 1),
            tile(Icons.schedule_rounded, tr(context, 'Opening hours', 'Aukioloajat'),
                _store?['openingHours'] == null ? tr(context, 'Not set — open whenever orders are on', 'Ei asetettu — auki aina, kun tilaukset ovat päällä') : tr(context, 'Closed automatically outside them', 'Suljettu automaattisesti niiden ulkopuolella'),
                () async {
              final id = asInt(_store?['id']);
              if (id == null) return;
              final saved = await Navigator.push<bool>(context, MaterialPageRoute(
                  builder: (_) => OpeningHoursScreen(storeId: id, initial: (_store?['openingHours'] as Map?)?.cast<String, dynamic>())));
              if (saved == true) _load();
            }),
            const Divider(height: 1),
            tile(Icons.storefront_outlined, tr(context, 'Store details', 'Kaupan tiedot'), tr(context, 'Name, address, pictures, seller type', 'Nimi, osoite, kuvat, myyjätyyppi'), () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreSetupScreen()));
              _load();
            }),
            const Divider(height: 1),
            const GoogleLinkTile(leading: CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(Icons.link_rounded, color: AppTheme.primary))),
            const Divider(height: 1),
            tile(Icons.help_outline_rounded, tr(context, 'Help', 'Apua'), tr(context, 'Answers for sellers', 'Vastauksia myyjille'),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatbotScreen(commissionRate: _store?['commissionRate'] as num?)))),
            const Divider(height: 1),
            tile(Icons.gavel_rounded, tr(context, 'Seller terms and privacy', 'Myyjän ehdot ja tietosuoja'), tr(context, 'The rules you agreed to', 'Hyväksymäsi säännöt'), () => openLegal('sellers')),
            const Divider(height: 1),
            tile(Icons.code_rounded, tr(context, 'Open-source licences', 'Avoimen lähdekoodin lisenssit'), tr(context, 'Software this app is built with', 'Ohjelmistot, joilla sovellus on tehty'),
                () => showLicensePage(context: context, applicationName: 'Malvoya Store', applicationLegalese: '© Malvoya')),
            const Divider(height: 1),
            const DeleteAccountTile(leading: CircleAvatar(backgroundColor: Color(0xFFFDECEA), child: Icon(Icons.delete_forever_rounded, color: Color(0xFFD93025)))),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
          icon: const Icon(Icons.logout_rounded),
          label: Text(tr(context, 'Sign out', 'Kirjaudu ulos')),
        ),
      ],
    ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}
