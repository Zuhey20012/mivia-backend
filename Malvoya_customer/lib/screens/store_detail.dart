import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../cart.dart';
import '../checkout.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/blocked_users.dart';
import '../core/delivery_location.dart';
import '../core/sign_in.dart';
import '../core/store_hours.dart';
import '../core/strings.dart';
import '../widgets/product_tile.dart';
import '../widgets/skeleton.dart';
import '../widgets/ugc_actions.dart';
import 'drops_feed.dart';
import '../core/haptics.dart';
import '../widgets/app_image.dart';

/// A store: delivery time and fee to your address, who the seller is, their drops, what
/// verified customers say, and everything they sell.
class StoreDetailScreen extends StatefulWidget {
  /// Needs at least `id`; anything else is shown while the full store loads.
  final Map<String, dynamic> store;
  const StoreDetailScreen({super.key, required this.store});

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  late Map<String, dynamic> _store = Map<String, dynamic>.from(widget.store);
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _drops = [];
  List<Map<String, dynamic>> _reviews = [];
  int _reviewTotal = 0;
  bool _loading = true;
  String? _error;

  // "All items" pages through the store's products (24 at a time) as the customer scrolls
  static const _pageSize = 24;
  int _productPage = 0;
  int? _productTotal;
  bool _loadingMore = false;

  int get _id => asInt(widget.store['id'])!;
  bool _followBusy = false;

