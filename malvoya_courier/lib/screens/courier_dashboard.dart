import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/haptics.dart';
import '../core/nav_apps.dart';
import '../core/screen_awake.dart';
import '../core/media_upload.dart';
import '../core/legal_links.dart';
import '../core/push_service.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
import '../core/delete_account_tile.dart';
import '../core/location_disclosure.dart';
import '../core/server_messages.dart';
import '../services/courier_telemetry_service.dart';
import '../services/socket_service.dart';
import '../widgets/earnings_chart.dart';
import '../widgets/job_map.dart';
import '../widgets/courier_profile_sheets.dart';
import '../widgets/mini_route.dart';
import '../widgets/onboarding_checklist.dart';
import '../widgets/skeletons.dart';
import '../widgets/swipe_to_confirm.dart';
import 'agreements_screen.dart';
import 'go_online_check.dart';
import 'help_screen.dart';
import 'offer_screen.dart';
import 'payouts_screen.dart';

enum _Load { loading, ready, error }

/// Go online, pick the jobs you want, deliver with navigation and chat, and see what you earn.
class CourierDashboard extends StatefulWidget {
  const CourierDashboard({super.key});

  @override
  State<CourierDashboard> createState() => _CourierDashboardState();
}

class _CourierDashboardState extends State<CourierDashboard> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _online = false;
  bool _switching = false;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _mine = [];
  Map<String, dynamic>? _earnings;
  // Chat with the customer of the active order. A notifier, so an open chat sheet shows new
  // messages as they arrive; _chatUnread puts a dot on the chat buttons while the sheet is closed.
  final ValueNotifier<List<Map<String, dynamic>>> _chat = ValueNotifier(const []);
  bool _chatOpen = false;
  bool _chatUnread = false;
  // The order whose chat is in _chat, and when its stored history was last fetched
  int? _chatOrderId;
  DateTime? _chatHistoryAt;
  // Whether the server stores chat (GET/POST /orders/:id/messages, API 2.10): null = not known yet.
  // When it does, messages can be sent over HTTP while the live connection is down.
  final ValueNotifier<bool?> _chatStored = ValueNotifier(null);

  // "Can't deliver?" (API 2.10): when the courier may take the order back, by order id (from the
  // server's answer; after a restart it is worked out from the order's deliveryProblemAt)
  final Map<int, DateTime> _canReturnAt = {};
  bool _reportingProblem = false;
  bool _returningToShop = false;
  // The server answered 404 (older version): the feature is hidden
  bool _problemUnsupported = false;
  // Orders taken back to the shop whose reminder the courier closed on this phone
  Set<String> _returnedDone = {};
  static const _returnedKey = 'returnedToShopOrders';

  // Each tab shows a placeholder until its first answer, and an error with "Try again" if that fails
  _Load _jobsLoad = _Load.loading;
  _Load _mineLoad = _Load.loading;
  _Load _earnLoad = _Load.loading;
  String? _jobsError;
  String? _mineError;
  String? _earnError;
  int _jobsRequest = 0; // only the newest job-list answer is used

  // Pay breakdowns that came with live offers, by order id (used if the job list has none yet)
  final Map<int, Map<String, dynamic>> _offerPay = {};
  // When a live offer reached this phone, by order id
  final Map<int, DateTime> _offeredAt = {};
  // The latest live offer, shown first and highlighted
  int? _newOfferId;
  // Which pay breakdowns are open ("job-12", "active-12")
  final Set<String> _openPay = {};

  int? _acceptingId;
  // Jobs closed (taken or cancelled) while this courier was accepting them, with the reason:
  // after the agreement sheet the retry is skipped and the courier is told at once
  final Map<int, String?> _closedWhileAccepting = {};

  // Onboarding checklist and announced agreement changes (API 2.11), shown above the tabs
  final _checklistKey = GlobalKey<OnboardingChecklistState>();
  final _agreementBannerKey = GlobalKey<AgreementUpdateBannerState>();
  String? _vehicleType;
  bool _arriving = false;
  bool _pickingUp = false;
  bool _completing = false;

  // Offers still open (shown in Jobs), so a full-screen offer closes when its job is taken
  final ValueNotifier<Set<int>> _openOffers = ValueNotifier({});
  bool _offerOnScreen = false;

  // Earnings: today by hour, or the last 7 days by day
  bool _earnWeek = false;

  // The job list is re-checked every 20 s while online, free and in the foreground (socket fallback)
  Timer? _poll;
  bool _foreground = true;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);
  ApiClient get _api => ApiClient(_auth);
  Map<String, dynamic>? get _active {
    for (final o in _mine) {
      if (['CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])) return o;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final socket = CourierSocketService();
    socket.onDispatchOffer = _onOffer;
    socket.onOrderStatus = (_) => _loadMine();
    socket.onChatMessage = _onChatMessage;
    socket.onOfferClosed = _onOfferClosed;
    socket.onChatHistory = (orderId, messages) {
      if (!mounted || orderId != _chatOrderId) return;
      _chatStored.value = true;
      final fromOthers = _mergeChat(messages);
      if (fromOthers > 0 && !_chatOpen) setState(() => _chatUnread = true);
    };
    PushService.instance.onOpen = (data) {
      if (!mounted || data['type'] != 'offer') return;
      if (_active == null) _tabs.animateTo(0);
      _loadJobs();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _restored = ConnectivityService.instance.onRestored.listen((_) => _backOnline());
  }

  StreamSubscription<void>? _restored;
  bool _meLoaded = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _restored?.cancel();
    PushService.instance.onOpen = null;
    final socket = CourierSocketService();
    socket.onDispatchOffer = null;
    socket.onOrderStatus = null;
    socket.onChatMessage = null;
    socket.onOfferClosed = null;
    socket.onChatHistory = null;
    _chat.dispose();
    _chatStored.dispose();
    _openOffers.dispose();
    ScreenAwake.instance.want(false);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _syncPolling();
    // Back in the app: catch up on anything missed while it was in the background
    if (foreground && _meLoaded) {
      _loadMine();
      if (_online) _loadJobs();
      // e.g. back from Stripe's payout pages
      _checklistKey.currentState?.reload();
    }
  }

  /// Polls the job list only while it is useful: online, no delivery in progress, app on screen.
  void _syncPolling() {
    final want = _online && _active == null && _foreground;
    if (want && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _loadJobs());
    } else if (!want) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// The internet is back. During a delivery the customer must see the courier again quickly:
  /// load the orders first (this also renews an expired session), then reconnect the live
  /// connection with the fresh token and send the latest position straight away.
  Future<void> _backOnline() async {
    if (!mounted) return;
    // Opened without internet: nothing is known yet, start properly
    if (!_meLoaded) return _init();
    await _loadMine();
    if (!mounted) return;
    if (_online) {
      final token = _auth.accessToken ?? '';
      CourierSocketService().ensureConnected(token);
      CourierTelemetryService().resume(token);
    }
    await Future.wait([_loadJobs(), _loadEarnings()]);
  }

  Future<void> _init() async {
    unawaited(_loadReturnedDone());
    final me = await _api.get('/courier/me');
    if (!mounted) return;
    _meLoaded = me.ok;
    final online = me.ok && me.data['courier']?['isOnline'] == true;
    setState(() {
      _online = online;
      final vehicle = me.data['courier']?['vehicleType'];
      if (vehicle is String) _vehicleType = vehicle;
    });
    if (online) {
      // Still online from last time. Sharing restarts by itself only when the courier has accepted
      // the location disclosure and the permission is still there; otherwise they are asked first.
      await _loadMine();
      if (!mounted) return;
      if (await LocationDisclosure.canResumeSilently()) {
        if (!await _startSharing() && mounted) {
          _snack(tr(context, 'Turn on location to keep sharing your position while you are online.',
              'Laita sijainti päälle, jotta sijaintisi jaetaan linjoilla ollessasi.'));
        }
      } else if (mounted) {
        await _resumeSharingWithConsent();
      }
    }
    await Future.wait([_loadJobs(), _loadMine(), _loadEarnings()]);
  }

  /// Online on the server, but this phone may not share the location yet (disclosure never
  /// accepted, or permission withdrawn): ask with the disclosure. If the courier says no, they go
  /// offline, unless they are carrying an order, which must not be dropped silently.
  Future<void> _resumeSharingWithConsent() async {
    final go = await GoOnlineCheck.run(context);
    if (!mounted) return;
    if (go && await _startSharing()) return;
    if (!mounted) return;
    if (_active != null) {
      _snack(tr(context, 'Location sharing is off, so the customer cannot follow your delivery. Allow location to turn it back on.',
          'Sijainnin jakaminen on pois päältä, joten asiakas ei voi seurata toimitusta. Salli sijainti, niin jakaminen jatkuu.'));
      return;
    }
    final res = await _api.post('/courier/status', {'isOnline': false});
    if (!mounted) return;
    if (res.ok) {
      setState(() => _online = false);
      _syncPolling();
      _snack(tr(context, 'You are offline because location is not shared. Go online when you are ready.',
          'Olet poissa linjoilta, koska sijaintia ei jaeta. Mene linjoille, kun olet valmis.'));
    }
  }

  Future<void> _refreshAll() => Future.wait([_loadJobs(manual: true), _loadMine(manual: true), _loadEarnings(manual: true)]);

  Future<bool> _startSharing() async {
    final token = _auth.accessToken ?? '';
    CourierSocketService().connect(token);
    final ok = await CourierTelemetryService().start(accessToken: token, orderId: asInt(_active?['id']));
    return ok;
  }

  /// Sends a position through the session-aware client (used right before location-checked actions).
  Future<bool> _postPosition(Map<String, dynamic> body) async => (await _api.post('/courier/telemetry', body)).ok;

  /// The switch on the online card. While carrying an order, going offline is blocked unless the
  /// courier confirms they have to stop; they are then shown how to tell Malvoya.
  Future<void> _onSwitch() async {
    final active = _active;
    if (_online && active != null) {
      if (!await _confirmStop(active)) return;
      await _setOnline(false);
      if (!mounted) return;
      await _openHelp(orderId: asInt(active['id']), stopping: true);
      return;
    }
    if (!_online) {
      // Location disclosure, permission and a short checklist before going online
      setState(() => _switching = true);
      final go = await GoOnlineCheck.run(context);
      if (!mounted) return;
      setState(() => _switching = false);
      if (!go) return;
    }
    await _setOnline(!_online);
  }

  Future<void> _setOnline(bool next) async {
    if (next == _online) return;
    HapticFeedback.mediumImpact();
    setState(() => _switching = true);
    double? lat;
    double? lng;
    if (next) {
      if (!await _startSharing()) {
        if (mounted) {
          setState(() => _switching = false);
          _snack(tr(context, 'Turn on location and allow it for Malvoya Courier to go online.', 'Laita sijainti päälle ja salli se Malvoya Courierille mennäksesi linjoille.'));
        }
        return;
      }
      try {
        final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        lat = p.latitude;
        lng = p.longitude;
      } catch (_) {}
    } else {
      CourierTelemetryService().stop();
    }
    final body = {'isOnline': next, 'latitude': lat, 'longitude': lng};
    var res = await _api.post('/courier/status', body);
    if (!mounted) return;
    // Going online needs the Courier Agreement in force (428, API 2.11): show it, then go online by itself
    final need = next ? AgreementRequired.from(res) : null;
    if (need != null) {
      if (await Agreements.resolve(context, _auth, need)) {
        if (!mounted) return;
        res = await _api.post('/courier/status', body);
        _checklistKey.currentState?.reload();
        _agreementBannerKey.currentState?.reload();
      }
      if (!mounted) return;
    }
    // Not online after all: location must not stay shared
    if (next && !res.ok && _active == null) CourierTelemetryService().stop();
    setState(() {
      _switching = false;
      if (res.ok) _online = next;
    });
    if (!res.ok) _snack(res.error!);
    _syncPolling();
    _syncAwake();
    if (_online) _loadJobs();
  }

  /// "You are carrying an order": explains why going offline is blocked. True = the courier has to stop.
  Future<bool> _confirmStop(Map<String, dynamic> o) async {
    HapticFeedback.mediumImpact();
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'You are carrying order #${o['id']}', 'Sinulla on tilaus #${o['id']}')),
        content: Text(tr(context,
            'Please stay online until you have handed it over. Going offline stops sharing your location, so the customer can no longer follow the delivery, and the order stays assigned to you.\n\nIf you really have to stop, you can go offline and then tell Malvoya through Help, so we can sort out the order with the shop and the customer.',
            'Pysy linjoilla, kunnes olet luovuttanut tilauksen. Linjoilta poistuminen lopettaa sijaintisi jakamisen, jolloin asiakas ei voi enää seurata toimitusta, ja tilaus pysyy sinulla.\n\nJos sinun on pakko lopettaa, voit poistua linjoilta ja kertoa siitä Malvoyalle Apua-sivun kautta, niin selvitämme tilauksen kaupan ja asiakkaan kanssa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'I have to stop', 'Minun on pakko lopettaa'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep delivering', 'Jatka toimitusta'))),
        ],
      ),
    );
    return stop == true;
  }

  Future<void> _openHelp({int? orderId, bool stopping = false}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => HelpScreen(orderId: orderId, stoppingDelivery: stopping)));

  /// Account: Google link, help, sign out and delete account.
  void _openAccount() {
    HapticFeedback.selectionClick();
    final user = _auth.currentUser;
    final email = user?.email ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Icon(Icons.person_outline_rounded, color: AppTheme.primary),
              ),
              title: Text(user?.name ?? tr(context, 'Your account', 'Tilisi'), style: AppTheme.display(size: 19)),
              // Phone sign-ins have a technical address that means nothing to the courier
              subtitle: email.isEmpty || email.endsWith('@phone.malvoya.app') ? null : Text(email),
            ),
            const Divider(height: 16),
            const GoogleLinkTile(),
            FutureBuilder<NavApp?>(
              future: NavApps.saved(),
              builder: (ctx, snap) => ListTile(
                leading: const Icon(Icons.navigation_outlined),
                title: Text(tr(context, 'Navigation app', 'Navigointisovellus'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(snap.data == null ? tr(context, 'Asked the first time you navigate', 'Kysytään, kun navigoit ensimmäisen kerran') : NavApps.label(context, snap.data!)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  Navigator.pop(ctx);
                  await NavApps.choose(context, offerRemember: false);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: Text(tr(context, 'Help and contact', 'Apua ja yhteydenotto'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _openHelp(orderId: asInt(_active?['id']));
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(tr(context, 'Name and phone', 'Nimi ja puhelin'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                if (await showCourierProfileSheet(context)) {
                  _checklistKey.currentState?.reload();
                  if (mounted) setState(() {});
                }
              },
            ),
            ListTile(
              leading: Icon(vehicleIcon(_vehicleType)),
              title: Text(tr(context, 'Vehicle', 'Kulkuneuvo'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _vehicleType == null ? null : Text(vehicleLabel(context, _vehicleType!)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showVehiclePicker(context, current: _vehicleType);
                if (picked == null || !mounted) return;
                setState(() => _vehicleType = picked);
                _checklistKey.currentState?.reload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_rounded),
              title: Text(tr(context, 'Agreements', 'Sopimukset'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tr(context, 'Courier Agreement, privacy, your copies', 'Lähettisopimus, tietosuoja, kopiosi')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsScreen()));
                if (!mounted) return;
                _checklistKey.currentState?.reload();
                _agreementBannerKey.currentState?.reload();
              },
            ),
            const Divider(height: 16),
            const DeleteAccountTile(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _signOut();
                },
                icon: const Icon(Icons.logout_rounded),
                label: Text(tr(context, 'Sign out', 'Kirjaudu ulos')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final active = _active;
    // Online with a delivery in progress has its own warning below; otherwise one plain confirmation
    if (!_online || active == null) {
      final ok = await _confirm(
        title: tr(context, 'Sign out?', 'Kirjaudutaanko ulos?'),
        body: _online
            ? tr(context, 'You go offline and stop getting job offers on this phone.', 'Poistut linjoilta etkä enää saa keikkatarjouksia tähän puhelimeen.')
            : tr(context, 'You stop getting job offers on this phone until you sign in again.', 'Et saa keikkatarjouksia tähän puhelimeen, ennen kuin kirjaudut uudelleen.'),
        yes: tr(context, 'Sign out', 'Kirjaudu ulos'),
      );
      if (!ok || !mounted) return;
    }
    if (_online && active != null) {
      if (!await _confirmStop(active)) return;
      await _setOnline(false);
      if (!mounted) return;
      await _openHelp(orderId: asInt(active['id']), stopping: true);
    } else if (_online) {
      await _setOnline(false);
    }
    CourierSocketService().disconnect();
    await _auth.logout();
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  /// Orders the courier app handles. Pickup orders (collected by the customer) never involve a
  /// courier, so they are skipped if one ever shows up.
  List<Map<String, dynamic>> _orders(dynamic list) => ((list as List?) ?? [])
      .whereType<Map>()
      .map((o) => Map<String, dynamic>.from(o))
      .where((o) => o['fulfilment'] != 'PICKUP')
      .toList();

  Future<void> _loadJobs({bool manual = false}) async {
    final request = ++_jobsRequest;
    final res = await _api.get('/orders/available');
    if (!mounted || request != _jobsRequest) return;
    if (!res.ok) {
      if (_jobsLoad == _Load.ready) {
        if (manual) _snack(res.error!);
      } else {
        setState(() {
          _jobsLoad = _Load.error;
          _jobsError = res.error;
        });
      }
      return;
    }
    final jobs = _orders(res.data['orders']);
    final ids = jobs.map((j) => asInt(j['id'])).toSet();
    // Taken by another courier or withdrawn: the offer disappears here and from the notifications
    for (final old in _jobs) {
      final id = asInt(old['id']);
      if (id != null && !ids.contains(id)) PushService.instance.clearOffer(id);
    }
    setState(() {
      _jobs = jobs;
      _jobsLoad = _Load.ready;
      _jobsError = null;
      if (!ids.contains(_newOfferId)) _newOfferId = null;
    });
    _openOffers.value = ids.whereType<int>().toSet();
  }

  Future<void> _loadMine({bool manual = false}) async {
    final res = await _api.get('/orders/courier/mine');
    if (!mounted) return;
    if (!res.ok) {
      if (_mineLoad == _Load.ready) {
        if (manual) _snack(res.error!);
      } else {
        setState(() {
          _mineLoad = _Load.error;
          _mineError = res.error;
        });
      }
      return;
    }
    setState(() {
      _mine = _orders(res.data['orders']);
      _mineLoad = _Load.ready;
      _mineError = null;
    });
    final active = _active;
    final activeId = asInt(active?['id']);
    CourierTelemetryService().setActiveOrder(activeId);
    if (activeId != _chatOrderId) {
      // Another order (or none): its own chat, filled from the server's stored history
      _chatOrderId = activeId;
      _chatHistoryAt = null;
      _chat.value = const [];
      if (_chatUnread) setState(() => _chatUnread = false);
    }
    if (activeId != null) {
      CourierSocketService().trackOrder(activeId);
      _loadChatHistory(activeId);
    }
    _syncAwake();
    _syncPolling();
  }

  /// The screen stays on while a delivery is in progress (not when the battery is low).
  void _syncAwake() => ScreenAwake.instance.want(_online && _active != null);

  Future<void> _loadEarnings({bool manual = false}) async {
    final res = await _api.get('/payouts');
    if (!mounted) return;
    if (!res.ok) {
      if (_earnLoad == _Load.ready) {
        if (manual) _snack(res.error!);
      } else {
        setState(() {
          _earnLoad = _Load.error;
          _earnError = res.error;
        });
      }
      return;
    }
    setState(() {
      _earnings = res.data;
      _earnLoad = _Load.ready;
      _earnError = null;
    });
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  /// The server's own message when it gave one (e.g. "Get closer to the shop"), in Finnish when
  /// the app is in Finnish and a translation is known, else [fallback].
  String _serverMessage(ApiResult res, String fallback) {
    final e = res.data['error'];
    return e is String && e.trim().isNotEmpty ? ServerMessages.localize(e) : fallback;
  }

  /// The server's English message, for recognising which refusal it was.
  String _rawError(ApiResult res) => '${res.data['error'] ?? ''}';

  static final _locationWords = RegExp(r'locat|far |km|metre|meter|closer|nearby|near the|sijain|etäi|lähe', caseSensitive: false);

  // ── Chat ────────────────────────────────────────────────────────────────

  void _resetChat() {
    _chat.value = const [];
    _chatUnread = false;
    _chatOrderId = null;
    _chatHistoryAt = null;
  }

  /// A chat message for the order being carried (the server also echoes the courier's own).
  void _onChatMessage(Map<String, dynamic> m) {
    if (!mounted || asInt(m['orderId']) != asInt(_active?['id'])) return;
    _chatOrderId ??= asInt(m['orderId']);
    final fromOthers = _mergeChat([m]);
    if (fromOthers > 0 && !_chatOpen) {
      HapticFeedback.mediumImpact();
      setState(() => _chatUnread = true);
    }
  }

  bool _isMine(Map m) {
    final sender = asInt(m['senderId']);
    final me = _auth.currentUser?.id;
    return sender != null && me != null ? sender == me : (m['role'] ?? m['senderRole']) == 'COURIER';
  }

  static DateTime? _messageTime(Map m) => DateTime.tryParse('${m['createdAt'] ?? m['timestamp'] ?? ''}');

  /// The same message arriving twice (live, in the stored history, as the answer to a send):
  /// same id when both have one, otherwise same sender and text within half a minute.
  static bool _sameMessage(Map a, Map b) {
    final ia = a['id'], ib = b['id'];
    if (ia != null && ib != null) return '$ia' == '$ib';
    if ('${a['text'] ?? ''}'.trim() != '${b['text'] ?? ''}'.trim()) return false;
    final sa = asInt(a['senderId']), sb = asInt(b['senderId']);
    if (sa != null && sb != null && sa != sb) return false;
    final ta = _messageTime(a), tb = _messageTime(b);
    return ta == null || tb == null || ta.difference(tb).inSeconds.abs() <= 30;
  }

  /// Adds messages to the open order's chat, each only once, oldest first. Returns how many new
  /// messages came from the customer.
  int _mergeChat(Iterable<Map<String, dynamic>> incoming) {
    final list = [..._chat.value];
    var fromOthers = 0;
    for (final m in incoming) {
      if ('${m['text'] ?? ''}'.trim().isEmpty) continue;
      final i = list.indexWhere((e) => _sameMessage(e, m));
      if (i >= 0) {
        // Keep the stored copy's id, so later copies are matched exactly
        if (list[i]['id'] == null && m['id'] != null) list[i] = {...list[i], ...m};
        continue;
      }
      list.add(m);
      if (!_isMine(m)) fromOthers++;
    }
    final far = DateTime.utc(2100);
    list.sort((a, b) => (_messageTime(a) ?? far).compareTo(_messageTime(b) ?? far));
    _chat.value = List.unmodifiable(list);
    return fromOthers;
  }

  /// The order's stored chat (API 2.10). A 404 means an older server that only relays live
  /// messages; then nothing is stored and sending needs the live connection.
  Future<void> _loadChatHistory(int orderId, {bool force = false}) async {
    final last = _chatHistoryAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 15)) return;
    _chatHistoryAt = DateTime.now();
    final res = await _api.get('/orders/$orderId/messages');
    if (!mounted || orderId != _chatOrderId) return;
    if (res.status == 404) {
      _chatStored.value = false;
      return;
    }
    if (!res.ok) return;
    _chatStored.value = true;
    final list = res.data['messages'];
    if (list is! List) return;
    final fromOthers = _mergeChat(list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
    if (fromOthers > 0 && !_chatOpen) setState(() => _chatUnread = true);
  }

  /// Sends over the live connection, or over HTTP while it is down (when the server stores chat).
  /// Returns an error to show, or null when sent.
  Future<String?> _sendChat(int orderId, String text, String myName) async {
    final socket = CourierSocketService();
    if (socket.isConnected) {
      socket.sendChat(orderId, text, myName);
      return null;
    }
    final notConnected = tr(context, 'Not connected right now, so the message was not sent. Check your internet connection.',
        'Ei yhteyttä juuri nyt, joten viestiä ei lähetetty. Tarkista nettiyhteys.');
    if (_chatStored.value == false) return notConnected;
    final res = await _api.post('/orders/$orderId/messages', {'text': text});
    if (!mounted) return null;
    if (res.status == 404) {
      _chatStored.value = false;
      return notConnected;
    }
    if (!res.ok) return res.error;
    _chatStored.value = true;
    final m = res.data['message'];
    _mergeChat([
      m is Map
          ? Map<String, dynamic>.from(m)
          : {
              'orderId': orderId,
              'text': text,
              'senderId': _auth.currentUser?.id,
              'role': 'COURIER',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
    ]);
    return null;
  }

  // ── Offers ──────────────────────────────────────────────────────────────

  /// Another courier took the job, or the order was cancelled: the offer disappears from the list
  /// and the notifications. If the courier was looking at it, they are told why.
  void _onOfferClosed(Map<String, dynamic> data) {
    final id = asInt(data['orderId']);
    if (id == null || !mounted) return;
    PushService.instance.clearOffer(id);
    // This courier's own accept is answered by the accept request itself
    if (_acceptingId == id) {
      _closedWhileAccepting[id] = data['reason'] as String?;
      return;
    }
    if (asInt(_active?['id']) == id) return;
    final shown = _jobs.any((j) => asInt(j['id']) == id);
    if (!shown) return;
    final watching = _foreground && _online && _active == null && _tabs.index == 0;
    setState(() {
      _jobs = _jobs.where((j) => asInt(j['id']) != id).toList();
      _offerPay.remove(id);
      if (_newOfferId == id) _newOfferId = null;
    });
    _openOffers.value = {..._openOffers.value}..remove(id);
    if (watching) _snack(_offerGoneText(cancelled: data['reason'] == 'cancelled'));
  }

  String _offerGoneText({bool cancelled = false}) => cancelled
      ? tr(context, 'That order was cancelled, so the job is gone.', 'Tilaus peruttiin, joten keikka poistui.')
      : tr(context, 'Taken by another courier.', 'Toinen lähetti otti keikan.');


  /// A live offer: shown at the top of Jobs straight away, announced once (haptic + the phone's
  /// notification sound), then confirmed against the job list. Never accepted automatically.
  void _onOffer(Map<String, dynamic> offer) {
    if (!mounted || offer['fulfilment'] == 'PICKUP') return;
    final id = asInt(offer['orderId'] ?? offer['id']);
    if (id == null) return;
    if (offer['courierPay'] is Map) _offerPay[id] = Map<String, dynamic>.from(offer['courierPay']);
    // The fallback broadcast reaches busy couriers too; they cannot take another job
    if (!_online || _active != null) return;
    final isNew = !_offeredAt.containsKey(id);
    _offeredAt.putIfAbsent(id, DateTime.now);
    if (isNew) {
      setState(() {
        _newOfferId = id;
        if (!_jobs.any((j) => asInt(j['id']) == id)) _jobs = [_jobFromOffer(id, offer), ..._jobs];
        _jobsLoad = _Load.ready;
      });
      _openOffers.value = {..._openOffers.value, id};
      Haptics.offer();
      final store = '${offer['storeName'] ?? ''}';
      final window = _windowText(offer);
      final where = store.isEmpty ? tr(context, 'Open Jobs to see it.', 'Katso Keikat-välilehdeltä.') : '${tr(context, 'Pick up at', 'Nouto')}: $store';
      PushService.instance.alertOffer(
        orderId: id,
        title: '${tr(context, 'New delivery', 'Uusi toimitus')} · ${_payText(offer)}',
        body: window == null ? where : '$where · $window',
      );
      if (_tabs.index != 0) _tabs.animateTo(0);
      // On screen: show it full screen, like a ride-hailing offer (never accepted automatically)
      if (_foreground) _presentOffer(id);
    }
    _loadJobs();
  }

  ({double lat, double lng})? _pt(dynamic lat, dynamic lng) {
    double? d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final a = d(lat), b = d(lng);
    return a == null || b == null ? null : (lat: a, lng: b);
  }

  /// Straight-line distances of a job: you → shop and shop → drop-off area, as text.
  ({String? toStore, String? drop}) _jobDistances(Map j) {
    final here = CourierTelemetryService().lastPosition;
    final s = (j['store'] as Map?) ?? {};
    final store = _pt(s['latitude'], s['longitude']);
    final area = _pt(j['deliveryAreaLat'], j['deliveryAreaLng']);
    return (
      toStore: here != null && store != null ? '${_km(Geolocator.distanceBetween(here.latitude, here.longitude, store.lat, store.lng) / 1000)} km' : null,
      drop: store != null && area != null ? '${_km(Geolocator.distanceBetween(store.lat, store.lng, area.lat, area.lng) / 1000)} km' : null,
    );
  }

  /// The full-screen offer for a job in the list. Accepting goes through the normal accept.
  Future<void> _presentOffer(int id) async {
    if (_offerOnScreen || !mounted) return;
    final job = _jobs.where((j) => asInt(j['id']) == id).firstOrNull;
    if (job == null) return;
    final s = (job['store'] as Map?) ?? {};
    final here = CourierTelemetryService().lastPosition;
    final pay = _payOf(job);
    final dist = _jobDistances(job);
    final view = OfferView(
      orderId: id,
      pay: _payText(job),
      tipCents: asInt(pay?['tipCents']) ?? asInt(job['tipCents']) ?? 0,
      explanation: _localized(pay?['summary']) ?? _localized(pay?['explanation']),
      window: _windowText(job),
      age: _offerAge(job),
      storeName: '${s['name'] ?? ''}',
      storeAddress: s['address']?.toString(),
      items: asInt(job['itemCount']),
      me: here == null ? null : (lat: here.latitude, lng: here.longitude),
      store: _pt(s['latitude'], s['longitude']),
      dropOff: _pt(job['deliveryAreaLat'], job['deliveryAreaLng']),
      toStore: dist.toStore,
      drop: dist.drop,
    );
    _offerOnScreen = true;
    final accept = await showOfferScreen(context, offer: view, openOffers: _openOffers);
    _offerOnScreen = false;
    if (accept && mounted) await _accept(job);
  }

  Map<String, dynamic> _jobFromOffer(int id, Map<String, dynamic> offer) => {
        'id': id,
        'status': 'CONFIRMED',
        'store': {
          'id': offer['storeId'],
          'name': offer['storeName'],
          'address': offer['storeAddress'],
          'latitude': offer['storeLat'],
          'longitude': offer['storeLng'],
        },
        'courierFeeCents': offer['courierFeeCents'],
        'tipCents': offer['tipCents'],
        if (offer['courierPay'] is Map) 'courierPay': offer['courierPay'],
        'deliveryAreaLat': offer['deliveryAreaLat'],
        'deliveryAreaLng': offer['deliveryAreaLng'],
        'createdAt': offer['createdAt'],
        'scheduledStart': offer['scheduledStart'],
        'scheduledEnd': offer['scheduledEnd'],
      };

  // ── Scheduled delivery windows ──────────────────────────────────────────
  // Since API 2.9.0 a scheduled order carries scheduledStart/scheduledEnd: it is handed over within
  // that window, so no "as soon as possible" estimate is shown for it.

  ({DateTime start, DateTime end})? _window(Map o) {
    final start = DateTime.tryParse('${o['scheduledStart'] ?? ''}')?.toLocal();
    final end = DateTime.tryParse('${o['scheduledEnd'] ?? ''}')?.toLocal();
    if (start == null || end == null || !end.isAfter(start)) return null;
    return (start: start, end: end);
  }

  String _clock(DateTime t) {
    final mm = t.minute.toString().padLeft(2, '0');
    return isFinnish(context) ? '${t.hour}.$mm' : '${t.hour.toString().padLeft(2, '0')}:$mm';
  }

  /// "Deliver 17:00–19:00" / "Toimita huomenna 17.00–19.00", or null for an as-soon-as-possible job.
  String? _windowText(Map o) {
    final w = _window(o);
    if (w == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(w.start.year, w.start.month, w.start.day).difference(today).inDays;
    final range = '${_clock(w.start)}–${_clock(w.end)}';
    final String when;
    if (day == 0) {
      when = range;
    } else if (day == 1) {
      when = tr(context, 'tomorrow $range', 'huomenna $range');
    } else {
      when = '${w.start.day}.${w.start.month}. $range';
    }
    return tr(context, 'Deliver $when', 'Toimita $when');
  }

  /// The delivery window on a job card or the active delivery.
  Widget _windowBadge(Map o, {bool detailed = false}) {
    final text = _windowText(o);
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppTheme.lilac, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.schedule_rounded, size: 18, color: AppTheme.malva),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr(context, 'Scheduled', 'Ajastettu')} · $text',
                style: const TextStyle(color: AppTheme.malva, fontWeight: FontWeight.w800, fontSize: 14)),
            if (detailed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    tr(context, 'The customer chose this delivery window. Hand the order over within it.',
                        'Asiakas valitsi tämän toimitusajan. Luovuta tilaus tämän aikavälin sisällä.'),
                    style: const TextStyle(color: AppTheme.malva, fontSize: 12.5, height: 1.35)),
              ),
          ]),
        ),
      ]),
    );
  }

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return tr(context, 'just now', 'juuri nyt');
    if (m < 60) return tr(context, '$m min ago', '$m min sitten');
    final h = m ~/ 60;
    return tr(context, '$h h ago', '$h h sitten');
  }

  /// How long the offer has been out: exact for live offers, otherwise from the server's timestamps.
  String? _offerAge(Map j) {
    final id = asInt(j['id']);
    final live = id == null ? null : _offeredAt[id];
    final offered = live ?? DateTime.tryParse('${j['offeredAt'] ?? j['confirmedAt'] ?? ''}')?.toLocal();
    if (offered != null) return '${tr(context, 'Offered', 'Tarjottu')} ${_ago(offered)}';
    final placed = DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal();
    return placed == null ? null : '${tr(context, 'Order placed', 'Tilattu')} ${_ago(placed)}';
  }

  Future<void> _accept(Map<String, dynamic> job) async {
    final id = asInt(job['id']);
    if (id == null || _acceptingId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _acceptingId = id);
    _closedWhileAccepting.remove(id);
    // The server checks how far the courier is from the shop, so it needs a fresh position
    var sent = await CourierTelemetryService().sendNow(post: _postPosition);
    final sentAt = DateTime.now();
    if (!mounted) return;
    var res = await _api.patch('/orders/$id/assign-courier');
    if (!mounted) return;
    // Taking jobs needs the Courier Agreement in force (428, API 2.11): show it, then accept by itself
    final need = AgreementRequired.from(res);
    if (need != null) {
      final accepted = await Agreements.resolve(context, _auth, need);
      if (!mounted) return;
      if (accepted) {
        _checklistKey.currentState?.reload();
        _agreementBannerKey.currentState?.reload();
      }
      if (accepted && _closedWhileAccepting.containsKey(id)) {
        // Taken by another courier (or cancelled) while the agreement was open: no point asking the server
        final reason = _closedWhileAccepting.remove(id);
        setState(() {
          _acceptingId = null;
          _jobs = _jobs.where((j) => asInt(j['id']) != id).toList();
          _offerPay.remove(id);
          if (_newOfferId == id) _newOfferId = null;
        });
        _openOffers.value = {..._openOffers.value}..remove(id);
        PushService.instance.clearOffer(id);
        _snack(_offerGoneText(cancelled: reason == 'cancelled'));
        _loadJobs();
        return;
      }
      if (accepted) {
        // Reading may have taken a while: the distance check needs a recent position
        if (DateTime.now().difference(sentAt) > const Duration(seconds: 60)) {
          sent = await CourierTelemetryService().sendNow(post: _postPosition);
          if (!mounted) return;
        }
        res = await _api.patch('/orders/$id/assign-courier');
        if (!mounted) return;
      }
    }
    _closedWhileAccepting.remove(id);
    setState(() => _acceptingId = null);
    if (!res.ok) {
      if (res.status == 409 && _rawError(res).contains('no longer available')) {
        // Someone else was faster (or the order was cancelled): drop it and refresh the list
        PushService.instance.clearOffer(id);
        setState(() {
          _jobs = _jobs.where((j) => asInt(j['id']) != id).toList();
          if (_newOfferId == id) _newOfferId = null;
        });
        _snack(_offerGoneText());
        _loadJobs();
        return;
      }
      var message = _serverMessage(res, res.error!);
      if (res.status == 409 && (!sent || _locationWords.hasMatch(_rawError(res)))) {
        message = '$message ${tr(context, 'Stay online with location on, so Malvoya can see you are near the shop, and try again.', 'Pysy linjoilla sijainti päällä, jotta Malvoya näkee sinun olevan lähellä kauppaa, ja yritä uudelleen.')}';
      }
      _snack(message);
      _loadJobs();
      return;
    }
    PushService.instance.clearOffer(id);
    _newOfferId = null;
    _resetChat();
    await _loadMine();
    _loadJobs();
    _tabs.animateTo(1);
  }

  // ── Delivery steps ──────────────────────────────────────────────────────

  /// Number of pieces in an order (quantities added up), or null if the items are not known.
  int? _pieceCount(Map<String, dynamic> o) {
    final items = (o['items'] as List?)?.whereType<Map>().toList();
    if (items == null || items.isEmpty) return null;
    return items.fold<int>(0, (n, i) => n + (asInt(i['quantity']) ?? 1));
  }

  String _piecesText(int n) => n == 1 ? tr(context, '1 item', '1 tuote') : tr(context, '$n items', '$n tuotetta');

  /// "I have the order": the courier first checks they were handed the right order.
  /// [swiped]: confirmed with the swipe bar, whose label names the order and the pieces, so no
  /// second question is asked.
  Future<void> _pickedUp(Map<String, dynamic> o, {bool swiped = false}) async {
    if (_pickingUp) return;
    HapticFeedback.mediumImpact();
    final id = o['id'];
    final n = _pieceCount(o);
    final items = ((o['items'] as List?) ?? []).whereType<Map>().toList();
    final ok = swiped || await _confirm(
      title: n == null
          ? tr(context, 'Did the shop hand you order #$id?', 'Antoiko kauppa sinulle tilauksen #$id?')
          : tr(context, 'Did the shop hand you order #$id — ${_piecesText(n)}?', 'Antoiko kauppa sinulle tilauksen #$id — ${_piecesText(n)}?'),
      body: tr(context, 'Check the order number with the shop and that nothing is missing. The customer is then told the order is on its way.',
          'Tarkista tilausnumero kaupan kanssa ja ettei mitään puutu. Asiakkaalle kerrotaan sen jälkeen, että tilaus on matkalla.'),
      yes: tr(context, 'Yes, I have it', 'Kyllä, se on mukanani'),
      no: tr(context, 'Not yet', 'Ei vielä'),
      extra: items.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final i in items)
                Text('${i['quantity']}× ${i['product']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
            ]),
    );
    if (!ok || !mounted) return;
    setState(() => _pickingUp = true);
    final res = await _api.patch('/orders/${o['id']}/status', {'status': 'SHIPPED'});
    if (!mounted) return;
    setState(() => _pickingUp = false);
    if (!res.ok) {
      Haptics.warning();
      _snack(res.error!);
    }
    await _loadMine();
  }

  /// Records that the courier is at the shop. The server checks the courier is really there,
  /// so a fresh position is sent first.
  Future<void> _arrivedAtStore(Map<String, dynamic> o) async {
    if (_arriving) return;
    HapticFeedback.mediumImpact();
    setState(() => _arriving = true);
    await CourierTelemetryService().sendNow(post: _postPosition);
    if (!mounted) return;
    final res = await _api.post('/orders/${o['id']}/arrived-at-store');
    if (!mounted) return;
    setState(() => _arriving = false);
    if (!res.ok) {
      return _snack(res.status == 409
          ? _serverMessage(res, tr(context, 'Get a bit closer to the shop and try again.', 'Mene vähän lähemmäs kauppaa ja yritä uudelleen.'))
          : res.error!);
    }
    await _loadMine();
  }

  // ── Courier pay ─────────────────────────────────────────────────────────
  // The server sends `courierPay` with each job and delivery. Older servers only send
  // courierFeeCents (tip included), so everything below falls back to that.

  Map<String, dynamic>? _payOf(Map o) {
    final p = o['courierPay'];
    if (p is Map) return Map<String, dynamic>.from(p);
    final id = asInt(o['id'] ?? o['orderId']);
    return id == null ? null : _offerPay[id];
  }

  int? _payTotal(Map o) => asInt(_payOf(o)?['totalCents']) ?? asInt(o['courierFeeCents']);

  String _payText(Map o) {
    final t = _payTotal(o);
    return t == null ? '–' : euro(context, t);
  }

  /// The server's text in the app language ({en, fi} or a plain string).
  String? _localized(dynamic e) {
    String? text;
    if (e is Map) {
      text = '${(isFinnish(context) ? e['fi'] : e['en']) ?? e['en'] ?? e['fi'] ?? ''}';
    } else if (e is String) {
      text = e;
    }
    text = text?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Free waiting minutes at the shop, if the server states them.
  int? _freeWaitMinutes(Map<String, dynamic>? pay) {
    final direct = asInt(pay?['freeWaitMinutes']);
    if (direct != null) return direct;
    for (final source in [pay?['waitPolicy'], pay?['explanation']]) {
      final en = source is Map ? '${source['en'] ?? ''}' : '${source ?? ''}';
      final m = RegExp(r'first (\d+) min|(\d+)\s*(?:free\s+)?min', caseSensitive: false).firstMatch(en);
      if (m != null) return int.tryParse(m.group(1) ?? m.group(2)!);
    }
    return null;
  }

  /// False when the server says waiting is not paid separately.
  bool _waitingPaid(Map<String, dynamic>? pay) {
    final policy = pay?['waitPolicy'];
    final en = policy is Map ? '${policy['en'] ?? ''}' : '${policy ?? ''}';
    return !en.toLowerCase().contains('not paid');
  }

  String _km(num km) {
    final s = km.toStringAsFixed(1);
    return isFinnish(context) ? s.replaceAll('.', ',') : s;
  }

  /// Line-by-line pay: base, distance, minimum top-up, ride to the shop, waiting, tip and total,
  /// then the server's explanation.
  Widget _payBreakdown(Map o, Map<String, dynamic> pay, {required bool showWaiting}) {
    final base = asInt(pay['baseCents']) ?? 0;
    num? number(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    final km = number(pay['distanceKm']);
    final dist = asInt(pay['distanceCents']) ?? 0;
    final topUp = asInt(pay['topUpCents']) ?? 0;
    final approachKm = number(pay['approachKm']);
    final approach = asInt(pay['approachCents']) ?? 0;
    final wait = asInt(pay['waitCents']) ?? 0;
    final waitMin = asInt(pay['waitMinutes']) ?? 0;
    final tip = asInt(pay['tipCents']) ?? asInt(o['tipCents']) ?? 0;
    final total = asInt(pay['totalCents']) ?? asInt(o['courierFeeCents']) ?? 0;
    final other = total - base - dist - topUp - approach - wait - tip;

    String distLabel = tr(context, 'Distance', 'Matka');
    if (km != null && km > 0) {
      final rate = (dist / km).round();
      final exactRate = rate > 0 && (rate * km).round() == dist;
      distLabel = exactRate ? '$distLabel ${_km(km)} km × ${euro(context, rate)}/km' : '$distLabel ${_km(km)} km';
    }

    Widget line(String label, int cents, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? AppTheme.textPrimary : AppTheme.textSecondary))),
            Text(euro(context, cents), style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    final explanation = _localized(pay['explanation']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(tr(context, 'Base (pickup + drop-off)', 'Perusmaksu (nouto + luovutus)'), base),
        if (dist != 0 || (km != null && km > 0)) line(distLabel, dist),
        if (topUp > 0) line(tr(context, 'Top-up to the minimum pay', 'Korotus vähimmäispalkkioon'), topUp),
        if (approach > 0)
          line(approachKm != null ? '${tr(context, 'Ride to the shop', 'Ajo kauppaan')} ${_km(approachKm)} km' : tr(context, 'Ride to the shop', 'Ajo kauppaan'), approach),
        if (showWaiting && wait > 0)
          line(waitMin > 0 ? '${tr(context, 'Waiting at the shop', 'Odotus kaupassa')} ($waitMin min)' : tr(context, 'Waiting at the shop', 'Odotus kaupassa'), wait),
        if (tip > 0) line(tr(context, 'Tip (all of it is yours)', 'Tippi (koko summa sinulle)'), tip),
        if (other != 0) line(tr(context, 'Other adjustment', 'Muu tasaus'), other),
        const Divider(height: 14),
        line(tr(context, 'Total', 'Yhteensä'), total, bold: true),
        if (explanation != null) ...[
          const SizedBox(height: 6),
          Text(explanation, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
        ],
      ]),
    );
  }

  /// A "How is this calculated?" toggle with the breakdown underneath. Nothing if the server sent no breakdown.
  Widget _payToggle(String key, Map o, {required bool showWaiting}) {
    final pay = _payOf(o);
    if (pay == null) return const SizedBox.shrink();
    final open = _openPay.contains(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => open ? _openPay.remove(key) : _openPay.add(key));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(open ? tr(context, 'Hide pay breakdown', 'Piilota palkkion erittely') : tr(context, 'How is this pay calculated?', 'Miten palkkio lasketaan?'),
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: AppTheme.primary),
          ]),
        ),
      ),
      if (open) _payBreakdown(o, pay, showWaiting: showWaiting),
    ]);
  }

  Future<Position?> _here() async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return CourierTelemetryService().lastPosition;
    }
  }

  // ── Handover ────────────────────────────────────────────────────────────

  Future<bool> _confirm({required String title, required String body, required String yes, String? no, Widget? extra}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (extra != null) ...[extra, const SizedBox(height: 12)],
            Text(body, style: const TextStyle(height: 1.4)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no ?? tr(context, 'Cancel', 'Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return ok == true;
  }

  /// [swiped]: the courier slid "Delivered", so an in-person handover needs no second question
  /// (a photo handover still shows the photo to check before it is sent).
  Future<void> _complete(Map<String, dynamic> o, {bool swiped = false}) async {
    if (_completing) return;
    HapticFeedback.mediumImpact();
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(tr(context, 'How did you hand it over?', 'Miten luovutit tilauksen?'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ),
          ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.handshake_outlined),
            title: Text(tr(context, 'To the customer in person', 'Asiakkaalle henkilökohtaisesti'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, 'IN_PERSON'),
          ),
          ListTile(
            minVerticalPadding: 16,
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr(context, 'Left at the door — take a photo', 'Jätetty ovelle — ota kuva'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr(context, 'Photograph only the parcel at the door — no people, faces or house numbers. Only the customer sees it; it is deleted after 30 days.',
                'Kuvaa vain paketti ovella — ei ihmisiä, kasvoja tai ovinumeroita. Vain asiakas näkee kuvan; se poistetaan 30 päivän kuluttua.')),
            onTap: () => Navigator.pop(ctx, 'PHOTO'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (method == null || !mounted) return;
    final orderId = asInt(o['id'])!;
    XFile? shot;
    if (method == 'PHOTO') {
      shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      if (shot == null || !mounted) return;
    }
    // Delivered cannot be undone: one last check before telling the customer
    final confirmed = (swiped && method == 'IN_PERSON') || await _confirm(
      title: tr(context, 'Mark order #$orderId as delivered?', 'Merkitäänkö tilaus #$orderId toimitetuksi?'),
      body: method == 'PHOTO'
          ? tr(context, 'The customer is told the order was left at the door and sees this photo. This cannot be undone.',
              'Asiakkaalle kerrotaan, että tilaus jätettiin ovelle, ja hän näkee tämän kuvan. Tätä ei voi perua.')
          : tr(context, 'Confirm only when the customer has the order in their hands. This cannot be undone.',
              'Vahvista vasta, kun tilaus on asiakkaan käsissä. Tätä ei voi perua.'),
      yes: tr(context, 'Delivered', 'Toimitettu'),
      extra: shot == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(shot.path), height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _completing = true);
    Map<String, dynamic>? proof;
    if (shot != null) {
      _snack(tr(context, 'Uploading photo…', 'Ladataan kuvaa…'));
      try {
        proof = (await MediaUpload.upload(api: _api, kind: 'delivery_proof', file: File(shot.path), orderId: orderId)).toProof();
      } catch (e) {
        if (mounted) {
          setState(() => _completing = false);
          _snack('$e');
        }
        return;
      }
    }
    final pos = await _here();
    final res = await _api.post('/orders/$orderId/deliver', {
      'method': method,
      if (proof != null) 'upload': proof,
      if (pos != null) 'latitude': pos.latitude,
      if (pos != null) 'longitude': pos.longitude,
    });
    if (!mounted) return;
    setState(() => _completing = false);
    if (!res.ok) return _snack(res.error!);
    HapticFeedback.heavyImpact();
    _resetChat();
    await Future.wait([_loadMine(), _loadEarnings(), _loadJobs()]);
    if (!mounted) return;
    final done = _mine.firstWhere((m) => asInt(m['id']) == orderId, orElse: () => o);
    await _showCompleted(done);
    if (mounted) _tabs.animateTo(0);
  }

  /// After the handover: the job's final pay, waiting included, then back to Jobs.
  Future<void> _showCompleted(Map<String, dynamic> o) {
    final pay = _payOf(o);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Color(0xFFE6F3EC), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'Delivered — nice work!', 'Toimitettu — hyvää työtä!'), style: AppTheme.display(size: 22)),
                  Text('${tr(context, 'Order', 'Tilaus')} #${o['id']}${o['store']?['name'] != null ? ' · ${o['store']['name']}' : ''}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Text(tr(context, 'Your pay for this job', 'Palkkiosi tästä keikasta'), style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            Text(_payText(o), style: AppTheme.display(size: 36)),
            if (pay != null) _payBreakdown(o, pay, showWaiting: true),
            const SizedBox(height: 10),
            Text(tr(context, 'You can find it under Earnings, with when it is paid out.', 'Löydät sen Ansiot-välilehdeltä, jossa näkyy myös maksuaika.'),
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.work_outline_rounded),
                label: Text(tr(context, 'Back to jobs', 'Takaisin keikkoihin')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Opens the phone's maps app with directions (Apple Maps on iPhone, Google Maps on Android,
  /// any maps app as a last resort).
  /// Turn-by-turn directions in the courier's navigation app (Google Maps, Waze or the phone's
  /// maps app, asked once and remembered). [ask] picks the app again (long-press on Navigate).
  Future<void> _navigate(double? lat, double? lng, String? address, {bool ask = false}) async {
    final hasPoint = lat != null && lng != null;
    if (!hasPoint && (address ?? '').trim().isEmpty) {
      return _snack(tr(context, 'There is no address to navigate to.', 'Navigoitavaa osoitetta ei ole.'));
    }
    final ok = await NavApps.navigate(context, lat: lat, lng: lng, address: address, ask: ask);
    if (!ok && mounted) _snack(tr(context, 'Could not open a maps app.', 'Karttasovellusta ei voitu avata.'));
  }

  /// "Navigate" button: tap opens the remembered app, long-press asks again.
  Widget _navButton(double? lat, double? lng, String? address) => _bigButton(
        outlined: true,
        onPressed: () => _navigate(lat, lng, address),
        onLongPress: () => _navigate(lat, lng, address, ask: true),
        icon: const Icon(Icons.navigation_outlined),
        label: Text(tr(context, 'Navigate', 'Navigoi')),
      );

  Future<void> _call(String phone) async {
    HapticFeedback.selectionClick();
    try {
      if (await launchUrl(Uri.parse('tel:$phone'))) return;
    } catch (_) {}
    if (mounted) _snack(tr(context, 'Could not start a call.', 'Puhelua ei voitu aloittaa.'));
  }

  /// Chat with the customer, at any step of the delivery. New messages appear while it is open.
  Future<void> _openChat(Map<String, dynamic> o) async {
    HapticFeedback.selectionClick();
    final orderId = asInt(o['id'])!;
    final myName = (_auth.currentUser?.name ?? 'Courier').split(' ').first;
    final pickedUp = _stage(o) >= 3;
    final problem = _problemAt(o) != null;
    final quick = problem
        ? [
            tr(context, "I'm at your door, please answer", 'Olen ovellasi, vastaathan'),
            tr(context, "I can't find the address", 'En löydä osoitetta'),
            tr(context, 'Where should I leave the order?', 'Mihin jätän tilauksen?'),
            tr(context, "I'm waiting outside", 'Odotan ulkona'),
          ]
        : pickedUp
        ? [
            tr(context, "I'm on my way", 'Olen matkalla'),
            tr(context, "I'm at the door", 'Olen ovella'),
            tr(context, "I'm outside", 'Olen ulkona'),
            tr(context, 'Running 5 min late', 'Myöhästyn 5 min'),
          ]
        : [
            tr(context, 'On my way to the shop', 'Olen matkalla kauppaan'),
            tr(context, 'At the shop, waiting for your order', 'Olen kaupalla, odotan tilaustasi'),
            tr(context, 'Running 5 min late', 'Myöhästyn 5 min'),
          ];
    setState(() {
      _chatOpen = true;
      _chatUnread = false;
    });
    _chatOrderId ??= orderId;
    // Anything sent while this phone was offline or the app was closed
    _loadChatHistory(orderId, force: true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ChatSheet(
        messages: _chat,
        stored: _chatStored,
        quickReplies: quick,
        isMine: _isMine,
        onSend: (text) => _sendChat(orderId, text, myName),
      ),
    );
    if (mounted) setState(() => _chatOpen = false);
  }

  /// Chat button with a dot while there are unread messages.
  Widget _chatButton(Map<String, dynamic> o, {bool prominent = false}) => _bigButton(
        outlined: !prominent,
        onPressed: () => _openChat(o),
        icon: Badge(
          isLabelVisible: _chatUnread,
          smallSize: 10,
          backgroundColor: prominent ? AppTheme.sunshine : AppTheme.primary,
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        label: Text(_chatUnread
            ? tr(context, 'New message', 'Uusi viesti')
            : (prominent ? tr(context, 'Chat with the customer', 'Chattaa asiakkaan kanssa') : tr(context, 'Chat', 'Chat'))),
      );

  void _howJobsWork() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'How jobs are offered', 'Miten keikat tarjotaan'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            tr(context,
                'When a store accepts an order, it is offered to online couriers within 7.5 km of the store, nearest first. If nobody is that close, every online courier sees it. Distance to the store is the only factor: ratings, acceptance rates and declines are not used. You choose which jobs to take — declining or ignoring a job never affects you.\n\nEach offer shows your pay before you accept, with a breakdown. If the shop is not ready when you arrive, waiting beyond the free minutes is paid and added when you pick up. Tips go to you in full.\n\nMalvoya is just starting, so there may be few jobs or none at first. No number of jobs or level of earnings is promised. You deliver as an independent entrepreneur and may also work for other platforms.\n\nNo automated system rates or deactivates you; account decisions are made by a person and explained to you.',
                'Kun kauppa hyväksyy tilauksen, se tarjotaan linjoilla oleville läheteille 7,5 km:n säteellä kaupasta, lähin ensin. Jos kukaan ei ole niin lähellä, kaikki linjoilla olevat näkevät sen. Ainoa peruste on etäisyys kauppaan: arvioita, hyväksymisprosenttia tai hylkäyksiä ei käytetä. Valitset itse keikkasi — kieltäytyminen tai ohittaminen ei vaikuta sinuun.\n\nJokainen tarjous näyttää palkkiosi erittelyineen ennen kuin hyväksyt. Jos tilaus ei ole valmis, kun saavut kauppaan, odotus ilmaisten minuuttien jälkeen maksetaan ja lisätään noudon yhteydessä. Tipit saat kokonaan.\n\nMalvoya on vasta aloittamassa, joten keikkoja voi aluksi olla vähän tai ei lainkaan. Keikkojen määrää tai ansioita ei luvata. Toimitat itsenäisenä yrittäjänä ja voit tehdä keikkoja myös muille alustoille.\n\nMikään automaatti ei arvioi tai sulje tiliäsi; päätökset tekee ihminen ja perustelee ne sinulle.'),
            style: const TextStyle(height: 1.45, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => openLegal('couriers'),
            icon: const Icon(Icons.gavel_rounded),
            label: Text(tr(context, 'Read the courier agreement', 'Lue lähettisopimus')),
          ),
          TextButton.icon(
            onPressed: () => showLicensePage(context: context, applicationName: 'Malvoya Courier', applicationLegalese: '© Malvoya'),
            icon: const Icon(Icons.code_rounded),
            label: Text(tr(context, 'Open-source licences', 'Avoimen lähdekoodin lisenssit')),
          ),
        ]),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final name = (_auth.currentUser?.name ?? '').split(' ').first;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        centerTitle: false,
        title: Text(name.isEmpty ? 'Malvoya Courier' : '${tr(context, 'Hi', 'Hei')} $name', style: AppTheme.display(size: 22)),
        actions: [
          IconButton(tooltip: tr(context, 'How jobs are offered', 'Miten keikat tarjotaan'), icon: const Icon(Icons.info_outline_rounded), onPressed: _howJobsWork),
          IconButton(
            tooltip: tr(context, 'Help and contact', 'Apua ja yhteydenotto'),
            icon: const Icon(Icons.support_agent_rounded),
            onPressed: () => _openHelp(orderId: asInt(active?['id'])),
          ),
          IconButton(
            tooltip: tr(context, 'Account', 'Tili'),
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: _openAccount,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppTheme.primary, width: 3),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          tabs: [
            Tab(text: '${tr(context, 'Jobs', 'Keikat')}${_online && _jobs.isNotEmpty && active == null ? ' (${_jobs.length})' : ''}'),
            Tab(text: tr(context, 'Delivery', 'Toimitus')),
            Tab(text: tr(context, 'Earnings', 'Ansiot')),
          ],
        ),
      ),
      body: Column(children: [
        _onlineBar(active),
        // Steps still open (vehicle, payouts, agreement, ...), hidden during a delivery and once all are done
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: SingleChildScrollView(
            child: OnboardingChecklist(
              key: _checklistKey,
              compact: true,
              suppressed: active != null,
              onLoaded: (data) {
                final vehicle = data?['courier'] is Map ? (data!['courier'] as Map)['vehicleType'] : null;
                if (vehicle is String && vehicle != _vehicleType && mounted) setState(() => _vehicleType = vehicle);
              },
            ),
          ),
        ),
        AgreementUpdateBanner(key: _agreementBannerKey, suppressed: active != null),
        if (active == null && _returningOrder() != null) _returnStrip(_returningOrder()!),
        Expanded(child: TabBarView(controller: _tabs, children: [_jobsTab(active), _deliveryTab(active), _earningsTab()])),
      ]),
    );
  }

  Widget _onlineBar(Map<String, dynamic>? active) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(
          color: _online ? AppTheme.successDark : AppTheme.textPrimary,
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(_online ? vehicleIcon(_vehicleType) : Icons.power_settings_new_rounded,
                size: 22, color: _online ? AppTheme.successDark : AppTheme.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(
                _online
                    ? (active != null ? '${tr(context, 'Online · delivering', 'Linjoilla · toimitus')} #${active['id']}' : tr(context, 'Online', 'Linjoilla'))
                    : tr(context, 'Offline · no job offers', 'Poissa · ei keikkatarjouksia'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
              ),
              // Same promise as the courier agreement (section 6)
              Text(
                _online
                    ? tr(context, 'Location is shared only while you are online; a notification shows while it is shared.',
                        'Sijaintisi jaetaan vain, kun olet linjoilla; ilmoitus näkyy jakamisen ajan.')
                    : tr(context, 'Your location is not shared while you are offline.', 'Sijaintiasi ei jaeta, kun olet poissa linjoilta.'),
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.25),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          _switching
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Semantics(
                  label: tr(context, 'Online', 'Linjoilla'),
                  child: Switch(value: _online, onChanged: (_) => _onSwitch(), activeColor: Colors.white, activeTrackColor: Colors.white38),
                ),
        ]),
      );

  /// Error state for a tab whose first load failed.
  Widget _loadError(String title, String? message, VoidCallback retry) => StateMessage(
        error: true,
        icon: Icons.cloud_off_rounded,
        title: title,
        text: message ?? tr(context, 'Something went wrong. Please try again.', 'Jotain meni vikaan. Yritä uudelleen.'),
        onRetry: () {
          HapticFeedback.selectionClick();
          retry();
        },
      );

  Widget _bigButton({required VoidCallback? onPressed, required Widget label, Widget? icon, bool busy = false, bool outlined = false, VoidCallback? onLongPress}) {
    final shownIcon = busy
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: outlined ? AppTheme.primary : Colors.white))
        : icon;
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(64, 56)));
    final tap = busy ? null : onPressed;
    final hold = busy ? null : onLongPress;
    final button = outlined
        ? (shownIcon == null
            ? OutlinedButton(style: style, onPressed: tap, onLongPress: hold, child: label)
            : OutlinedButton.icon(style: style, onPressed: tap, onLongPress: hold, icon: shownIcon, label: label))
        : (shownIcon == null
            ? FilledButton(style: style, onPressed: tap, onLongPress: hold, child: label)
            : FilledButton.icon(style: style, onPressed: tap, onLongPress: hold, icon: shownIcon, label: label));
    // Grows with large text instead of clipping the label
    return ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 56), child: button);
  }

  Widget _jobsTab(Map<String, dynamic>? active) {
    if (active != null) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: StateMessage(
          icon: Icons.pedal_bike_rounded,
          text: tr(context, 'Finish your current delivery to take the next job.', 'Tee nykyinen toimitus loppuun ottaaksesi seuraavan keikan.'),
          action: OutlinedButton.icon(
            onPressed: () => _tabs.animateTo(1),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(tr(context, 'Open the delivery', 'Avaa toimitus')),
          ),
        ),
      );
    }
    if (!_online) return RefreshIndicator(onRefresh: _refreshAll, child: _goOnlinePrompt());
    if (_jobsLoad == _Load.loading) return const JobsSkeleton();
    if (_jobsLoad == _Load.error) {
      return RefreshIndicator(
        onRefresh: () => _loadJobs(manual: true),
        child: _loadError(tr(context, 'Could not load jobs', 'Keikkoja ei voitu ladata'), _jobsError, () {
          setState(() => _jobsLoad = _Load.loading);
          _loadJobs();
        }),
      );
    }
    if (_jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadJobs(manual: true),
        child: StateMessage(
          icon: Icons.hourglass_empty_rounded,
          text: tr(context, 'No jobs right now. Malvoya is just starting, so jobs may be rare at first. While you are online, you get a notification when one comes in.',
              'Ei keikkoja juuri nyt. Malvoya on vasta aloittamassa, joten keikkoja voi aluksi olla harvoin. Kun olet linjoilla, saat ilmoituksen uudesta keikasta.'),
        ),
      );
    }
    // The newest live offer first
    final jobs = [..._jobs]..sort((a, b) => (asInt(a['id']) == _newOfferId ? 0 : 1) - (asInt(b['id']) == _newOfferId ? 0 : 1));
    return RefreshIndicator(
      onRefresh: () => _loadJobs(manual: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [for (final j in jobs) _jobCard(j)],
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final here = CourierTelemetryService().lastPosition;
    final s = (j['store'] as Map?) ?? {};
    final id = asInt(j['id']);
    final isNew = id != null && id == _newOfferId;
    double? d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final sLat = d(s['latitude']), sLng = d(s['longitude']);
    final aLat = d(j['deliveryAreaLat']), aLng = d(j['deliveryAreaLng']);
    String? toStore;
    String? drop;
    if (here != null && sLat != null && sLng != null) {
      toStore = '${_km(Geolocator.distanceBetween(here.latitude, here.longitude, sLat, sLng) / 1000)} km';
    }
    if (sLat != null && sLng != null && aLat != null && aLng != null) {
      drop = '${_km(Geolocator.distanceBetween(sLat, sLng, aLat, aLng) / 1000)} km';
    }
    final tip = asInt(_payOf(j)?['tipCents']) ?? asInt(j['tipCents']) ?? 0;
    final items = asInt(j['itemCount']);
    final age = _offerAge(j);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: isNew ? AppTheme.primary : AppTheme.divider, width: isNew ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isNew || age != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              if (isNew)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
                  child: Text(tr(context, 'New offer', 'Uusi tarjous'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              if (age != null)
                Expanded(child: Text(age, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
            ]),
          ),
        Row(children: [
          Text(_payText(j), style: AppTheme.display(size: 32)),
          if (tip > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(12)),
              child: Text('${tr(context, 'incl. tip', 'sis. tipin')} ${euro(context, tip)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
          const Spacer(),
          if (items != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(12)),
              child: Text('$items ${tr(context, 'item(s)', 'tuote(tta)')}', style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ]),
        Text(tr(context, 'Your pay for this job', 'Palkkiosi tästä keikasta'), style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        _windowBadge(j),
        _payToggle('job-$id', j, showWaiting: false),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr(context, 'Pick up', 'Nouto')}: ${s['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (s['address'] != null) Text('${s['address']}', style: const TextStyle(color: AppTheme.textSecondary)),
            ]),
          ),
        ]),
        if (sLat != null && sLng != null) ...[
          const SizedBox(height: 12),
          MiniRoute(
            me: here == null ? null : (lat: here.latitude, lng: here.longitude),
            store: (lat: sLat, lng: sLng),
            dropOff: aLat != null && aLng != null ? (lat: aLat, lng: aLng) : null,
            toStoreText: toStore,
            dropText: drop,
            height: 96,
          ),
          MiniRouteLegend(showMe: here != null),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _distanceTile(Icons.storefront_outlined, tr(context, 'You → store', 'Sinä → kauppa'), toStore ?? '–'),
          const SizedBox(width: 8),
          _distanceTile(Icons.location_on_outlined, tr(context, 'Store → drop-off area', 'Kauppa → toimitusalue'), drop == null ? '–' : '~$drop'),
        ]),
        const SizedBox(height: 8),
        Text(
          toStore == null
              ? tr(context, 'Distance to the store appears once your location is found. The exact address is shown after you accept.',
                  'Etäisyys kauppaan näkyy, kun sijaintisi löytyy. Tarkka osoite näytetään hyväksynnän jälkeen.')
              : tr(context, 'Straight-line distances. The exact address is shown after you accept.', 'Linnuntie-etäisyydet. Tarkka osoite näytetään hyväksynnän jälkeen.'),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        _bigButton(
          onPressed: _acceptingId == null ? () => _accept(j) : null,
          busy: _acceptingId == id,
          label: Text(tr(context, 'Accept job', 'Ota keikka'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _distanceTile(IconData icon, String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            Text(value, style: AppTheme.display(size: 20)),
          ]),
        ),
      );

  /// Offline couriers get no jobs: make going online the obvious next step.
  Widget _goOnlinePrompt() => StateMessage(
        icon: Icons.pedal_bike_rounded,
        title: tr(context, 'You are offline', 'Olet poissa linjoilta'),
        text: tr(context, 'Go online to get job offers near you. Your location is shared only while you are online.',
            'Mene linjoille saadaksesi keikkatarjouksia lähelläsi. Sijaintisi jaetaan vain, kun olet linjoilla.'),
        action: SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton.icon(
            onPressed: _switching ? null : _onSwitch,
            icon: _switching
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.power_settings_new_rounded),
            label: Text(tr(context, 'Go online', 'Mene linjoille'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      );

  // ── Delivery ────────────────────────────────────────────────────────────

  /// 0 go to shop · 1 at the shop · 2 picked up · 3 deliver · 4 done
  int _stage(Map<String, dynamic> o) {
    if (o['status'] == 'DELIVERED') return 4;
    if (o['status'] == 'SHIPPED') return 3;
    if (o['courierArrivedAt'] != null) return 1;
    return 0;
  }

  Widget _stepIndicator(int current) {
    final labels = [
      tr(context, 'Go to shop', 'Kauppaan'),
      tr(context, 'At the shop', 'Kaupalla'),
      tr(context, 'Picked up', 'Noudettu'),
      tr(context, 'Deliver', 'Toimita'),
      tr(context, 'Done', 'Valmis'),
    ];
    Widget bar(bool on, {bool hidden = false}) =>
        Expanded(child: Container(height: 3, color: hidden ? Colors.transparent : (on ? AppTheme.success : AppTheme.divider)));
    return Semantics(
      label: tr(context, 'Step ${current + 1} of 5: ${labels[current]}', 'Vaihe ${current + 1}/5: ${labels[current]}'),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Column(children: [
                  Row(children: [
                    bar(i <= current, hidden: i == 0),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < current ? AppTheme.success : (i == current ? AppTheme.primary : AppTheme.divider),
                      ),
                      child: Center(
                        child: i < current
                            ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
                            : Text('${i + 1}', style: TextStyle(color: i == current ? Colors.white : AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    bar(i < current, hidden: i == labels.length - 1),
                  ]),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                          color: i == current ? AppTheme.textPrimary : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
          border: Border.all(color: AppTheme.primary, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _deliveryTab(Map<String, dynamic>? o) {
    if (_mineLoad == _Load.loading) return const DeliverySkeleton();
    if (_mineLoad == _Load.error) {
      return RefreshIndicator(
        onRefresh: () => _loadMine(manual: true),
        child: _loadError(tr(context, 'Could not load your delivery', 'Toimitusta ei voitu ladata'), _mineError, () {
          setState(() => _mineLoad = _Load.loading);
          _loadMine();
        }),
      );
    }
    final returning = o == null ? _returningOrder() : null;
    if (returning != null) {
      return RefreshIndicator(
        onRefresh: () => _loadMine(manual: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [_returnCard(returning)],
        ),
      );
    }
    if (o == null) {
      return RefreshIndicator(
        onRefresh: () => _loadMine(manual: true),
        child: StateMessage(
          icon: Icons.inventory_2_outlined,
          text: tr(context, 'No delivery in progress. Jobs you accept appear here, step by step.', 'Ei toimitusta käynnissä. Hyväksymäsi keikat näkyvät täällä vaihe vaiheelta.'),
          action: _online
              ? OutlinedButton.icon(
                  onPressed: () => _tabs.animateTo(0),
                  icon: const Icon(Icons.work_outline_rounded),
                  label: Text(tr(context, 'See jobs', 'Katso keikat')),
                )
              : null,
        ),
      );
    }
    final stage = _stage(o);
    final s = (o['store'] as Map?) ?? {};
    final storePt = _pt(s['latitude'], s['longitude']);
    final dropPt = _pt(o['deliveryLat'], o['deliveryLng']);
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _loadMine(manual: true),
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
            Text('${tr(context, 'Order', 'Tilaus')} #${o['id']} · ${tr(context, 'your pay', 'palkkiosi')} ${_payText(o)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            _payToggle('active-${o['id']}', o, showWaiting: true),
            const SizedBox(height: 4),
            _stepIndicator(stage),
            if (storePt != null) ...[
              const SizedBox(height: 12),
              JobMap(
                store: LatLng(storePt.lat, storePt.lng),
                dropOff: dropPt == null ? null : LatLng(dropPt.lat, dropPt.lng),
                towardsDropOff: stage >= 3,
              ),
            ],
            if (stage < 3) _pickupCard(o, stage) else _dropOffCard(o),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: ScreenAwake.instance,
              builder: (context, _) => Text(
                ScreenAwake.instance.pausedForBattery
                    ? tr(context, 'Battery low: the screen may switch off to save power. Your location is still shared.',
                        'Akku vähissä: näyttö voi sammua virran säästämiseksi. Sijaintisi jaetaan edelleen.')
                    : tr(context, 'The screen stays on during the delivery. Keep the app open or in the background so the customer can follow you.',
                        'Näyttö pysyy päällä toimituksen ajan. Pidä sovellus auki tai taustalla, jotta asiakas voi seurata sinua.'),
                style: TextStyle(fontSize: 12, color: ScreenAwake.instance.pausedForBattery ? AppTheme.danger : AppTheme.textSecondary),
              ),
            ),
          ]),
        ),
      ),
      _actionBar(o, stage),
    ]);
  }

  /// The main action of the current step, full width at the bottom within thumb reach. Steps that
  /// cannot be undone (picked up, delivered) are a swipe, so a pocket or a glove cannot trigger them.
  Widget _actionBar(Map<String, dynamic> o, int stage) {
    final arrivalSupported = o.containsKey('courierArrivedAt');
    final Widget action;
    if (stage == 0 && arrivalSupported) {
      action = _bigButton(
        onPressed: () => _arrivedAtStore(o),
        busy: _arriving,
        icon: const Icon(Icons.storefront_rounded),
        label: Text(tr(context, "I'm at the shop", 'Olen kaupalla'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
    } else if (stage < 3) {
      final n = _pieceCount(o);
      action = SwipeToConfirm(
        busy: _pickingUp,
        icon: Icons.shopping_bag_rounded,
        label: n == null
            ? tr(context, 'Slide: I have order #${o['id']}', 'Liu\'uta: tilaus #${o['id']} mukana')
            : tr(context, 'Slide: I have all ${_piecesText(n)}', 'Liu\'uta: kaikki ${_piecesText(n)} mukana'),
        onConfirmed: () => _pickedUp(o, swiped: true),
      );
    } else {
      action = SwipeToConfirm(
        busy: _completing,
        color: AppTheme.successDark,
        icon: Icons.task_alt_rounded,
        label: tr(context, 'Slide to hand over', 'Liu\'uta luovuttaaksesi'),
        onConfirmed: () => _complete(o, swiped: true),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(top: false, child: action),
    );
  }

  /// Go to the shop, check in, pick up.
  Widget _pickupCard(Map<String, dynamic> o, int stage) {
    final s = (o['store'] as Map?) ?? {};
    final storeReady = o['status'] == 'PROCESSING';
    final items = (o['items'] as List?) ?? [];
    final arrivalSupported = o.containsKey('courierArrivedAt');
    final arrived = stage == 1;
    final storeName = '${s['name'] ?? ''}';
    final pieces = _pieceCount(o);
    return _card([
      Text(arrived ? tr(context, 'At $storeName', 'Kaupalla: $storeName') : tr(context, 'Go to $storeName', 'Kauppaan: $storeName'), style: AppTheme.display(size: 22)),
      _windowBadge(o, detailed: true),
      // At the shop the courier shows this number so the shop hands over the right bag
      if (arrived || !arrivalSupported)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'Show the shop this order number', 'Näytä kaupalle tämä tilausnumero'),
                style: const TextStyle(color: Color(0xFF6A4500), fontWeight: FontWeight.w700, fontSize: 13)),
            Text('#${o['id']}', style: AppTheme.display(size: 44)),
            if (pieces != null) Text(_piecesText(pieces), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
      if (s['address'] != null) ...[
        const SizedBox(height: 4),
        Text('${s['address']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Icon(storeReady ? Icons.check_circle_rounded : Icons.hourglass_top_rounded, size: 18, color: storeReady ? AppTheme.success : AppTheme.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            storeReady ? tr(context, 'The store says the order is packed and ready.', 'Kauppa ilmoittaa tilauksen olevan valmis.') : tr(context, 'The store is still packing.', 'Kauppa pakkaa vielä.'),
            style: TextStyle(color: storeReady ? AppTheme.success : AppTheme.textSecondary, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final i in items.whereType<Map>()) Text('${i['quantity']}× ${i['product']?['name'] ?? ''}', style: const TextStyle(height: 1.4)),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _navButton((s['latitude'] as num?)?.toDouble(), (s['longitude'] as num?)?.toDouble(), s['address']?.toString())),
        if (s['phone'] != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _bigButton(
              outlined: true,
              onPressed: () => _call('${s['phone']}'),
              icon: const Icon(Icons.call_outlined),
              label: Text(tr(context, 'Call store', 'Soita kauppaan')),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      _chatButton(o),
      const SizedBox(height: 12),
      ..._arrivalSection(o),
      // Before checking in, the courier may still have the order handed over straight away
      if (arrivalSupported && !arrived)
        _bigButton(
          outlined: true,
          onPressed: () => _pickedUp(o),
          busy: _pickingUp,
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text(tr(context, 'I have the order', 'Tilaus on mukanani')),
        ),
    ]);
  }

  /// Ride to the customer and hand over.
  Widget _dropOffCard(Map<String, dynamic> o) {
    final customer = (o['user']?['name'] ?? '').toString().split(' ').first;
    final note = (o['notes'] ?? '').toString().trim();
    final address = o['deliveryAddress']?.toString();
    final problemAt = _problemAt(o);
    return _card([
      Text('${tr(context, 'Deliver to', 'Toimita:')} ${customer.isEmpty ? tr(context, 'the customer', 'asiakkaalle') : customer}', style: AppTheme.display(size: 22)),
      if (address != null) ...[
        const SizedBox(height: 6),
        Text(address, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
      ],
      _windowBadge(o, detailed: problemAt == null),
      if (note.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.sunshineLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.sunshine, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.sticky_note_2_outlined, size: 18, color: Color(0xFF6A4500)),
              const SizedBox(width: 6),
              Text(tr(context, 'Delivery note from the customer', 'Asiakkaan toimitusohje'),
                  style: const TextStyle(color: Color(0xFF6A4500), fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            Text(note, style: const TextStyle(color: Color(0xFF4A3000), fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
          ]),
        ),
      if (problemAt != null) _problemCard(o, problemAt),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _navButton((o['deliveryLat'] as num?)?.toDouble(), (o['deliveryLng'] as num?)?.toDouble(), address)),
        if (problemAt == null) ...[
          const SizedBox(width: 8),
          Expanded(child: _chatButton(o)),
        ],
      ]),
      const SizedBox(height: 12),
      if (problemAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(tr(context, 'The customer turned up? Hand the order over as usual.', 'Asiakas tuli paikalle? Luovuta tilaus tavalliseen tapaan.'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ),
      // "Delivered" is the swipe bar at the bottom of the screen
      if (problemAt != null) ...[
        _returnButton(o, problemAt),
      ] else if (_problemSupported(o)) ...[
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger, minimumSize: const Size(48, 48)),
            onPressed: _reportingProblem ? null : () => _reportProblem(o),
            icon: _reportingProblem
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger))
                : const Icon(Icons.report_problem_outlined, size: 20),
            label: Text(tr(context, "Can't deliver?", 'Etkö saa toimitettua?')),
          ),
        ),
      ],
    ]);
  }

  // ── Can't deliver (API 2.10) ────────────────────────────────────────────
  // The courier reports the problem (POST delivery-problem): the customer is asked to answer the
  // chat and the store is told. After 10 minutes the order can be taken back to the shop
  // (POST return-to-store): it is cancelled, the customer is refunded for the items and the
  // courier keeps the job pay and the tip. Everything is read again from the order after a restart.

  static const _returnWait = Duration(minutes: 10);

  /// The server knows this flow when its orders carry the deliveryProblemAt field.
  bool _problemSupported(Map o) => !_problemUnsupported && o.containsKey('deliveryProblemAt');

  DateTime? _problemAt(Map o) => DateTime.tryParse('${o['deliveryProblemAt'] ?? ''}')?.toLocal();

  DateTime _returnAllowedAt(Map o, DateTime problemAt) {
    final id = asInt(o['id']);
    final fromOrder = DateTime.tryParse('${o['canReturnAt'] ?? ''}')?.toLocal();
    return (id == null ? null : _canReturnAt[id]) ?? fromOrder ?? problemAt.add(_returnWait);
  }

  String _reasonText(String? reason) => switch (reason) {
        'CUSTOMER_UNAVAILABLE' => tr(context, 'The customer does not answer', 'Asiakas ei vastaa'),
        'WRONG_ADDRESS' => tr(context, 'The address is wrong or cannot be found', 'Osoite on väärä tai sitä ei löydy'),
        _ => tr(context, 'Something else', 'Jokin muu syy'),
      };

  /// "Can't deliver?": pick a reason, then the waiting time starts.
  Future<void> _reportProblem(Map<String, dynamic> o) async {
    HapticFeedback.mediumImpact();
    final note = TextEditingController();
    String reason = 'CUSTOMER_UNAVAILABLE';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, "Can't deliver?", 'Etkö saa toimitettua?'), style: AppTheme.display(size: 22)),
                const SizedBox(height: 6),
                Text(
                    tr(context,
                        'Tell Malvoya what is wrong. The customer gets a notification asking them to answer the chat, and the shop is told. Wait for the customer for 10 minutes; if you still cannot hand the order over, you can then take it back to the shop.',
                        'Kerro Malvoyalle, mikä on vialla. Asiakas saa ilmoituksen, jossa häntä pyydetään vastaamaan chattiin, ja kaupalle kerrotaan. Odota asiakasta 10 minuuttia; jos et vieläkään saa luovutettua tilausta, voit sitten viedä sen takaisin kauppaan.'),
                    style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
                const SizedBox(height: 10),
                for (final r in const ['CUSTOMER_UNAVAILABLE', 'WRONG_ADDRESS', 'OTHER'])
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: r,
                    groupValue: reason,
                    onChanged: (v) => setSheet(() => reason = v ?? reason),
                    title: Text(_reasonText(r), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 6),
                TextField(
                  controller: note,
                  maxLength: 200,
                  maxLines: 2,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: reason == 'OTHER'
                        ? tr(context, 'What happened?', 'Mitä tapahtui?')
                        : tr(context, 'Note for Malvoya (optional)', 'Lisätieto Malvoyalle (valinnainen)'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                    onPressed: () => Navigator.pop(ctx, reason),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: Text(tr(context, 'Report and start waiting', 'Ilmoita ja aloita odotus')),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(tr(context, 'Keep trying to deliver', 'Yritän vielä toimittaa')),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (picked == null || !mounted) return;
    final id = asInt(o['id']);
    if (id == null) return;
    setState(() => _reportingProblem = true);
    final res = await _api.post('/orders/$id/delivery-problem', {'reason': picked, if (text.isNotEmpty) 'note': text});
    if (!mounted) return;
    setState(() => _reportingProblem = false);
    if (res.status == 404 && !_rawError(res).toLowerCase().contains('order')) {
      setState(() => _problemUnsupported = true);
      _snack(tr(context, 'Reporting this in the app is not available yet. Chat with the customer, or contact Malvoya through Help.',
          'Ilmoittaminen sovelluksessa ei ole vielä käytössä. Chattaa asiakkaan kanssa tai ota yhteyttä Malvoyaan Apua-sivun kautta.'));
      return;
    }
    if (!res.ok) return _snack(res.error!);
    HapticFeedback.heavyImpact();
    final canReturn = DateTime.tryParse('${res.data['canReturnAt'] ?? ''}')?.toLocal();
    if (canReturn != null) _canReturnAt[id] = canReturn;
    await _loadMine();
  }

  /// Waiting for the customer: a live countdown to when the order can be taken back, the chat
  /// and what to try in the meantime.
  Widget _problemCard(Map<String, dynamic> o, DateTime problemAt) {
    final until = _returnAllowedAt(o, problemAt);
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppTheme.textPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w500))),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dangerLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.danger, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.report_problem_rounded, color: AppTheme.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(context, 'Waiting for the customer', 'Odotetaan asiakasta'), style: AppTheme.display(size: 19, color: AppTheme.danger))),
        ]),
        const SizedBox(height: 4),
        Text('${tr(context, 'Reported at', 'Ilmoitettu klo')} ${_clock(problemAt)} · ${_reasonText(o['deliveryProblemReason']?.toString())}',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _Countdown(
          until: until,
          builder: (context, left) {
            if (left == Duration.zero) {
              return Text(
                  tr(context, 'You have waited 10 minutes. If you still cannot hand it over, you can take the order back to the shop.',
                      'Olet odottanut 10 minuuttia. Jos et vieläkään saa luovutettua tilausta, voit viedä sen takaisin kauppaan.'),
                  style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35));
            }
            final mm = left.inMinutes;
            final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
            return Semantics(
              liveRegion: false,
              label: tr(context, '$mm minutes $ss seconds left', '$mm minuuttia $ss sekuntia jäljellä'),
              child: ExcludeSemantics(
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$mm:$ss', style: AppTheme.display(size: 40)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(tr(context, 'until you can take it back to the shop', 'kunnes voit viedä tilauksen takaisin kauppaan'),
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, height: 1.3)),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(tr(context, 'The customer was asked to answer the chat.', 'Asiakasta pyydettiin vastaamaan chattiin.'),
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        _chatButton(o, prominent: true),
        const SizedBox(height: 6),
        tip(Icons.doorbell_outlined, tr(context, 'Try the door phone or knock, then wait a moment.', 'Kokeile ovipuhelinta tai koputa, ja odota hetki.')),
        tip(Icons.place_outlined, tr(context, "Check the address and any note from the customer above.", 'Tarkista osoite ja asiakkaan mahdollinen ohje yllä.')),
        tip(Icons.chat_outlined, tr(context, 'Write in the chat where you are waiting.', 'Kirjoita chattiin, missä odotat.')),
      ]),
    );
  }

  /// "Return to shop": outlined red, usable once the waiting time is over.
  Widget _returnButton(Map<String, dynamic> o, DateTime problemAt) => _Countdown(
        until: _returnAllowedAt(o, problemAt),
        builder: (context, left) {
          final ready = left == Duration.zero;
          return SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: BorderSide(color: ready ? AppTheme.danger : AppTheme.divider, width: 1.5),
              ),
              onPressed: ready && !_returningToShop ? () => _returnToShop(o) : null,
              icon: _returningToShop
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.danger))
                  : const Icon(Icons.keyboard_return_rounded),
              label: Text(ready
                  ? tr(context, 'Return to shop', 'Palauta kauppaan')
                  : tr(context, 'Return to shop (in ${left.inMinutes + 1} min)', 'Palauta kauppaan (${left.inMinutes + 1} min päästä)')),
            ),
          );
        },
      );

  /// Confirms the return: the courier must hand everything back at the shop counter, and keeps
  /// the job pay and tip.
  Future<void> _returnToShop(Map<String, dynamic> o) async {
    final id = asInt(o['id']);
    if (id == null || _returningToShop) return;
    HapticFeedback.mediumImpact();
    final store = (o['store'] as Map?) ?? {};
    final storeName = '${store['name'] ?? tr(context, 'the shop', 'kauppaan')}';
    final pieces = _pieceCount(o);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Return order #$id to the shop?', 'Palautetaanko tilaus #$id kauppaan?')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tr(context,
                    'Take ${pieces == null ? 'all the items' : 'all ${_piecesText(pieces)}'} back to $storeName and hand them over at the shop counter. Show the order number #$id. Do not leave them anywhere else.',
                    'Vie ${pieces == null ? 'kaikki tuotteet' : 'kaikki ${_piecesText(pieces)}'} takaisin: $storeName, ja luovuta ne myyntitiskille. Näytä tilausnumero #$id. Älä jätä niitä mihinkään muualle.'),
                style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600)),
            if (store['address'] != null) ...[
              const SizedBox(height: 8),
              Text('${store['address']}', style: const TextStyle(color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 12),
            Text(
                tr(context,
                    'The order is cancelled and the customer is refunded for the items. You keep the pay for this job and any tip.',
                    'Tilaus perutaan ja asiakas saa hyvityksen tuotteista. Saat pitää tämän keikan palkkion ja mahdollisen tipin.'),
                style: const TextStyle(height: 1.4)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'Keep waiting', 'Odotan vielä'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(context, 'Return to shop', 'Palauta kauppaan')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _returningToShop = true);
    final res = await _api.post('/orders/$id/return-to-store');
    if (!mounted) return;
    setState(() => _returningToShop = false);
    if (res.status == 404 && !_rawError(res).toLowerCase().contains('order')) {
      setState(() => _problemUnsupported = true);
      return _snack(tr(context, 'Returning in the app is not available yet. Contact Malvoya through Help.',
          'Palauttaminen sovelluksessa ei ole vielä käytössä. Ota yhteyttä Malvoyaan Apua-sivun kautta.'));
    }
    if (!res.ok) return _snack(res.error!);
    HapticFeedback.heavyImpact();
    _resetChat();
    await _loadMine();
  }

  /// An order the courier is taking back to the shop: cancelled after a delivery problem in the
  /// last 12 hours, reminder not yet closed on this phone.
  Map<String, dynamic>? _returningOrder() {
    for (final o in _mine) {
      if (o['status'] != 'CANCELLED') continue;
      // returnedToStoreAt marks the courier's own return; deliveryProblemAt covers the moment before it is read
      if (o.containsKey('returnedToStoreAt') && o['returnedToStoreAt'] == null) continue;
      final at = DateTime.tryParse('${o['returnedToStoreAt'] ?? ''}')?.toLocal() ?? _problemAt(o);
      if (at == null || DateTime.now().difference(at) > const Duration(hours: 12)) continue;
      if (_returnedDone.contains('${o['id']}')) continue;
      return o;
    }
    return null;
  }

  Future<void> _loadReturnedDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_returnedKey) ?? const [];
      if (mounted) setState(() => _returnedDone = ids.toSet());
    } catch (_) {}
  }

  Future<void> _markReturned(Map<String, dynamic> o) async {
    HapticFeedback.mediumImpact();
    setState(() => _returnedDone = {..._returnedDone, '${o['id']}'});
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only the latest few are kept
      final list = _returnedDone.toList();
      await prefs.setStringList(_returnedKey, list.length > 20 ? list.sublist(list.length - 20) : list);
    } catch (_) {}
  }

  /// A strip under the online bar while an order is on its way back to the shop.
  Widget _returnStrip(Map<String, dynamic> o) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Material(
          color: AppTheme.dangerLight,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _tabs.animateTo(1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.keyboard_return_rounded, color: AppTheme.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr(context, 'Take order #${o['id']} back to the shop', 'Vie tilaus #${o['id']} takaisin kauppaan'),
                        style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.danger),
                ]),
              ),
            ),
          ),
        ),
      );

  /// After "Return to shop": where to take the items and what to do there.
  Widget _returnCard(Map<String, dynamic> o) {
    final s = (o['store'] as Map?) ?? {};
    final storeName = '${s['name'] ?? ''}';
    final pieces = _pieceCount(o);
    final items = ((o['items'] as List?) ?? []).whereType<Map>().toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
        border: Border.all(color: AppTheme.danger, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(storeName.isEmpty ? tr(context, 'Back to the shop', 'Takaisin kauppaan') : tr(context, 'Back to $storeName', 'Takaisin kauppaan: $storeName'),
            style: AppTheme.display(size: 22)),
        if (s['address'] != null) ...[
          const SizedBox(height: 4),
          Text('${s['address']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'Show the shop this order number', 'Näytä kaupalle tämä tilausnumero'),
                style: const TextStyle(color: Color(0xFF6A4500), fontWeight: FontWeight.w700, fontSize: 13)),
            Text('#${o['id']}', style: AppTheme.display(size: 44)),
            if (pieces != null) Text(_piecesText(pieces), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final i in items) Text('${i['quantity']}× ${i['product']?['name'] ?? ''}', style: const TextStyle(height: 1.4)),
        ],
        const SizedBox(height: 12),
        Text(
            tr(context,
                'Hand all the items back at the shop counter. The order was cancelled and the customer is refunded for the items. You keep the pay for this job and any tip.',
                'Luovuta kaikki tuotteet kaupan myyntitiskille. Tilaus peruttiin ja asiakas saa hyvityksen tuotteista. Saat pitää tämän keikan palkkion ja mahdollisen tipin.'),
            style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _bigButton(
              outlined: true,
              onPressed: () => _navigate((s['latitude'] as num?)?.toDouble(), (s['longitude'] as num?)?.toDouble(), s['address']?.toString()),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(tr(context, 'Navigate', 'Navigoi')),
            ),
          ),
          if (s['phone'] != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _bigButton(
                outlined: true,
                onPressed: () => _call('${s['phone']}'),
                icon: const Icon(Icons.call_outlined),
                label: Text(tr(context, 'Call store', 'Soita kauppaan')),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        _bigButton(
          onPressed: () => _markReturned(o),
          icon: const Icon(Icons.check_rounded),
          label: Text(tr(context, 'I handed it back', 'Palautin tilauksen'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        Text(tr(context, 'This only closes the reminder on this phone.', 'Tämä sulkee vain muistutuksen tästä puhelimesta.'),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ]),
    );
  }

  /// Waiting at the shop: paid only when the shop isn't ready after the free minutes, and added
  /// at pickup. Shown only when the server supports check-in (the order carries `courierArrivedAt`).
  List<Widget> _arrivalSection(Map<String, dynamic> o) {
    if (!o.containsKey('courierArrivedAt')) return const [];
    final pay = _payOf(o);
    final free = _freeWaitMinutes(pay);
    final arrived = DateTime.tryParse('${o['courierArrivedAt'] ?? ''}')?.toLocal();
    final String rule;
    if (!_waitingPaid(pay)) {
      rule = _localized(pay?['waitPolicy']) ?? tr(context, 'Waiting at the shop is not paid separately.', 'Odotusta kaupassa ei makseta erikseen.');
    } else if (free != null) {
      rule = tr(context,
          'If the shop isn\'t ready when you get there, waiting after the first $free minutes is paid and added at pickup. It stops counting when the shop marks the order ready.',
          'Jos tilaus ei ole valmis, kun saavut, odotus ensimmäisten $free minuutin jälkeen maksetaan ja lisätään noudettaessa. Laskenta päättyy, kun kauppa merkitsee tilauksen valmiiksi.');
    } else {
      rule = tr(context,
          'If the shop isn\'t ready when you get there, waiting after the free minutes is paid and added at pickup. It stops counting when the shop marks the order ready.',
          'Jos tilaus ei ole valmis, kun saavut, odotus ilmaisten minuuttien jälkeen maksetaan ja lisätään noudettaessa. Laskenta päättyy, kun kauppa merkitsee tilauksen valmiiksi.');
    }
    if (arrived != null) {
      final hhmm = '${arrived.hour.toString().padLeft(2, '0')}.${arrived.minute.toString().padLeft(2, '0')}';
      return [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF6A4500)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(context, 'Arrival at the shop recorded at $hhmm', 'Saapuminen kauppaan kirjattu klo $hhmm'),
                    style: const TextStyle(color: Color(0xFF6A4500), fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(rule, style: const TextStyle(color: Color(0xFF6A4500), fontSize: 12.5, height: 1.4)),
          ]),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(rule, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
      ),
    ];
  }

  // ── Earnings ────────────────────────────────────────────────────────────

  Widget _earningsTab() {
    if (_earnLoad == _Load.loading || (_earnLoad == _Load.ready && _mineLoad == _Load.loading)) return const EarningsSkeleton();
    if (_earnLoad == _Load.error) {
      return RefreshIndicator(
        onRefresh: () => _loadEarnings(manual: true),
        child: _loadError(tr(context, 'Could not load your earnings', 'Ansioita ei voitu ladata'), _earnError, () {
          setState(() => _earnLoad = _Load.loading);
          _loadEarnings();
        }),
      );
    }
    final summary = (_earnings?['summary'] as Map?) ?? {};
    final delivered = _mine.where((o) => o['status'] == 'DELIVERED').toList();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    DateTime? deliveredAt(Map o) => DateTime.tryParse('${o['deliveredAt']}')?.toLocal();
    final today = delivered.where((o) {
      final d = deliveredAt(o);
      return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
    int sum(Iterable<Map> list, String key) => list.fold<int>(0, (s, o) => s + (asInt(o[key]) ?? 0));
    final todayCents = today.fold<int>(0, (s, o) => s + (_payTotal(o) ?? 0)); // the pay already includes the tip
    final todayTips = sum(today, 'tipCents');
    final weekTips = sum(delivered.where((o) => deliveredAt(o)?.isAfter(weekAgo) ?? false), 'tipCents');

    Widget stat(String label, String value, {String? sub, bool highlight = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: highlight ? AppTheme.sunshine : Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2),
              border: highlight ? null : Border.all(color: AppTheme.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: highlight ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: AppTheme.display(size: 22)),
              if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: highlight ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    final waitingForAccount = asInt(summary['waitingForAccountCents']) ?? 0;

    // The chosen period, from the deliveries the server lists for this courier (its latest 100):
    // the pay of each job exactly as the server states it (tip included), tips also on their own
    final startOfToday = DateTime(now.year, now.month, now.day);
    final periodStart = _earnWeek ? startOfToday.subtract(const Duration(days: 6)) : startOfToday;
    final inPeriod = delivered.where((o) {
      final d = deliveredAt(o);
      return d != null && !d.isBefore(periodStart);
    }).toList();
    final periodCents = inPeriod.fold<int>(0, (s, o) => s + (_payTotal(o) ?? 0));
    final periodTips = sum(inPeriod, 'tipCents');
    final List<EarningsBar> bars;
    int? highlightBar;
    if (_earnWeek) {
      final fi = isFinnish(context);
      const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const fiDays = ['ma', 'ti', 'ke', 'to', 'pe', 'la', 'su'];
      bars = [
        for (var i = 0; i < 7; i++)
          () {
            final day = periodStart.add(Duration(days: i));
            final cents = inPeriod.where((o) {
              final d = deliveredAt(o)!;
              return d.year == day.year && d.month == day.month && d.day == day.day;
            }).fold<int>(0, (s, o) => s + (_payTotal(o) ?? 0));
            return (label: (fi ? fiDays : en)[day.weekday - 1], cents: cents);
          }(),
      ];
      highlightBar = 6;
    } else {
      // Hours 8–20, widened to any hour with a delivery today
      final hours = inPeriod.map((o) => deliveredAt(o)!.hour).toList();
      final first = hours.fold<int>(8, (a, b) => b < a ? b : a);
      final last = hours.fold<int>(20, (a, b) => b > a ? b : a);
      bars = [
        for (var h = first; h <= last; h++)
          (label: '$h', cents: inPeriod.where((o) => deliveredAt(o)!.hour == h).fold<int>(0, (s, o) => s + (_payTotal(o) ?? 0))),
      ];
      highlightBar = now.hour >= first && now.hour <= last ? now.hour - first : null;
    }
    final periodName = _earnWeek ? tr(context, 'Last 7 days', 'Viimeiset 7 päivää') : tr(context, 'Today', 'Tänään');
    return RefreshIndicator(
      onRefresh: () async => Future.wait([_loadEarnings(manual: true), _loadMine(manual: true)]),
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(64, 48)), tapTargetSize: MaterialTapTargetSize.padded),
          segments: [
            ButtonSegment(value: false, label: Text(tr(context, 'Today', 'Tänään'))),
            ButtonSegment(value: true, label: Text(tr(context, '7 days', '7 päivää'))),
          ],
          selected: {_earnWeek},
          onSelectionChanged: (v) {
            Haptics.select();
            setState(() => _earnWeek = v.first);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2), border: Border.all(color: AppTheme.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(periodName, style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
            Text(euro(context, periodCents), style: AppTheme.display(size: 34)),
            Text(
              [
                inPeriod.length == 1 ? tr(context, '1 delivery', '1 toimitus') : tr(context, '${inPeriod.length} deliveries', '${inPeriod.length} toimitusta'),
                '${tr(context, 'tips', 'tipit')} ${euro(context, periodTips)}',
              ].join(' · '),
              style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            EarningsChart(
              bars: bars,
              highlight: highlightBar,
              money: (c) => euro(context, c),
              summary: '$periodName: ${euro(context, periodCents)}, ${inPeriod.length} ${tr(context, 'deliveries', 'toimitusta')}',
            ),
            const SizedBox(height: 4),
            Text(
              _earnWeek ? tr(context, 'Pay per day, tips included', 'Palkkio päivittäin, tipit mukana') : tr(context, 'Pay per hour of handover, tips included', 'Palkkio luovutustunneittain, tipit mukana'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          stat(tr(context, 'Today', 'Tänään'), euro(context, todayCents),
              sub: todayTips > 0 ? '${tr(context, 'incl. tips', 'sis. tipit')} ${euro(context, todayTips)}' : null, highlight: true),
          const SizedBox(width: 10),
          stat(tr(context, 'Deliveries today', 'Toimituksia tänään'), '${today.length}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat(tr(context, 'Tips today', 'Tipit tänään'), euro(context, todayTips)),
          const SizedBox(width: 10),
          stat(tr(context, 'Tips, 7 days', 'Tipit, 7 pv'), euro(context, weekTips)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat(tr(context, 'Paid this week', 'Maksettu tällä viikolla'), euro(context, summary['paidThisWeekCents'])),
          const SizedBox(width: 10),
          stat(tr(context, 'Not yet paid out', 'Odottaa tilitystä'), euro(context, (asInt(summary['scheduledCents']) ?? 0) + waitingForAccount)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat(tr(context, 'Paid out in total', 'Maksettu yhteensä'), euro(context, summary['paidCents'])),
        ]),
        if (waitingForAccount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr(context, 'Set up payouts to receive the money you have earned.', 'Ota tilitykset käyttöön saadaksesi ansaitsemasi rahat.'),
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.schedule_rounded, size: 20, color: Color(0xFF6A4500)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(context, 'When do I get paid?', 'Milloin saan rahat?'), style: AppTheme.display(size: 17, color: const Color(0xFF6A4500)))),
            ]),
            const SizedBox(height: 8),
            Text(
              tr(context,
                  'You are paid after each delivery. Once payouts are set up, the pay for a delivery, including the whole tip, is sent to your Stripe account right after you hand it over (if Stripe is busy, it is retried within minutes). Stripe then moves it to your bank on your payout schedule, usually within a few working days (the very first payout can take longer). Money earned before you set up payouts waits safely and is sent as soon as setup is done.',
                  'Saat maksun jokaisesta toimituksesta. Kun tilitykset on otettu käyttöön, toimituksen palkkio ja koko tippi lähetetään Stripe-tilillesi heti luovutuksen jälkeen (jos Stripe ei vastaa, yritetään uudelleen muutaman minuutin kuluttua). Stripe siirtää rahat pankkitilillesi maksuaikataulusi mukaan, yleensä muutaman arkipäivän kuluessa (ensimmäinen maksu voi kestää pidempään). Ennen käyttöönottoa ansaitut rahat odottavat tallessa ja lähetetään heti, kun käyttöönotto on valmis.'),
              style: const TextStyle(color: Color(0xFF6A4500), height: 1.45, fontSize: 13.5),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutsScreen()));
              _loadEarnings();
            },
            icon: const Icon(Icons.account_balance_outlined),
            label: Text(tr(context, 'Payouts and bank details', 'Tilitykset ja pankkitiedot')),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
          child: ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: Text(tr(context, 'Help and contact', 'Apua ja yhteydenotto')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openHelp(),
          ),
        ),
        const SizedBox(height: 16),
        Text('${tr(context, 'Deliveries', 'Toimitukset')} · $periodName', style: AppTheme.display(size: 18)),
        if (_mineLoad == _Load.error)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(_mineError ?? tr(context, 'Could not load your deliveries.', 'Toimituksia ei voitu ladata.'), style: const TextStyle(color: AppTheme.textSecondary))),
              TextButton(onPressed: () => _loadMine(manual: true), child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
            ]),
          )
        else if (inPeriod.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  delivered.isEmpty
                      ? tr(context, 'No deliveries yet.', 'Ei vielä toimituksia.')
                      : (_earnWeek ? tr(context, 'No deliveries in the last 7 days.', 'Ei toimituksia viimeisten 7 päivän aikana.') : tr(context, 'No deliveries today yet.', 'Ei vielä toimituksia tänään.')),
                  style: const TextStyle(color: AppTheme.textSecondary)),
              if (!_online)
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => _tabs.animateTo(0),
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: Text(tr(context, 'Go online to get jobs', 'Mene linjoille saadaksesi keikkoja')),
                ),
            ]),
          ),
        for (final o in inPeriod.take(50)) _deliveryRow(o),
      ]),
    );
  }

  /// One delivery in Earnings; tapping it shows the pay breakdown, waiting pay included.
  Widget _deliveryRow(Map<String, dynamic> o) {
    final pay = _payOf(o);
    final wait = asInt(pay?['waitCents']) ?? 0;
    final tip = asInt(pay?['tipCents']) ?? asInt(o['tipCents']) ?? 0;
    final subtitle = Text([
      _when(o['deliveredAt']),
      if (tip > 0) '${tr(context, 'incl. tip', 'sis. tipin')} ${euro(context, tip)}',
      if (wait > 0) '${tr(context, 'incl. waiting', 'sis. odotuksen')} ${euro(context, wait)}',
    ].join(' · '));
    final title = Text('${o['store']?['name'] ?? ''} · #${o['id']}');
    final amount = Text(_payText(o), style: const TextStyle(fontWeight: FontWeight.w700));
    if (pay == null) return ListTile(contentPadding: EdgeInsets.zero, title: title, subtitle: subtitle, trailing: amount);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: title,
        subtitle: subtitle,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [amount, const Icon(Icons.expand_more_rounded, color: AppTheme.textSecondary)]),
        children: [_payBreakdown(o, pay, showWaiting: true)],
      ),
    );
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    return d == null ? '' : '${d.day}.${d.month}. ${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
  }
}

