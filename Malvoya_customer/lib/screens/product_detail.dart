import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/add_to_bag_sheet.dart';
import '../widgets/price_tag.dart';
import '../widgets/product_gallery.dart';
import 'store_detail.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? _product;
  String? _error;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final res = await ApiClient(auth).get('/products/${widget.productId}');
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _product = Map<String, dynamic>.from(res.data['product']);
        _favorite = _product!['isFavorite'] == true;
        _error = null;
      } else {
        _error = res.error;
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      _snack(tr(context, 'Sign in to save favourites', 'Kirjaudu sisään tallentaaksesi suosikkeja'));
      return;
    }
    HapticFeedback.lightImpact();
    final next = !_favorite;
    setState(() => _favorite = next);
    final api = ApiClient(auth);
    final res = next ? await api.put('/me/favorites/${widget.productId}') : await api.delete('/me/favorites/${widget.productId}');
    if (!res.ok && mounted) {
      setState(() => _favorite = !next);
      _snack(res.error!);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground(context),
      body: p == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
                      ]),
                    ),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: MediaQuery.of(context).size.width * 1.2,
                  backgroundColor: AppTheme.scaffoldBackground(context),
                  leading: Padding(
                    padding: const EdgeInsets.all(6),
                    child: _circleButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: _circleButton(
                        icon: _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _favorite ? AppTheme.lingon : AppTheme.ink,
                        tooltip: tr(context, 'Favourite', 'Suosikki'),
                        onTap: _toggleFavorite,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  flexibleSpace: FlexibleSpaceBar(background: _gallery(p)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  sliver: SliverList(delegate: SliverChildListDelegate(_details(p))),
                ),
              ],
            ),
      bottomNavigationBar: p == null ? null : _buyBar(p),
    );
  }

  Widget _circleButton({required IconData icon, required String tooltip, required VoidCallback onTap, Color color = AppTheme.ink}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 22)),
        ),
      ),
    );
  }

  Widget _gallery(Map<String, dynamic> p) => ProductGallery(items: GalleryItem.forProduct(p));

  List<Widget> _details(Map<String, dynamic> p) {
    final store = (p['store'] as Map?)?.cast<String, dynamic>();
    final text = AppTheme.primaryText(context);
    final muted = AppTheme.secondaryText(context);
    final dark = AppTheme.isDarkMode(context);
    // Each fact gets its own soft colour: condition lilac, second hand butter, eco mint, handmade peach
    final chips = <(String, Color, Color)>[
      (_conditionLabel(p['condition']), AppTheme.lilac, AppTheme.primary),
      if (p['isSecondHand'] == true) (tr(context, 'Second hand', 'Käytetty'), AppTheme.sunshineLight, const Color(0xFF8A5A00)),
      if (p['isEcoFriendly'] == true) (tr(context, 'Eco-friendly', 'Ympäristöystävällinen'), AppTheme.mint, const Color(0xFF1D6B44)),
      if (p['isHandmade'] == true) (tr(context, 'Handmade', 'Käsintehty'), AppTheme.peach, AppTheme.lingon),
    ].where((c) => c.$1.isNotEmpty).toList();

    return [
      Text(p['name'] ?? '', style: AppTheme.display(context, size: 27)),
      const SizedBox(height: 8),
      PriceTag(pricing: p['pricing'] as Map<String, dynamic>?, size: 20, showReferenceLabel: true),
      const SizedBox(height: 4),
      Text(tr(context, 'Price includes VAT', 'Hinta sisältää ALV:n'), style: TextStyle(fontSize: 12, color: muted)),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: AppTheme.pastel(context, c.$2, c.$3), borderRadius: BorderRadius.circular(16)),
                    child: Text(c.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dark ? Color.lerp(c.$3, Colors.white, 0.5) : c.$3)),
                  ))
              .toList(),
        ),
      ],
      if ((p['description'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(p['description'], style: TextStyle(fontSize: 15, height: 1.5, color: text)),
      ],
      const SizedBox(height: 18),
      _row(Icons.straighten_rounded, tr(context, 'Size guide', 'Kokotaulukko'), () => _showSizeGuide()),
      if (store != null) ...[
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store))),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd + 2),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryLight,
                  backgroundImage: store['logoUrl'] != null ? CachedNetworkImageProvider(store['logoUrl']) : null,
                  child: store['logoUrl'] == null ? const Icon(Icons.storefront_rounded, color: AppTheme.primary) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: text)),
                      Text(
                        [
                          store['sellerType'] == 'PRIVATE' ? tr(context, 'Private seller', 'Yksityinen myyjä') : tr(context, 'Business seller', 'Yritysmyyjä'),
                          if ((asInt(store['totalReviews']) ?? 0) > 0) '★ ${store['rating']} (${store['totalReviews']})',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _row(Icons.info_outline_rounded, tr(context, 'Seller information', 'Myyjän tiedot'), () => _showTraderInfo(store)),
      ],
    ];
  }

  Widget _row(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: AppTheme.primaryText(context)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: AppTheme.primaryText(context)))),
            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
          ]),
        ),
      );

  String _conditionLabel(dynamic c) {
    switch (c) {
      case 'NEW':
        return tr(context, 'New', 'Uusi');
      case 'LIKE_NEW':
        return tr(context, 'Like new', 'Kuin uusi');
      case 'GOOD':
        return tr(context, 'Good condition', 'Hyvä kunto');
      case 'FAIR':
        return tr(context, 'Fair condition', 'Kohtalainen kunto');
      case 'POOR':
        return tr(context, 'Worn', 'Kulunut');
    }
    return '';
  }

  /// Seller identity shown to shoppers (DSA Art. 30 trader traceability).
  void _showTraderInfo(Map<String, dynamic> store) {
    final isPrivate = store['sellerType'] == 'PRIVATE';
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Seller information', 'Myyjän tiedot'), style: AppTheme.display(context, size: 21)),
            const SizedBox(height: 14),
            Text(store['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!isPrivate && store['businessId'] != null) Text('Y-tunnus ${store['businessId']}'),
            if (!isPrivate && store['address'] != null) Text(store['address']),
            const SizedBox(height: 12),
            Text(
              isPrivate
                  ? tr(
                      context,
                      'This seller has told Malvoya they are a private person selling their own items, not a business. EU consumer rights such as the 14-day right of withdrawal do not apply to purchases from private sellers.',
                      'Myyjä on ilmoittanut Malvoyalle olevansa yksityishenkilö, joka myy omia tavaroitaan. EU:n kuluttajansuoja, kuten 14 päivän peruuttamisoikeus, ei koske ostoja yksityisiltä myyjiltä.')
                  : tr(context, 'This seller is a business. Consumer protection law applies, including the 14-day right of withdrawal from delivery.',
                      'Myyjä on yritys. Ostoon sovelletaan kuluttajansuojalakia, mukaan lukien 14 päivän peruuttamisoikeus toimituksesta.'),
              style: TextStyle(color: AppTheme.secondaryText(context), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  void _showSizeGuide() {
    const rows = [
      ['XS', '32–34', '80–84', '62–66'],
      ['S', '36–38', '84–90', '66–72'],
      ['M', '40–42', '90–98', '72–80'],
      ['L', '44–46', '98–106', '80–88'],
      ['XL', '48–50', '106–114', '88–96'],
      ['XXL', '52–54', '114–122', '96–104'],
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Size guide (EU)', 'Kokotaulukko (EU)'), style: AppTheme.display(context, size: 21)),
            const SizedBox(height: 4),
            Text(
                tr(context, 'Body measurements in cm. Brands vary — check the description for the store\'s own sizing.',
                    'Vartalon mitat senttimetreinä. Merkkien koot vaihtelevat — katso kaupan oma mitoitus kuvauksesta.'),
                style: TextStyle(fontSize: 12.5, color: AppTheme.secondaryText(context))),
            const SizedBox(height: 14),
            Table(
              children: [
                TableRow(children: [
                  for (final h in [tr(context, 'Size', 'Koko'), 'EU', tr(context, 'Chest', 'Rinta'), tr(context, 'Waist', 'Vyötärö')])
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                for (final r in rows) TableRow(children: [for (final c in r) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(c))]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buyBar(Map<String, dynamic> p) {
    final inStock = p['inStock'] != false;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 16, 14 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(child: PriceTag(pricing: p['pricing'] as Map<String, dynamic>?, size: 18)),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: inStock
                  ? () async {
                      final added = await showAddToBagSheet(context, p);
                      if (added && mounted) _snack(tr(context, 'Added to your bag', 'Lisätty kassiin'));
                    }
                  : null,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text(inStock ? tr(context, 'Add to bag', 'Lisää kassiin') : tr(context, 'Sold out', 'Loppuunmyyty')),
            ),
          ),
        ],
      ),
    );
  }
}
