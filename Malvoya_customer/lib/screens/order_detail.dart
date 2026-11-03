import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../core/reorder.dart';
import '../core/network_status.dart';
import '../services/socket_service.dart';
import '../core/notification_primer.dart';
import '../core/route_path.dart';
import '../widgets/live_route_map.dart';
import '../widgets/paid_moment.dart';
import 'returns_screen.dart';

/// One order: live map while it is on its way, a timeline with real times, chat with the
/// courier, and — once delivered — the delivery photo, a rating and returns.
///
/// While a paid delivery is under way (since 2.17) the screen is a full map with a draggable sheet:
/// the street route of the current stage from `GET /orders/:id/route` (courier → shop, then
/// shop → home), the courier moving along it, a large ETA, a 4-step progress bar and shortcuts to
/// the chat. Without a route (an older server) the map draws what it drew before.
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

  // ── Live route (API 2.17) ──
  /// The street route of the current stage, its stage (`to_shop`, `to_customer`, `preview`) and the
  /// provider's distance and time for the whole of it. Null: none (yet), or an older server.
  RoutePath? _route;
  String? _routeStage;
  int? _routeDistanceM;
  int? _routeDurationS;

  /// What the route was fetched for (status, courier, stage), so a stage change fetches the next one.
  String? _routeKey;
  DateTime? _routeFetchedAt;
  bool _routeLoading = false;

  /// The server has no route endpoint (older API): the map works as before, without asking again.
  bool _routeUnavailable = false;

  /// How far along [_route] the courier is (metres); null when not on it.
  double? _courierAlong;

  /// The marker takes about as long to reach a new position as the courier took to report it.
  Duration _moveDuration = const Duration(milliseconds: 1400);

  /// The courier app's own estimate from the last position update (minutes), if it sent one.
  int? _courierEta;

  /// "Almost there" has buzzed once.
  bool _almostBuzzed = false;

  /// The order arrived while this screen was open: a short "Delivered" moment.
  bool _deliveredMoment = false;

  /// "Thanks for your order": a short moment right after paying.
  late bool _celebrate = widget.justPaid;

  /// "Confirming your payment…": set after paying in the sheet here or at checkout.
  late bool _justPaid = widget.justPaid;
  bool _paying = false;

  /// The server cannot hand out the payment of an unpaid order (older API): no button.
  bool _payUnavailable = false;

  /// Stored chat history (newer servers keep messages for 30 days after the order is done).
  bool _chatStored = false;
  bool _historyMissing = false;

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
    socket.addChatHistoryListener(_onChatHistory);
    socket.addReconnectListener(_onReconnect);
    _loadChatHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NetworkStatus.instance.removeListener(_onNetwork);
    final socket = CustomerSocketService();
    socket.removeCourierLocationListener(_onCourierLocation);
    socket.removeOrderStatusListener(_onOrderStatus);
    socket.removeChatListener(_onChatMessage);
    socket.removeChatHistoryListener(_onChatHistory);
    socket.removeReconnectListener(_onReconnect);
    socket.stopTracking(widget.orderId);
    socket.leaveChat(widget.orderId);
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
    if (!mounted) return;
    _load();
    // Messages sent while this phone was offline
    _loadChatHistory();
  }

  void _onCourierLocation(Map<String, dynamic> d) {
    if (asInt(d['orderId']) != widget.orderId) return;
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    if (lat == null || lng == null || !mounted) return;
    final next = LatLng(lat, lng);
    final now = DateTime.now();
    final last = _courierSeenAt;
    setState(() {
      // Glide for about as long as the courier took to report again (1.2–12 s), so the marker
      // keeps moving between updates instead of hopping and waiting
      if (last != null) _moveDuration = Duration(milliseconds: now.difference(last).inMilliseconds.clamp(1200, 12000));
      _courier = next;
      _courierSeenAt = now;
      _courierAlong = _snap(next);
      final eta = asInt(d['etaMinutes']);
      _courierEta = eta != null && eta > 0 ? eta : null;
    });
    _checkAlmostThere();
    // Courier → shop routes are recomputed by the server at most once a minute
    final fetched = _routeFetchedAt;
    final stale = fetched == null || now.difference(fetched) > const Duration(seconds: 60);
    if (stale && (_routeStage != _expectedStage || (_routeStage == 'to_shop' && _courierAlong == null))) {
      unawaited(_refreshRoute(force: true));
    }
  }

  /// The courier's place on the route (metres along it), or null when the route is not the
  /// courier's own (a preview, or another stage) or the courier is more than ~80 m off it.
  double? _snap(LatLng p) {
    final r = _route;
    if (r == null || (_routeStage != 'to_shop' && _routeStage != 'to_customer') || _routeStage != _expectedStage) return null;
    final hit = r.project(p, from: _courierAlong);
    return hit.offset <= 80 ? hit.along : null;
  }

  /// The stage the order is in now, as the route endpoint names it.
  String get _expectedStage {
    final o = _order;
    if (o == null) return 'preview';
    if (o['status'] == 'SHIPPED') return 'to_customer';
    if (o['courier'] != null && (o['status'] == 'CONFIRMED' || o['status'] == 'PROCESSING') && _courier != null) return 'to_shop';
    return 'preview';
  }

  /// A paid delivery that is still under way: the full-screen map with the sheet.
  bool _tracking(Map<String, dynamic> o) =>
      !_isPickup && o['paymentStatus'] == 'SUCCEEDED' && _active.contains(o['status']) && (_storePos != null || _homePos != null);

  /// Fetches the street route for the current stage (API 2.17). A 404 on an active order means an
  /// older server: the map then keeps the pre-2.17 look and the route is not asked for again.
  Future<void> _refreshRoute({bool force = false}) async {
    final o = _order;
    if (o == null || _routeUnavailable || _routeLoading) return;
    if (!_tracking(o)) {
      if (_route != null) setState(_clearRoute);
      return;
    }
    final key = _routeKeyNow;
    if (!force && key == _routeKey) return;
    _routeLoading = true;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/orders/${widget.orderId}/route');
    _routeLoading = false;
    if (!mounted) return;
    _routeFetchedAt = DateTime.now();
    if (res.status == 404) {
      setState(() {
        _clearRoute();
        _routeUnavailable = true;
      });
      return;
    }
    // Offline or a hiccup: keep what is drawn and try again with the next update
    if (!res.ok) return;
    final path = RoutePath.fromJson(res.data['points']);
    setState(() {
      _routeKey = key;
      _route = path;
      _routeStage = path == null ? null : res.data['stage']?.toString();
      _routeDistanceM = asInt(res.data['distanceM']);
      _routeDurationS = asInt(res.data['durationS']);
      _courierAlong = _courier == null ? null : _snap(_courier!);
    });
    // The order moved on while this request was out: fetch the next stage's route
    if (_routeKeyNow != key) unawaited(_refreshRoute());
  }

  String get _routeKeyNow => '${_order?['status']}|${_order?['courier']?['id']}|$_expectedStage';

  void _clearRoute() {
    _route = null;
    _routeStage = null;
    _routeKey = null;
    _routeDistanceM = null;
    _routeDurationS = null;
    _courierAlong = null;
  }

  /// Within about 300 m of home after pickup.
  bool get _almostThere {
    final o = _order;
    if (o == null || o['status'] != 'SHIPPED') return false;
    final c = _courier, home = _homePos;
    if (c != null && home != null) return RoutePath.metres(c, home) <= 300;
    return o['arrivingNotifiedAt'] != null;
  }

  void _checkAlmostThere() {
    if (_almostBuzzed || !_almostThere) return;
    _almostBuzzed = true;
    Haptics.light();
  }

  void _onOrderStatus(Map<String, dynamic> d) {
    if (asInt(d['orderId']) == widget.orderId && mounted) _load();
  }

  void _onChatMessage(Map<String, dynamic> d) {
    if (asInt(d['orderId']) != widget.orderId || !mounted) return;
    final before = _chat.value.length;
    _mergeChat([d]);
    if (_chat.value.length > before && !_chatOpen && _roleOf(d) != 'CUSTOMER') setState(() => _unread = true);
  }

  void _onChatHistory(int orderId, List<Map<String, dynamic>> messages) {
    if (orderId != widget.orderId || !mounted) return;
    _chatStored = true;
    _mergeChat(messages);
  }

  static String? _roleOf(Map<String, dynamic> m) => (m['role'] ?? m['senderRole'])?.toString();
  static DateTime? _timeOf(Map<String, dynamic> m) => DateTime.tryParse('${m['timestamp'] ?? m['createdAt'] ?? ''}');

  /// The same message can come from the socket, the stored history and our own HTTP send:
  /// keep one of each (same id, or same sender and text within a few seconds), oldest first.
  bool _sameMessage(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a['id'] != null && b['id'] != null) return '${a['id']}' == '${b['id']}';
    if ('${a['text']}' != '${b['text']}' || _roleOf(a) != _roleOf(b)) return false;
    final ta = _timeOf(a), tb = _timeOf(b);
    if (ta == null || tb == null) return true;
    return ta.difference(tb).inSeconds.abs() <= 10;
  }

  void _mergeChat(List<Map<String, dynamic>> incoming) {
    final list = List<Map<String, dynamic>>.of(_chat.value);
    var changed = false;
    for (final m in incoming) {
      if ('${m['text'] ?? ''}'.trim().isEmpty) continue;
      final i = list.indexWhere((x) => _sameMessage(x, m));
      if (i >= 0) {
        // Keep the stored copy's id so later copies match exactly
        if (list[i]['id'] == null && m['id'] != null) {
          list[i] = {...list[i], 'id': m['id']};
          changed = true;
        }
        continue;
      }
      list.add(m);
      changed = true;
    }
    if (!changed) return;
    list.sort((a, b) => (_timeOf(a) ?? DateTime(2100)).compareTo(_timeOf(b) ?? DateTime(2100)));
    _chat.value = list;
  }

  Future<void> _loadChatHistory() async {
    if (_historyMissing) return;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/orders/${widget.orderId}/messages');
    if (!mounted) return;
    if (res.status == 404) {
      // Older server: the chat is relayed live only
      _historyMissing = true;
      return;
    }
    final list = res.data['messages'];
    if (!res.ok || list is! List) return;
    _chatStored = true;
    _mergeChat(list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
  }

  /// Stripe's payment sheet for an order whose payment was left unfinished.
  Future<void> _completePayment() async {
    if (_paying) return;
    setState(() => _paying = true);
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/orders/${widget.orderId}/payment');
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _paying = false;
        if (res.status == 404) _payUnavailable = true;
      });
      _snack(res.status == 404
          ? tr(context, 'This order cannot be paid from here. Place the order again from your bag.',
              'Tätä tilausta ei voi maksaa täältä. Tee tilaus uudelleen kassista.')
          : res.status == 409
              ? tr(context, 'This order can no longer be paid. It may have been paid already or the hold ran out.',
                  'Tätä tilausta ei voi enää maksaa. Se on ehkä jo maksettu tai varausaika on päättynyt.')
              : res.errorText(context)!);
      _load();
      return;
    }
    final clientSecret = res.data['clientSecret']?.toString() ?? '';
    try {
      if (clientSecret.isEmpty) throw StateError('no client secret');
      // Same sheet as checkout: card details never touch Malvoya; SCA is handled by Stripe.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Malvoya',
          style: ThemeMode.system,
          allowsDelayedPaymentMethods: false,
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'FI',
            currencyCode: 'EUR',
            testEnv: AppConstants.stripePublishableKey.startsWith('pk_test_'),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      _snack(e.error.code == FailureCode.Canceled
          ? tr(context, 'Payment cancelled. You were not charged.', 'Maksu peruttiin. Sinua ei veloitettu.')
          : (e.error.localizedMessage ?? tr(context, 'Your bank declined the payment.', 'Pankkisi hylkäsi maksun.')));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _paying = false);
      _snack(tr(context, 'Payment could not be started. You were not charged.', 'Maksua ei voitu aloittaa. Sinua ei veloitettu.'));
      return;
    }
    if (!mounted) return;
    Haptics.medium();
    setState(() {
      _paying = false;
      _justPaid = true;
      _celebrate = true;
    });
    // Stripe tells the server within seconds; the socket usually brings the update, these are a fallback
    for (final s in const [3, 8, 15, 30]) {
      Future.delayed(Duration(seconds: s), () {
        if (mounted && _order != null && _unpaid(_order!)) _load();
      });
    }
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
    // It arrived while this screen was open: a short "Delivered" moment before the rating card
    final arrivedNow = _order != null && _order!['status'] == 'SHIPPED' && order['status'] == 'DELIVERED' && order['fulfilment'] != 'PICKUP';
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
      if (arrivedNow) _deliveredMoment = true;
      final c = order['courier'];
      // The server sends the courier's coordinates only while the order is active and assigned (2.16.1)
      if (_courier == null && c?['latitude'] != null && c?['longitude'] != null && _active.contains(order['status'])) {
        _courier = LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble());
      }
      if (!_active.contains(order['status'])) _courier = null;
    });
    if (arrivedNow) Haptics.success();
    _checkAlmostThere();
    unawaited(_refreshRoute());
  }

  void _snack(String t) => MSnack.show(context, t);

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
    final eta = _etaWindow(o);
    return eta == null ? null : tr(context, 'Estimated arrival $eta', 'Arvioitu saapuminen $eta');
  }

  /// The 10-minute window promised at payment ("12.40–12.50"), or null.
  String? _etaWindow(Map<String, dynamic> o) {
    final eta = asInt(o['etaMinutes']);
    final paid = _time('paidAt') ?? _time('createdAt');
    if (eta == null || paid == null) return null;
    final from = paid.add(Duration(minutes: eta));
    return '${_clock(from)}–${_clock(from.add(const Duration(minutes: 10)))}';
  }

  /// Minutes until the courier is at the door after pickup: the routing provider's time for the
  /// route, scaled by the part still ahead; else the courier app's own estimate. Null = unknown.
  int? get _minutesLeft {
    if (_order?['status'] != 'SHIPPED') return null;
    final r = _route, total = _routeDurationS;
    if (r != null && _routeStage == 'to_customer' && total != null && total > 0 && r.length > 0) {
      return (total * _fractionLeft(r) / 60).ceil();
    }
    return _courierEta;
  }

  /// Share of the shop → home route still ahead of the courier (all of it while the courier is unknown).
  double _fractionLeft(RoutePath r) {
    final c = _courier;
    final along = _courierAlong ?? (c == null ? 0.0 : r.project(c).along);
    return ((r.length - along) / r.length).clamp(0.0, 1.0);
  }

  /// Metres still to ride after pickup: along the route when there is one, else in a straight line.
  double? get _metresLeft {
    if (_order?['status'] != 'SHIPPED') return null;
    final r = _route;
    if (r != null && _routeStage == 'to_customer') return (_routeDistanceM?.toDouble() ?? r.length) * _fractionLeft(r);
    final c = _courier, home = _homePos;
    return c == null || home == null ? null : RoutePath.metres(c, home);
  }

  /// "about 6 min": whole minutes up to 10, then steps of 5 — never more precise than the data.
  String _aboutMinutes(int minutes) {
    final m = minutes <= 1 ? 1 : (minutes <= 10 ? minutes : (minutes / 5).round() * 5);
    return tr(context, 'about $m min', 'noin $m min');
  }

  String _distanceText(double metres) {
    if (metres < 950) {
      final m = ((metres / 50).round() * 50).clamp(50, 950);
      return '$m m';
    }
    final km = (metres / 1000).toStringAsFixed(1);
    return tr(context, '$km km', '${km.replaceAll('.', ',')} km');
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
              padding: const EdgeInsets.all(MSpace.lg),
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

  Future<void> _rate({int initial = 0}) async {
    int store = initial;
    int courier = 0;
    final comment = TextEditingController();
    final hasCourier = _order?['courier'] != null;
    final sent = await showMSheet<bool>(context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget stars(int value, void Function(int) onPick) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: tr(context, '${i + 1} of 5 stars', '${i + 1}/5 tähteä'),
                    iconSize: 36,
                    icon: Icon(i < value ? Icons.star_rounded : Icons.star_outline_rounded, color: MPalette.amber),
                    onPressed: () {
                      Haptics.selection();
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
                Text(tr(context, 'How was your order?', 'Millainen tilauksesi oli?'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: MSpace.md),
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
                const SizedBox(height: MSpace.sm),
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
                              MSnack.show(ctx, res.errorText(context)!);
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
                  style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context)),
                ),
              ],
            ),
          );
        },
      ), isScrollControlled: true, useSafeArea: false);
    if (sent == true && mounted) {
      _snack(tr(context, 'Thanks for your review!', 'Kiitos arviostasi!'));
      _load();
    }
  }

  Future<void> _openChat({String? prefill}) async {
    final input = TextEditingController(text: prefill ?? '');
    final scroll = ScrollController();
    final auth = Provider.of<AuthService>(context, listen: false);
    final myName = (auth.currentUser?.name ?? '').split(' ').first;
    setState(() {
      _chatOpen = true;
      _unread = false;
    });
    // Everything said so far, also from before this screen was opened
    unawaited(_loadChatHistory());

    // Keeps the newest message in view
    void toNewest() => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) {
            scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
          }
        });

    var sending = false;
    Future<void> send(String text) async {
      final message = text.trim();
      if (message.isEmpty || sending) return;
      final live = CustomerSocketService().sendChatMessage(widget.orderId, message, myName.isEmpty ? tr(context, 'Customer', 'Asiakas') : myName);
      if (live) {
        input.clear();
        return;
      }
      // No live connection: send over HTTP (newer servers store it and pass it on to the courier)
      sending = true;
      final res = await ApiClient(auth).post('/orders/${widget.orderId}/messages', {'text': message});
      sending = false;
      if (!mounted) return;
      if (res.ok) {
        if (input.text.trim() == message) input.clear();
        final stored = res.data['message'];
        _mergeChat([
          stored is Map
              ? Map<String, dynamic>.from(stored)
              : {'orderId': widget.orderId, 'text': message, 'role': 'CUSTOMER', 'timestamp': DateTime.now().toUtc().toIso8601String()},
        ]);
      } else {
        _snack(res.status == 0 || res.status == 404
            ? tr(context, 'Not sent: no connection. Your message is still in the box.', 'Ei lähetetty: ei yhteyttä. Viestisi on yhä kentässä.')
            : res.errorText(context)!);
      }
    }

    final quick = [
      tr(context, 'I\'m coming down', 'Tulen alas'),
      tr(context, 'Please leave it at the door', 'Jätä ovelle'),
      tr(context, 'The door code is ', 'Ovikoodi on '),
    ];
    await showMSheet(context, builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            children: [
              ListTile(
                title: Text(tr(context, 'Chat with your courier', 'Chat kuriirin kanssa'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_chatStored
                    ? tr(context, 'Messages are deleted 30 days after the order is completed.', 'Viestit poistetaan 30 päivää tilauksen päättymisen jälkeen.')
                    : tr(context, 'Messages are not stored after delivery.', 'Viestejä ei tallenneta toimituksen jälkeen.')),
              ),
              Expanded(
                // Rebuilds when a message arrives, also while the sheet is open
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _chat,
                  builder: (ctx, messages, _) {
                    toNewest();
                    return ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(MSpace.lg),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        final mine = _roleOf(m) == 'CUSTOMER';
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: MSpace.sm),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: mine ? AppTheme.primary : AppTheme.inputBackground(context),
                              borderRadius: BorderRadius.circular(MRadius.md),
                            ),
                            child: Text('${m['text'] ?? ''}', style: TextStyle(color: mine ? AppTheme.onBrand : AppTheme.primaryText(context))),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: MSpace.md),
                child: Row(
                  children: quick
                      .map((q) => Padding(
                            padding: const EdgeInsets.only(right: MSpace.sm),
                            child: ActionChip(label: Text(q), onPressed: () => q.endsWith(' ') ? input.text = q : send(q)),
                          ))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.sm, MSpace.md, MSpace.md),
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
                        Haptics.selection();
                        send(input.text);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ), isScrollControlled: true, useSafeArea: false);
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
      body: Stack(children: [
        Positioned.fill(child: _body(o)),
        if (_celebrate) Positioned.fill(child: PaidMoment(onDone: _afterCelebration)),
        if (_deliveredMoment && !_celebrate)
          Positioned.fill(
            child: PaidMoment(
              title: tr(context, 'Delivered!', 'Toimitettu!'),
              subtitle: tr(context, 'Enjoy your new things.', 'Nauti uusista ostoksistasi.'),
              onDone: () {
                if (mounted) setState(() => _deliveredMoment = false);
              },
            ),
          ),
      ]),
    );
  }

  /// After the thank-you moment: the first order is the right time to offer order notifications.
  void _afterCelebration() {
    if (!mounted) return;
    setState(() => _celebrate = false);
    unawaited(NotificationPrimer.maybeAsk(context));
  }

  Widget _body(Map<String, dynamic>? o) {
    if (o != null && _tracking(o)) return _trackingBody(o);
    return o == null
          ? (_error == null ? const MSkeletonDetail(heroHeight: 240) : MStateMessage.error(message: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: MSpace.x3l),
                children: [
                  if (_deliveryProblem(o)) _deliveryProblemCard(o),
                  if (!_isPickup && _active.contains(o['status']) && (_storePos != null || _homePos != null)) _mapCard(),
                  _statusCard(o),
                  if (_isPickup && o['status'] != 'CANCELLED' && o['status'] != 'REFUNDED') _pickupCard(o),
                  if (_canRate(o)) _ratePrompt(o),
                  _itemsCard(o),
                  _actions(o),
                ],
              ),
            );
  }

  bool _canRate(Map<String, dynamic> o) {
    final delivered = _time('deliveredAt');
    return o['status'] == 'DELIVERED' && _review == null && delivered != null && DateTime.now().difference(delivered).inDays < 30;
  }

  /// A gentle, one-tap way to rate: pick the stars here, the rest (comment, delivery) follows.
  Widget _ratePrompt(Map<String, dynamic> o) {
    final storeName = (o['store']?['name'] ?? '').toString();
    return _card(Column(
      children: [
        Text(tr(context, 'How was it?', 'Millaista oli?'), style: AppTheme.display(context, size: 20)),
        const SizedBox(height: MSpace.xs),
        Text(
          storeName.isEmpty
              ? tr(context, 'Your rating helps other shoppers.', 'Arviosi auttaa muita ostajia.')
              : tr(context, 'Rate $storeName. It helps other shoppers.', 'Arvioi $storeName. Se auttaa muita ostajia.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.label),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: tr(context, '$i of 5 stars', '$i/5 tähteä'),
                iconSize: 38,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.star_outline_rounded, color: MPalette.amber),
                onPressed: () {
                  Haptics.selection();
                  _rate(initial: i);
                },
              ),
          ],
        ),
      ],
    ));
  }

  Widget _mapCard() => Container(
        height: 280,
        margin: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        child: _liveMap(),
      );

  Widget _liveMap({EdgeInsets cameraPadding = const EdgeInsets.all(56)}) => LiveRouteMap(
        shop: _storePos,
        home: _homePos,
        courier: _courier,
        route: _route,
        courierAlong: _courierAlong,
        moveDuration: _moveDuration,
        courierIcon: _vehicleIcon(_order?['courier']?['vehicleType']?.toString()),
        // Paid and waiting for the shop to accept; then home, once the courier is nearly there
        pulseShop: _order?['status'] == 'PENDING' && _order?['paymentStatus'] == 'SUCCEEDED',
        pulseHome: _almostThere,
        cameraPadding: cameraPadding,
      );

  static IconData _vehicleIcon(String? vehicle) => switch (vehicle) {
        'car' => Icons.directions_car_rounded,
        'moped' => Icons.moped_rounded,
        'scooter' => Icons.electric_scooter_rounded,
        'ebike' => Icons.electric_bike_rounded,
        'on_foot' => Icons.directions_walk_rounded,
        _ => Icons.pedal_bike_rounded,
      };

  String? _vehicleText(String? vehicle) => switch (vehicle) {
        'bicycle' => tr(context, 'Bike courier', 'Pyöräkuriiri'),
        'ebike' => tr(context, 'E-bike courier', 'Sähköpyöräkuriiri'),
        'moped' => tr(context, 'Moped courier', 'Mopokuriiri'),
        'scooter' => tr(context, 'Scooter courier', 'Skootterikuriiri'),
        'car' => tr(context, 'Car courier', 'Autokuriiri'),
        'on_foot' => tr(context, 'Courier on foot', 'Kuriiri kävellen'),
        _ => null,
      };

  // ── Live tracking: full map with a Wolt-style sheet ───────────────────────

  static const _sheetInitial = 0.46;

  Widget _trackingBody(Map<String, dynamic> o) {
    return LayoutBuilder(builder: (context, box) {
      final sheetTop = box.maxHeight * _sheetInitial;
      return Stack(children: [
        Positioned.fill(
          // The route stays clear of the sheet as it first opens
          child: _liveMap(cameraPadding: EdgeInsets.fromLTRB(48, 72, 48, sheetTop + MSpace.xxl)),
        ),
        DraggableScrollableSheet(
          initialChildSize: _sheetInitial,
          minChildSize: 0.3,
          maxChildSize: 0.94,
          snap: true,
          snapSizes: const [_sheetInitial],
          builder: (context, scroll) => DecoratedBox(
            decoration: BoxDecoration(
              color: context.mColors.surface,
              borderRadius: MRadius.sheetTop,
              boxShadow: context.mTokens.shadow(MElevation.e3),
            ),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: MSpace.x3l),
              children: [
                const MSheetHandle(),
                _sheetHeader(o),
                if (_deliveryProblem(o)) _deliveryProblemCard(o),
                _statusCard(o, compact: true),
                _itemsCard(o),
                _actions(o),
              ],
            ),
          ),
        ),
      ]);
    });
  }

  /// Large ETA, one status line, the 4-step bar, the courier and the chat shortcuts.
  Widget _sheetHeader(Map<String, dynamic> o) {
    final c = context.mColors;
    final status = o['status'];
    final store = (o['store']?['name'] ?? '').toString();
    final courier = o['courier'] is Map ? Map<String, dynamic>.from(o['courier']) : null;
    final name = (courier?['name'] ?? '').toString().split(' ').first;
    final window = scheduledWindow(context, o['scheduledStart'], o['scheduledEnd']) ?? _etaWindow(o);
    final arrival = tr(context, 'Estimated arrival', 'Arvioitu saapuminen');
    String? label;
    String big;
    String line;
    if (status == 'SHIPPED') {
      final minutes = _minutesLeft;
      final left = _metresLeft;
      final onTheWay = name.isEmpty ? tr(context, 'Your courier is on the way', 'Kuriiri on matkalla') : tr(context, '$name is on the way', '$name on matkalla');
      if (_almostThere) {
        big = tr(context, 'Almost there', 'Melkein perillä');
        line = name.isEmpty ? tr(context, 'Your courier is nearly at your door', 'Kuriiri on kohta ovellasi') : tr(context, '$name is nearly at your door', '$name on kohta ovellasi');
      } else if (minutes != null) {
        label = tr(context, 'Arriving in', 'Perillä');
        big = _aboutMinutes(minutes);
        line = left == null ? onTheWay : '$onTheWay · ${_distanceText(left)}';
      } else {
        big = left == null ? (window ?? tr(context, 'On the way', 'Matkalla')) : _distanceText(left);
        label = left == null && window != null ? arrival : (left != null ? tr(context, 'Distance', 'Matkaa jäljellä') : null);
        line = onTheWay;
      }
    } else if (courier != null && (status == 'CONFIRMED' || status == 'PROCESSING')) {
      label = window == null ? null : arrival;
      big = window ?? tr(context, 'Courier on the way', 'Kuriiri tulossa');
      line = name.isEmpty
          ? tr(context, 'Your courier is picking up your order', 'Kuriiri hakee tilauksesi kaupasta')
          : tr(context, '$name is picking up your order', '$name hakee tilauksesi kaupasta');
    } else if (status == 'CONFIRMED' || status == 'PROCESSING') {
      label = window == null ? null : arrival;
      big = window ?? tr(context, 'Being prepared', 'Valmistellaan');
      line = status == 'PROCESSING'
          ? tr(context, '$store has packed your order. Finding a courier…', '$store on pakannut tilauksesi. Etsitään kuriiria…')
          : tr(context, '$store is preparing your order', '$store valmistelee tilaustasi');
    } else {
      label = window == null ? null : arrival;
      big = window ?? tr(context, 'Waiting for the store', 'Odotetaan kauppaa');
      line = tr(context, 'Waiting for $store to accept your order', 'Odotetaan, että $store hyväksyy tilauksesi');
    }
    final stale = _courierSeenAt != null && DateTime.now().difference(_courierSeenAt!) > const Duration(minutes: 2);
    final active = ['CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(status);
    final vehicle = courier?['vehicleType']?.toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.xs, MSpace.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (label != null) Text(label, style: MType.label.copyWith(color: c.onSurfaceVariant)),
              Text(big, style: MType.displayL.copyWith(color: c.onSurface)),
              const SizedBox(height: MSpace.xs),
              Text(line, style: MType.bodyL.copyWith(color: c.onSurface)),
            ]),
          ),
          const SizedBox(height: MSpace.lg),
          _progress4(o),
          if (courier != null && name.isNotEmpty) ...[
            const SizedBox(height: MSpace.lg),
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.peach, AppTheme.lingon), shape: BoxShape.circle),
                child: Icon(_vehicleIcon(vehicle), color: AppTheme.lingon, size: 24),
              ),
              const SizedBox(width: MSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: MType.title.copyWith(color: c.onSurface)),
                  if (stale)
                    Text(tr(context, 'Location updating…', 'Sijaintia päivitetään…'), style: MType.caption.copyWith(color: c.onSurfaceVariant))
                  else if (_vehicleText(vehicle) != null)
                    Text(_vehicleText(vehicle)!, style: MType.caption.copyWith(color: c.onSurfaceVariant)),
                ]),
              ),
            ]),
            if (active) ...[
              const SizedBox(height: MSpace.md),
              Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
                MChip(
                  label: _unread ? tr(context, 'New message', 'Uusi viesti') : tr(context, 'Chat', 'Chat'),
                  icon: Icons.chat_bubble_outline_rounded,
                  selected: _unread,
                  onSelected: (_) {
                    Haptics.selection();
                    _openChat();
                  },
                ),
                MChip(
                  label: tr(context, 'Door code', 'Ovikoodi'),
                  icon: Icons.dialpad_rounded,
                  onSelected: (_) {
                    Haptics.selection();
                    _openChat(prefill: tr(context, 'The door code is ', 'Ovikoodi on '));
                  },
                ),
              ]),
            ],
          ],
        ],
      ),
    );
  }

  /// Received → being prepared → on the way → delivered; the step under way is half filled.
  Widget _progress4(Map<String, dynamic> o) {
    final c = context.mColors;
    final status = o['status'];
    final reached = [
      true,
      ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'].contains(status),
      ['SHIPPED', 'DELIVERED'].contains(status),
      status == 'DELIVERED',
    ];
    final done = reached.where((r) => r).length;
    final labels = [
      tr(context, 'Received', 'Vastaanotettu'),
      tr(context, 'Preparing', 'Valmistellaan'),
      tr(context, 'On the way', 'Matkalla'),
      tr(context, 'Delivered', 'Perillä'),
    ];
    final brand = AppTheme.isDarkMode(context) ? MPalette.malvaOnDark : AppTheme.primary;
    return Semantics(
      label: tr(context, 'Step $done of 4: ${labels[done - 1]}', 'Vaihe $done/4: ${labels[done - 1]}'),
      excludeSemantics: true,
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: MSpace.xs),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(color: c.outline, borderRadius: BorderRadius.circular(3)),
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: MMotion.of(context, MMotion.slow),
                  curve: MMotion.standard,
                  widthFactor: i < done ? 1 : (i == done ? 0.4 : 0),
                  child: Container(decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(3))),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: MSpace.xs),
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Text(
                labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MType.caption.copyWith(color: i < done ? c.onSurface : c.onSurfaceVariant),
              ),
            ),
        ]),
      ]),
    );
  }

  void _tap(VoidCallback action) {
    Haptics.selection();
    action();
  }

  /// Opens the shop in the phone's maps app (geo: link), or OpenStreetMap in the browser.
  Future<void> _openMaps(Map<String, dynamic> store) async {
    Haptics.selection();
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
    final brand = AppTheme.isDarkMode(context) ? MPalette.malvaOnDark : AppTheme.primary;
    final ready = _time('readyAt');
    final hasPlace = (store['address'] ?? '').toString().isNotEmpty || store['latitude'] != null;
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCode) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: MSpace.xl, horizontal: MSpace.lg),
            decoration: BoxDecoration(
              color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Column(children: [
              Text(tr(context, 'Show this code at the shop', 'Näytä tämä koodi kaupassa'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
              const SizedBox(height: MSpace.sm),
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
                style: TextStyle(fontSize: MTextSize.label, color: AppTheme.primaryText(context), height: 1.35),
              ),
            ]),
          ),
          const SizedBox(height: MSpace.lg),
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
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store['name']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL, color: AppTheme.primaryText(context))),
                  if ((store['address'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(store['address'].toString(), style: TextStyle(fontSize: MTextSize.label, color: muted, height: 1.35)),
                    ),
                  if (status == 'PROCESSING' && ready != null)
                    Padding(
                      padding: const EdgeInsets.only(top: MSpace.xs),
                      child: Text(
                        tr(context, 'Ready since ${ready.day}.${ready.month}. ${_clock(ready)}', 'Valmiina ${ready.day}.${ready.month}. klo ${_clock(ready)} alkaen'),
                        style: TextStyle(fontSize: MTextSize.caption, color: muted),
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
            style: TextStyle(fontSize: MTextSize.caption, color: muted, height: 1.35),
          ),
      ],
    ));
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: child,
      );

  Widget _statusCard(Map<String, dynamic> o, {bool compact = false}) {
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
      (tr(context, 'Store accepted', 'Kauppa hyväksyi'), _time('confirmedAt'), ['CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Courier on the way to the store', 'Kuriiri matkalla kauppaan'), _time('acceptedAt'), o['courier'] != null),
      (tr(context, 'Picked up', 'Noudettu'), _time('pickedUpAt'), ['SHIPPED', 'DELIVERED'].contains(status)),
      (tr(context, 'Delivered', 'Toimitettu'), _time('deliveredAt'), status == 'DELIVERED'),
    ];
    final cancelled = status == 'CANCELLED' || status == 'REFUNDED';
    final unpaid = _unpaid(o);
    // Right after paying, the bank's confirmation may still be on its way to Malvoya
    final confirming = unpaid && _justPaid && o['paymentStatus'] != 'FAILED';
    final created = _time('createdAt');
    final heldUntil = created?.add(const Duration(minutes: 30));
    final courierName = (o['courier']?['name'] ?? '').toString().split(' ').first;
    final stale = _courierSeenAt != null && DateTime.now().difference(_courierSeenAt!) > const Duration(minutes: 2);

    final done = steps.where((s) => s.$3).length;
    final brand = AppTheme.isDarkMode(context) ? MPalette.malvaOnDark : AppTheme.primary;
    final showCourier = !compact && !_isPickup && courierName.isNotEmpty && _active.contains(status);

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
        Text(
          cancelled
              ? tr(context, 'Cancelled', 'Peruttu')
              : unpaid
                  ? (confirming ? tr(context, 'Confirming your payment…', 'Vahvistetaan maksua…') : tr(context, 'Payment not finished', 'Maksu jäi kesken'))
                  : (eta ?? tr(context, 'Waiting for the store', 'Odotetaan kauppaa')),
          style: AppTheme.display(context, size: 25),
        ),
        ],
        Padding(
          padding: EdgeInsets.only(top: compact ? 0 : MSpace.xs),
          child: Text('#${o['id']} · ${o['store']?['name'] ?? ''}', style: TextStyle(color: AppTheme.secondaryText(context))),
        ),
        if (cancelled && o['cancelReason'] != null) ...[
          Padding(padding: const EdgeInsets.only(top: MSpace.xs), child: Text(_cancelReason(o['cancelReason'].toString()), style: TextStyle(color: AppTheme.secondaryText(context)))),
          if (_unreachable(o))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(context,
                    'Your courier came to your address but could not reach you, so the order went back to the shop. The items are refunded to your card. The delivery fee and tip are not refunded, because the delivery was made.',
                    'Kuriiri tuli osoitteeseesi mutta ei tavoittanut sinua, joten tilaus palautettiin kauppaan. Tuotteiden hinta hyvitetään kortillesi. Toimitusmaksua ja tippiä ei hyvitetä, koska toimitus tehtiin.'),
                style: TextStyle(fontSize: MTextSize.label, height: 1.4, color: AppTheme.primaryText(context)),
              ),
            ),
        ],
        if (unpaid && !confirming) ...[
          const SizedBox(height: MSpace.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: MPalette.amberInk, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  heldUntil == null
                      ? tr(context, 'Payment not finished — nothing was charged. The items are held for 30 minutes.',
                          'Maksu jäi kesken – mitään ei veloitettu. Tuotteet pidetään varattuina 30 minuuttia.')
                      : tr(context, 'Payment not finished — nothing was charged. The items are held for 30 minutes (until ${_clock(heldUntil)}), then the order is cancelled.',
                          'Maksu jäi kesken – mitään ei veloitettu. Tuotteet pidetään varattuina 30 minuuttia (klo ${_clock(heldUntil)} asti), minkä jälkeen tilaus perutaan.'),
                  style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, height: 1.35, color: AppTheme.primaryText(context)),
                ),
              ),
            ]),
          ),
        ],
        if (!cancelled) ...[
          const SizedBox(height: 14),
          // One segment per step, filled as the order moves along (the sheet has its own 4-step bar)
          if (!compact) Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: MSpace.xs),
                Expanded(
                  child: AnimatedContainer(
                    duration: MMotion.slow,
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
                  const SizedBox(width: MSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(context, '$courierName is delivering', '$courierName toimittaa'),
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                        if (stale)
                          Text(tr(context, 'Location updating…', 'Sijaintia päivitetään…'),
                              style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context))),
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
                            Haptics.selection();
                            _openChat();
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.onBrand, size: 20),
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
          const SizedBox(height: MSpace.lg),
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
                      child: steps[i].$3 ? const Icon(Icons.check_rounded, size: 12, color: AppTheme.onBrand) : null,
                    ),
                    if (i < steps.length - 1)
                      Container(width: 2, height: 22, color: steps[i + 1].$3 ? brand : AppTheme.cardBorder(context)),
                  ],
                ),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Text(steps[i].$1,
                      style: TextStyle(
                        fontWeight: steps[i].$3 ? FontWeight.w600 : FontWeight.w400,
                        color: steps[i].$3 ? AppTheme.primaryText(context) : AppTheme.secondaryText(context),
                      )),
                ),
                if (steps[i].$2 != null) Text(_clock(steps[i].$2!), style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.label)),
              ],
            ),
        ],
      ],
    ));
  }

  static const _unreachableReason = 'customer could not be reached';

  bool _unreachable(Map<String, dynamic> o) =>
      '${o['cancelReason'] ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '') == _unreachableReason;

  String _cancelReason(String reason) {
    if (reason.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '') == _unreachableReason) {
      return tr(context, 'Customer could not be reached', 'Kuriiri ei tavoittanut sinua');
    }
    return localizeServerMessage(context, reason);
  }

  /// The courier is at the door (or cannot find it) and cannot reach the customer.
  bool _deliveryProblem(Map<String, dynamic> o) => o['deliveryProblemAt'] != null && o['status'] == 'SHIPPED' && !_isPickup;

  Widget _deliveryProblemCard(Map<String, dynamic> o) {
    const red = MPalette.red;
    final wrongAddress = o['deliveryProblemReason'] == 'WRONG_ADDRESS';
    final since = _time('deliveryProblemAt');
    final returnAt = since?.add(const Duration(minutes: 10));
    final dark = AppTheme.isDarkMode(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? red.withValues(alpha: 0.18) : MPalette.redLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: red, width: 1.5),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline_rounded, color: red, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  wrongAddress
                      ? tr(context, 'Your courier can\'t find your address — open the chat', 'Kuriiri ei löydä osoitettasi – avaa chat')
                      : tr(context, 'Your courier can\'t reach you — open the chat', 'Kuriiri ei tavoita sinua – avaa chat'),
                  style: AppTheme.display(context, size: 19, color: dark ? MPalette.white : MPalette.redInk),
                ),
              ),
            ]),
            const SizedBox(height: MSpace.sm),
            Text(
              returnAt == null
                  ? tr(context, 'Reply in the chat or come to the door. If the courier cannot reach you, the order goes back to the shop: the items are refunded, the delivery fee and tip are not.',
                      'Vastaa chatissa tai tule ovelle. Jos kuriiri ei tavoita sinua, tilaus palautetaan kauppaan: tuotteet hyvitetään, mutta toimitusmaksua ja tippiä ei.')
                  : tr(context, 'Reply in the chat or come to the door. From ${_clock(returnAt)} the courier may take the order back to the shop: the items are then refunded, the delivery fee and tip are not.',
                      'Vastaa chatissa tai tule ovelle. Klo ${_clock(returnAt)} alkaen kuriiri voi viedä tilauksen takaisin kauppaan. Tuotteet hyvitetään silloin, mutta toimitusmaksua ja tippiä ei.'),
              style: TextStyle(fontSize: MTextSize.bodyM, height: 1.4, color: AppTheme.primaryText(context)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: AppTheme.onBrand),
                onPressed: () {
                  Haptics.medium();
                  _openChat();
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(tr(context, 'Open the chat', 'Avaa chat')),
              ),
            ),
          ],
        ),
      ),
    );
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
        Row(children: [
          Expanded(child: Text(o['store']?['name'] ?? '', style: AppTheme.display(context, size: 18))),
          Text(tr(context, 'Receipt', 'Kuitti'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: muted)),
        ]),
        if (_isPickup)
          Text(tr(context, 'Collect from the shop', 'Nouto kaupasta'), style: TextStyle(color: muted, fontSize: MTextSize.label))
        else if (o['deliveryAddress'] != null)
          Text(o['deliveryAddress'], style: TextStyle(color: muted, fontSize: MTextSize.label)),
        if (!_isPickup && scheduledWindow(context, o['scheduledStart'], o['scheduledEnd']) != null)
          Text(
            '${tr(context, 'Delivery time', 'Toimitusaika')}: ${scheduledWindow(context, o['scheduledStart'], o['scheduledEnd'])}',
            style: TextStyle(color: muted, fontSize: MTextSize.label),
          ),
        const Divider(height: 24),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: MSpace.sm),
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
    // Not while Stripe is still confirming a payment that was just made
    final canPay = _unpaid(o) && !_payUnavailable && o['paymentStatus'] != 'PROCESSING' && !(_justPaid && o['paymentStatus'] != 'FAILED');
    final buttons = <Widget>[
      if (canPay)
        _button(Icons.lock_outline_rounded, tr(context, 'Complete payment', 'Viimeistele maksu'), _completePayment, primary: true, busy: _paying),
      if (status == 'PENDING') _button(Icons.close_rounded, tr(context, 'Cancel order', 'Peru tilaus'), _cancel),
      if (status == 'DELIVERED' && o['handoverMethod'] == 'PHOTO')
        _button(Icons.photo_camera_outlined, tr(context, 'Delivery photo', 'Toimituskuva'), _showProof),
      if (_review != null)
        Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
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
      // The withdrawal function (KSL 6:14 a, API 2.16): business sellers only, while the period lasts
      if (status == 'DELIVERED' && o['withdrawal'] is Map && o['withdrawal']['available'] == true)
        _button(Icons.assignment_turned_in_outlined, tr(context, 'Withdraw from contract here', 'Peru sopimus tästä'), () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ReturnsScreen(order: o, withdrawal: true)));
          if (mounted) _load();
        }, primary: true),
      if (status == 'DELIVERED' && withinReturn && o['withdrawal'] is Map && o['withdrawal']['reason'] == 'private_seller')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            tr(context,
                'This seller is a private person, so the legal right of withdrawal does not apply. You can still send a return request below.',
                'Myyjä on yksityishenkilö, joten lakisääteinen peruuttamisoikeus ei koske tätä ostoa. Voit silti lähettää palautuspyynnön alta.'),
            style: TextStyle(fontSize: MTextSize.label, height: 1.4, color: AppTheme.secondaryText(context)),
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
    return Padding(padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 0), child: Column(children: buttons));
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
