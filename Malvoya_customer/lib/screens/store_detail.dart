import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../cart.dart';
import '../checkout.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/delivery_location.dart';
import '../core/store_hours.dart';
import '../core/strings.dart';
import '../widgets/product_tile.dart';
import 'drops_feed.dart';

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

  int get _id => asInt(widget.store['id'])!;
  bool _followBusy = false;

  Future<void> _toggleFollow() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'Sign in to follow stores', 'Kirjaudu sisään seurataksesi kauppoja'))));
      return;
    }
    HapticFeedback.lightImpact();
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
    if (!res.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
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
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final store = results[0];
      if (!store.ok) {
        _error = store.error;
        return;
      }
      _error = null;
      _store = Map<String, dynamic>.from(store.data['store']);
      _products = ((_store['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
      if (results[1].ok) _drops = ((results[1].data['drops'] as List?) ?? []).map((d) => Map<String, dynamic>.from(d)).toList();
      if (results[2].ok) {
        _reviews = ((results[2].data['reviews'] as List?) ?? []).map((r) => Map<String, dynamic>.from(r)).toList();
        _reviewTotal = asInt(results[2].data['total']) ?? _reviews.length;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.primaryText(context);
    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
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
                        ? CachedNetworkImage(imageUrl: _store['bannerUrl'], fit: BoxFit.cover)
                        : Container(
                            color: AppTheme.isDarkMode(context) ? const Color(0xFF3A2F42) : AppTheme.primary,
                            child: Center(child: Icon(Icons.storefront_outlined, size: 72, color: Colors.white.withValues(alpha: 0.25))),
                          ),
                  ),
                ),
                if (_error != null)
                  SliverFillRemaining(child: Center(child: Text(_error!)))
                else ...[
                  SliverToBoxAdapter(child: _header()),
                  if (_drops.isNotEmpty) SliverToBoxAdapter(child: _dropsStrip()),
                  if (_reviews.isNotEmpty) SliverToBoxAdapter(child: _reviewsBlock()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Text(tr(context, 'All items', 'Kaikki tuotteet'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                    ),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
                  else if (_products.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(tr(context, 'This store has not listed anything yet.', 'Kauppa ei ole vielä lisännyt tuotteita.'),
                            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context))),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
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
                ],
              ],
            ),
          ),
          Positioned(bottom: 20, left: 16, right: 16, child: _bagBar()),
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
            child: Text(tr(context, 'Drops', 'Julkaisut'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
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
                    HapticFeedback.selectionClick();
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
                          if (poster != null) CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover),
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

  Widget _reviewsBlock() {
    final muted = AppTheme.secondaryText(context);
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
          for (final r in _reviews.take(3))
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
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
            ),
        ],
      ),
    );
  }

  Widget _bagBar() => Consumer<CartService>(
        builder: (ctx, cart, _) {
          if (cart.items.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
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
