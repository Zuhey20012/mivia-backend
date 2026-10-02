import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
import '../core/delete_account_tile.dart';
import '../services/socket_service.dart';
import 'chatbot.dart';
import 'drops_manager.dart';
import 'payouts_screen.dart';
import 'product_editor.dart';
import 'returns_manager.dart';
import 'store_setup.dart';

/// The store owner's home: incoming orders, products, drops and the store itself.
class VendorDashboard extends StatefulWidget {
  const VendorDashboard({super.key});

  @override
  State<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends State<VendorDashboard> with SingleTickerProviderStateMixin {
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
  }

  @override
  void dispose() {
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
    await _loadOrders();
  }

  Future<void> _loadOrders() async {
    final res = await _api.get('/orders');
    if (!mounted || !res.ok) return;
    setState(() => _orders = ((res.data['orders'] as List?) ?? []).map((o) => Map<String, dynamic>.from(o)).toList());
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
        backgroundColor: Colors.white,
        titleSpacing: 16,
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryLight,
            backgroundImage: _store?['logoUrl'] != null ? CachedNetworkImageProvider(_store!['logoUrl']) : null,
            child: _store?['logoUrl'] == null ? const Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 20) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_store?['name'] ?? 'Malvoya Store', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              Text(
                _store?['isVerified'] == true ? tr(context, 'Live — customers can order', 'Julkaistu — asiakkaat voivat tilata') : tr(context, 'In review — not visible yet', 'Tarkistuksessa — ei vielä näkyvissä'),
                style: TextStyle(fontSize: 11.5, color: _store?['isVerified'] == true ? AppTheme.primary : AppTheme.warning, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr(context, 'Orders', 'Tilaukset')),
              if (newOrders > 0) ...[
                const SizedBox(width: 6),
                CircleAvatar(radius: 9, backgroundColor: AppTheme.accent, child: Text('$newOrders', style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800))),
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
          if (_orders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Text(
                _store?['isVerified'] == true
                    ? tr(context, 'No orders yet. New orders appear here the moment they are paid, with a sound and a notification.', 'Ei vielä tilauksia. Uudet tilaukset näkyvät täällä heti maksun jälkeen.')
                    : tr(context, 'Your store is in review. Add products and drops meanwhile — they go live when you are approved.', 'Kauppasi on tarkistuksessa. Lisää sillä välin tuotteita ja julkaisuja — ne julkaistaan hyväksynnän jälkeen.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
          for (final o in active) _orderCard(o),
          if (done.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(tr(context, 'Earlier', 'Aiemmat'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
          for (final o in done) _orderCard(o),
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final status = o['status'];
    final items = (o['items'] as List?) ?? [];
    final created = DateTime.tryParse('${o['createdAt']}')?.toLocal();
    final (label, color) = switch (status) {
      'PENDING' => (tr(context, 'New — accept or decline', 'Uusi — hyväksy tai hylkää'), AppTheme.accent),
      'CONFIRMED' => (tr(context, 'Accepted — pack it', 'Hyväksytty — pakkaa'), AppTheme.primary),
      'PROCESSING' => (tr(context, 'Ready — waiting for courier', 'Valmis — odottaa kuriiria'), AppTheme.primary),
      'SHIPPED' => (tr(context, 'With the courier', 'Kuriirilla'), AppTheme.primary),
      'DELIVERED' => (tr(context, 'Delivered', 'Toimitettu'), AppTheme.textSecondary),
      _ => (tr(context, 'Cancelled / refunded', 'Peruttu / hyvitetty'), AppTheme.textSecondary),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status == 'PENDING' ? AppTheme.accent : AppTheme.divider, width: status == 'PENDING' ? 1.5 : 1),
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
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          const Divider(height: 20),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${i['quantity']}×  ${i['product']?['name'] ?? ''}'
                '${i['variant'] != null ? '  ·  ${[i['variant']['size'], i['variant']['color']].where((x) => x != null).join(' · ')}' : ''}',
                style: const TextStyle(fontSize: 14.5),
              ),
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
          return InkWell(
            onTap: () => _editProduct(p),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 78,
                    child: images.isEmpty ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.image_outlined, color: AppTheme.primary)) : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(euro(context, p['salePriceCents']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      [
                        stock == 0 ? tr(context, 'Sold out', 'Loppu') : '$stock ${tr(context, 'in stock', 'varastossa')}',
                        if (variants.isNotEmpty) '${variants.length} ${tr(context, 'options', 'vaihtoehtoa')}',
                        if (p['isAvailable'] == false) tr(context, 'Hidden', 'Piilotettu'),
                        if (images.isEmpty) tr(context, 'No photo', 'Ei kuvaa'),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: stock == 0 || images.isEmpty ? AppTheme.accent : AppTheme.textSecondary),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
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
