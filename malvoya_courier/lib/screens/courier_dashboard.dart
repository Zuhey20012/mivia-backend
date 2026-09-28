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
import '../core/media_upload.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
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
    socket.onDispatchOffer = (_) {
      HapticFeedback.heavyImpact();
      _loadJobs();
    };
    socket.onOrderStatus = (_) => _loadMine();
    socket.onChatMessage = (m) {
      if (mounted && asInt(m['orderId']) == asInt(_active?['id'])) setState(() => _chat.add(m));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final me = await _api.get('/courier/me');
    if (!mounted) return;
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
            subtitle: Text(tr(context, 'Only the customer sees the photo. It is deleted after 30 days.', 'Vain asiakas näkee kuvan. Se poistetaan 30 päivän kuluttua.')),
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
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'How jobs are offered', 'Miten keikat tarjotaan'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            tr(context,
                'When a store accepts an order, it is offered to online couriers within 7.5 km of the store, nearest first. If nobody is that close, every online courier sees it. You choose which jobs to take — declining or ignoring a job never affects you. The pay shown is what you earn for the job. No automated system rates or deactivates you; account decisions are made by a person and explained to you.',
                'Kun kauppa hyväksyy tilauksen, se tarjotaan linjoilla oleville kuriireille 7,5 km:n säteellä kaupasta, lähin ensin. Jos kukaan ei ole niin lähellä, kaikki linjoilla olevat näkevät sen. Valitset itse keikkasi — kieltäytyminen tai ohittaminen ei vaikuta sinuun. Näytetty palkkio on se, mitä ansaitset. Mikään automaatti ei arvioi tai sulje tiliäsi; päätökset tekee ihminen ja perustelee ne sinulle.'),
            style: const TextStyle(height: 1.45, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => openLegal('couriers'),
            icon: const Icon(Icons.gavel_rounded),
            label: Text(tr(context, 'Read the courier agreement', 'Lue lähettisopimus')),
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
        backgroundColor: Colors.white,
        title: Text(name.isEmpty ? 'Malvoya Courier' : '${tr(context, 'Hi', 'Hei')} $name'),
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
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
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

  Widget _onlineBar() => Container(
        color: _online ? AppTheme.success : AppTheme.textPrimary,
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(children: [
          Icon(_online ? Icons.circle : Icons.circle_outlined, size: 12, color: Colors.white),
          const SizedBox(width: 10),
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
    if (!_online) {
      return _empty(Icons.power_settings_new_rounded, tr(context, 'Go online to see jobs near you.', 'Mene linjoille nähdäksesi keikat lähelläsi.'));
    }
    final here = CourierTelemetryService().lastPosition;
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: _jobs.isEmpty
          ? ListView(children: [_empty(Icons.hourglass_empty_rounded, tr(context, 'No jobs right now. You get a notification when one comes in.', 'Ei keikkoja juuri nyt. Saat ilmoituksen, kun uusi tulee.'))])
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(euro(context, j['courierFeeCents'] ?? j['deliveryFeeCents']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text('${j['itemCount']} ${tr(context, 'item(s)', 'tuote(tta)')}', style: const TextStyle(color: AppTheme.textSecondary)),
                    ]),
                    const SizedBox(height: 8),
                    Text('${tr(context, 'Pick up', 'Nouto')}: ${s['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (s['address'] != null) Text(s['address'], style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (toStore != null) '${tr(context, 'To store', 'Kauppaan')} $toStore',
                        if (drop != null) '${tr(context, 'then', 'sitten')} ~$drop ${tr(context, 'to the customer', 'asiakkaalle')}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    Text(tr(context, 'The exact address is shown after you accept.', 'Tarkka osoite näytetään hyväksynnän jälkeen.'), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () => _accept(j), child: Text(tr(context, 'Accept job', 'Ota keikka')))),
                  ]),
                );
              }).toList(),
            ),
    );
  }

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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: current ? AppTheme.primary : AppTheme.divider, width: current ? 1.6 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 13, backgroundColor: done ? AppTheme.success : (current ? AppTheme.primary : AppTheme.divider),
                  child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : Text('$n', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            if (current) ...[const SizedBox(height: 10), ...children],
          ]),
        );

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${tr(context, 'Order', 'Tilaus')} #${o['id']} · ${euro(context, o['courierFeeCents'] ?? o['deliveryFeeCents'])}', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
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
          SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () => _pickedUp(o), child: Text(tr(context, 'I have the order', 'Tilaus on mukanani')))),
        ]),
        step(2, '${tr(context, 'Deliver to', 'Toimita')} ${customer.isEmpty ? tr(context, 'the customer', 'asiakkaalle') : customer}', false, pickedUp, [
          if (o['deliveryAddress'] != null) Text(o['deliveryAddress'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if ((o['notes'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${o['notes']}”', style: const TextStyle(fontStyle: FontStyle.italic))),
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
          SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () => _complete(o), child: Text(tr(context, 'Complete delivery', 'Merkitse toimitetuksi')))),
        ]),
        Text(tr(context, 'Keep the app open or in the background while delivering so the customer can follow you.', 'Pidä sovellus auki tai taustalla toimituksen aikana, jotta asiakas voi seurata sinua.'),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _earningsTab() {
    final summary = (_earnings?['summary'] as Map?) ?? {};
    final delivered = _mine.where((o) => o['status'] == 'DELIVERED').toList();
    final today = DateTime.now();
    final todayCents = delivered
        .where((o) {
          final d = DateTime.tryParse('${o['deliveredAt']}')?.toLocal();
          return d != null && d.year == today.year && d.month == today.month && d.day == today.day;
        })
        .fold<int>(0, (s, o) => s + (asInt(o['courierFeeCents']) ?? 0));
    Widget stat(String label, dynamic cents) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              Text(euro(context, cents), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
        );
    return RefreshIndicator(
      onRefresh: () async => Future.wait([_loadEarnings(), _loadMine()]),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          stat(tr(context, 'Today', 'Tänään'), todayCents),
          const SizedBox(width: 10),
          stat(tr(context, 'This week (paid)', 'Tällä viikolla'), summary['paidThisWeekCents']),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat(tr(context, 'Paid out', 'Maksettu'), summary['paidCents']),
          const SizedBox(width: 10),
          stat(tr(context, 'Waiting', 'Odottaa'), (asInt(summary['scheduledCents']) ?? 0) + (asInt(summary['waitingForAccountCents']) ?? 0)),
        ]),
        if ((asInt(summary['waitingForAccountCents']) ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr(context, 'Set up payouts to receive the money you have earned.', 'Ota tilitykset käyttöön saadaksesi ansaitsemasi rahat.'),
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutsScreen()));
            _loadEarnings();
          },
          icon: const Icon(Icons.account_balance_outlined),
          label: Text(tr(context, 'Payouts and bank details', 'Tilitykset ja pankkitiedot')),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'Recent deliveries', 'Viimeisimmät toimitukset'), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final o in delivered.take(30))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${o['store']?['name'] ?? ''} · #${o['id']}'),
            subtitle: Text(_when(o['deliveredAt'])),
            trailing: Text(euro(context, o['courierFeeCents']), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
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
            Icon(icon, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
          ]),
        ),
      );
}
