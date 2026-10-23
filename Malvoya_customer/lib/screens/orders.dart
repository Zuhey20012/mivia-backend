import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/network_status.dart';
import '../core/reorder.dart';
import '../core/sign_in.dart';
import '../services/socket_service.dart';
import 'main_navigation.dart';
import 'order_detail.dart';
import 'returns_screen.dart';
import '../widgets/app_image.dart';

/// Your orders: what is on its way first, then everything delivered or cancelled.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _reloadSoon;
  bool _inFlight = false;
  bool _again = false;

  /// Orders whose room this screen joined, so live status events reach the list.
  final Set<int> _tracked = {};

  /// The account the list was loaded for (the tab stays alive, so it reloads after signing in).
  int? _loadedFor;

  static const _active = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NetworkStatus.instance.addListener(_onNetwork);
    final socket = CustomerSocketService();
    socket.addOrderStatusListener(_onOrderStatus);
    socket.addReconnectListener(_reloadQuietly);
    _loadedFor = Provider.of<AuthService>(context, listen: false).currentUser?.id;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NetworkStatus.instance.removeListener(_onNetwork);
    final socket = CustomerSocketService();
    socket.removeOrderStatusListener(_onOrderStatus);
    socket.removeReconnectListener(_reloadQuietly);
    for (final id in _tracked) {
      socket.stopTracking(id);
    }
    _reloadSoon?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadQuietly();
  }

  void _onNetwork() {
    if (NetworkStatus.instance.online) _reloadQuietly();
  }

  void _onOrderStatus(Map<String, dynamic> data) {
    // Several events can arrive together (paid, then accepted); one reload is enough
    _reloadSoon?.cancel();
    _reloadSoon = Timer(const Duration(milliseconds: 300), _reloadQuietly);
  }

  void _reloadQuietly() {
    if (mounted) _load(quiet: true);
  }

  void _reloadAfterSignIn() {
    if (mounted) _load();
  }

  /// Joins the live room of every order that can still change, and leaves the others.
  void _syncTracking(AuthService auth) {
    final socket = CustomerSocketService();
    final live = _orders
        .where((o) => _active.contains(o['status']))
        .map((o) => asInt(o['id']))
        .whereType<int>()
        .toSet();
    if (live.isNotEmpty) socket.connect(auth.accessToken ?? '');
    for (final id in live.difference(_tracked)) {
      socket.trackOrder(id);
    }
    for (final id in _tracked.difference(live)) {
      socket.stopTracking(id);
    }
    _tracked
      ..clear()
      ..addAll(live);
  }

  Future<void> _load({bool quiet = false}) async {
    if (_inFlight) {
      _again = true;
      return;
    }
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    if (!quiet) setState(() => _loading = true);
    _inFlight = true;
    final res = await ApiClient(auth).get('/orders');
    _inFlight = false;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        // Unpaid, abandoned checkouts are not orders from the customer's point of view
        _orders = ((res.data['orders'] as List?) ?? [])
            .map((o) => Map<String, dynamic>.from(o))
            .where((o) => !(o['status'] == 'CANCELLED' && o['paymentStatus'] == 'PENDING'))
            .toList();
        _error = null;
      } else if (!quiet || _orders.isEmpty) {
        // A failed background refresh keeps the list that is already on screen
        _error = res.errorText(context);
      }
    });
    if (res.ok) _syncTracking(auth);
    if (_again) {
      _again = false;
      _load(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final uid = auth.currentUser?.id;
    if (uid != _loadedFor) {
      _loadedFor = uid;
      _orders = [];
      if (uid != null) WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAfterSignIn());
    }
    final active = _orders.where((o) => _active.contains(o['status']) && o['paymentStatus'] == 'SUCCEEDED').toList();
    final past = _orders.where((o) => !active.contains(o)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Orders', 'Tilaukset')),
        actions: [
          IconButton(
            tooltip: tr(context, 'Returns', 'Palautukset'),
            icon: const Icon(Icons.assignment_return_outlined),
            onPressed: auth.isAuthenticated
                ? () {
                    Haptics.selection();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen()));
                  }
                : null,
          ),
        ],
      ),
      body: !auth.isAuthenticated
          ? MStateMessage(
              icon: Icons.receipt_long_outlined,
              message: tr(context, 'Sign in to see your orders.', 'Kirjaudu sisään nähdäksesi tilauksesi.'),
              actionLabel: tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili'),
              onAction: () => openSignIn(context),
            )
          : _loading
              ? const MSkeletonList(thumbnail: true)
              : RefreshIndicator(
                  onRefresh: () => _load(quiet: true),
                  child: _error != null
                      ? MStateMessage.error(message: _error!, onRetry: () => _load())
                      : _orders.isEmpty
                          ? MStateMessage(
                              icon: Icons.receipt_long_outlined,
                              title: tr(context, 'No orders yet', 'Ei vielä tilauksia'),
                              message: tr(context, 'When you order, you can follow it here live.',
                                  'Kun tilaat, voit seurata tilaustasi täällä reaaliajassa.'),
                              actionLabel: tr(context, 'Start shopping', 'Aloita ostokset'),
                              actionIcon: Icons.storefront_rounded,
                              onAction: () => openMainTab(context, MainTab.home),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, 120),
                              children: [
                                if (active.isNotEmpty) _section(tr(context, 'In progress', 'Käynnissä')),
                                ...active.map(_card),
                                if (past.isNotEmpty) _section(tr(context, 'Earlier', 'Aiemmat')),
                                ...past.map(_card),
                              ],
                            ),
                ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.xs, MSpace.lg, MSpace.xs, 10),
        child: Text(label, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w700, color: AppTheme.secondaryText(context), letterSpacing: 0.3)),
      );

  (String, Color) _status(Map<String, dynamic> o) {
    if (o['fulfilment'] == 'PICKUP') {
      switch (o['status']) {
        case 'CONFIRMED':
          return (tr(context, 'Being prepared', 'Valmistellaan'), AppTheme.primary);
        case 'PROCESSING':
          return (tr(context, 'Ready for pickup', 'Valmis noudettavaksi'), AppTheme.success);
        case 'DELIVERED':
          return (tr(context, 'Collected', 'Noudettu'), AppTheme.success);
      }
    }
    switch (o['status']) {
      case 'PENDING':
        return o['paymentStatus'] == 'SUCCEEDED'
            ? (tr(context, 'Waiting for the store', 'Odottaa kauppaa'), AppTheme.warning)
            : (tr(context, 'Payment not finished', 'Maksu kesken'), AppTheme.warning);
      case 'CONFIRMED':
        return (tr(context, 'Accepted', 'Hyväksytty'), AppTheme.primary);
      case 'PROCESSING':
        return (tr(context, 'Being packed', 'Pakataan'), AppTheme.primary);
      case 'SHIPPED':
        return (tr(context, 'On its way', 'Matkalla'), AppTheme.primary);
      case 'DELIVERED':
        return (tr(context, 'Delivered', 'Toimitettu'), AppTheme.success);
      case 'REFUNDED':
        return (tr(context, 'Refunded', 'Hyvitetty'), AppTheme.secondaryText(context));
      default:
        return (tr(context, 'Cancelled', 'Peruttu'), AppTheme.secondaryText(context));
    }
  }

  Widget _card(Map<String, dynamic> o) {
    final (label, color) = _status(o);
    final items = (o['items'] as List?) ?? [];
    final first = items.isNotEmpty ? items.first : null;
    final images = (first?['product']?['images'] as List?)?.cast<String>() ?? const [];
    final created = DateTime.tryParse('${o['createdAt']}')?.toLocal();
    final count = items.fold<int>(0, (s, i) => s + (asInt(i['quantity']) ?? 0));

    return GestureDetector(
      onTap: () async {
        Haptics.selection();
        await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: asInt(o['id'])!)));
        if (mounted) _load(quiet: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: MSpace.md),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MRadius.sm),
              child: SizedBox(
                width: 56,
                height: 68,
                child: images.isEmpty
                    ? Container(color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk), child: const Icon(Icons.checkroom_outlined, color: AppTheme.clayInk))
                    : AppImage(images.first),
              ),
            ),
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o['store']?['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL, color: AppTheme.primaryText(context))),
                  const SizedBox(height: 2),
                  Text(
                    '${count == 1 ? tr(context, '1 item', '1 tuote') : tr(context, '$count items', '$count tuotetta')} · ${euro(context, o['totalCents'])}'
                    '${created != null ? ' · ${created.day}.${created.month}.' : ''}',
                    style: TextStyle(fontSize: MTextSize.label, color: AppTheme.secondaryText(context)),
                  ),
                  // Scheduled delivery: the window it was booked for, while it is still to come
                  if (_active.contains(o['status']) && scheduledWindow(context, o['scheduledStart'], o['scheduledEnd']) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${tr(context, 'Delivery', 'Toimitus')}: ${scheduledWindow(context, o['scheduledStart'], o['scheduledEnd'])}',
                        style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: AppTheme.primaryText(context)),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: MSpace.xs),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(MRadius.sm)),
                      child: Text(label, style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: color)),
                    ),
                    if (o['fulfilment'] == 'PICKUP') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: MSpace.xs),
                        decoration: BoxDecoration(
                            color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine), borderRadius: BorderRadius.circular(MRadius.sm)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.storefront_rounded, size: 13, color: AppTheme.primaryText(context)),
                          const SizedBox(width: MSpace.xs),
                          Text(tr(context, 'Collect', 'Nouto'),
                              style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                        ]),
                      ),
                    ],
                    const Spacer(),
                    if (o['status'] == 'DELIVERED')
                      ValueListenableBuilder<int?>(
                        valueListenable: reorderBusy,
                        builder: (_, busy, __) => TextButton.icon(
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: MSpace.sm)),
                          onPressed: busy != null
                              ? null
                              : () {
                                  Haptics.selection();
                                  reorder(context, Map<String, dynamic>.from(o));
                                },
                          icon: busy == asInt(o['id'])
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.replay_rounded, size: 18),
                          label: Text(tr(context, 'Again', 'Uudelleen')),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
          ],
        ),
      ),
    );
  }
}
