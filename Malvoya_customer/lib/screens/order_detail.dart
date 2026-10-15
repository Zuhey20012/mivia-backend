import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/reorder.dart';
import '../core/network_status.dart';
import '../core/strings.dart';
import '../services/socket_service.dart';
import '../widgets/skeleton.dart';
import 'returns_screen.dart';

/// One order: live map while it is on its way, a timeline with real times, chat with the
/// courier, and — once delivered — the delivery photo, a rating and returns.
class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  /// Opened straight after the payment sheet succeeded: until Stripe confirms the payment to the
  /// server (usually seconds) the order still looks unpaid, so it says "confirming" instead.
  final bool justPaid;
  const OrderDetailScreen({super.key, required this.orderId, this.justPaid = false});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _review;
  String? _error;
  LatLng? _courier;
  DateTime? _courierSeenAt;
  /// Chat messages of this delivery. The chat sheet is its own route, so it listens to this
  /// directly and shows replies that arrive while it is open.
  final _chat = ValueNotifier<List<Map<String, dynamic>>>(const []);
  bool _chatOpen = false;

  /// A courier message arrived while the chat was closed (a dot on the chat button).
  bool _unread = false;
  final _map = MapController();
  bool _cameraFitted = false;

  static const _active = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NetworkStatus.instance.addListener(_onNetwork);
    _load();
    final socket = CustomerSocketService();
    _connectSocket();
    socket.trackOrder(widget.orderId);
    socket.joinChat(widget.orderId);
    socket.addCourierLocationListener(_onCourierLocation);
    socket.addOrderStatusListener(_onOrderStatus);
    socket.addChatListener(_onChatMessage);
    socket.addReconnectListener(_onReconnect);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NetworkStatus.instance.removeListener(_onNetwork);
    final socket = CustomerSocketService();
    socket.removeCourierLocationListener(_onCourierLocation);
    socket.removeOrderStatusListener(_onOrderStatus);
    socket.removeChatListener(_onChatMessage);
    socket.removeReconnectListener(_onReconnect);
    socket.stopTracking(widget.orderId);
    socket.leaveChat(widget.orderId);
    _map.dispose();
    _chat.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final auth = Provider.of<AuthService>(context, listen: false);
    CustomerSocketService().connect(auth.accessToken ?? '');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Events may have been missed while the app was in the background
    if (state == AppLifecycleState.resumed && mounted) {
      _connectSocket();
      _load();
    }
  }

  void _onNetwork() {
    if (NetworkStatus.instance.online && mounted) {
      _connectSocket();
      _load();
    }
  }

  void _onReconnect() {
    if (mounted) _load();
  }

  void _onCourierLocation(Map<String, dynamic> d) {
    if (asInt(d['orderId']) != widget.orderId) return;
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    if (lat == null || lng == null || !mounted) return;
    setState(() {
      _courier = LatLng(lat, lng);
      _courierSeenAt = DateTime.now();
    });
  }

  void _onOrderStatus(Map<String, dynamic> d) {
    if (asInt(d['orderId']) == widget.orderId && mounted) _load();
  }

  void _onChatMessage(Map<String, dynamic> d) {
    if (asInt(d['orderId']) != widget.orderId || !mounted) return;
    _chat.value = [..._chat.value, d];
    if (!_chatOpen && d['role'] != 'CUSTOMER') setState(() => _unread = true);
  }

  Future<void> _load() async {
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final res = await api.get('/orders/${widget.orderId}');
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.errorText(context));
      return;
    }
    final order = Map<String, dynamic>.from(res.data['order']);
    Map<String, dynamic>? review;
    if (order['status'] == 'DELIVERED') {
      final r = await api.get('/orders/${widget.orderId}/review');
      if (r.ok && r.data['review'] != null) review = Map<String, dynamic>.from(r.data['review']);
    }
    if (!mounted) return;
    setState(() {
      _order = order;
      _review = review;
      _error = null;
      final c = order['courier'];
      if (_courier == null && c?['latitude'] != null && c?['longitude'] != null && order['status'] == 'SHIPPED') {
        _courier = LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble());
      }
    });
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  // ── Derived values ──────────────────────────────────────────────────────

  /// Reserve & collect: the customer picks the order up at the shop (no courier, no map).
  bool get _isPickup => _order?['fulfilment'] == 'PICKUP';

  LatLng? get _storePos {
    final s = _order?['store'];
    if (s?['latitude'] == null || s?['longitude'] == null) return null;
    return LatLng((s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble());
  }

  LatLng? get _homePos {
    final o = _order;
    if (o?['deliveryLat'] == null || o?['deliveryLng'] == null) return null;
    return LatLng((o!['deliveryLat'] as num).toDouble(), (o['deliveryLng'] as num).toDouble());
  }

  DateTime? _time(String key) {
    final v = _order?[key];
    return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  }

  String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  /// The honest best estimate: live distance once the courier has the parcel, otherwise the
  /// estimate given at payment time.
  String? _etaText() {
    final o = _order!;
    final status = o['status'];
    if (_isPickup) {
      if (status == 'DELIVERED') {
        final t = _time('deliveredAt');
        return t == null ? tr(context, 'Collected', 'Noudettu') : tr(context, 'Collected at ${_clock(t)}', 'Noudettu klo ${_clock(t)}');
      }
      if (status == 'PROCESSING') return tr(context, 'Ready for pickup', 'Valmis noudettavaksi');
      if (status == 'CONFIRMED') return tr(context, 'The shop is getting it ready', 'Kauppa valmistelee tilausta');
      return null;
    }
    if (status == 'DELIVERED') {
      final t = _time('deliveredAt');
      return t == null ? null : tr(context, 'Delivered at ${_clock(t)}', 'Toimitettu klo ${_clock(t)}');
    }
    if (!_active.contains(status)) return null;
    final home = _homePos;
    if (status == 'SHIPPED' && o['arrivingNotifiedAt'] != null) {
      return tr(context, 'Your courier is arriving', 'Kuriiri on perillä hetken päästä');
    }
    if (status == 'SHIPPED' && _courier != null && home != null) {
      final meters = const Distance().as(LengthUnit.Meter, _courier!, home);
      // The courier's live distance (straight line), not a promised arrival time
      final km = (meters / 1000).toStringAsFixed(1);
      return tr(context, 'Your courier is $km km away', 'Kuriiri on ${km.replaceAll('.', ',')} km:n päässä');
    }
    // A scheduled delivery is promised its window, not minutes from now
    final window = scheduledWindow(context, o['scheduledStart'], o['scheduledEnd']);
    if (window != null) return tr(context, 'Scheduled: $window', 'Ajastettu: $window');
    final eta = asInt(o['etaMinutes']);
    final paid = _time('paidAt') ?? _time('createdAt');
    if (eta != null && paid != null) {
      final from = paid.add(Duration(minutes: eta));
      final to = from.add(const Duration(minutes: 10));
      return tr(context, 'Estimated arrival ${_clock(from)}–${_clock(to)}', 'Arvioitu saapuminen ${_clock(from)}–${_clock(to)}');
    }
    return null;
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Payment was never completed (left or declined in the payment sheet): nothing was charged.
  bool _unpaid(Map<String, dynamic> o) =>
      o['status'] == 'PENDING' && o['paymentStatus'] != 'SUCCEEDED' && o['paymentStatus'] != 'REFUNDED';

  Future<void> _cancel() async {
    final unpaid = _order != null && _unpaid(_order!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Cancel this order?', 'Perutaanko tilaus?')),
        content: Text(unpaid
            ? tr(context, 'Nothing was charged, so there is nothing to refund. The items go back on sale.',
                'Mitään ei veloitettu, joten palautettavaa ei ole. Tuotteet palaavat myyntiin.')
            : tr(context, 'You will get your money back in full.', 'Saat rahasi takaisin kokonaan.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep order', 'Pidä tilaus'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Cancel order', 'Peru tilaus'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/orders/${widget.orderId}/cancel');
    if (!mounted) return;
    _snack(res.ok ? tr(context, 'Order cancelled', 'Tilaus peruttu') : res.errorText(context)!);
    _load();
  }

  Future<void> _showProof() async {
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/orders/${widget.orderId}/proof');
    if (!mounted) return;
    if (!res.ok) return _snack(res.errorText(context)!);
    final url = res.data['proof']?['photoUrl'];
    showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (url != null) CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                url != null
                    ? tr(context, 'Photo taken by your courier at delivery. Kept for 30 days.', 'Kuriirin toimitushetkellä ottama kuva. Säilytetään 30 päivää.')
                    : tr(context, 'Handed over in person.', 'Luovutettu henkilökohtaisesti.'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rate() async {
    int store = 0;
    int courier = 0;
    final comment = TextEditingController();
    final hasCourier = _order?['courier'] != null;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget stars(int value, void Function(int) onPick) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: tr(context, '${i + 1} of 5 stars', '${i + 1}/5 tähteä'),
                    iconSize: 36,
                    icon: Icon(i < value ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE08A00)),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      set(() => onPick(i + 1));
                    },
                  ),
                ),
              );
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(context, 'How was your order?', 'Millainen tilauksesi oli?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(_order?['store']?['name'] ?? ''),
                stars(store, (v) => store = v),
                if (hasCourier) ...[
                  Text(tr(context, 'Delivery (only Malvoya sees this)', 'Toimitus (vain Malvoya näkee tämän)')),
                  stars(courier, (v) => courier = v),
                ],
                TextField(
                  controller: comment,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: tr(context, 'Tell others about the store (optional)', 'Kerro muille kaupasta (valinnainen)')),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: store == 0
                        ? null
                        : () async {
                            final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/orders/${widget.orderId}/review', {
                              'storeRating': store,
                              if (hasCourier && courier > 0) 'courierRating': courier,
                              if (comment.text.trim().isNotEmpty) 'comment': comment.text.trim(),
                            });
                            if (!ctx.mounted) return;
                            if (res.ok) {
                              Navigator.pop(ctx, true);
                            } else {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res.errorText(context)!)));
                            }
                          },
                    child: Text(tr(context, 'Send review', 'Lähetä arvio')),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'Your first name and last initial are shown with your review. Only customers with a delivered order can review.',
                      'Etunimesi ja sukunimen alkukirjain näkyvät arviossa. Vain asiakkaat, joiden tilaus on toimitettu, voivat arvioida.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context)),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (sent == true && mounted) {
      _snack(tr(context, 'Thanks for your review!', 'Kiitos arviostasi!'));
      _load();
    }
  }

  Future<void> _openChat() async {
    final input = TextEditingController();
    final scroll = ScrollController();
    final auth = Provider.of<AuthService>(context, listen: false);
    final myName = (auth.currentUser?.name ?? '').split(' ').first;
    setState(() {
      _chatOpen = true;
      _unread = false;
    });

    // Keeps the newest message in view
    void toNewest() => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) {
            scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
          }
        });

    void send(String text) {
      if (text.trim().isEmpty) return;
      CustomerSocketService().sendChatMessage(widget.orderId, text.trim(), myName.isEmpty ? tr(context, 'Customer', 'Asiakas') : myName);
      input.clear();
    }

    final quick = [
      tr(context, 'I\'m coming down', 'Tulen alas'),
      tr(context, 'Please leave it at the door', 'Jätä ovelle'),
      tr(context, 'The door code is ', 'Ovikoodi on '),
    ];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            children: [
              ListTile(
                title: Text(tr(context, 'Chat with your courier', 'Chat kuriirin kanssa'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr(context, 'Messages are not stored after delivery.', 'Viestejä ei tallenneta toimituksen jälkeen.')),
              ),
              Expanded(
                // Rebuilds when a message arrives, also while the sheet is open
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _chat,
                  builder: (ctx, messages, _) {
                    toNewest();
                    return ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        final mine = m['role'] == 'CUSTOMER';
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: mine ? AppTheme.primary : AppTheme.inputBackground(context),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('${m['text'] ?? ''}', style: TextStyle(color: mine ? Colors.white : AppTheme.primaryText(context))),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: quick
                      .map((q) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(label: Text(q), onPressed: () => q.endsWith(' ') ? input.text = q : send(q)),
                          ))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: send,
                        decoration: InputDecoration(counterText: '', hintText: tr(context, 'Message', 'Viesti')),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'Send', 'Lähetä'),
                      icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        send(input.text);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _chatOpen = false;
    scroll.dispose();
    input.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Order #${widget.orderId}', 'Tilaus #${widget.orderId}'))),
      body: o == null
          ? (_error == null ? const SkeletonDetail(heroHeight: 240) : StateMessage.error(message: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (!_isPickup && _active.contains(o['status']) && (_storePos != null || _homePos != null)) _mapCard(),
                  _statusCard(o),
                  if (_isPickup && o['status'] != 'CANCELLED' && o['status'] != 'REFUNDED') _pickupCard(o),
                  _itemsCard(o),
                  _actions(o),
                ],
              ),
            ),
    );
  }

  Widget _mapCard() {
    final points = [if (_storePos != null) _storePos!, if (_homePos != null) _homePos!, if (_courier != null) _courier!];
    if (!_cameraFitted && points.length > 1) {
      _cameraFitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(48)));
        } catch (_) {}
      });
    }
    Widget pin(IconData icon, Color color) => Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
          child: Icon(icon, color: Colors.white, size: 18),
        );
    return Container(
      height: 280,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: points.first, initialZoom: 14, maxZoom: 18),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.malvoya.customer'),
          if (_courier != null && _homePos != null)
            PolylineLayer(polylines: [Polyline(points: [_courier!, _homePos!], strokeWidth: 4, color: AppTheme.primary.withValues(alpha: 0.6), pattern: StrokePattern.dashed(segments: const [10, 8]))]),
          MarkerLayer(markers: [
            if (_storePos != null) Marker(point: _storePos!, width: 38, height: 38, child: pin(Icons.storefront_rounded, AppTheme.primary)),
            if (_homePos != null) Marker(point: _homePos!, width: 38, height: 38, child: pin(Icons.home_rounded, AppTheme.success)),
            if (_courier != null) Marker(point: _courier!, width: 46, height: 46, child: pin(Icons.pedal_bike_rounded, AppTheme.lingon)),
          ]),
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(padding: EdgeInsets.all(8), child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black87))),
          ),
        ],
      ),
    );
  }

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  /// Opens the shop in the phone's maps app (geo: link), or OpenStreetMap in the browser.
  Future<void> _openMaps(Map<String, dynamic> store) async {
    HapticFeedback.selectionClick();
    final lat = (store['latitude'] as num?)?.toDouble();
    final lng = (store['longitude'] as num?)?.toDouble();
    final address = (store['address'] ?? '').toString();
    final name = (store['name'] ?? '').toString();
    final geo = lat != null && lng != null
        ? Uri.parse('geo:$lat,$lng?q=${Uri.encodeComponent('$lat,$lng($name)')}')
        : Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
    final web = lat != null && lng != null
        ? Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng')
        : Uri.parse('https://www.openstreetmap.org/search?query=${Uri.encodeComponent(address)}');
    try {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) _snack(tr(context, 'Could not open maps.', 'Karttaa ei voitu avata.'));
  }

  /// Reserve & collect: the pickup code (while it can be used), the shop and how to get there.
  Widget _pickupCard(Map<String, dynamic> o) {
    final status = o['status'];
    final store = o['store'] is Map ? Map<String, dynamic>.from(o['store']) : <String, dynamic>{};
    final code = o['pickupCode']?.toString() ?? '';
    final showCode = code.isNotEmpty && (status == 'CONFIRMED' || status == 'PROCESSING');
    final muted = AppTheme.secondaryText(context);
    final brand = AppTheme.isDarkMode(context) ? const Color(0xFFC9A3DD) : AppTheme.primary;
    final ready = _time('readyAt');
    final hasPlace = (store['address'] ?? '').toString().isNotEmpty || store['latitude'] != null;
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCode) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Column(children: [
              Text(tr(context, 'Show this code at the shop', 'Näytä tämä koodi kaupassa'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
              const SizedBox(height: 8),
              Semantics(
                label: '${tr(context, 'Pickup code', 'Noutokoodi')} ${code.split('').join(' ')}',
                excludeSemantics: true,
                child: FittedBox(
                  child: SelectableText(
                    spaced,
                    style: AppTheme.display(context, size: 44, color: AppTheme.primaryText(context)).copyWith(letterSpacing: 6),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status == 'PROCESSING'
                    ? tr(context, 'Your order is ready. Please collect it within 3 days.', 'Tilauksesi on valmis. Nouda se 3 päivän kuluessa.')
                    : tr(context, 'Wait until the shop marks it ready before you go.', 'Odota, että kauppa merkitsee tilauksen valmiiksi, ennen kuin lähdet.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.primaryText(context), height: 1.35),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary), shape: BoxShape.circle),
              child: Icon(Icons.storefront_rounded, color: brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store['name']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.primaryText(context))),
                  if ((store['address'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(store['address'].toString(), style: TextStyle(fontSize: 13, color: muted, height: 1.35)),
                    ),
                  if (status == 'PROCESSING' && ready != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr(context, 'Ready since ${ready.day}.${ready.month}. ${_clock(ready)}', 'Valmiina ${ready.day}.${ready.month}. klo ${_clock(ready)} alkaen'),
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (hasPlace) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openMaps(store),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(tr(context, 'Open in maps', 'Avaa kartalla')),
            ),
          ),
        ],
        if (status == 'CONFIRMED' || status == 'PROCESSING')
          Text(
            tr(context, 'If it isn’t collected within 3 days of being ready, the order is cancelled and refunded.',
                'Jos tilausta ei noudeta 3 päivän kuluessa valmistumisesta, se perutaan ja rahat palautetaan.'),
            style: TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
      ],
    ));
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: child,
      );

  Widget _statusCard(Map<String, dynamic> o) {
    final status = o['status'];
    final eta = _etaText();
    final paid = o['paymentStatus'] == 'SUCCEEDED' || o['paymentStatus'] == 'REFUNDED';
    final steps = _isPickup
        ? <(String, DateTime?, bool)>[
            (tr(context, 'Paid', 'Maksettu'), _time('paidAt'), paid),
            (tr(context, 'Accepted', 'Hyväksytty'), _time('confirmedAt'), ['CONFIRMED', 'PROCESSING', 'DELIVERED'].contains(status)),
            (tr(context, 'Ready for pickup', 'Valmis noudettavaksi'), _time('readyAt'), ['PROCESSING', 'DELIVERED'].contains(status)),
            (tr(context, 'Collected', 'Noudettu'), _time('deliveredAt'), status == 'DELIVERED'),
          ]
        : <(String, DateTime?, bool)>[
      (tr(context, 'Order paid', 'Tilaus maksettu'), _time('paidAt'), paid),
      (tr(context, 'Store accepted', 'Kauppa hyväksyi'), null, ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Courier on the way to the store', 'Kuriiri matkalla kauppaan'), _time('acceptedAt'), o['courier'] != null),
      (tr(context, 'Picked up', 'Noudettu'), _time('pickedUpAt'), ['SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Delivered', 'Toimitettu'), _time('deliveredAt'), status == 'DELIVERED'),
    ];
    final cancelled = status == 'CANCELLED' || status == 'REFUNDED';
    final unpaid = _unpaid(o);
    // Right after paying, the bank's confirmation may still be on its way to Malvoya
    final confirming = unpaid && widget.justPaid && o['paymentStatus'] != 'FAILED';
    final created = _time('createdAt');
    final heldUntil = created?.add(const Duration(minutes: 30));
    final courierName = (o['courier']?['name'] ?? '').toString().split(' ').first;
    final stale = _courierSeenAt != null && DateTime.now().difference(_courierSeenAt!) > const Duration(minutes: 2);

    final done = steps.where((s) => s.$3).length;
    final brand = AppTheme.isDarkMode(context) ? const Color(0xFFC9A3DD) : AppTheme.primary;
    final showCourier = !_isPickup && courierName.isNotEmpty && _active.contains(status);

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cancelled
              ? tr(context, 'Cancelled', 'Peruttu')
              : unpaid
                  ? (confirming ? tr(context, 'Confirming your payment…', 'Vahvistetaan maksua…') : tr(context, 'Payment not finished', 'Maksu jäi kesken'))
                  : (eta ?? tr(context, 'Waiting for the store', 'Odotetaan kauppaa')),
          style: AppTheme.display(context, size: 25),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('#${o['id']} · ${o['store']?['name'] ?? ''}', style: TextStyle(color: AppTheme.secondaryText(context))),
        ),
        if (cancelled && o['cancelReason'] != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(o['cancelReason'], style: TextStyle(color: AppTheme.secondaryText(context)))),
        if (unpaid && !confirming) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF8A5A00), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  heldUntil == null
                      ? tr(context, 'Payment not finished — nothing was charged. The items are held for 30 minutes.',
                          'Maksu jäi kesken – mitään ei veloitettu. Tuotteet pidetään varattuina 30 minuuttia.')
                      : tr(context, 'Payment not finished — nothing was charged. The items are held for 30 minutes (until ${_clock(heldUntil)}), then the order is cancelled.',
                          'Maksu jäi kesken – mitään ei veloitettu. Tuotteet pidetään varattuina 30 minuuttia (klo ${_clock(heldUntil)} asti), minkä jälkeen tilaus perutaan.'),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35, color: AppTheme.primaryText(context)),
                ),
              ),
            ]),
          ),
        ],
        if (!cancelled) ...[
          const SizedBox(height: 14),
          // One segment per step, filled as the order moves along
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < done ? brand : AppTheme.cardBorder(context),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showCourier) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.inputBackground(context), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.peach, AppTheme.lingon), shape: BoxShape.circle),
                    child: const Icon(Icons.pedal_bike_rounded, color: AppTheme.lingon, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(context, '$courierName is delivering', '$courierName toimittaa'),
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                        if (stale)
                          Text(tr(context, 'Location updating…', 'Sijaintia päivitetään…'),
                              style: TextStyle(fontSize: 12.5, color: AppTheme.secondaryText(context))),
                      ],
                    ),
                  ),
                  if (['CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(status))
                    Tooltip(
                      message: tr(context, 'Chat with courier', 'Chat kuriirin kanssa'),
                      child: Material(
                        color: AppTheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _openChat();
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                                // A courier message the customer has not opened yet
                                if (_unread)
                                  Positioned(
                                    top: 9,
                                    right: 9,
                                    child: Semantics(
                                      label: tr(context, 'New message', 'Uusi viesti'),
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: AppTheme.sunshine,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.primary, width: 2),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: steps[i].$3 ? brand : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: steps[i].$3 ? brand : AppTheme.cardBorder(context), width: 2),
                      ),
                      child: steps[i].$3 ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                    ),
                    if (i < steps.length - 1)
                      Container(width: 2, height: 22, color: steps[i + 1].$3 ? brand : AppTheme.cardBorder(context)),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(steps[i].$1,
                      style: TextStyle(
                        fontWeight: steps[i].$3 ? FontWeight.w600 : FontWeight.w400,
                        color: steps[i].$3 ? AppTheme.primaryText(context) : AppTheme.secondaryText(context),
                      )),
                ),
                if (steps[i].$2 != null) Text(_clock(steps[i].$2!), style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 13)),
              ],
            ),
        ],
      ],
    ));
  }

  /// The promo code used for this order: the API sends `{code, description}` (or just the code).
  String? _promoCode(Map<String, dynamic> o) {
    final p = o['promoCode'];
    final code = p is Map ? p['code'] : p;
    return code is String && code.isNotEmpty ? code : null;
  }

  Widget _itemsCard(Map<String, dynamic> o) {
    final items = (o['items'] as List?) ?? [];
    final muted = AppTheme.secondaryText(context);
    Widget line(String label, num? cents, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
            Text(euro(context, cents), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
          ]),
        );
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(o['store']?['name'] ?? '', style: AppTheme.display(context, size: 18)),
        if (_isPickup)
          Text(tr(context, 'Collect from the shop', 'Nouto kaupasta'), style: TextStyle(color: muted, fontSize: 13))
        else if (o['deliveryAddress'] != null)
          Text(o['deliveryAddress'], style: TextStyle(color: muted, fontSize: 13)),
        if (!_isPickup && scheduledWindow(context, o['scheduledStart'], o['scheduledEnd']) != null)
          Text(
            '${tr(context, 'Delivery time', 'Toimitusaika')}: ${scheduledWindow(context, o['scheduledStart'], o['scheduledEnd'])}',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        const Divider(height: 24),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('${i['quantity']}×  '),
              Expanded(
                child: Text(
                  [i['product']?['name'], i['variant']?['size'], i['variant']?['color']].where((x) => x != null).join(' · '),
                ),
              ),
              Text(euro(context, (asInt(i['unitCents']) ?? 0) * (asInt(i['quantity']) ?? 1))),
            ]),
          ),
        const Divider(height: 20),
        line(tr(context, 'Items', 'Tuotteet'), o['subtotalCents']),
        if (!_isPickup || (asInt(o['deliveryFeeCents']) ?? 0) > 0) line(tr(context, 'Delivery', 'Toimitus'), o['deliveryFeeCents']),
        if ((asInt(o['serviceFeeCents']) ?? 0) > 0) line(tr(context, 'Service fee', 'Palvelumaksu'), o['serviceFeeCents']),
        if ((asInt(o['smallOrderFeeCents']) ?? 0) > 0) line(tr(context, 'Small-order fee', 'Pientilauslisä'), o['smallOrderFeeCents']),
        if ((asInt(o['discountCents']) ?? 0) > 0)
          line(
            _promoCode(o) == null ? tr(context, 'Discount', 'Alennus') : '${tr(context, 'Discount', 'Alennus')} (${_promoCode(o)})',
            -(asInt(o['discountCents']) ?? 0),
          ),
        if ((asInt(o['tipCents']) ?? 0) > 0) line(tr(context, 'Courier tip', 'Tippi kuriirille'), o['tipCents']),
        line(tr(context, 'Total', 'Yhteensä'), o['totalCents'], bold: true),
        if ((asInt(o['refundedCents']) ?? 0) > 0) line(tr(context, 'Refunded', 'Hyvitetty'), o['refundedCents']),
      ],
    ));
  }

  Widget _actions(Map<String, dynamic> o) {
    final status = o['status'];
    final delivered = _time('deliveredAt');
    final withinReturn = delivered != null && DateTime.now().difference(delivered).inDays < 14;
    final withinReview = delivered != null && DateTime.now().difference(delivered).inDays < 30;
    final buttons = <Widget>[
      if (status == 'PENDING') _button(Icons.close_rounded, tr(context, 'Cancel order', 'Peru tilaus'), _cancel),
      if (status == 'DELIVERED' && o['handoverMethod'] == 'PHOTO')
        _button(Icons.photo_camera_outlined, tr(context, 'Delivery photo', 'Toimituskuva'), _showProof),
      if (status == 'DELIVERED' && _review == null && withinReview)
        _button(Icons.star_outline_rounded, tr(context, 'Rate your order', 'Arvioi tilaus'), _rate, primary: true),
      if (_review != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            label: '${tr(context, 'Your rating', 'Arviosi')}: ${asInt(_review!['storeRating']) ?? 0}/5',
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${tr(context, 'Your rating', 'Arviosi')}: ', style: TextStyle(color: AppTheme.secondaryText(context))),
              for (var i = 0; i < 5; i++)
                Icon(i < (asInt(_review!['storeRating']) ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18, color: AppTheme.warning),
            ]),
          ),
        ),
      if (status == 'DELIVERED' || status == 'CANCELLED')
        ValueListenableBuilder<int?>(
          valueListenable: reorderBusy,
          builder: (_, busy, __) => _button(
            Icons.replay_rounded,
            tr(context, 'Order again', 'Tilaa uudelleen'),
            () => reorder(context, o),
            primary: status == 'DELIVERED' && _review != null,
            busy: busy != null,
          ),
        ),
      if (status == 'DELIVERED' && withinReturn)
        _button(Icons.assignment_return_outlined, tr(context, 'Return items', 'Palauta tuotteita'),
            () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ReturnsScreen(order: o)));
          if (mounted) _load();
        }),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Column(children: buttons));
  }

  Widget _button(IconData icon, String label, VoidCallback onTap, {bool primary = false, bool busy = false}) {
    final glyph = busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon);
    final onPressed = busy ? null : () => _tap(onTap);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: primary
            ? FilledButton.icon(onPressed: onPressed, icon: glyph, label: Text(label))
            : OutlinedButton.icon(onPressed: onPressed, icon: glyph, label: Text(label)),
      ),
    );
  }
}
