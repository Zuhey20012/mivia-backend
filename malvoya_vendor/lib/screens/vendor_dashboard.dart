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
import 'chatbot.dart';
import 'drops_manager.dart';
import 'payouts_screen.dart';
import 'product_editor.dart';
import 'returns_manager.dart';
import 'store_setup.dart';
import 'opening_hours_screen.dart';

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

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VendorSocketService().connect(Provider.of<AuthService>(context, listen: false).accessToken ?? '');
      _load();
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
    if (state == AppLifecycleState.resumed) _loadOrders();
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
    super.dispose();
  }

  void _onSocket() {
    HapticFeedback.mediumImpact();
    _loadOrders();
  }

  Future<void> _load() async {
    final res = await _api.get('/stores/my');
    if (!mounted) return;
    if (res.status == 404) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StoreSetupScreen()));
      return;
    }
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok) _store = Map<String, dynamic>.from(res.data['store']);
    });
    if (res.ok) _loadNormalPrep();
    await _loadOrders();
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
    if (!mounted || !res.ok) return;
    setState(() => _orders = ((res.data['orders'] as List?) ?? []).map((o) => Map<String, dynamic>.from(o)).toList());
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
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Decline', 'Hylkää'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    HapticFeedback.mediumImpact();
    final res = await _api.patch('/orders/${order['id']}/status', {'status': status});
    if (!mounted) return;
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
    _loadOrders();
  }

  Future<void> _editProduct([Map<String, dynamic>? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductEditorScreen(product: p)));
    if (saved == true) _load();
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
                  _store?['isVerified'] == true ? tr(context, 'Live — customers can order', 'Julkaistu — asiakkaat voivat tilata') : tr(context, 'In review — not visible yet', 'Tarkistuksessa — ei vielä näkyvissä'),
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
            Tab(text: tr(context, 'Store', 'Kauppa')),
          ],
        ),
      ),
      floatingActionButton: switch (_tabs.index) {
        1 => FloatingActionButton.extended(onPressed: () => _editProduct(), icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Product', 'Tuote'))),
        2 => FloatingActionButton.extended(onPressed: () => _dropsKey.currentState?.create(), icon: const Icon(Icons.videocam_rounded), label: Text(tr(context, 'New drop', 'Uusi julkaisu'))),
        _ => null,
      },
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: Text(tr(context, 'Try again', 'Yritä uudelleen')))]))
              : TabBarView(controller: _tabs, children: [_ordersTab(), _productsTab(), DropsManager(key: _dropsKey), _storeTab()]),
    );
  }

  // ── Orders ──────────────────────────────────────────────────────────────

  Widget _ordersTab() {
    final active = _orders.where((o) => ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])).toList();
    final done = _orders.where((o) => !active.contains(o)).take(30).toList();
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _availabilityCard(),
          if (_orders.isEmpty) ...[
            const SizedBox(height: 64),
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(color: AppTheme.sunshineLight, shape: BoxShape.circle),
                child: const Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFF8A5A00)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Text(
                _store?['isVerified'] == true
                    ? tr(context, 'No orders yet. New orders appear here the moment they are paid, with a sound and a notification.', 'Ei vielä tilauksia. Uudet tilaukset näkyvät täällä heti maksun jälkeen.')
                    : tr(context, 'Your store is in review. Add products and drops meanwhile — they go live when you are approved.', 'Kauppasi on tarkistuksessa. Lisää sillä välin tuotteita ja julkaisuja — ne julkaistaan hyväksynnän jälkeen.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: 15),
              ),
            ),
          ],
          for (final o in active) _orderCard(o),
          if (done.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(tr(context, 'Earlier', 'Aiemmat'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
          for (final o in done) _orderCard(o),
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

  Widget _orderCard(Map<String, dynamic> o) {
    final status = o['status'];
    final items = (o['items'] as List?) ?? [];
    final created = DateTime.tryParse('${o['createdAt']}')?.toLocal();
    // Status as a soft pill: new orders are sunny so they stand out, active ones green, finished grey
    final (label, bg, fg) = switch (status) {
      'PENDING' => (tr(context, 'New — accept or decline', 'Uusi — hyväksy tai hylkää'), AppTheme.sunshine, AppTheme.textPrimary),
      'CONFIRMED' => (tr(context, 'Accepted — pack it', 'Hyväksytty — pakkaa'), AppTheme.primaryLight, AppTheme.primary),
      'PROCESSING' => (tr(context, 'Ready — waiting for courier', 'Valmis — odottaa kuriiria'), AppTheme.primaryLight, AppTheme.primary),
      'SHIPPED' => (tr(context, 'With the courier', 'Kuriirilla'), AppTheme.peach, AppTheme.accent),
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
            Text('#${o['id']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            if (created != null) Text('  ${created.hour.toString().padLeft(2, '0')}.${created.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppTheme.textSecondary)),
            const Spacer(),
            Text(euro(context, o['subtotalCents']), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          if (_isWaiting(o)) _waitingNote(o),
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
          if (o['courier'] != null && ['CONFIRMED', 'PROCESSING'].contains(status))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${tr(context, 'Courier', 'Kuriiri')} ${(o['courier']['name'] ?? '').toString().split(' ').first} ${tr(context, 'is on the way to you', 'on matkalla luoksesi')}',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ),
          if (status == 'PENDING') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _setStatus(o, 'CANCELLED'), child: Text(tr(context, 'Decline', 'Hylkää')))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(onPressed: () => _setStatus(o, 'CONFIRMED'), child: Text(tr(context, 'Accept', 'Hyväksy')))),
            ]),
          ],
          if (status == 'CONFIRMED') ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _setStatus(o, 'PROCESSING'), child: Text(tr(context, 'Packed — ready for pickup', 'Pakattu — valmis noudettavaksi')))),
          ],
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
          : value
              ? tr(context, '${p['name']} is available again', '${p['name']} on taas saatavilla')
              : tr(context, '${p['name']} is sold out and hidden from shoppers', '${p['name']} on loppu ja piilotettu asiakkailta')),
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _productsTab() {
    final products = ((_store?['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.checkroom_rounded, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(tr(context, 'Add your first product with photos, price and sizes.', 'Lisää ensimmäinen tuotteesi kuvineen, hintoineen ja kokoineen.'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => _editProduct(), icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Add product', 'Lisää tuote'))),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = products[i];
          final images = (p['images'] as List?)?.cast<String>() ?? const [];
          final variants = (p['variants'] as List?) ?? [];
          final stock = variants.isEmpty ? (asInt(p['stockQuantity']) ?? 0) : variants.fold<int>(0, (s, v) => s + (asInt(v['stock']) ?? 0));
          final available = p['isAvailable'] != false;
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
                      child: images.isEmpty ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.image_outlined, color: AppTheme.primary)) : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(euro(context, p['salePriceCents']), style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    available ? tr(context, 'Available', 'Saatavilla') : tr(context, 'Sold out', 'Loppu'),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: available ? AppTheme.primary : AppTheme.accent),
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
    final weekSales = paid.where((o) => (DateTime.tryParse('${o['createdAt']}') ?? DateTime(2000)).isAfter(weekAgo)).fold<int>(0, (s, o) => s + (asInt(o['subtotalCents']) ?? 0));
    final reviews = asInt(_store?['totalReviews']) ?? 0;
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
          leading: CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(icon, color: AppTheme.primary)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _stat(tr(context, 'Sales, 7 days', 'Myynti, 7 pv'), euro(context, weekSales)),
          const SizedBox(width: 10),
          _stat(tr(context, 'Orders', 'Tilaukset'), '${paid.length}'),
          const SizedBox(width: 10),
          _stat(tr(context, 'Rating', 'Arvio'), reviews > 0 ? '★ ${_store?['rating']}' : '—'),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            tile(Icons.account_balance_outlined, tr(context, 'Payouts', 'Tilitykset'), tr(context, 'Get paid through Stripe', 'Tilitykset Stripen kautta'),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutsScreen()))),
            const Divider(height: 1),
            tile(Icons.assignment_return_outlined, tr(context, 'Returns', 'Palautukset'), tr(context, 'Approve and refund returns', 'Hyväksy ja hyvitä palautukset'),
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsManager()))),
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
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen()))),
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
