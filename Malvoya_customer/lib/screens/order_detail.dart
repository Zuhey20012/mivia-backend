import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../widgets/paid_moment.dart';
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

class _OrderDetailScreenState extends State<OrderDetailScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  bool _mapReady = false;

  /// The camera has been fitted to shop, home and the courier (once the courier is known).
  bool _fittedWithCourier = false;

  /// The courier marker glides from where it was drawn to each new position instead of jumping.
  late final _courierMove = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  LatLng? _courierFrom;

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
    _map.dispose();
    _courierMove.dispose();
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
    final firstFix = _courier == null;
    setState(() {
      _courierFrom = firstFix ? next : _courierShown;
      _courier = next;
      _courierSeenAt = DateTime.now();
    });
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _courierMove.value = 1;
    } else {
      _courierMove.forward(from: 0);
    }
    if (firstFix || !_fittedWithCourier) WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera());
  }

  /// Where the courier marker is drawn right now (between the last two positions while it moves).
  LatLng? get _courierShown {
    final to = _courier;
    final from = _courierFrom;
    if (to == null || from == null) return to;
    final t = Curves.easeInOut.transform(_courierMove.value);
    return LatLng(from.latitude + (to.latitude - from.latitude) * t, from.longitude + (to.longitude - from.longitude) * t);
  }

  List<LatLng> get _mapPoints => [if (_storePos != null) _storePos!, if (_homePos != null) _homePos!, if (_courier != null) _courier!];

  /// Shows the shop, the courier and home together.
  void _fitCamera() {
    final points = _mapPoints;
    if (!_mapReady || !mounted || points.length < 2) return;
    try {
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(56), maxZoom: 16.5));
      if (_courier != null) _fittedWithCourier = true;
    } catch (_) {}
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
        _courierFrom = _courier;
        _courierMove.value = 1;
      }
    });
    if (_courier != null && !_fittedWithCourier) WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera());
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

  Future<void> _openChat() async {
    final input = TextEditingController();
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
                  if (!_isPickup && _handoverPin(o) != null) _handoverPinCard(o, _handoverPin(o)!),
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

  Widget _mapCard() {
    final points = _mapPoints;
    Widget pin(IconData icon, Color color, String label) => Semantics(
          label: label,
          child: Container(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: MPalette.white, width: 3),
                boxShadow: [BoxShadow(color: MPalette.night.withValues(alpha: 0.26), blurRadius: 6)]),
            child: Icon(icon, color: AppTheme.onBrand, size: 18),
          ),
        );
    return Container(
      height: 280,
      margin: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 14,
              maxZoom: 18,
              // Shop and home (and the courier, when known) all in view from the start
              initialCameraFit: points.length > 1
                  ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(56), maxZoom: 16.5)
                  : null,
              onMapReady: () {
                _mapReady = true;
                if (_courier != null) _fittedWithCourier = true;
              },
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.malvoya.customer'),
              // Only the courier layers repaint while the marker glides
              AnimatedBuilder(
                animation: _courierMove,
                builder: (context, _) {
                  final courier = _courierShown;
                  return PolylineLayer(polylines: [
                    if (courier != null && _homePos != null)
                      Polyline(
                        points: [courier, _homePos!],
                        strokeWidth: 4,
                        color: AppTheme.primary.withValues(alpha: 0.6),
                        pattern: StrokePattern.dashed(segments: const [10, 8]),
                      ),
                  ]);
                },
              ),
              AnimatedBuilder(
                animation: _courierMove,
                builder: (context, _) {
                  final courier = _courierShown;
                  return MarkerLayer(markers: [
                    if (_storePos != null)
                      Marker(point: _storePos!, width: 38, height: 38, child: pin(Icons.storefront_rounded, AppTheme.primary, tr(context, 'Shop', 'Kauppa'))),
                    if (_homePos != null)
                      Marker(point: _homePos!, width: 38, height: 38, child: pin(Icons.home_rounded, AppTheme.success, tr(context, 'Your address', 'Osoitteesi'))),
                    if (courier != null)
                      Marker(point: courier, width: 46, height: 46, child: pin(Icons.pedal_bike_rounded, AppTheme.lingon, tr(context, 'Courier', 'Kuriiri'))),
                  ]);
                },
              ),
              const Align(
                alignment: Alignment.bottomRight,
                child: Padding(padding: EdgeInsets.all(MSpace.sm), child: Text('© OpenStreetMap', style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.ink))),
              ),
            ],
          ),
          if (points.length > 1)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: MPalette.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  tooltip: tr(context, 'Show the whole route', 'Näytä koko reitti'),
                  icon: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.ink),
                  onPressed: () {
                    Haptics.selection();
                    _fitCamera();
                  },
                ),
              ),
            ),
        ],
      ),
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

  /// The 4-digit handover PIN of a larger delivery (API 2.16, orders of 80 € or more): only the
  /// customer gets it, and only while the order is on its way. Null when the order has none.
  String? _handoverPin(Map<String, dynamic> o) {
    final pin = o['handoverPin']?.toString().trim() ?? '';
    if (pin.isEmpty) return null;
    return const {'CONFIRMED', 'PROCESSING', 'SHIPPED'}.contains(o['status']) ? pin : null;
  }

  /// Shown like the pickup code: the courier asks for it at the door.
  Widget _handoverPinCard(Map<String, dynamic> o, String pin) {
    return _card(Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: MSpace.xl, horizontal: MSpace.lg),
      decoration: BoxDecoration(
        color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(children: [
        Text(tr(context, 'Handover PIN', 'Luovutuskoodi'), style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
        const SizedBox(height: MSpace.sm),
        Semantics(
          label: '${tr(context, 'Handover PIN', 'Luovutuskoodi')} ${pin.split('').join(' ')}',
          excludeSemantics: true,
          child: FittedBox(
            child: SelectableText(
              pin,
              style: AppTheme.display(context, size: 44, color: AppTheme.primaryText(context)).copyWith(letterSpacing: 10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(context, 'Tell this code to the courier when they hand over your order. Do not share it with anyone else.',
              'Kerro tämä koodi kuriirille, kun hän luovuttaa tilauksesi. Älä anna sitä kenellekään muulle.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: MTextSize.label, color: AppTheme.primaryText(context), height: 1.35),
        ),
      ]),
    ));
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
          padding: const EdgeInsets.only(top: MSpace.xs),
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
          // One segment per step, filled as the order moves along
          Row(
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
