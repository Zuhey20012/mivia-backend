import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../core/catalog.dart';
import '../core/delivery_location.dart';
import '../core/network_status.dart';
import '../core/store_hours.dart';
import '../core/notification_primer.dart';
import '../widgets/app_image.dart';
import 'category_detail.dart';
import 'location_selector_modal.dart';
import 'notification_center_drawer.dart';
import 'order_detail.dart';
import 'orders.dart';
import 'product_detail.dart';
import 'returns_screen.dart';
import 'search.dart';
import 'size_shade_help_screen.dart';
import 'store_detail.dart';
import 'support_hub_screen.dart';

/// Home (docs/design/home-and-drops-redesign.md §3, category-sections-v2.md §6): address, search,
/// the audience switch, the active order, "Shop by category" from the API, the services row,
/// collections, product rails and the shops near you. Every section comes from the API and hides
/// when it has nothing to show. Drops live only in their own tab.
class HomeScreen extends StatefulWidget {
  /// Switches the app to the Drops tab (kept for callers; Home no longer promotes Drops).
  final VoidCallback? onOpenDrops;

  /// Ticks whenever Home is shown again (tab switch, back from checkout or an order), so the
  /// active-order card is fresh.
  final ValueListenable<int>? visible;
  const HomeScreen({super.key, this.onOpenDrops, this.visible});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> stores = [];
  bool loading = true;
  bool error = false;
  Map<String, dynamic>? activeOrder;

  /// The active delivery address; empty until the customer picks one (never a made-up default).
  String _currentDeliveryCity = '';

  // "Tell me when Malvoya opens near me"
  bool _alertSaved = false;
  bool _alertBusy = false;

  // Catalogue (API 2.12)
  AudienceChoice _audience = homeAudience.value;
  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;
  double? _reachKm;
  List<Map<String, dynamic>> _collections = [];
  List<Map<String, dynamic>> _newIn = [];
  List<Map<String, dynamic>> _secondHand = [];

