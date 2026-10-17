import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/haptics.dart';
import '../core/images.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
import '../core/delete_account_tile.dart';
import '../services/socket_service.dart';
import '../core/push_service.dart';
import '../widgets/language_sheet.dart';
import '../widgets/loading_states.dart';
import '../widgets/setup_checklist.dart';
import 'chatbot.dart';
import 'drops_manager.dart';
import 'import_products_screen.dart';
import 'incoming_order_sheet.dart';
import 'payouts_screen.dart';
import 'pickup_code_sheet.dart';
import 'product_editor.dart';
import 'product_quick_edit.dart';
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
    _returnsSub = VendorSocketService().returnsNew.listen(_onNewReturn);
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
  StreamSubscription<Map<String, dynamic>>? _returnsSub;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
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
    _returnsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.stopRinging();
    _waitingIds.dispose();
    VendorSocketService().removeListener(_onSocket);
    _tabs.dispose();
    _productSearch.dispose();
    _searchDebounce?.cancel();
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
      _loadProductPage(reset: true);
    }
    await _loadOrders();
  }

  // ── Open returns (badge on the Store tab) ───────────────────────────────
  // The count is refreshed on load, on resume, with pull to refresh and when the server announces a
  // new return request (socket `return:new`; the store also gets a push).

  static const _openReturnStatuses = {'REQUESTED', 'APPROVED', 'IN_TRANSIT', 'RECEIVED'};
  int _openReturns = 0;

  Future<void> _loadReturns() async {
    final res = await _api.get('/returns');
    if (!mounted || !res.ok) return;
    final open = ((res.data['returns'] as List?) ?? const []).whereType<Map>().where((r) => _openReturnStatuses.contains(r['status'])).length;
    if (open != _openReturns) setState(() => _openReturns = open);
  }

  void _onNewReturn(Map<String, dynamic> data) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _loadReturns();
    // The Returns screen refreshes itself when it is open
    if (ReturnsManager.openCount > 0) return;
    final orderId = data['orderId'] ?? (data['order'] is Map ? data['order']['id'] : null);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(
      backgroundColor: AppTheme.sunshineLight,
      leading: const Icon(Icons.assignment_return_outlined, color: Color(0xFF6A4500)),
      content: Text(
        orderId != null
            ? tr(context, 'New return request for order #$orderId', 'Uusi palautuspyyntö tilaukselle #$orderId')
            : tr(context, 'New return request', 'Uusi palautuspyyntö'),
        style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTheme.textSecondary),
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
          child: Text(tr(context, 'Later', 'Myöhemmin')),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            _openReturnsScreen();
          },
          child: Text(tr(context, 'Open', 'Avaa')),
        ),
      ],
    ));
  }

  Future<void> _openReturnsScreen() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsManager()));
    if (mounted) _loadReturns();
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
    final waiting = _orders.where(_isWaiting).toList();
    PushService.instance.ringNewOrders(waiting.length);
    _waitingIds.value = waiting.map((o) => o['id'] as Object?).toSet();
    _showNextIncoming();
  }

  // ── New-order moment ────────────────────────────────────────────────────
  // Each paid order that waits for an answer is shown once as a full-screen sheet (while the app is
  // on screen). Closing it ("answer later") keeps the alert ringing and the order on top of the list.

  final _waitingIds = ValueNotifier<Set<Object?>>({});
  final Set<Object?> _announced = {};
  bool _showingIncoming = false;
  bool _foreground = true;

  Future<void> _showNextIncoming() async {
    if (_showingIncoming || !_foreground || !mounted) return;
    final next = _orders.where((o) => _isWaiting(o) && !_announced.contains(o['id'])).toList();
    if (next.isEmpty) return;
    final order = next.last; // the oldest first (the list is newest first)
    _announced.add(order['id']);
    _showingIncoming = true;
    if (_tabs.index != 0) _tabs.animateTo(0);
    await showIncomingOrder(context, order: order, waitingIds: _waitingIds, onAnswer: (status) => _setStatus(order, status));
    _showingIncoming = false;
    if (mounted) _showNextIncoming();
  }

  /// True when the server took the change (the incoming-order sheet closes then).
  Future<bool> _setStatus(Map<String, dynamic> order, String status) async {
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
      if (ok != true) return false;
    }
    Haptics.tap();
    final res = await _api.patch('/orders/${order['id']}/status', {'status': status});
    if (!mounted) return res.ok;
    if (!res.ok) {
      Haptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorMessage)));
    } else if (status == 'CONFIRMED') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr(context, 'Order #${order['id']} accepted', 'Tilaus #${order['id']} hyväksytty'))));
    }
    _loadOrders();
    return res.ok;
  }

  static const _red = Color(0xFFD93025);

  // ── "Can't fulfil": cancel an accepted order with a full refund ─────────
  // The API lets the store cancel CONFIRMED and PROCESSING orders (not once the courier has it);
  // cancelOrderInternal restocks and refunds the whole payment.

  /// What the customer reads as the reason (≤ 200 characters, "Finnish / English").
  static const _customerReasons = {
    'DAMAGED': 'Kauppa peruutti tilauksen: tuote on vaurioitunut. / The store cancelled the order: the item is damaged.',
    'OUT_OF_STOCK': 'Kauppa peruutti tilauksen: tuote on loppunut. / The store cancelled the order: the item is out of stock.',
    'OTHER': 'Kauppa ei pysty toimittamaan tilausta. / The store cannot fulfil the order.',
  };

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
    // The server stores `reason` as the cancel reason and shows it to the customer, whose language the
    // store does not know, so it is written in Finnish and English (servers before 2.10 ignore it)
    final res = await _api.patch('/orders/${o['id']}/status', {'status': 'CANCELLED', 'reason': _customerReasons[reason] ?? _customerReasons['OTHER']!});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok
          ? tr(context, 'Order #${o['id']} cancelled. The customer gets a full refund.', 'Tilaus #${o['id']} peruttu. Asiakas saa täyden hyvityksen.')
          : res.errorMessage),
    ));
    _loadOrders();
  }

  // ── Setup checklist ────────────────────────────────────────────────────

  /// Products the store has: /stores/my's list (newest 100), or the paged list's total when it was
  /// loaded without a search or filter. Null until the store is known.
  int? get _productCount {
    final embedded = (_store?['products'] as List?)?.length;
    final pagedAll = _paged == true && _pageItemsKey == 'all|' ? _pageTotal : null;
    if (embedded == null) return pagedAll;
    return pagedAll != null && pagedAll > embedded ? pagedAll : embedded;
  }

  Future<void> _openSetupStep(SetupStep step) async {
    switch (step) {
      case SetupStep.details:
      case SetupStep.pin:
        // The store details screen holds the address, the map pin, the description and the logo
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreSetupScreen()));
        if (mounted) _load();
      case SetupStep.hours:
        final id = asInt(_store?['id']);
        if (id == null) return;
        final saved = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => OpeningHoursScreen(storeId: id, initial: (_store?['openingHours'] as Map?)?.cast<String, dynamic>())));
        if (saved == true && mounted) _load();
      case SetupStep.payouts:
        await Navigator.push(context, MaterialPageRoute(builder: (_) => PayoutsScreen(commissionRate: _store?['commissionRate'] as num?)));
        // Stripe's status is saved on the store when the payouts screen checks it
        if (mounted) _load();
      case SetupStep.product:
        await _editProduct();
      case SetupStep.tax:
        await _openTaxInfo();
      case SetupStep.approval:
        break;
    }
  }

  // ── Today ──────────────────────────────────────────────────────────────
  // Worked out from the order list the server sent (its latest 200 orders): paid orders placed
  // today, their item totals, and how many need the store right now. Nothing is estimated.

  Widget _todayHeader() {
    final now = DateTime.now();
    bool isToday(Map o) {
      final d = DateTime.tryParse('${o['paidAt'] ?? o['createdAt'] ?? ''}')?.toLocal();
      return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    }

    final today = _orders.where((o) => o['paymentStatus'] == 'SUCCEEDED' && o['status'] != 'CANCELLED' && isToday(o)).toList();
    final sales = today.fold<int>(0, (s, o) => s + (asInt(o['subtotalCents']) ?? 0));
    // Waiting for the store: new paid orders to answer, accepted orders to pack or get ready
    final needYou = _orders.where((o) => _isWaiting(o) || o['status'] == 'CONFIRMED').length;
    Widget tile(String label, String value, {bool highlight = false}) => Expanded(
          child: Semantics(
            label: '$label: $value',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: highlight ? AppTheme.sunshine : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: highlight ? null : Border.all(color: AppTheme.divider),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 2, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600, height: 1.2)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppTheme.display(size: 22))),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(tr(context, 'Orders today', 'Tilauksia tänään'), '${today.length}'),
          const SizedBox(width: 8),
          tile(tr(context, 'Sales today', 'Myynti tänään'), euro(context, sales)),
          const SizedBox(width: 8),
          tile(tr(context, 'Waiting for you', 'Odottaa sinua'), '$needYou', highlight: needYou > 0),
        ]),
      ),
    );
  }

  // ── Quick edit and undo ────────────────────────────────────────────────

  /// Every copy of a product the dashboard shows (the paged list and /stores/my's list).
  List<Map> _copiesOf(Object? id) => [
        ...((_store?['products'] as List?) ?? []).whereType<Map>().where((x) => x['id'] == id),
        ..._pageItems.where((x) => x['id'] == id),
      ];

  Future<void> _quickEdit(Map<String, dynamic> p) async {
    Haptics.select();
    final result = await showProductQuickEdit(context, product: p, api: _api);
    if (!mounted || result == null) return;
    switch (result) {
      case QuickEditOpenEditor():
        await _editProduct(p);
      case QuickEditRemove():
        await _removeWithUndo(p);
      case QuickEditSaved(:final product, :final sent):
        setState(() {
          for (final t in _copiesOf(p['id'])) {
            t.addAll(product ?? sent);
          }
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr(context, '${p['name']} saved', '${p['name']} tallennettu')), duration: const Duration(seconds: 2)));
    }
  }

  /// Takes the product out of the list at once and removes it on the server only when the
  /// snackbar closes without "Undo", so a slip of the finger costs nothing.
  Future<void> _removeWithUndo(Map<String, dynamic> p) async {
    final id = p['id'];
    // Taken now: the screen may be gone when the undo time is over
    final api = _api;
    final storeList = _store?['products'] as List?;
    final storeIndex = storeList?.indexWhere((x) => x is Map && x['id'] == id) ?? -1;
    final pageIndex = _pageItems.indexWhere((x) => x['id'] == id);
    final storeCopy = storeIndex >= 0 ? storeList![storeIndex] : null;
    final pageCopy = pageIndex >= 0 ? _pageItems[pageIndex] : null;
    Haptics.tap();
    setState(() {
      if (storeIndex >= 0) storeList!.removeAt(storeIndex);
      if (pageIndex >= 0) {
        _pageItems.removeAt(pageIndex);
        if (_pageTotal > 0) _pageTotal--;
      }
    });
    void restore() {
      if (!mounted) return;
      setState(() {
        if (storeCopy != null) storeList!.insert(storeIndex.clamp(0, storeList.length), storeCopy);
        if (pageCopy != null) {
          _pageItems.insert(pageIndex.clamp(0, _pageItems.length), pageCopy);
          _pageTotal++;
        }
      });
    }

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final removed = tr(context, '${p['name']} removed', '${p['name']} poistettu');
    final undo = tr(context, 'Undo', 'Kumoa');
    final reason = await messenger
        .showSnackBar(SnackBar(content: Text(removed), duration: const Duration(seconds: 5), action: SnackBarAction(label: undo, onPressed: () {})))
        .closed;
    if (reason == SnackBarClosedReason.action) {
      Haptics.select();
      restore();
      return;
    }
    final res = await api.delete('/products/$id');
    if (res.ok) return;
    restore();
    messenger.showSnackBar(SnackBar(content: Text(res.errorMessage)));
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
            backgroundImage: _store?['logoUrl'] != null ? netImageProvider(context, '${_store!['logoUrl']}', size: 44) : null,
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
    // Orders the courier is bringing back stay on top for a while, so the store expects them at the counter
    final active = _orders.where((o) => ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status']) || _isBringingBack(o)).toList();
    final done = _orders.where((o) => !active.contains(o)).take(30).toList();
    return RefreshIndicator(
      onRefresh: () => Future.wait([_loadOrders(), _loadReturns(), PushService.instance.refreshPermission()]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _notificationsOffBar(),
          if (_store != null)
            SetupChecklist(store: _store!, productCount: _productCount, onOpen: _openSetupStep),
          _availabilityCard(),
          if (_ordersLoaded) _todayHeader(),
          // The checklist already lists the tax step while it is shown
          if (_store == null || SetupChecklist.isComplete(_store!, _productCount)) _taxInfoBanner(),
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

  // ── Courier cannot deliver (API 2.10: deliveryProblemAt / return-to-store) ────
  // The courier reports a problem at the door (the customer gets a push to answer in the chat). After
  // 10 minutes the courier may bring the order back; the server then cancels it with the reason
  // "Customer could not be reached". Older servers send neither field.

  static final _notReachedReason = RegExp(r'could not be reached|ei tavoitettu|ei saatu kiinni', caseSensitive: false);

  bool _notDeliveredCustomerAway(Map<String, dynamic> o) =>
      o['status'] == 'CANCELLED' && (o['deliveryProblemAt'] != null || _notReachedReason.hasMatch('${o['cancelReason'] ?? ''}'));

  /// Cancelled because the customer could not be reached, within the last 3 hours: the courier is
  /// probably on the way back with the items.
  bool _isBringingBack(Map<String, dynamic> o) {
    if (!_notDeliveredCustomerAway(o)) return false;
    final at = DateTime.tryParse('${o['cancelledAt'] ?? o['updatedAt'] ?? ''}')?.toLocal();
    return at != null && DateTime.now().difference(at) < const Duration(hours: 3);
  }

  String _problemReason(Map<String, dynamic> o) => switch ('${o['deliveryProblemReason'] ?? ''}') {
        'CUSTOMER_UNAVAILABLE' => tr(context, 'The customer is not answering.', 'Asiakas ei vastaa.'),
        'WRONG_ADDRESS' => tr(context, 'The address seems to be wrong.', 'Osoite näyttää olevan väärä.'),
        'OTHER' => tr(context, 'Another problem at the address.', 'Muu ongelma osoitteessa.'),
        _ => '',
      };

  Widget? _deliveryProblemNote(Map<String, dynamic> o) {
    final problemAt = DateTime.tryParse('${o['deliveryProblemAt'] ?? ''}')?.toLocal();
    if (o['status'] == 'SHIPPED' && problemAt != null) {
      final returnFrom = problemAt.add(const Duration(minutes: 10));
      final reason = _problemReason(o);
      return _problemBox(
        icon: Icons.report_problem_rounded,
        bg: const Color(0xFFFDECEA),
        fg: _red,
        title: tr(context, "The courier can't reach the customer", 'Kuriiri ei tavoita asiakasta'),
        body: [
          if (reason.isNotEmpty) reason,
          tr(context,
              'The customer has been asked to answer in the chat. If they cannot be reached, the courier may bring the order back to your shop from ${_hhmm(returnFrom)}.',
              'Asiakasta on pyydetty vastaamaan chatissa. Jos asiakasta ei tavoiteta, kuriiri voi tuoda tilauksen takaisin kauppaasi klo ${_hhmm(returnFrom)} alkaen.'),
        ].join(' '),
      );
    }
    if (_isBringingBack(o)) {
      return _problemBox(
        icon: Icons.keyboard_return_rounded,
        bg: AppTheme.sunshine,
        fg: AppTheme.textPrimary,
        title: tr(context, 'Courier is bringing order #${o['id']} back', 'Kuriiri tuo tilauksen #${o['id']} takaisin'),
        body: tr(context,
            'The customer could not be reached, so the order was cancelled. Take the items back from the courier at the counter and check them.',
            'Asiakasta ei tavoitettu, joten tilaus peruttiin. Ota tuotteet kuriirilta vastaan tiskillä ja tarkista ne.'),
      );
    }
    if (_notDeliveredCustomerAway(o)) {
      return _problemBox(
        icon: Icons.keyboard_return_rounded,
        bg: AppTheme.sand,
        fg: AppTheme.textSecondary,
        title: tr(context, 'Not delivered: the customer could not be reached', 'Ei toimitettu: asiakasta ei tavoitettu'),
      );
    }
    return null;
  }

  Widget _problemBox({required IconData icon, required Color bg, required Color fg, required String title, String? body}) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
              if (body != null && body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(body, style: TextStyle(fontSize: 12.5, color: fg, height: 1.35)),
                ),
            ]),
          ),
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
      _ when _isBringingBack(o) => (tr(context, 'Cancelled — coming back to the shop', 'Peruttu — palautuu kauppaan'), AppTheme.sunshine, AppTheme.textPrimary),
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
          if (_deliveryProblemNote(o) case final note?) note,
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
    // The same product may be in the paged list and in the /stores/my list
    final targets = <Map>[
      ...((_store?['products'] as List?) ?? []).whereType<Map>().where((x) => x['id'] == id),
      ..._pageItems.where((x) => x['id'] == id),
    ];
    if (targets.isEmpty || _savingProducts.contains(id)) return;
    HapticFeedback.selectionClick();
    final before = targets.first['isAvailable'] != false;
    final wasDraft = _isDraft(p);
    setState(() {
      for (final t in targets) {
        t['isAvailable'] = value;
      }
      _savingProducts.add(id);
    });
    final res = await _api.patch('/products/$id', {'isAvailable': value});
    if (!mounted) return;
    setState(() {
      _savingProducts.remove(id);
      if (!res.ok) {
        for (final t in targets) {
          t['isAvailable'] = before;
        }
      }
    });
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (!res.ok) Haptics.warning();
    messenger.showSnackBar(SnackBar(
      // Hiding is one tap away from a mistake: offer to put it straight back
      action: res.ok && !value ? SnackBarAction(label: tr(context, 'Undo', 'Kumoa'), onPressed: () => _setProductAvailable(p, true)) : null,
      content: Text(!res.ok
          ? (res.error ?? tr(context, 'Could not change it', 'Muutos epäonnistui'))
          : value && wasDraft
              ? tr(context, '${p['name']} is published', '${p['name']} on julkaistu')
          : value
              ? tr(context, '${p['name']} is available again', '${p['name']} on taas saatavilla')
              : tr(context, '${p['name']} is sold out and hidden from shoppers', '${p['name']} on loppu ja piilotettu asiakkailta')),
      duration: Duration(seconds: res.ok && !value ? 4 : 2),
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

  // Products tab. From API 2.10 it pages through GET /stores/my/products (30 at a time, more while
  // scrolling) and the server searches and filters. Older servers answer 404: then search and filters
  // work on the products embedded in /stores/my, as before.
  final _productSearch = TextEditingController();
  String _productFilter = 'all';
  Timer? _searchDebounce;

  /// null = not known yet (the /stores/my list is shown meanwhile), false = older server.
  bool? _paged;
  final List<Map<String, dynamic>> _pageItems = [];
  int _pageTotal = 0;
  int _page = 0;
  bool _pageLoading = false;
  bool _pageHasMore = false;
  String? _pageError;
  int _pageGeneration = 0;
  static const _pageSize = 30;

  /// The search and filter the listed products were loaded for.
  String _pageItemsKey = '';
  String get _pageQueryKey => '$_productFilter|${_productSearch.text.trim()}';

  Future<void> _loadProductPage({bool reset = false}) async {
    if (_paged == false) return;
    if (!reset && (_pageLoading || !_pageHasMore)) return;
    final generation = reset ? ++_pageGeneration : _pageGeneration;
    final page = reset ? 1 : _page + 1;
    final q = _productSearch.text.trim();
    final key = _pageQueryKey;
    setState(() => _pageLoading = true);
    final res = await _api.get('/stores/my/products', query: {
      'page': '$page',
      'limit': '$_pageSize',
      'filter': _productFilter,
      if (q.isNotEmpty) 'q': q,
    });
    // A newer search or filter has started meanwhile
    if (!mounted || generation != _pageGeneration) return;
    if (res.status == 404) {
      setState(() {
        _paged = false;
        _pageLoading = false;
        _pageItems.clear();
      });
      return;
    }
    if (!res.ok || res.data['products'] is! List) {
      setState(() {
        _pageLoading = false;
        _pageError = res.errorMessage;
        // Never show the products of the previous search under the new one
        if (key != _pageItemsKey) {
          _pageItems.clear();
          _pageTotal = 0;
          _pageHasMore = false;
        }
      });
      return;
    }
    final items = (res.data['products'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    setState(() {
      _paged = true;
      if (reset) _pageItems.clear();
      final seen = _pageItems.map((p) => p['id']).toSet();
      _pageItems.addAll(items.where((p) => seen.add(p['id'])));
      _page = page;
      _pageTotal = asInt(res.data['total']) ?? _pageItems.length;
      _pageHasMore = items.isNotEmpty && _pageItems.length < _pageTotal;
      _pageLoading = false;
      _pageError = null;
      _pageItemsKey = key;
    });
  }

  void _retryProductPage() {
    HapticFeedback.selectionClick();
    setState(() => _pageError = null);
    _loadProductPage(reset: _pageItems.isEmpty || _pageItemsKey != _pageQueryKey);
  }

  /// New search text or filter: the server is asked again (after a short pause while typing).
  void _productQueryChanged({bool debounce = false}) {
    setState(() {});
    if (_paged == false) return;
    _searchDebounce?.cancel();
    if (debounce) {
      _searchDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) _loadProductPage(reset: true);
      });
    } else {
      _loadProductPage(reset: true);
    }
  }

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

  Widget _productFilters(String? countText) {
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
        onChanged: (_) => _productQueryChanged(debounce: true),
        onSubmitted: (_) => _productQueryChanged(),
        decoration: InputDecoration(
          hintText: tr(context, 'Search your products', 'Hae tuotteistasi'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _productSearch.text.isEmpty
              ? null
              : IconButton(
                  tooltip: tr(context, 'Clear', 'Tyhjennä'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _productSearch.clear();
                    _productQueryChanged();
                  },
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
            onSelected: (_) {
              if (_productFilter == f.key) return;
              _productFilter = f.key;
              _productQueryChanged();
            },
          ),
      ]),
      if (countText != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(countText, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _productsEmpty() => RefreshIndicator(
        // Pull to refresh works here too (e.g. after importing on another phone)
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

  Widget _productsTab() {
    final paged = _paged == true;
    final embedded = ((_store?['products'] as List?) ?? []).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    final products = paged ? _pageItems : embedded.where(_matchesFilter).toList();
    final narrowed = _productSearch.text.trim().isNotEmpty || _productFilter != 'all';
    final storeHasNone = paged ? (_pageItems.isEmpty && _pageTotal == 0 && !narrowed && !_pageLoading && _pageError == null) : embedded.isEmpty;
    if (storeHasNone) return _productsEmpty();

    final countText = paged
        ? (narrowed ? tr(context, '$_pageTotal products', '$_pageTotal tuotetta') : null)
        : (products.length != embedded.length ? tr(context, '${products.length} of ${embedded.length} products', '${products.length}/${embedded.length} tuotetta') : null);
    final footer = paged && (_pageHasMore || _pageLoading || _pageError != null);
    final noMatch = products.isEmpty && !(paged && (_pageLoading || _pageError != null));
    final count = 1 + products.length + (noMatch ? 1 : 0) + (footer ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == 0) return _productFilters(countText);
          final i = index - 1;
          if (i < products.length) {
            // Close to the end: fetch the next page
            if (paged && _pageHasMore && !_pageLoading && _pageError == null && i >= products.length - 5) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadProductPage();
              });
            }
            return _productTile(products[i]);
          }
          if (noMatch) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(tr(context, 'No products match.', 'Ei osuvia tuotteita.'), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            );
          }
          if (_pageError != null) return ErrorBanner(message: _pageError!, onRetry: _retryProductPage);
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))),
          );
        },
      ),
    );
  }

  Widget _productTile(Map<String, dynamic> p) {
    final images = ((p['images'] as List?) ?? const []).map((e) => '$e').toList();
    final variants = (p['variants'] as List?) ?? [];
    final stock = _stockOf(p);
    final available = p['isAvailable'] != false;
    final draft = _isDraft(p);
    final noPrice = p['salePriceCents'] == null;
    final saving = _savingProducts.contains(p['id']);
    return InkWell(
      // Tap: price, stock and visibility in a sheet. Long press: the full editor.
      onTap: () => _quickEdit(p),
      onLongPress: () => _editProduct(p),
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
                child: images.isEmpty
                    ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.image_outlined, color: AppTheme.primary))
                    : NetImage(images.first, width: 64, height: 78),
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
              _openReturnsScreen,
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
            tile(Icons.language_rounded, tr(context, 'Language', 'Kieli'),
                tr(context, 'English — also for your notifications and emails', 'Suomi — myös ilmoituksissa ja sähköposteissa'), () => showLanguageSheet(context)),
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