  Future<void> _toggleFollow() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Sign in to follow stores', 'Kirjaudu sisään seurataksesi kauppoja')),
        action: SnackBarAction(label: tr(context, 'Sign in', 'Kirjaudu'), onPressed: () => openSignIn(context)),
      ));
      return;
    }
    Haptics.light();
    final next = _store['followedByMe'] != true;
    setState(() => _followBusy = true);
    final api = ApiClient(auth);
    final res = next ? await api.put('/stores/$_id/follow') : await api.delete('/stores/$_id/follow');
    if (!mounted) return;
    setState(() {
      _followBusy = false;
      if (res.ok) {
        _store['followedByMe'] = res.data['following'] == true;
        _store['followerCount'] = res.data['followerCount'];
      }
    });
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorText(context)!)));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DeliveryLocation.instance.load();
    if (!mounted) return;
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final results = await Future.wait([
      api.get('/stores/$_id', query: DeliveryLocation.instance.query),
      api.get('/stores/$_id/drops', query: {'limit': '12'}),
      api.get('/stores/$_id/reviews'),
      api.get('/stores/$_id/products', query: {'page': '1', 'limit': '$_pageSize'}),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final store = results[0];
      if (!store.ok) {
        _error = store.errorText(context);
        return;
      }
      _error = null;
      _store = Map<String, dynamic>.from(store.data['store']);
      final page = results[3];
      if (page.ok && page.data['products'] is List) {
        _products = (page.data['products'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
        _productPage = 1;
        _productTotal = asInt(page.data['total']);
      } else {
        // The store's own first products, if the paged list is not available
        _products = ((_store['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
        _productPage = 0;
        _productTotal = null;
      }
      if (results[1].ok) _drops = ((results[1].data['drops'] as List?) ?? []).map((d) => Map<String, dynamic>.from(d)).toList();
      if (results[2].ok) {
        _reviews = ((results[2].data['reviews'] as List?) ?? []).map((r) => Map<String, dynamic>.from(r)).toList();
        _reviewTotal = asInt(results[2].data['total']) ?? _reviews.length;
      }
    });
  }

  bool get _hasMoreProducts => _productPage > 0 && _productTotal != null && _products.length < _productTotal!;

  /// The next page of "All items".
  Future<void> _loadMoreProducts() async {
    if (_loadingMore || !_hasMoreProducts) return;
    setState(() => _loadingMore = true);
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false))
        .get('/stores/$_id/products', query: {'page': '${_productPage + 1}', 'limit': '$_pageSize'});
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (!res.ok || res.data['products'] is! List) return;
      final incoming = (res.data['products'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
      final known = _products.map((p) => asInt(p['id'])).toSet();
      _products.addAll(incoming.where((p) => !known.contains(asInt(p['id']))));
      _productPage++;
      _productTotal = asInt(res.data['total']) ?? _productTotal;
      // An empty page means the list is complete even if the total said otherwise
      if (incoming.isEmpty) _productTotal = _products.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.primaryText(context);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) _loadMoreProducts();
                return false;
              },
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(_store['name'] ?? '',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                    background: _store['bannerUrl'] != null
                        ? AppImage(_store['bannerUrl'])
                        : Container(
                            color: AppTheme.isDarkMode(context) ? const Color(0xFF3A2F42) : AppTheme.primary,
                            child: Center(child: Icon(Icons.storefront_outlined, size: 72, color: Colors.white.withValues(alpha: 0.25))),
                          ),
                  ),
                ),
                if (_error != null)
                  SliverFillRemaining(
                    child: StateMessage.error(
                      message: _error!,
                      top: 60,
                      onRetry: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _load();
                      },
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: _header()),
                  if (_drops.isNotEmpty) SliverToBoxAdapter(child: _dropsStrip()),
                  if (_reviews.isNotEmpty) SliverToBoxAdapter(child: _reviewsBlock()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Text(
                        _productTotal != null && _productTotal! > 0
                            ? tr(context, 'All items ($_productTotal)', 'Kaikki tuotteet ($_productTotal)')
                            : tr(context, 'All items', 'Kaikki tuotteet'),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                      ),
                    ),
                  ),
                  if (_loading)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.58,
                        ),
                        delegate: SliverChildBuilderDelegate((_, __) => const SkeletonProductTile(), childCount: 4),
                      ),
                    )
                  else if (_products.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(children: [
                          Icon(Icons.checkroom_outlined, size: 40, color: AppTheme.secondaryText(context)),
                          const SizedBox(height: 10),
                          Text(tr(context, 'This store has not listed anything yet.', 'Kauppa ei ole vielä lisännyt tuotteita.'),
                              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context))),
                        ]),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, _hasMoreProducts ? 16 : 120 + safeBottom),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.58,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => ProductTile(product: {..._products[i], 'store': _store}, storeName: ''),
                          childCount: _products.length,
                        ),
                      ),
                    ),
                    if (_hasMoreProducts)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 120 + safeBottom),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
                                : TextButton(onPressed: _loadMoreProducts, child: Text(tr(context, 'Show more', 'Näytä lisää'))),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
            ),
          ),
          // Above the phone's gesture/navigation bar
          Positioned(bottom: 20 + safeBottom, left: 16, right: 16, child: _bagBar()),
        ],
      ),
    );
  }

  Widget _header() {
    final muted = AppTheme.secondaryText(context);
    final reviews = asInt(_store['totalReviews']) ?? 0;
    final eta = etaWindow(_store);
    final isPrivate = _store['sellerType'] == 'PRIVATE';
    final closed = closedLabel(context, _store);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (closed != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, color: Color(0xFF8A5A00)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$closed. ${tr(context, 'You can look around and save favourites.', 'Voit katsella ja tallentaa suosikkeja.')}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryText(context), height: 1.35)),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: Text(
                  (asInt(_store['followerCount']) ?? 0) == 1
                      ? tr(context, '1 follower', '1 seuraaja')
                      : tr(context, '${asInt(_store['followerCount']) ?? 0} followers', '${asInt(_store['followerCount']) ?? 0} seuraajaa'),
                  style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                ),
              ),
              _store['followedByMe'] == true
                  ? OutlinedButton.icon(
                      onPressed: _followBusy ? null : _toggleFollow,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(tr(context, 'Following', 'Seuraat')),
                    )
                  : FilledButton.icon(
                      onPressed: _followBusy ? null : _toggleFollow,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr(context, 'Follow', 'Seuraa')),
                    ),
            ]),
          ),
          if ((_store['description'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_store['description'], style: TextStyle(fontSize: 14.5, height: 1.45, color: AppTheme.primaryText(context))),
            ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _meta(Icons.star_rounded, reviews > 0 ? '${_store['rating']} ($reviews)' : tr(context, 'No reviews yet', 'Ei vielä arvioita'),
                  color: reviews > 0 ? const Color(0xFFE08A00) : muted),
              if (eta != null) _meta(Icons.schedule_rounded, eta),
              if (_store['deliveryFeeCents'] != null) _meta(Icons.delivery_dining_rounded, '${euro(context, _store['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}'),
              if (_store['distanceKm'] != null) _meta(Icons.near_me_outlined, '${_store['distanceKm']} km'),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _traderInfo,
            child: Row(
              children: [
                Icon(isPrivate ? Icons.person_outline_rounded : Icons.verified_outlined, size: 18, color: muted),
                const SizedBox(width: 6),
                Text(isPrivate ? tr(context, 'Private seller', 'Yksityinen myyjä') : tr(context, 'Business seller', 'Yritysmyyjä'),
                    style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text('· ${tr(context, 'Seller information', 'Myyjän tiedot')}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color ?? AppTheme.secondaryText(context)),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primaryText(context))),
        ],
      );

  void _traderInfo() {
    Haptics.selection();
    final isPrivate = _store['sellerType'] == 'PRIVATE';
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Seller information', 'Myyjän tiedot'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(_store['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!isPrivate && _store['businessId'] != null) Text('Y-tunnus ${_store['businessId']}'),
            if (!isPrivate && _store['address'] != null) Text(_store['address']),
            const SizedBox(height: 12),
            Text(
              isPrivate
                  ? tr(context, 'A private person selling their own items. Consumer rights such as the 14-day right of withdrawal do not apply.',
                      'Yksityishenkilö, joka myy omia tavaroitaan. Kuluttajan oikeudet, kuten 14 päivän peruuttamisoikeus, eivät koske ostoa.')
                  : tr(context, 'A business. Consumer protection law applies to your purchase, including the 14-day right of withdrawal.',
                      'Yritys. Ostoon sovelletaan kuluttajansuojalakia, mukaan lukien 14 päivän peruuttamisoikeus.'),
              style: TextStyle(color: AppTheme.secondaryText(context), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropsStrip() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(tr(context, 'Drops', 'Dropit'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
          ),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _drops.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final d = _drops[i];
                final poster = d['media']?['poster'];
                return GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DropsFeedScreen(storeId: _id, storeName: _store['name'], startDropId: asInt(d['id'])),
                    ));
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 110,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: Colors.black12),
                          if (poster != null) AppImage(poster),
                          if (d['kind'] == 'VIDEO') const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Row(children: [
                              const Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 3),
                              Text('${d['likeCount'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );

  Future<void> _reportReview(Map<String, dynamic> r) async {
    final reason = await pickReportReason(context, title: tr(context, 'Report this review', 'Ilmoita arviosta'));
    if (reason == null || !mounted) return;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/reviews/${r['id']}/report', {'reason': reason});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok
          ? tr(context, 'Thanks — we will review it.', 'Kiitos — tarkistamme sen.')
          : res.status == 404
              ? tr(context, 'Reporting reviews is not available yet.', 'Arvioista ilmoittaminen ei ole vielä käytössä.')
              : res.errorText(context)!),
    ));
  }

  Widget _reviewActions(Map<String, dynamic> r, Widget child) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final authorId = authorIdOf(r);
    // Only on servers that send the author's public id (they also take reports and blocks)
    if (!auth.isAuthenticated || authorId == null || authorId == auth.currentUser?.id || r['id'] == null) return child;
    final canBlock = BlockedUsers.instance.available;
    void act(String? v) {
      if (v == 'report') _reportReview(r);
      if (v == 'block') confirmAndBlock(context, userId: authorId, name: '${r['author'] ?? ''}');
    }
    return GestureDetector(
      onLongPress: () async => act(await showUgcActions(context, canReport: true, canBlock: canBlock)),
      child: Stack(
        children: [
          child,
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              tooltip: tr(context, 'More', 'Lisää'),
              icon: Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.secondaryText(context)),
              onSelected: act,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(tr(context, 'Report', 'Ilmoita'))),
                if (canBlock) PopupMenuItem(value: 'block', child: Text(tr(context, 'Block user', 'Estä käyttäjä'))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewsBlock() => ListenableBuilder(listenable: BlockedUsers.instance, builder: (context, _) => _reviewsList());

  Widget _reviewsList() {
    final muted = AppTheme.secondaryText(context);
    final shown = _reviews.where((r) => !BlockedUsers.instance.isBlocked(authorIdOf(r))).take(3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(tr(context, 'Reviews', 'Arviot'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
            const Spacer(),
            Text('$_reviewTotal', style: TextStyle(color: muted)),
          ]),
          const SizedBox(height: 4),
          Text(tr(context, 'Only customers whose order was delivered can review.', 'Vain asiakkaat, joiden tilaus on toimitettu, voivat arvioida.'),
              style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 10),
          for (final r in shown)
            _reviewActions(r, Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 14, 40, 14),
              decoration: BoxDecoration(color: AppTheme.cardBackground(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder(context))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('★' * (asInt(r['rating']) ?? 0), style: const TextStyle(color: Color(0xFFE08A00))),
                    const SizedBox(width: 8),
                    Text(r['author'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text(tr(context, '· Verified purchase', '· Vahvistettu ostos'), style: TextStyle(fontSize: 12, color: muted)),
                  ]),
                  if ((r['comment'] ?? '').toString().isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(r['comment'], style: const TextStyle(height: 1.4))),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _bagBar() => Consumer<CartService>(
        builder: (ctx, cart, _) {
          if (cart.items.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () {
              Haptics.selection();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
            },
            child: Container(
              height: 62,
              padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(31),
                boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppTheme.sunshine, shape: BoxShape.circle),
                    child: Text('${cart.itemCount}', style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  const SizedBox(width: 12),
                  Text(euro(context, (cart.total * 100).round()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                  const Spacer(),
                  Text(tr(context, 'View bag', 'Näytä kassi'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                ],
              ),
            ),
          );
        },
      );
}