/// The chat sheet: the message list follows [messages] and scrolls to the newest one.
class _ChatSheet extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> messages;
  /// Whether the server stores chat and accepts messages over HTTP (null = not known yet).
  final ValueListenable<bool?> stored;
  final List<String> quickReplies;
  final bool Function(Map) isMine;
  /// Sends a message; returns an error to show, or null when it was sent.
  final Future<String?> Function(String text) onSend;

  const _ChatSheet({required this.messages, required this.stored, required this.quickReplies, required this.isMine, required this.onSend});

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.messages.addListener(_toBottom);
    _jumpToBottom();
  }

  @override
  void dispose() {
    widget.messages.removeListener(_toBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void _jumpToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _send(String t) async {
    final text = t.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.selectionClick();
    final typed = _input.text;
    _input.clear();
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await widget.onSend(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      // Not sent: the text comes back so nothing is lost
      if (error != null && _input.text.isEmpty) _input.text = typed.trim().isEmpty ? text : typed;
    });
  }

  String _time(Map m) {
    final t = DateTime.tryParse('${m['createdAt'] ?? m['timestamp'] ?? ''}')?.toLocal();
    if (t == null) return '';
    final mm = t.minute.toString().padLeft(2, '0');
    return isFinnish(context) ? '${t.hour}.$mm' : '${t.hour.toString().padLeft(2, '0')}:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          ListTile(
            title: Text(tr(context, 'Chat with the customer', 'Chat asiakkaan kanssa'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(context, 'Phone numbers are never shared.', 'Puhelinnumeroita ei jaeta.')),
          ),
          // Without the live connection, messages can still be sent when the server stores chat
          ListenableBuilder(
            listenable: Listenable.merge([CourierSocketService(), widget.stored]),
            builder: (context, _) => CourierSocketService().isConnected || widget.stored.value == true
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                        tr(context, 'Not connected right now, so messages may not be sent. Check your internet connection.',
                            'Ei yhteyttä juuri nyt, joten viestit eivät ehkä lähde. Tarkista nettiyhteys.'),
                        style: const TextStyle(color: Color(0xFF6A4500), fontSize: 13)),
                  ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: widget.messages,
              builder: (context, chat, _) => chat.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr(context, 'No messages yet.', 'Ei vielä viestejä.'), style: const TextStyle(color: AppTheme.textSecondary)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: chat.length,
                      itemBuilder: (context, i) {
                        final m = chat[i];
                        final mine = widget.isMine(m);
                        final time = _time(m);
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(color: mine ? AppTheme.primary : AppTheme.divider, borderRadius: BorderRadius.circular(16)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: 1,
                                child: Text('${m['text'] ?? ''}', style: TextStyle(color: mine ? Colors.white : AppTheme.textPrimary)),
                              ),
                              if (time.isNotEmpty)
                                Text(time, style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : AppTheme.textSecondary)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.dangerLight, borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: widget.quickReplies
                  .map((q) => Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(q), onPressed: _sending ? null : () => _send(q))))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 1000,
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(counterText: '', hintText: tr(context, 'Message', 'Viesti')),
                ),
              ),
              _sending
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
                    )
                  : IconButton(
                      tooltip: tr(context, 'Send message', 'Lähetä viesti'),
                      iconSize: 28,
                      icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                      onPressed: () => _send(_input.text),
                    ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Rebuilds every second until [until], then once more with [Duration.zero] and stops.
class _Countdown extends StatefulWidget {
  final DateTime until;
  final Widget Function(BuildContext context, Duration left) builder;

  const _Countdown({required this.until, required this.builder});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;

  Duration get _left {
    final d = widget.until.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _Countdown old) {
    super.didUpdateWidget(old);
    if (old.until != widget.until) _start();
  }

  void _start() {
    _timer?.cancel();
    if (_left == Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_left == Duration.zero) t.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left);
}