  /// Numbers each catalogue load, so an older answer never replaces a newer one.
  int _catalogRequest = 0;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.12).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    DeliveryLocation.instance.addListener(_onLocationChanged);
    NetworkStatus.instance.addListener(_onNetwork);
    widget.visible?.addListener(checkActiveOrders);
    DeliveryLocation.instance.load().then((_) {
      final addr = DeliveryLocation.instance.address;
      if (addr != null && addr.isNotEmpty && mounted) setState(() => _currentDeliveryCity = addr);
      _loadAll();
    });
    checkActiveOrders();
    _loadLaunchAlert();
  }

  Future<void> _loadLaunchAlert() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) return;
    final res = await ApiClient(auth).get('/me/launch-alert');
    if (mounted && res.ok) setState(() => _alertSaved = res.data['alert'] != null && res.data['alert']['notifiedAt'] == null);
  }

  Future<void> _toggleLaunchAlert() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      MSnack.show(context, tr(context, 'Sign in or create an account to get a notification.', 'Kirjaudu tai luo tili saadaksesi ilmoituksen.'));
      return;
    }
    final loc = DeliveryLocation.instance;
    if (!_alertSaved && !loc.hasCoordinates) {
      MSnack.show(context, tr(context, 'Pin your address on the map first.', 'Merkitse ensin osoitteesi kartalle.'));
      _pickAddress();
      return;
    }
    Haptics.medium();
    setState(() => _alertBusy = true);
    final api = ApiClient(auth);
    final res = _alertSaved
        ? await api.delete('/me/launch-alert')
        : await api.put('/me/launch-alert', {'latitude': loc.lat, 'longitude': loc.lng, 'area': _currentDeliveryCity});
    if (!mounted) return;
    setState(() {
      _alertBusy = false;
      if (res.ok) _alertSaved = !_alertSaved;
    });
    // The alert arrives as a notification: explain and ask now, if the phone does not allow them yet
    if (res.ok && _alertSaved) unawaited(NotificationPrimer.maybeAsk(context, reason: PrimerReason.storeAlert, force: true));
    if (!res.ok) MSnack.error(context, res.errorText(context) ?? tr(context, 'Something went wrong', 'Jokin meni vikaan'));
  }

  /// Back online after a failed load: try again without the customer having to pull to refresh.
  void _onNetwork() {
    if (!mounted || !NetworkStatus.instance.online || !error) return;
    setState(() => loading = true);
    _refresh();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() => loading = true);
    _loadAll();
  }

  /// The order to track: paid and on its way. Checkouts left unpaid (PENDING with a pending or
  /// failed payment) are not "on the way", so they do not get the Track card.
  Future<void> checkActiveOrders() async {
    if (!mounted) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      if (activeOrder != null) setState(() => activeOrder = null);
      return;
    }
    final res = await ApiClient(auth).get('/orders');
    if (!mounted || !res.ok) return;
    final list = res.data['orders'];
    final activeList = (list is List ? list : const [])
        .whereType<Map>()
        .where((o) => ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status']))
        .where((o) => !(o['status'] == 'PENDING' && (o['paymentStatus'] == 'PENDING' || o['paymentStatus'] == 'FAILED')))
        .toList();
    setState(() => activeOrder = activeList.isNotEmpty ? Map<String, dynamic>.from(activeList.first) : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" in the phone's accessibility settings: keep the courier icon still
    if (MediaQuery.of(context).disableAnimations) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0.5;
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    DeliveryLocation.instance.removeListener(_onLocationChanged);
    NetworkStatus.instance.removeListener(_onNetwork);
    widget.visible?.removeListener(checkActiveOrders);
    _pulseCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic list) => (list is List ? list : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> fetchStores() async {
    final res = await _api.get('/stores', query: {...DeliveryLocation.instance.query, 'limit': '50'});
    if (!mounted) return;
    setState(() {
      loading = false;
      error = !res.ok;
      if (res.ok) stores = _maps(res.data['stores']);
    });
  }

  /// Categories, collections and rails for the current place and audience.
  Future<void> _loadCatalog() async {
    final request = ++_catalogRequest;
    final place = {...DeliveryLocation.instance.query, ..._audience.query};
    setState(() => _categoriesLoading = _categories.isEmpty);
    final results = await Future.wait([
      _api.get('/categories', query: place),
      _api.get('/collections', query: place),
    ]);
    if (!mounted || request != _catalogRequest) return;
    var cats = results[0];
    // Nothing with stock nearby yet: still show the tree so it can be browsed (counts hidden at 0)
    if (cats.ok && _maps(cats.data['categories']).isEmpty) {
      final all = await _api.get('/categories', query: {...place, 'includeEmpty': '1'});
      if (!mounted || request != _catalogRequest) return;
      if (all.ok) cats = all;
    }
    setState(() {
      _categoriesLoading = false;
      if (cats.ok) {
        _categories = _maps(cats.data['categories']);
        final km = cats.data['reach'] is Map ? cats.data['reach']['km'] : null;
        _reachKm = km is num ? km.toDouble() : null;
      }
      _collections = results[1].ok ? _maps(results[1].data['collections']) : [];
    });
    await _loadRails(request);
  }

  /// Shops within delivery reach of the pinned address (the same reach the API counts with).
  Map<int, Map<String, dynamic>> get _nearbyStores {
    if (!DeliveryLocation.instance.hasCoordinates) return const {};
    return {
      for (final s in stores)
        if (s['distanceKm'] is num && (_reachKm == null || (s['distanceKm'] as num) <= _reachKm!) && asInt(s['id']) != null) asInt(s['id'])!: s,
    };
  }

  /// "New in near you" and "Second-hand finds": the newest items of shops within reach, at most two
  /// per shop; a rail with fewer than four items is hidden.
  Future<void> _loadRails(int request) async {
    final nearby = _nearbyStores;
    if (nearby.isEmpty) {
      setState(() {
        _newIn = [];
        _secondHand = [];
      });
      return;
    }
    final base = {..._audience.query, 'sort': 'newest', 'limit': '50', 'page': '1'};
    final results = await Future.wait([
      _api.get('/products/search', query: base),
      _api.get('/products/search', query: {...base, 'secondHand': 'true'}),
    ]);
    if (!mounted || request != _catalogRequest) return;
    List<Map<String, dynamic>> rail(ApiResult res) {
      if (!res.ok) return [];
      final perShop = <int, int>{};
      final out = <Map<String, dynamic>>[];
      for (final p in _maps(res.data['products'])) {
        final storeId = asInt(p['storeId'] ?? p['store']?['id']);
        if (storeId == null || !nearby.containsKey(storeId) || p['inStock'] == false) continue;
        if ((perShop[storeId] ?? 0) >= 2) continue;
        perShop[storeId] = (perShop[storeId] ?? 0) + 1;
        out.add(p);
        if (out.length >= 12) break;
      }
      return out.length >= 4 ? out : [];
    }

    setState(() {
      _newIn = rail(results[0]);
      _secondHand = rail(results[1]);
    });
  }

  Future<void> _loadAll() async {
    await fetchStores();
    if (mounted) await _loadCatalog();
  }

  Future<void> _refresh() async {
    await Future.wait([_loadAll(), checkActiveOrders()]);
  }

  void _setAudience(AudienceChoice a) {
    if (a == _audience) return;
    Haptics.selection();
    setState(() => _audience = a);
    homeAudience.value = a;
    _loadCatalog();
  }

  void _push(Widget screen) {
    Haptics.light();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _pickAddress() {
    Haptics.selection();
    showMSheet(context, builder: (_) => LocationSelectorModal(
        currentLocation: _currentDeliveryCity,
        onLocationSelected: (newCity) => setState(() => _currentDeliveryCity = newCity),
      ), transparent: true, isScrollControlled: true, useSafeArea: false);
  }

  // ── Header ───────────────────────────────────────────────────────────────
  String _addressLabel(BuildContext context) => _currentDeliveryCity.isEmpty
      ? tr(context, 'Choose your address', 'Valitse osoitteesi')
      : _currentDeliveryCity;

  Widget _header(BuildContext context, AppLocalizations l10n) {
    final c = context.mColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.md, MSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${l10n.translate('deliveringTo')} ${_addressLabel(context)}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: MRadius.brSm,
                onTap: _pickAddress,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: MSpace.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.translate('deliveringTo'), style: MType.caption.copyWith(color: c.primary, fontWeight: FontWeight.w700)),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _addressLabel(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MType.title.copyWith(fontFamily: MFonts.body, fontWeight: FontWeight.w800, color: c.onSurface),
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: c.onSurface),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: MSpace.sm),
          Tooltip(
            message: tr(context, 'Updates', 'Ilmoitukset'),
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(borderRadius: MRadius.brMd, side: BorderSide(color: c.outline)),
              child: InkWell(
                borderRadius: MRadius.brMd,
                onTap: () {
                  Haptics.light();
                  NotificationCenterDrawer.show(context);
                },
                child: SizedBox(width: kMinTouchTarget, height: kMinTouchTarget, child: Icon(Icons.notifications_none_rounded, size: 22, color: c.onSurface)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchPill(BuildContext context) {
    final c = context.mColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.xs),
      child: Semantics(
        button: true,
        label: tr(context, 'Search lipstick, dresses, shops', 'Hae huulipunia, mekkoja, kauppoja'),
        excludeSemantics: true,
        child: Material(
          color: c.surfaceVariant,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              Haptics.selection();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.sm),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: c.onSurfaceVariant, size: 22),
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: Text(
                        tr(context, 'Search lipstick, dresses, shops', 'Hae huulipunia, mekkoja, kauppoja'),
                        style: MType.bodyL.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Audience switch ──────────────────────────────────────────────────────
  Widget _audienceSwitch(BuildContext context) {
    final a = _audience;
    final top = <(String, String, AudienceChoice)>[
      ('all', tr(context, 'All', 'Kaikki'), AudienceChoice.all),
      ('women', tr(context, 'Women', 'Naiset'), const AudienceChoice(audience: 'WOMEN')),
      ('men', tr(context, 'Men', 'Miehet'), const AudienceChoice(audience: 'MEN')),
      ('kids', tr(context, 'Kids', 'Lapset'), const AudienceChoice(audience: 'KIDS')),
      ('teens', tr(context, 'Teens', 'Nuoret'), const AudienceChoice(ageGroup: 'TEEN')),
    ];
    final ages = <(String, String)>[
      ('BABY', tr(context, 'Baby 0–2', 'Vauvat 0–2 v')),
      ('TODDLER', tr(context, 'Toddler 2–4', 'Taaperot 2–4 v')),
      ('KIDS', tr(context, 'Kids 4–8', 'Lapset 4–8 v')),
      ('JUNIOR', tr(context, 'Junior 8–14', 'Juniorit 8–14 v')),
    ];
    Widget row(List<Widget> chips) => SizedBox(
          height: 52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: MSpace.sm),
            itemBuilder: (_, i) => Center(child: chips[i]),
          ),
        );
    return Semantics(
      label: tr(context, 'Show products for', 'Näytä tuotteet'),
      container: true,
      child: Column(children: [
        row([
          for (final t in top)
            MChip(label: t.$2, selected: a.key == t.$1, showCheck: false, onSelected: (_) => _setAudience(t.$3)),
        ]),
        if (a.isKids)
          row([
            for (final g in ages)
              MChip(
                label: g.$2,
                selected: a.ageGroup == g.$1,
                onSelected: (on) => _setAudience(AudienceChoice(audience: 'KIDS', ageGroup: on ? g.$1 : null)),
              ),
          ]),
      ]),
    );
  }

  // ── Active order ─────────────────────────────────────────────────────────
  /// Shown only while you have a real order on its way.
  Widget _activeOrderCard(BuildContext context) {
    final order = activeOrder;
    if (order == null) return const SizedBox.shrink();
    final label = switch (order['status']) {
      'PENDING' => tr(context, 'Waiting for the store', 'Odottaa kauppaa'),
      'CONFIRMED' => tr(context, 'Accepted by the store', 'Kauppa hyväksyi'),
      'PROCESSING' => tr(context, 'Being packed', 'Pakataan'),
      _ => tr(context, 'On its way to you', 'Matkalla sinulle'),
    };
    final window = order['status'] == 'SHIPPED' ? null : scheduledWindow(context, order['scheduledStart'], order['scheduledEnd']);
    final c = context.mColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, 0),
      child: Material(
        color: AppTheme.primary,
        borderRadius: MRadius.brLg,
        child: InkWell(
          borderRadius: MRadius.brLg,
          onTap: () => _push(OrderDetailScreen(orderId: asInt(order['id'])!)),
          child: Padding(
            padding: const EdgeInsets.all(MSpace.md),
            child: Row(
              children: [
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: MPalette.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: const Icon(Icons.delivery_dining_rounded, color: AppTheme.onBrand, size: 26),
                  ),
                ),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: MType.bodyL.copyWith(color: AppTheme.onBrand, fontWeight: FontWeight.w800)),
                      Text([order['store']?['name'] ?? '', '#${order['id']}', if (window != null) window].join(' · '),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: MType.label.copyWith(color: AppTheme.onBrand.withValues(alpha: 0.75), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: MSpace.sm),
                  decoration: BoxDecoration(color: c.sunshine, borderRadius: MRadius.pillRadius),
                  child: Text(tr(context, 'Track', 'Seuraa'), style: MType.label.copyWith(color: c.onSunshine, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shop by category ─────────────────────────────────────────────────────
  Widget _categoryGrid(BuildContext context) {
    if (_categoriesLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
        child: MSkeleton(
          child: Column(children: [
            for (var r = 0; r < 2; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: MSpace.sm),
                child: Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: MSpace.sm),
                    const Expanded(child: MSkeletonBox(height: 96, radius: MRadius.md)),
                  ],
                ]),
              ),
          ]),
        ),
      );
    }
    if (_categories.isEmpty) return const SizedBox.shrink();
    final shown = _categories.take(9).toList();
    final rows = <List<Map<String, dynamic>>>[
      for (var i = 0; i < shown.length; i += 3) shown.sublist(i, (i + 3).clamp(0, shown.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MSectionHeader(tr(context, 'Shop by category', 'Osta kategorioittain')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
          child: Column(children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: MSpace.sm),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: MSpace.sm),
                      Expanded(child: i < r.length ? _categoryTile(context, r[i]) : const SizedBox.shrink()),
                    ],
                  ]),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: MButton(
                label: tr(context, 'All categories', 'Kaikki kategoriat'),
                variant: MButtonVariant.text,
                size: MButtonSize.sm,
                icon: Icons.grid_view_rounded,
                onPressed: () => _push(AllCategoriesScreen(categories: _categories, audience: _audience)),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _categoryTile(BuildContext context, Map<String, dynamic> cat) {
    final tile = catalogTile(context, cat['tileColor'] as String?);
    final name = catalogName(context, cat['name']);
    final count = asInt(cat['count']) ?? 0;
    return Semantics(
      button: true,
      label: count > 0 ? tr(context, '$name, $count items', '$name, $count tuotetta') : name,
      excludeSemantics: true,
      child: Material(
        color: tile.fill,
        borderRadius: MRadius.brMd,
        child: InkWell(
          borderRadius: MRadius.brMd,
          onTap: () => _push(CategoryScreen(slug: '${cat['slug']}', audience: _audience)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.all(MSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(catalogIcon(cat['icon'] as String?), color: tile.ink, size: 26),
                  const SizedBox(height: MSpace.sm),
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MType.label.copyWith(color: tile.ink, fontWeight: FontWeight.w800)),
                  if (count > 0) Text('$count', style: MType.caption.copyWith(color: tile.ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Services (things people do, not buy): outline tiles ──────────────────
  Widget _services(BuildContext context) {
    final pickup = _nearbyStores.values.where((s) => '${s['address'] ?? ''}'.trim().isNotEmpty).toList();
    final items = <(IconData, String, VoidCallback)>[
      (Icons.assignment_return_outlined, tr(context, 'Returns & refunds', 'Palautukset'), () => _push(const ReturnsScreen())),
      (
        Icons.local_shipping_outlined,
        tr(context, 'Track order', 'Seuraa tilausta'),
        () => _push(activeOrder != null ? OrderDetailScreen(orderId: asInt(activeOrder!['id'])!) : const OrdersScreen()),
      ),
      if (pickup.isNotEmpty) (Icons.storefront_outlined, tr(context, 'Reserve & collect', 'Varaa ja nouda'), () => _push(PickupStoresScreen(stores: pickup))),
      (Icons.straighten_rounded, tr(context, 'Size & shade help', 'Koko- ja sävyapu'), () => _push(const SizeShadeHelpScreen())),
      (Icons.support_agent_rounded, tr(context, 'Help', 'Apua'), () => _push(const SupportHubScreen())),
    ];
    final c = context.mColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MSectionHeader(tr(context, 'Services', 'Palvelut')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: MSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in items)
                Semantics(
                  button: true,
                  label: s.$2,
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: MRadius.brMd,
                    onTap: s.$3,
                    child: SizedBox(
                      width: 84,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: MSpace.xs),
                        child: Column(children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface, border: Border.all(color: c.outlineStrong, width: 1.2)),
                            child: Icon(s.$1, color: c.primary, size: 24),
                          ),
                          const SizedBox(height: MSpace.xs),
                          Text(s.$2, textAlign: TextAlign.center, maxLines: 3, style: MType.caption.copyWith(color: c.onSurface, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Collections ──────────────────────────────────────────────────────────
  void _openCollection(Map<String, dynamic> col) {
    final open = col['open'];
    if (open is Map && open['brands'] != null) {
      _push(BrandsScreen(audience: _audience));
      return;
    }
    _push(ProductGridScreen(title: catalogName(context, col['name']), params: {..._audience.query, 'collection': '${col['slug']}'}));
  }

  Widget _collectionRow(BuildContext context, String title, List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MSectionHeader(title),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final col in list) ...[
                  Builder(builder: (context) {
                    final tile = catalogTile(context, col['tileColor'] as String?);
                    final name = catalogName(context, col['name']);
                    final count = asInt(col['count']) ?? 0;
                    return SizedBox(
                      width: 150,
                      child: Semantics(
                        button: true,
                        label: tr(context, '$name, $count items', '$name, $count tuotetta'),
                        excludeSemantics: true,
                        child: Material(
                          color: tile.fill,
                          borderRadius: MRadius.brLg,
                          child: InkWell(
                            borderRadius: MRadius.brLg,
                            onTap: () => _openCollection(col),
                            child: Padding(
                              padding: const EdgeInsets.all(MSpace.md),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(catalogIcon(col['icon'] as String?), color: tile.ink),
                                const SizedBox(height: MSpace.xl),
                                Text(name, maxLines: 3, style: MType.bodyM.copyWith(fontWeight: FontWeight.w800, color: tile.ink)),
                                const SizedBox(height: MSpace.xs),
                                Text(tr(context, '$count items', '$count tuotetta'), style: MType.caption.copyWith(color: tile.ink)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: MSpace.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Collections other than gifts (own section) and second-hand finds (own rail): the current
  /// season first.
  List<Map<String, dynamic>> get _mainCollections {
    final list = _collections.where((c) => c['group'] != 'gifts' && c['group'] != 'second_hand').toList();
    list.sort((a, b) => (a['group'] == 'season' ? 0 : 1).compareTo(b['group'] == 'season' ? 0 : 1));
    return list;
  }

  List<Map<String, dynamic>> get _giftCollections => _collections.where((c) => c['group'] == 'gifts').toList();

  // ── Product rails ────────────────────────────────────────────────────────
  Widget _rail(BuildContext context, {required String title, required List<Map<String, dynamic>> items, required Map<String, String> seeAll}) {
    if (items.isEmpty) return const SizedBox.shrink();
    final width = (MediaQuery.sizeOf(context).width - MSpace.lg * 2 - MSpace.sm * 2) / 2.5;
    final nearby = _nearbyStores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MSectionHeader(
          title,
          actionLabel: tr(context, 'See all', 'Näytä kaikki'),
          onAction: () => _push(ProductGridScreen(title: title, params: {..._audience.query, ...seeAll})),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in items) ...[
                SizedBox(width: width, child: _RailCard(product: p, store: nearby[asInt(p['storeId'] ?? p['store']?['id'])])),
                const SizedBox(width: MSpace.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Shops near you ───────────────────────────────────────────────────────
  Widget _storeCard(BuildContext context, Map<String, dynamic> store) {
    final c = context.mColors;
    final reviews = asInt(store['totalReviews']) ?? 0;
    final eta = etaWindow(store);
    final km = store['distanceKm'];
    final closed = closedLabel(context, store);

    return Padding(
      padding: const EdgeInsets.only(bottom: MSpace.lg),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: MRadius.brLg, side: BorderSide(color: c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _push(StoreDetailScreen(store: store)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 136,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (store['bannerUrl'] != null)
                      AppImage(store['bannerUrl'])
                    else
                      Container(
                        color: context.mPastels.clay,
                        alignment: Alignment.center,
                        child: store['logoUrl'] != null
                            ? CircleAvatar(radius: 34, backgroundImage: sizedImageProvider(context, store['logoUrl'], 68))
                            : Icon(Icons.storefront_outlined, size: 48, color: context.mPastels.clayInk),
                      ),
                    if (closed != null)
                      Container(
                        color: MPalette.white.withValues(alpha: c.isDark ? 0.12 : 0.45),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: MSpace.sm),
                          decoration: BoxDecoration(color: c.inverseSurface, borderRadius: MRadius.brMd),
                          child: Text(closed, style: MType.label.copyWith(color: c.onInverseSurface, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    if (eta != null && closed == null)
                      Positioned(
                        left: MSpace.md,
                        top: MSpace.md,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.xs),
                          decoration: BoxDecoration(color: c.sunshine, borderRadius: MRadius.brSm),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.schedule_rounded, size: 15, color: c.onSunshine),
                            const SizedBox(width: MSpace.xs),
                            Text(eta, style: MType.caption.copyWith(color: c.onSunshine, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(store['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: MType.title.copyWith(color: c.onSurface)),
                        ),
                        if (reviews > 0) ...[
                          Icon(Icons.star_rounded, size: 18, color: c.warning),
                          const SizedBox(width: 3),
                          Text('${store['rating']} ($reviews)', style: MType.label.copyWith(color: c.onSurface)),
                        ] else
                          MBadge(tr(context, 'New', 'Uusi')),
                      ],
                    ),
                    if ('${store['description'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(store['description'], maxLines: 2, overflow: TextOverflow.ellipsis, style: MType.label.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w400)),
                    ],
                    const SizedBox(height: MSpace.sm),
                    Wrap(
                      spacing: MSpace.md,
                      runSpacing: 6,
                      children: [
                        _meta(Icons.delivery_dining_outlined, '${euro(context, store['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}', c.onSurfaceVariant),
                        if (km != null) _meta(Icons.near_me_outlined, '$km km', c.onSurfaceVariant),
                        if (store['sellerType'] == 'PRIVATE') _meta(Icons.person_outline_rounded, tr(context, 'Private seller', 'Yksityinen myyjä'), c.onSurfaceVariant),
                      ],
                    ),
                    if (!DeliveryLocation.instance.hasCoordinates)
                      Padding(
                        padding: const EdgeInsets.only(top: MSpace.sm),
                        child: Text(
                          tr(context, 'Pin your address on the map to see the exact delivery fee and time.',
                              'Merkitse osoitteesi kartalle nähdäksesi tarkan toimitusmaksun ja -ajan.'),
                          style: MType.caption.copyWith(color: c.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: MSpace.xs),
          Text(text, style: MType.label.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    final c = context.mColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.x3l, MSpace.xxl, MSpace.xxl),
      decoration: BoxDecoration(color: c.sunshineSoft, borderRadius: MRadius.brLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.sunshine, shape: BoxShape.circle),
            child: Icon(Icons.storefront_outlined, color: c.onSunshine, size: 30),
          ),
          const SizedBox(height: MSpace.md),
          Text(l10n.translate('launchingCityTitle'), textAlign: TextAlign.center, style: MType.displayS.copyWith(color: c.onSurface)),
          const SizedBox(height: MSpace.sm),
          Text(l10n.translate('launchingCitySubtitle'), textAlign: TextAlign.center, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
          const SizedBox(height: MSpace.lg),
          if (_alertSaved) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_active_rounded, color: c.success, size: 20),
                const SizedBox(width: MSpace.sm),
                Flexible(
                  child: Text(tr(context, 'We will tell you when a store opens near you.', 'Kerromme, kun lähellesi avautuu kauppa.'),
                      style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
                ),
              ],
            ),
            MButton(label: tr(context, 'Stop reminding me', 'Lopeta muistutukset'), variant: MButtonVariant.text, onPressed: _alertBusy ? null : _toggleLaunchAlert),
          ] else
            MButton(
              label: tr(context, 'Notify me when it opens here', 'Ilmoita kun täällä aukeaa'),
              icon: Icons.notifications_none_rounded,
              loading: _alertBusy,
              onPressed: _toggleLaunchAlert,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final c = context.mColors;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final mainCollections = _mainCollections;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Room for the floating tab bar and bag bar
                padding: EdgeInsets.only(bottom: bottomInset + 96),
                children: [
                  _header(context, l10n),
                  _searchPill(context),
                  _audienceSwitch(context),
                  _activeOrderCard(context),
                  _categoryGrid(context),
                  _services(context),
                  // One seasonal collection first, then the rest of the collections in season
                  _collectionRow(context, tr(context, 'Collections', 'Kokoelmat'), mainCollections),
                  // "Delivered today" needs the API to say same-day delivery is possible; it has no such field yet, so the rail stays hidden
                  _rail(context, title: tr(context, 'New in near you', 'Uutta lähelläsi'), items: _newIn, seeAll: {'sort': 'newest'}),
                  _rail(context, title: tr(context, 'Second-hand finds', 'Käytetyt löydöt'), items: _secondHand, seeAll: {'sort': 'newest', 'secondHand': 'true'}),
                  _collectionRow(context, tr(context, 'Gifts by price', 'Lahjat hinnan mukaan'), _giftCollections),
                  MSectionHeader(l10n.translate('storesNearYou')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                    child: Column(
                      children: [
                        if (loading)
                          for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: MSpace.lg), child: MSkeleton(child: MSkeletonBox(height: 220, radius: MRadius.lg)))
                        else if (error)
                          MStateMessage.error(
                            message: l10n.translate('couldNotLoadStores'),
                            scrollable: false,
                            top: MSpace.lg,
                            onRetry: () {
                              setState(() {
                                loading = true;
                                error = false;
                              });
                              _loadAll();
                            },
                          )
                        else if (stores.isEmpty)
                          _emptyState(context, l10n)
                        else
                          ...stores.map((s) => _storeCard(context, s)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A product in a Home rail: 4:5 photo, name, price (with the unit price), shop and distance, and
/// at most one status chip.
class _RailCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? store;
  const _RailCard({required this.product, this.store});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final images = (product['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final shop = '${product['store']?['name'] ?? store?['name'] ?? ''}';
    final km = store?['distanceKm'];
    final chip = product['isSecondHand'] == true
        ? tr(context, 'Second-hand', 'Käytetty')
        : (((product['certificates'] as List?) ?? const []).isNotEmpty ? tr(context, 'Certified', 'Sertifioitu') : null);
    final unit = UnitPrice.fromJson(product['unitPrice']);
    return Pressable(
      onTap: () {
        Haptics.selection();
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: asInt(product['id'])!)));
      },
      child: Semantics(
        button: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ClipRRect(
                borderRadius: MRadius.brMd,
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: context.mPastels.clay),
                  if (images.isNotEmpty) AppImage(images.first) else Icon(Icons.checkroom_outlined, size: 40, color: context.mPastels.clayInk),
                  if (chip != null) Positioned(left: MSpace.sm, top: MSpace.sm, child: MBadge(chip, tone: MBadgeTone.neutral)),
                ]),
              ),
            ),
            const SizedBox(height: MSpace.sm),
            Text('${product['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
            MPrice.fromPricing(product['pricing'] as Map<String, dynamic>?, size: MPriceSize.sm),
            if (unit != null) MUnitPrice(unit),
            if (shop.isNotEmpty)
              Text(km == null ? shop : '$shop · $km km', maxLines: 1, overflow: TextOverflow.ellipsis, style: MType.caption.copyWith(color: c.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Reserve & collect: shops near you with an address to collect from (pickup needs one).
class PickupStoresScreen extends StatelessWidget {
  final List<Map<String, dynamic>> stores;
  const PickupStoresScreen({super.key, required this.stores});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Reserve & collect', 'Varaa ja nouda'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: MSpace.x4l),
        children: [
          Padding(
            padding: const EdgeInsets.all(MSpace.lg),
            child: Text(
              tr(context, 'These shops near you have an address to collect from. Choose “Collect from shop” at checkout: there is no delivery fee, your order page shows when it is ready and the 6-digit code to show at the till.',
                  'Näillä lähelläsi olevilla kaupoilla on noutopaikka. Valitse kassalla ”Nouto kaupasta”: toimitusmaksua ei ole, ja tilaussivultasi näet, kun tilaus on valmis, sekä 6-numeroisen koodin, jonka näytät kassalla.'),
              style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
            ),
          ),
          for (final s in stores)
            MListTile(
              title: '${s['name'] ?? ''}',
              subtitle: [
                '${s['address'] ?? ''}',
                if (s['distanceKm'] != null) '${s['distanceKm']} km',
                if (closedLabel(context, s) != null) closedLabel(context, s)!,
              ].where((x) => x.isNotEmpty).join(' · '),
              icon: Icons.storefront_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: s))),
            ),
        ],
      ),
    );
  }
}
