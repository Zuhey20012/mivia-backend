import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/media_upload.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
import '../core/delete_account_tile.dart';
import '../services/courier_telemetry_service.dart';
import '../services/socket_service.dart';
import 'payouts_screen.dart';

/// Go online, pick the jobs you want, deliver with navigation and chat, and see what you earn.
class CourierDashboard extends StatefulWidget {
  const CourierDashboard({super.key});

  @override
  State<CourierDashboard> createState() => _CourierDashboardState();
}

class _CourierDashboardState extends State<CourierDashboard> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _online = false;
  bool _switching = false;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _mine = [];
  Map<String, dynamic>? _earnings;
  final List<Map<String, dynamic>> _chat = [];
  bool _loading = true;
  // Pay breakdowns that came with live offers, by order id (used if the job list has none yet)
  final Map<int, Map<String, dynamic>> _offerPay = {};
  // Which pay breakdowns are open ("job-12", "active-12")
  final Set<String> _openPay = {};
  bool _arriving = false;

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
    final socket = CourierSocketService();
    socket.onDispatchOffer = (offer) {
      final id = asInt(offer['orderId'] ?? offer['id']);
      if (id != null && offer['courierPay'] is Map) _offerPay[id] = Map<String, dynamic>.from(offer['courierPay']);
      HapticFeedback.heavyImpact();
      _loadJobs();
    };
    socket.onOrderStatus = (_) => _loadMine();
    socket.onChatMessage = (m) {
      if (mounted && asInt(m['orderId']) == asInt(_active?['id'])) setState(() => _chat.add(m));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _restored = ConnectivityService.instance.onRestored.listen((_) => _backOnline());
  }

  StreamSubscription<void>? _restored;
  bool _meLoaded = false;

  @override
  void dispose() {
    _restored?.cancel();
    _tabs.dispose();
    super.dispose();
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
    final me = await _api.get('/courier/me');
    if (!mounted) return;
    _meLoaded = me.ok;
    final online = me.ok && me.data['courier']?['isOnline'] == true;
    setState(() => _online = online);
    if (online) await _startSharing();
    await Future.wait([_loadJobs(), _loadMine(), _loadEarnings()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _startSharing() async {
    final token = _auth.accessToken ?? '';
    CourierSocketService().connect(token);
    final ok = await CourierTelemetryService().start(accessToken: token, orderId: asInt(_active?['id']));
    return ok;
  }

  Future<void> _toggleOnline() async {
    HapticFeedback.mediumImpact();
    setState(() => _switching = true);
    final next = !_online;
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
    final res = await _api.post('/courier/status', {'isOnline': next, 'latitude': lat, 'longitude': lng});
    if (!mounted) return;
    setState(() {
      _switching = false;
      if (res.ok) _online = next;
    });
    if (!res.ok) _snack(res.error!);
    if (next) _loadJobs();
  }

  Future<void> _loadJobs() async {
    final res = await _api.get('/orders/available');
    if (!mounted || !res.ok) return;
    setState(() => _jobs = ((res.data['orders'] as List?) ?? []).map((o) => Map<String, dynamic>.from(o)).toList());
  }

  Future<void> _loadMine() async {
    final res = await _api.get('/orders/courier/mine');
    if (!mounted || !res.ok) return;
    setState(() => _mine = ((res.data['orders'] as List?) ?? []).map((o) => Map<String, dynamic>.from(o)).toList());
    final active = _active;
    CourierTelemetryService().setActiveOrder(asInt(active?['id']));
    if (active != null) CourierSocketService().trackOrder(asInt(active['id'])!);
  }

  Future<void> _loadEarnings() async {
    final res = await _api.get('/payouts');
    if (!mounted || !res.ok) return;
    setState(() => _earnings = res.data);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  Future<void> _accept(Map<String, dynamic> job) async {
    HapticFeedback.mediumImpact();
    final res = await _api.patch('/orders/${job['id']}/assign-courier');
    if (!mounted) return;
    if (!res.ok) {
      _snack(res.error!);
      _loadJobs();
      return;
    }
    _chat.clear();
    await _loadMine();
    _loadJobs();
    _tabs.animateTo(1);
  }

  Future<void> _pickedUp(Map<String, dynamic> o) async {
    HapticFeedback.mediumImpact();
    final res = await _api.patch('/orders/${o['id']}/status', {'status': 'SHIPPED'});
    if (!mounted) return;
    if (!res.ok) _snack(res.error!);
    _loadMine();
  }

  /// Records that the courier is at the shop, so waiting beyond the free minutes is paid at pickup.
  Future<void> _arrivedAtStore(Map<String, dynamic> o) async {
    HapticFeedback.mediumImpact();
    setState(() => _arriving = true);
    final res = await _api.post('/orders/${o['id']}/arrived-at-store');
    if (!mounted) return;
    setState(() => _arriving = false);
    if (!res.ok) return _snack(res.error!);
    await _loadMine();
  }

  // ── Courier pay ─────────────────────────────────────────────────────────
  // The server sends `courierPay` with each job and delivery. Older servers only send
  // courierFeeCents (tip included), so everything below falls back to that.

  Map<String, dynamic>? _payOf(Map o) {
    final p = o['courierPay'];
    if (p is Map) return Map<String, dynamic>.from(p);
    final id = asInt(o['id']);
    return id == null ? null : _offerPay[id];
  }

  int? _payTotal(Map o) => asInt(_payOf(o)?['totalCents']) ?? asInt(o['courierFeeCents']);

  String _payText(Map o) {
    final t = _payTotal(o);
    return t == null ? '–' : euro(context, t);
  }

  /// The server's one-line explanation of how the pay is worked out, in the app language.
  String? _payExplanation(Map<String, dynamic>? pay) {
    final e = pay?['explanation'];
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
    final e = pay?['explanation'];
    final en = e is Map ? '${e['en'] ?? ''}' : '${e ?? ''}';
    final m = RegExp(r'(\d+)\s*(?:free\s+)?min', caseSensitive: false).firstMatch(en);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  String _km(num km) {
    final s = km.toStringAsFixed(1);
    return isFinnish(context) ? s.replaceAll('.', ',') : s;
  }

  /// Line-by-line pay: base, distance, waiting, tip and total, then the explanation.
  Widget _payBreakdown(Map o, Map<String, dynamic> pay, {required bool showWaiting}) {
    final base = asInt(pay['baseCents']) ?? 0;
    final km = pay['distanceKm'] is num ? pay['distanceKm'] as num : num.tryParse('${pay['distanceKm'] ?? ''}');
    final dist = asInt(pay['distanceCents']) ?? 0;
    final wait = asInt(pay['waitCents']) ?? 0;
    final tip = asInt(pay['tipCents']) ?? asInt(o['tipCents']) ?? 0;
    final total = asInt(pay['totalCents']) ?? asInt(o['courierFeeCents']) ?? 0;
    final other = total - base - dist - wait - tip;

    String distLabel = tr(context, 'Distance', 'Matka');
    if (km != null && km > 0) {
      final rate = (dist / km).round();
      final exactRate = rate > 0 && (rate * km).round() == dist;
      distLabel = exactRate
          ? '$distLabel ${_km(km)} km × ${euro(context, rate)}/km'
          : '$distLabel ${_km(km)} km';
    }

    Widget line(String label, int cents, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? AppTheme.textPrimary : AppTheme.textSecondary))),
            Text(euro(context, cents), style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    final explanation = _payExplanation(pay);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(tr(context, 'Base (pickup + drop-off)', 'Perusmaksu (nouto + luovutus)'), base),
        if (dist != 0 || (km != null && km > 0)) line(distLabel, dist),
        if (showWaiting && wait > 0) line(tr(context, 'Waiting at the shop', 'Odotus kaupassa'), wait),
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
        onTap: () => setState(() => open ? _openPay.remove(key) : _openPay.add(key)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
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

  Future<void> _complete(Map<String, dynamic> o) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(tr(context, 'How did you hand it over?', 'Miten luovutit tilauksen?'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: Text(tr(context, 'To the customer in person', 'Asiakkaalle henkilökohtaisesti')),
            onTap: () => Navigator.pop(ctx, 'IN_PERSON'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr(context, 'Left at the door — take a photo', 'Jätetty ovelle — ota kuva')),
            subtitle: Text(tr(context, 'Photograph only the parcel at the door — no people, faces or house numbers. Only the customer sees it; it is deleted after 30 days.',
                'Kuvaa vain paketti ovella — ei ihmisiä, kasvoja tai ovinumeroita. Vain asiakas näkee kuvan; se poistetaan 30 päivän kuluttua.')),
            onTap: () => Navigator.pop(ctx, 'PHOTO'),
          ),
        ]),
      ),
    );
    if (method == null || !mounted) return;
    final orderId = asInt(o['id'])!;
    Map<String, dynamic>? proof;
    if (method == 'PHOTO') {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      if (shot == null || !mounted) return;
      _snack(tr(context, 'Uploading photo…', 'Ladataan kuvaa…'));
      try {
        proof = (await MediaUpload.upload(api: _api, kind: 'delivery_proof', file: File(shot.path), orderId: orderId)).toProof();
      } catch (e) {
        if (mounted) _snack('$e');
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
    if (!res.ok) return _snack(res.error!);
    HapticFeedback.heavyImpact();
    _snack(tr(context, 'Delivered — nice work!', 'Toimitettu — hyvää työtä!'));
    _chat.clear();
    await Future.wait([_loadMine(), _loadEarnings(), _loadJobs()]);
  }

  Future<void> _navigate(double? lat, double? lng, String? address) async {
    final destination = lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent(address ?? '');
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=bicycling');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openChat(Map<String, dynamic> o) {
    final input = TextEditingController();
    final orderId = asInt(o['id'])!;
    final myName = (_auth.currentUser?.name ?? 'Courier').split(' ').first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void send(String t) {
          if (t.trim().isEmpty) return;
          CourierSocketService().sendChat(orderId, t.trim(), myName);
          input.clear();
          Future.delayed(const Duration(milliseconds: 400), () => ctx.mounted ? set(() {}) : null);
        }

        final quick = [
          tr(context, 'I\'m at the door', 'Olen ovella'),
          tr(context, 'I\'m outside', 'Olen ulkona'),
          tr(context, 'Running 5 min late', 'Myöhästyn 5 min'),
        ];
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(children: [
              ListTile(
                title: Text(tr(context, 'Chat with the customer', 'Chat asiakkaan kanssa'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr(context, 'Phone numbers are never shared.', 'Puhelinnumeroita ei jaeta.')),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _chat.map((m) {
                    final mine = m['role'] == 'COURIER';
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(color: mine ? AppTheme.primary : AppTheme.divider, borderRadius: BorderRadius.circular(16)),
                        child: Text(m['text'] ?? '', style: TextStyle(color: mine ? Colors.white : AppTheme.textPrimary)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: quick.map((q) => Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(q), onPressed: () => send(q)))).toList()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(children: [
                  Expanded(child: TextField(controller: input, maxLength: 1000, onSubmitted: send, decoration: InputDecoration(counterText: '', hintText: tr(context, 'Message', 'Viesti')))),
                  IconButton(icon: const Icon(Icons.send_rounded, color: AppTheme.primary), onPressed: () => send(input.text)),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

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
                'When a store accepts an order, it is offered to online couriers within 7.5 km of the store, nearest first. If nobody is that close, every online courier sees it. Distance to the store is the only factor: ratings, acceptance rates and declines are not used. You choose which jobs to take — declining or ignoring a job never affects you.\n\nEach offer shows your pay before you accept, with a breakdown. If you wait at the shop beyond the free minutes, waiting pay is added when you pick up. Tips go to you in full.\n\nMalvoya is just starting, so there may be few jobs or none at first. No number of jobs or level of earnings is promised. You deliver as an independent entrepreneur and may also work for other platforms.\n\nNo automated system rates or deactivates you; account decisions are made by a person and explained to you.',
                'Kun kauppa hyväksyy tilauksen, se tarjotaan linjoilla oleville läheteille 7,5 km:n säteellä kaupasta, lähin ensin. Jos kukaan ei ole niin lähellä, kaikki linjoilla olevat näkevät sen. Ainoa peruste on etäisyys kauppaan: arvioita, hyväksymisprosenttia tai hylkäyksiä ei käytetä. Valitset itse keikkasi — kieltäytyminen tai ohittaminen ei vaikuta sinuun.\n\nJokainen tarjous näyttää palkkiosi erittelyineen ennen kuin hyväksyt. Jos odotat kaupassa ilmaisten minuuttien jälkeen, odotuksesta maksetaan noudon yhteydessä. Tipit saat kokonaan.\n\nMalvoya on vasta aloittamassa, joten keikkoja voi aluksi olla vähän tai ei lainkaan. Keikkojen määrää tai ansioita ei luvata. Toimitat itsenäisenä yrittäjänä ja voit tehdä keikkoja myös muille alustoille.\n\nMikään automaatti ei arvioi tai sulje tiliäsi; päätökset tekee ihminen ja perustelee ne sinulle.'),
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
          IconButton(tooltip: tr(context, 'Sign out', 'Kirjaudu ulos'), icon: const Icon(Icons.logout_rounded), onPressed: () async {
            if (_online) await _toggleOnline();
            CourierSocketService().disconnect();
            await _auth.logout();
          }),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppTheme.primary, width: 3),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          tabs: [
            Tab(text: '${tr(context, 'Jobs', 'Keikat')}${_jobs.isNotEmpty && active == null ? ' (${_jobs.length})' : ''}'),
            Tab(text: tr(context, 'Delivery', 'Toimitus')),
            Tab(text: tr(context, 'Earnings', 'Ansiot')),
          ],
        ),
      ),
      body: Column(children: [
        _onlineBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(controller: _tabs, children: [_jobsTab(active), _deliveryTab(active), _earningsTab()]),
        ),
      ]),
    );
  }

  Widget _onlineBar() => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(
          color: _online ? AppTheme.success : AppTheme.textPrimary,
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(_online ? Icons.pedal_bike_rounded : Icons.power_settings_new_rounded,
                size: 22, color: _online ? AppTheme.success : AppTheme.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _online
                  ? tr(context, 'Online — sharing your location while online', 'Linjoilla — sijaintisi jaetaan, kun olet linjoilla')
                  : tr(context, 'Offline — you get no jobs and your location is not shared', 'Poissa — et saa keikkoja eikä sijaintiasi jaeta'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          _switching
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Switch(value: _online, onChanged: (_) => _toggleOnline(), activeColor: Colors.white, activeTrackColor: Colors.white38),
        ]),
      );

  Widget _jobsTab(Map<String, dynamic>? active) {
    if (active != null) {
      return _empty(Icons.pedal_bike_rounded, tr(context, 'Finish your current delivery to take the next job.', 'Tee nykyinen toimitus loppuun ottaaksesi seuraavan keikan.'));
    }
    if (!_online) return _goOnlinePrompt();
    final here = CourierTelemetryService().lastPosition;
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: _jobs.isEmpty
          ? ListView(children: [_empty(Icons.hourglass_empty_rounded, tr(context, 'No jobs right now. Malvoya is just starting, so jobs may be rare at first. While you are online, you get a notification when one comes in.', 'Ei keikkoja juuri nyt. Malvoya on vasta aloittamassa, joten keikkoja voi aluksi olla harvoin. Kun olet linjoilla, saat ilmoituksen uudesta keikasta.'))])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _jobs.map((j) {
                final s = (j['store'] as Map?) ?? {};
                String? toStore;
                String? drop;
                if (here != null && s['latitude'] != null) {
                  toStore = '${(Geolocator.distanceBetween(here.latitude, here.longitude, (s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble()) / 1000).toStringAsFixed(1)} km';
                }
                if (s['latitude'] != null && j['deliveryAreaLat'] != null) {
                  drop = '${(Geolocator.distanceBetween((s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble(), (j['deliveryAreaLat'] as num).toDouble(), (j['deliveryAreaLng'] as num).toDouble()) / 1000).toStringAsFixed(1)} km';
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg), border: Border.all(color: AppTheme.divider)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(_payText(j), style: AppTheme.display(size: 32)),
                      if ((asInt(_payOf(j)?['tipCents']) ?? asInt(j['tipCents']) ?? 0) > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(12)),
                          child: Text('${tr(context, 'incl. tip', 'sis. tipin')} ${euro(context, asInt(_payOf(j)?['tipCents']) ?? asInt(j['tipCents']))}',
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(12)),
                        child: Text('${j['itemCount']} ${tr(context, 'item(s)', 'tuote(tta)')}',
                            style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                    ]),
                    Text(tr(context, 'Your pay for this job', 'Palkkiosi tästä keikasta'), style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                    _payToggle('job-${j['id']}', j, showWaiting: false),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${tr(context, 'Pick up', 'Nouto')}: ${s['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          if (s['address'] != null) Text(s['address'], style: const TextStyle(color: AppTheme.textSecondary)),
                        ]),
                      ),
                    ]),
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
                          : tr(context, 'Straight-line distances. The exact address is shown after you accept.',
                              'Linnuntie-etäisyydet. Tarkka osoite näytetään hyväksynnän jälkeen.'),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: () => _accept(j), child: Text(tr(context, 'Accept job', 'Ota keikka')))),
                  ]),
                );
              }).toList(),
            ),
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
  Widget _goOnlinePrompt() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: AppTheme.sunshineLight, shape: BoxShape.circle),
              child: const Icon(Icons.pedal_bike_rounded, size: 46, color: AppTheme.primary),
            ),
            const SizedBox(height: 18),
            Text(tr(context, 'You are offline', 'Olet poissa linjoilta'), style: AppTheme.display(size: 24), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              tr(context, 'Go online to get job offers near you. Your location is shared only while you are online.',
                  'Mene linjoille saadaksesi keikkatarjouksia lähelläsi. Sijaintisi jaetaan vain, kun olet linjoilla.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: _switching ? null : _toggleOnline,
                icon: _switching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.power_settings_new_rounded),
                label: Text(tr(context, 'Go online', 'Mene linjoille'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      );

  Widget _deliveryTab(Map<String, dynamic>? o) {
    if (o == null) return _empty(Icons.inventory_2_outlined, tr(context, 'No delivery in progress.', 'Ei toimitusta käynnissä.'));
    final s = (o['store'] as Map?) ?? {};
    final pickedUp = o['status'] == 'SHIPPED';
    final storeReady = o['status'] == 'PROCESSING';
    final items = (o['items'] as List?) ?? [];
    final customer = (o['user']?['name'] ?? '').toString().split(' ').first;

    Widget step(int n, String title, bool done, bool current, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
            border: Border.all(color: current ? AppTheme.primary : AppTheme.divider, width: current ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 13, backgroundColor: done ? AppTheme.success : (current ? AppTheme.primary : AppTheme.divider),
                  child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : Text('$n', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.display(size: 18))),
            ]),
            if (current) ...[const SizedBox(height: 10), ...children],
          ]),
        );

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${tr(context, 'Order', 'Tilaus')} #${o['id']} · ${tr(context, 'your pay', 'palkkiosi')} ${_payText(o)}', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        _payToggle('active-${o['id']}', o, showWaiting: true),
        const SizedBox(height: 6),
        step(1, '${tr(context, 'Pick up at', 'Nouda')} ${s['name'] ?? ''}', pickedUp, !pickedUp, [
          if (s['address'] != null) Text(s['address']),
          const SizedBox(height: 6),
          Text(storeReady ? tr(context, 'The store says the order is packed and ready.', 'Kauppa ilmoittaa tilauksen olevan valmis.') : tr(context, 'The store is still packing.', 'Kauppa pakkaa vielä.'),
              style: TextStyle(color: storeReady ? AppTheme.success : AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final i in items) Text('${i['quantity']}× ${i['product']?['name'] ?? ''}'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _navigate((s['latitude'] as num?)?.toDouble(), (s['longitude'] as num?)?.toDouble(), s['address']),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(tr(context, 'Navigate', 'Navigoi')),
            )),
            if (s['phone'] != null) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:${s['phone']}')),
                icon: const Icon(Icons.call_outlined),
                label: Text(tr(context, 'Call store', 'Soita kauppaan')),
              )),
            ],
          ]),
          const SizedBox(height: 10),
          ..._arrivalSection(o),
          SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: () => _pickedUp(o), child: Text(tr(context, 'I have the order', 'Tilaus on mukanani')))),
        ]),
        step(2, '${tr(context, 'Deliver to', 'Toimita')} ${customer.isEmpty ? tr(context, 'the customer', 'asiakkaalle') : customer}', false, pickedUp, [
          if (o['deliveryAddress'] != null) Text(o['deliveryAddress'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if ((o['notes'] ?? '').toString().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
              child: Text('“${o['notes']}”', style: const TextStyle(color: Color(0xFF6A4500), height: 1.4)),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _navigate((o['deliveryLat'] as num?)?.toDouble(), (o['deliveryLng'] as num?)?.toDouble(), o['deliveryAddress']),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(tr(context, 'Navigate', 'Navigoi')),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _openChat(o), icon: const Icon(Icons.chat_bubble_outline_rounded), label: Text(tr(context, 'Chat', 'Chat')))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: () => _complete(o), child: Text(tr(context, 'Complete delivery', 'Merkitse toimitetuksi')))),
        ]),
        Text(tr(context, 'Keep the app open or in the background while delivering so the customer can follow you.', 'Pidä sovellus auki tai taustalla toimituksen aikana, jotta asiakas voi seurata sinua.'),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ]),
    );
  }

  /// "I'm at the shop": records the arrival time on the server, so waiting beyond the free minutes
  /// is paid at pickup. Shown only when the server supports it (the order carries `courierArrivedAt`).
  List<Widget> _arrivalSection(Map<String, dynamic> o) {
    if (!o.containsKey('courierArrivedAt')) return const [];
    final pay = _payOf(o);
    final free = _freeWaitMinutes(pay);
    final arrived = DateTime.tryParse('${o['courierArrivedAt'] ?? ''}')?.toLocal();
    final rule = free != null
        ? tr(context, 'Waiting at the shop beyond $free free minutes is paid, and added to your pay when you pick up the order.',
            'Kaupassa odottaminen $free ilmaisen minuutin jälkeen maksetaan, ja se lisätään palkkioosi, kun noudat tilauksen.')
        : tr(context, 'Waiting at the shop beyond the free minutes is paid, and added to your pay when you pick up the order.',
            'Kaupassa odottaminen ilmaisten minuuttien jälkeen maksetaan, ja se lisätään palkkioosi, kun noudat tilauksen.');
    if (arrived != null) {
      final hhmm = '${arrived.hour.toString().padLeft(2, '0')}.${arrived.minute.toString().padLeft(2, '0')}';
      return [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.storefront_rounded, size: 18, color: Color(0xFF6A4500)),
              const SizedBox(width: 6),
              Expanded(child: Text(tr(context, 'Arrival at the shop recorded at $hhmm', 'Saapuminen kauppaan kirjattu klo $hhmm'),
                  style: const TextStyle(color: Color(0xFF6A4500), fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            Text(rule, style: const TextStyle(color: Color(0xFF6A4500), fontSize: 12.5, height: 1.4)),
          ]),
        ),
      ];
    }
    return [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _arriving ? null : () => _arrivedAtStore(o),
          icon: _arriving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.storefront_outlined),
          label: Text(tr(context, "I'm at the shop", 'Olen kaupalla')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Text(rule, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
      ),
    ];
  }

  Widget _earningsTab() {
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
    return RefreshIndicator(
      onRefresh: () async => Future.wait([_loadEarnings(), _loadMine()]),
      child: ListView(padding: const EdgeInsets.all(16), children: [
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
          child: const Column(children: [GoogleLinkTile(), Divider(height: 1), DeleteAccountTile()]),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'Recent deliveries', 'Viimeisimmät toimitukset'), style: AppTheme.display(size: 18)),
        if (delivered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr(context, 'No deliveries yet.', 'Ei vielä toimituksia.'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        for (final o in delivered.take(30)) _deliveryRow(o),
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

  Widget _empty(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
          ]),
        ),
      );
}
