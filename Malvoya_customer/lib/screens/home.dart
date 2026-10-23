import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'store_detail.dart';
import 'category_detail.dart';
import 'order_detail.dart';
import 'location_selector_modal.dart';
import 'notification_center_drawer.dart';
import 'returns_screen.dart';
import 'search.dart';
import '../core/delivery_location.dart';
import '../core/network_status.dart';
import '../core/store_hours.dart';
import 'package:shimmer/shimmer.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../widgets/app_image.dart';
import '../core/notification_primer.dart';

class HomeScreen extends StatefulWidget {
  /// Switches the app to the Drops tab.
  final VoidCallback? onOpenDrops;

  /// Ticks whenever Home is shown again (tab switch, back from checkout or an order), so the
  /// active-order card is fresh.
  final ValueListenable<int>? visible;
  const HomeScreen({super.key, this.onOpenDrops, this.visible});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Category {
  final String name;
  final IconData icon;
  final Color tile;
  final Color hue;
  const _Category(this.name, this.icon, this.tile, this.hue);
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List stores = [];
  bool loading = true;
  bool error = false;
  bool hasActiveOrder = false;
  Map<String, dynamic>? activeOrder;
  /// The active delivery address; empty until the customer picks one (never a made-up default).
  String _currentDeliveryCity = '';

  // "Tell me when Malvoya opens near me"
  bool _alertSaved = false;
  bool _alertBusy = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _categories = [
    _Category('Clothing', Icons.checkroom_rounded, AppTheme.lilac, AppTheme.primary),
    _Category('Shoes', Icons.snowshoeing_rounded, AppTheme.clay, AppTheme.clayInk),
    _Category('Bags', Icons.shopping_bag_outlined, AppTheme.mint, AppTheme.moss),
    _Category('Accessories', Icons.watch_outlined, AppTheme.sunshineLight, MPalette.amberInk),
    _Category('Jewelry', Icons.diamond_outlined, AppTheme.lilac, AppTheme.primary),
    _Category('Vintage', Icons.auto_awesome_outlined, AppTheme.peach, AppTheme.lingon),
    _Category('Beauty', Icons.spa_outlined, AppTheme.peach, AppTheme.lingon),
    _Category('Home', Icons.chair_outlined, AppTheme.clay, AppTheme.clayInk),
    _Category('Returns', Icons.assignment_return_outlined, AppTheme.sand, AppTheme.inkSecondary),
  ];

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
      fetchStores();
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
    final messenger = ScaffoldMessenger.of(context);
    if (!auth.isAuthenticated) {
      messenger.showSnackBar(SnackBar(content: Text(tr(context, 'Sign in or create an account to get a notification.', 'Kirjaudu tai luo tili saadaksesi ilmoituksen.'))));
      return;
    }
    final loc = DeliveryLocation.instance;
    if (!_alertSaved && !loc.hasCoordinates) {
      messenger.showSnackBar(SnackBar(content: Text(tr(context, 'Pin your address on the map first.', 'Merkitse ensin osoitteesi kartalle.'))));
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
    if (!res.ok) messenger.showSnackBar(SnackBar(content: Text(res.errorText(context) ?? tr(context, 'Something went wrong', 'Jokin meni vikaan'))));
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
    fetchStores();
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
    setState(() {
      hasActiveOrder = activeList.isNotEmpty;
      activeOrder = activeList.isNotEmpty ? Map<String, dynamic>.from(activeList.first) : null;
    });
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

  Future<void> fetchStores() async {
    try {
      final q = DeliveryLocation.instance.query;
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/stores').replace(queryParameters: q.isEmpty ? null : q),
              headers: AppLanguage.headers)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          stores = data['stores'] ?? [];
          loading = false;
          error = false;
        });
      } else {
        setState(() {
          error = true;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = true;
          loading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([fetchStores(), checkActiveOrders()]);
  }

  void _openCategory(String name) {
    Haptics.light();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => name == 'Returns' ? const ReturnsScreen() : CategoryDetailScreen(categoryName: name)),
    );
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
    final textPrimary = AppTheme.primaryText(context);
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
                borderRadius: BorderRadius.circular(14),
                onTap: _pickAddress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: MSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('deliveringTo'),
                        style: TextStyle(
                          color: AppTheme.isDarkMode(context) ? MPalette.malvaOnDark : AppTheme.primary,
                          fontSize: MTextSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _addressLabel(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.2),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: textPrimary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: MSpace.sm),
          _roundButton(
            context,
            icon: Icons.notifications_none_rounded,
            label: tr(context, 'Updates', 'Ilmoitukset'),
            onTap: () {
              Haptics.light();
              NotificationCenterDrawer.show(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _roundButton(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    return Tooltip(
      message: label,
      child: Material(
        color: AppTheme.cardBackground(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MRadius.md),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(MRadius.md),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22, color: AppTheme.primaryText(context))),
        ),
      ),
    );
  }

  Widget _searchPill(BuildContext context) {
    final sub = AppTheme.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, 10, MSpace.lg, MSpace.xs),
      child: Material(
        color: AppTheme.inputBackground(context),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            Haptics.selection();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
          },
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 18),
                Icon(Icons.search_rounded, color: sub, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, 'Search items and stores', 'Hae tuotteita ja kauppoja'),
                    style: TextStyle(color: sub, fontSize: MTextSize.bodyL, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Active order ─────────────────────────────────────────────────────────
  /// Shown only while you have a real order on its way.
  Widget _activeOrderCard(BuildContext context) {
    final order = activeOrder;
    if (!hasActiveOrder || order == null) return const SizedBox.shrink();
    final label = switch (order['status']) {
      'PENDING' => tr(context, 'Waiting for the store', 'Odottaa kauppaa'),
      'CONFIRMED' => tr(context, 'Accepted by the store', 'Kauppa hyväksyi'),
      'PROCESSING' => tr(context, 'Being packed', 'Pakataan'),
      _ => tr(context, 'On its way to you', 'Matkalla sinulle'),
    };
    final window = order['status'] == 'SHIPPED' ? null : scheduledWindow(context, order['scheduledStart'], order['scheduledEnd']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, 14, MSpace.lg, 0),
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: () {
            Haptics.selection();
            Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: asInt(order['id'])!)));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                      Text(label, style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
                      Text([order['store']?['name'] ?? '', '#${order['id']}', if (window != null) window].join(' · '),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.onBrand.withValues(alpha: 0.7), fontSize: MTextSize.label)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(20)),
                  child: Text(tr(context, 'Track', 'Seuraa'),
                      style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: MTextSize.label)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bento: Drops + two favourite shelves ────────────────────────────────
  Widget _bento(BuildContext context, AppLocalizations l10n) {
    // Grows with the phone's text size (up to 1.5×) so the labels never overflow
    final grow = (MediaQuery.textScalerOf(context).scale(100) / 100).clamp(1.0, 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, 18, MSpace.lg, 0),
      child: SizedBox(
        height: 214 * grow,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _bentoTile(
                context,
                color: AppTheme.primary,
                onTap: () {
                  Haptics.light();
                  widget.onOpenDrops?.call();
                },
                child: Stack(
                  children: [
                    Positioned(
                      right: -18,
                      bottom: 26,
                      child: Icon(Icons.play_circle_outline_rounded, size: 120, color: AppTheme.onBrand.withValues(alpha: 0.18)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(MRadius.sm)),
                          child: Text(tr(context, 'Watch & shop', 'Katso ja osta'),
                              style: const TextStyle(color: AppTheme.ink, fontSize: MTextSize.caption, fontWeight: FontWeight.w800)),
                        ),
                        const Spacer(),
                        Flexible(
                          flex: 4,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              tr(context, 'Drops\nnear you', 'Dropit\nlähelläsi'),
                              style: AppTheme.display(context, size: 26, color: MPalette.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _shelfTile(context, l10n, 'Second Hand', Icons.recycling_rounded, AppTheme.sunshine, AppTheme.ink),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _shelfTile(
                      context,
                      l10n,
                      'Eco-Friendly',
                      Icons.eco_outlined,
                      AppTheme.pastel(context, AppTheme.mint, AppTheme.emerald),
                      AppTheme.isDarkMode(context) ? MPalette.mossOnDark : MPalette.greenDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bentoTile(BuildContext context, {required Color color, required VoidCallback onTap, required Widget child}) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: child)),
    );
  }

  Widget _shelfTile(BuildContext context, AppLocalizations l10n, String name, IconData icon, Color bg, Color fg) {
    return _bentoTile(
      context,
      color: bg,
      onTap: () => _openCategory(name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 26),
          const Spacer(),
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Text(l10n.translateCategory(name), maxLines: 1, style: AppTheme.display(context, size: 18, color: fg)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Categories ───────────────────────────────────────────────────────────
  Widget _categoryRow(BuildContext context, AppLocalizations l10n) {
    final textPrimary = AppTheme.primaryText(context);
    final dark = AppTheme.isDarkMode(context);
    return SizedBox(
      // Icon tile + label; the label line grows with the phone's text size
      height: 82 + MediaQuery.textScalerOf(context).scale(18),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = _categories[i];
          final label = l10n.translateCategory(c.name);
          return Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => _openCategory(c.name),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: AppTheme.pastel(context, c.tile, c.hue),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(c.icon, size: 28, color: dark ? Color.lerp(c.hue, MPalette.white, 0.45) : c.hue),
                    ),
                    const SizedBox(height: 7),
                    Text(label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.caption, color: textPrimary)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Stores ───────────────────────────────────────────────────────────────
  Widget _storeCard(BuildContext context, Map<String, dynamic> store) {
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final reviews = asInt(store['totalReviews']) ?? 0;
    final eta = etaWindow(store);
    final km = store['distanceKm'];
    final closed = closedLabel(context, store);

    return Padding(
      padding: const EdgeInsets.only(bottom: MSpace.lg),
      child: Material(
        color: AppTheme.cardBackground(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          side: BorderSide(color: AppTheme.cardBorder(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.light();
            Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
          },
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
                        color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk),
                        alignment: Alignment.center,
                        child: store['logoUrl'] != null
                            ? CircleAvatar(radius: 34, backgroundImage: sizedImageProvider(context, store['logoUrl'], 68))
                            : Icon(Icons.storefront_outlined, size: 48, color: AppTheme.clayInk.withValues(alpha: 0.8)),
                      ),
                    if (closed != null)
                      Container(
                        color: MPalette.white.withValues(alpha: AppTheme.isDarkMode(context) ? 0.12 : 0.45),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.sm),
                          decoration: BoxDecoration(color: AppTheme.ink, borderRadius: BorderRadius.circular(MRadius.md)),
                          child: Text(closed, style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w800, fontSize: MTextSize.label)),
                        ),
                      ),
                    if (eta != null && closed == null)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded, size: 15, color: AppTheme.ink),
                              const SizedBox(width: MSpace.xs),
                              Text(eta, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: MTextSize.caption)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.lg, 14, MSpace.lg, MSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(store['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
                        ),
                        if (reviews > 0) ...[
                          const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
                          const SizedBox(width: 3),
                          Text('${store['rating']} ($reviews)',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label, color: textPrimary)),
                        ] else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: MSpace.xs),
                            decoration: BoxDecoration(
                              color: AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(tr(context, 'New', 'Uusi'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: MTextSize.caption,
                                  color: AppTheme.isDarkMode(context) ? MPalette.malvaOnDark : AppTheme.primary,
                                )),
                          ),
                      ],
                    ),
                    if ((store['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(store['description'],
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSecondary, fontSize: MTextSize.label, height: 1.35)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _meta(Icons.delivery_dining_outlined, '${euro(context, store['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}', textSecondary),
                        if (km != null) _meta(Icons.near_me_outlined, '$km km', textSecondary),
                        if (store['sellerType'] == 'PRIVATE') _meta(Icons.person_outline_rounded, tr(context, 'Private seller', 'Yksityinen myyjä'), textSecondary),
                      ],
                    ),
                    if (!DeliveryLocation.instance.hasCoordinates)
                      Padding(
                        padding: const EdgeInsets.only(top: MSpace.sm),
                        child: Text(
                          tr(context, 'Pin your address on the map to see the exact delivery fee and time.',
                              'Merkitse osoitteesi kartalle nähdäksesi tarkan toimitusmaksun ja -ajan.'),
                          style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
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
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: MTextSize.label)),
        ],
      );

  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(MSpace.xxl, 28, MSpace.xxl, 26),
      decoration: BoxDecoration(
        color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppTheme.sunshine, shape: BoxShape.circle),
            child: const Icon(Icons.storefront_outlined, color: AppTheme.ink, size: 30),
          ),
          const SizedBox(height: 14),
          Text(l10n.translate('launchingCityTitle'), textAlign: TextAlign.center, style: AppTheme.display(context, size: 20)),
          const SizedBox(height: MSpace.sm),
          Text(
            l10n.translate('launchingCitySubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.bodyM, height: 1.45),
          ),
          const SizedBox(height: 18),
          if (_alertSaved) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_active_rounded, color: AppTheme.success, size: 20),
                const SizedBox(width: MSpace.sm),
                Flexible(
                  child: Text(tr(context, 'We will tell you when a store opens near you.', 'Kerromme, kun lähellesi avautuu kauppa.'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                ),
              ],
            ),
            TextButton(onPressed: _alertBusy ? null : _toggleLaunchAlert, child: Text(tr(context, 'Stop reminding me', 'Lopeta muistutukset'))),
          ] else
            ElevatedButton.icon(
              onPressed: _alertBusy ? null : _toggleLaunchAlert,
              icon: const Icon(Icons.notifications_none_rounded),
              label: Text(tr(context, 'Notify me when it opens here', 'Ilmoita kun täällä aukeaa')),
            ),
        ],
      ),
    );
  }

  Widget _shimmerCard(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.lg),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Shimmer.fromColors(
        baseColor: isDark ? MPalette.nightSurfaceVariant : AppTheme.sand,
        highlightColor: isDark ? MPalette.nightRaised : MPalette.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 136, width: double.infinity, color: MPalette.white),
            Padding(
              padding: const EdgeInsets.all(MSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 18, width: 180, decoration: BoxDecoration(color: MPalette.white, borderRadius: BorderRadius.circular(9))),
                  const SizedBox(height: 10),
                  Container(height: 14, width: 120, decoration: BoxDecoration(color: MPalette.white, borderRadius: BorderRadius.circular(7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xxl, MSpace.lg, MSpace.md),
        child: Text(text, style: AppTheme.display(context, size: 21)),
      );

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _refresh,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                // Room for the floating tab bar and bag bar
                padding: EdgeInsets.only(bottom: bottomInset + 86),
                children: [
                  _header(context, l10n),
                  _searchPill(context),
                  _activeOrderCard(context),
                  _bento(context, l10n),
                  _sectionTitle(context, l10n.translate('categories')),
                  _categoryRow(context, l10n),
                  _sectionTitle(context, l10n.translate('storesNearYou')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                    child: Column(
                      children: [
                        if (loading)
                          ...List.generate(2, (_) => _shimmerCard(context, isDark))
                        else if (error)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Column(
                              children: [
                                Icon(Icons.wifi_off_rounded, size: 44, color: textSecondary),
                                const SizedBox(height: 14),
                                Text(l10n.translate('couldNotLoadStores'),
                                    style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      loading = true;
                                      error = false;
                                    });
                                    fetchStores();
                                  },
                                  style: ElevatedButton.styleFrom(minimumSize: const Size(160, 50)),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(tr(context, 'Try again', 'Yritä uudelleen')),
                                ),
                              ],
                            ),
                          )
                        else if (stores.isEmpty)
                          _emptyState(context, l10n)
                        else
                          ...stores.map((s) => _storeCard(context, Map<String, dynamic>.from(s))),
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
