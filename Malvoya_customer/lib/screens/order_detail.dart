import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../services/socket_service.dart';
import 'returns_screen.dart';

/// One order: live map while it is on its way, a timeline with real times, chat with the
/// courier, and — once delivered — the delivery photo, a rating and returns.
class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _review;
  String? _error;
  LatLng? _courier;
  DateTime? _courierSeenAt;
  final List<Map<String, dynamic>> _chat = [];
  final _map = MapController();
  bool _cameraFitted = false;

  static const _active = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'];

  @override
  void initState() {
    super.initState();
    _load();
    final auth = Provider.of<AuthService>(context, listen: false);
    final socket = CustomerSocketService();
    socket.connect(auth.accessToken ?? '');
    socket.trackOrder(widget.orderId);
    socket.joinChat(widget.orderId);
    socket.onCourierLocationUpdate = (d) {
      if (asInt(d['orderId']) != widget.orderId) return;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null || !mounted) return;
      setState(() {
        _courier = LatLng(lat, lng);
        _courierSeenAt = DateTime.now();
      });
    };
    socket.onOrderStatusUpdate = (d) {
      if (asInt(d['orderId']) == widget.orderId) _load();
    };
    socket.onChatMessage = (d) {
      if (asInt(d['orderId']) != widget.orderId || !mounted) return;
      setState(() => _chat.add(d));
    };
  }

  @override
  void dispose() {
    final socket = CustomerSocketService();
    socket.onCourierLocationUpdate = null;
    socket.onOrderStatusUpdate = null;
    socket.onChatMessage = null;
    socket.stopTracking(widget.orderId);
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final res = await api.get('/orders/${widget.orderId}');
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error);
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
    if (status == 'DELIVERED') {
      final t = _time('deliveredAt');
      return t == null ? null : tr(context, 'Delivered at ${_clock(t)}', 'Toimitettu klo ${_clock(t)}');
    }
    if (!_active.contains(status)) return null;
    final home = _homePos;
    if (status == 'SHIPPED' && _courier != null && home != null) {
      final meters = const Distance().as(LengthUnit.Meter, _courier!, home);
      final minutes = (meters / 250).ceil() + 2; // cycling ~15 km/h plus handover
      return tr(context, 'Arriving in about $minutes min', 'Perillä noin $minutes min kuluttua');
    }
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

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Cancel this order?', 'Perutaanko tilaus?')),
        content: Text(tr(context, 'You will get your money back in full.', 'Saat rahasi takaisin kokonaan.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep order', 'Pidä tilaus'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Cancel order', 'Peru tilaus'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/orders/${widget.orderId}/cancel');
    if (!mounted) return;
    _snack(res.ok ? tr(context, 'Order cancelled', 'Tilaus peruttu') : res.error!);
    _load();
  }

  Future<void> _showProof() async {
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/orders/${widget.orderId}/proof');
    if (!mounted) return;
    if (!res.ok) return _snack(res.error!);
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
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(res.error!)));
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

  void _openChat() {
    final input = TextEditingController();
    final auth = Provider.of<AuthService>(context, listen: false);
    final myName = (auth.currentUser?.name ?? '').split(' ').first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void send(String text) {
          if (text.trim().isEmpty) return;
          CustomerSocketService().sendChatMessage(widget.orderId, text.trim(), myName.isEmpty ? 'Customer' : myName);
          input.clear();
          Future.delayed(const Duration(milliseconds: 400), () {
            if (ctx.mounted) set(() {});
          });
        }

        final quick = [
          tr(context, 'I\'m coming down', 'Tulen alas'),
          tr(context, 'Please leave it at the door', 'Jätä ovelle'),
          tr(context, 'The door code is ', 'Ovikoodi on '),
        ];
        return SizedBox(
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
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _chat.map((m) {
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
                          child: Text(m['text'] ?? '', style: TextStyle(color: mine ? Colors.white : AppTheme.primaryText(context))),
                        ),
                      );
                    }).toList(),
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
                      IconButton(icon: const Icon(Icons.send_rounded, color: AppTheme.primary), onPressed: () => send(input.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Order #${widget.orderId}', 'Tilaus #${widget.orderId}'))),
      body: o == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
                    ]),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (_active.contains(o['status']) && (_storePos != null || _homePos != null)) _mapCard(),
                  _statusCard(o),
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
    final steps = <(String, DateTime?, bool)>[
      (tr(context, 'Order paid', 'Tilaus maksettu'), _time('paidAt'), o['paymentStatus'] == 'SUCCEEDED' || o['paymentStatus'] == 'REFUNDED'),
      (tr(context, 'Store accepted', 'Kauppa hyväksyi'), null, ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Courier on the way to the store', 'Kuriiri matkalla kauppaan'), _time('acceptedAt'), o['courier'] != null),
      (tr(context, 'Picked up', 'Noudettu'), _time('pickedUpAt'), ['SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Delivered', 'Toimitettu'), _time('deliveredAt'), status == 'DELIVERED'),
    ];
    final cancelled = status == 'CANCELLED' || status == 'REFUNDED';
    final courierName = (o['courier']?['name'] ?? '').toString().split(' ').first;
    final stale = _courierSeenAt != null && DateTime.now().difference(_courierSeenAt!) > const Duration(minutes: 2);

    final done = steps.where((s) => s.$3).length;
    final brand = AppTheme.isDarkMode(context) ? const Color(0xFFC9A3DD) : AppTheme.primary;
    final showCourier = courierName.isNotEmpty && _active.contains(status);

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cancelled ? tr(context, 'Cancelled', 'Peruttu') : (eta ?? tr(context, 'Waiting for the store', 'Odotetaan kauppaa')),
          style: AppTheme.display(context, size: 25),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('#${o['id']} · ${o['store']?['name'] ?? ''}', style: TextStyle(color: AppTheme.secondaryText(context))),
        ),
        if (cancelled && o['cancelReason'] != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(o['cancelReason'], style: TextStyle(color: AppTheme.secondaryText(context)))),
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
                          onTap: _openChat,
                          child: const SizedBox(width: 44, height: 44, child: Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20)),
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
        if (o['deliveryAddress'] != null) Text(o['deliveryAddress'], style: TextStyle(color: muted, fontSize: 13)),
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
        line(tr(context, 'Delivery', 'Toimitus'), o['deliveryFeeCents']),
        line(tr(context, 'Total (VAT incl.)', 'Yhteensä (sis. ALV)'), o['totalCents'], bold: true),
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
          child: Text('${tr(context, 'Your rating', 'Arviosi')}: ${'★' * (asInt(_review!['storeRating']) ?? 0)}',
              style: TextStyle(color: AppTheme.secondaryText(context))),
        ),
      if (status == 'DELIVERED' && withinReturn)
        _button(Icons.assignment_return_outlined, tr(context, 'Return items', 'Palauta tuotteita'),
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen()))),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Column(children: buttons));
  }

  Widget _button(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: primary
              ? FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label))
              : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
        ),
      );
}
