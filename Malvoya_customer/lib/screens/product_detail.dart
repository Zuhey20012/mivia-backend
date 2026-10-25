import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/catalog.dart';
import '../widgets/add_to_bag_sheet.dart';
import '../widgets/app_image.dart';
import '../widgets/product_gallery.dart';
import '../widgets/product_info.dart';
import 'category_detail.dart';
import 'store_detail.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;

  /// Set when opened from a product tile: its photo flies into place (shown while loading too).
  final String? heroTag;
  final String? heroImage;

  /// The exact copy the tile drew (already on the phone): flies, and shows until the sharp one loads.
  final String? heroPreview;
  const ProductDetailScreen({super.key, required this.productId, this.heroTag, this.heroImage, this.heroPreview});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? _product;
  String? _error;
  bool _favorite = false;

  /// The chosen option (size, colour, shade or content).
  int? _variantId;

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
        final inStock = productVariants(_product!).where((v) => v['inStock'] == true).toList();
        if (inStock.length == 1) _variantId = asInt(inStock.first['id']);
      } else {
        _error = res.errorText(context);
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      _snack(tr(context, 'Sign in to save favourites', 'Kirjaudu sisään tallentaaksesi suosikkeja'));
      return;
    }
    Haptics.light();
    final next = !_favorite;
    setState(() => _favorite = next);
    final api = ApiClient(auth);
    final res = next ? await api.put('/me/favorites/${widget.productId}') : await api.delete('/me/favorites/${widget.productId}');
    if (!res.ok && mounted) {
      setState(() => _favorite = !next);
      _snack(res.errorText(context)!);
    }
  }

  void _snack(String text) => MSnack.show(context, text);

  Map<String, dynamic>? get _selected =>
      _product == null ? null : productVariants(_product!).where((v) => asInt(v['id']) == _variantId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground(context),
      body: p == null && _error == null && widget.heroTag != null && widget.heroImage != null
          ? _loadingWithPhoto()
          : p == null
          ? SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.all(MSpace.xs), child: BackButton()),
                  Expanded(
                    child: _error == null
                        ? MSkeletonDetail(heroHeight: MediaQuery.of(context).size.width)
                        : MStateMessage.error(
                            message: _error!,
                            onRetry: () {
                              setState(() => _error = null);
                              _load();
                            },
                          ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: MediaQuery.of(context).size.width * 1.2,
                  backgroundColor: AppTheme.scaffoldBackground(context),
                  leading: Padding(
                    padding: const EdgeInsets.all(MSpace.xs),
                    child: _circleButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.all(MSpace.xs),
                      child: _circleButton(
                        icon: _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _favorite ? AppTheme.lingon : AppTheme.ink,
                        tooltip: tr(context, 'Favourite', 'Suosikki'),
                        onTap: _toggleFavorite,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(MSpace.xs),
                      child: _circleButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: tr(context, 'More', 'Lisää'),
                        onTap: _openMenu,
                      ),
                    ),
                    const SizedBox(width: MSpace.xs),
                  ],
                  flexibleSpace: FlexibleSpaceBar(background: _gallery(p)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.xl, MSpace.xl, 120),
                  sliver: SliverList(delegate: SliverChildListDelegate(_details(p))),
                ),
              ],
            ),
      bottomNavigationBar: p == null ? null : _buyBar(p),
    );
  }

  void _openMenu() {
    showMSheet(
      context,
      builder: (ctx) => MSheet(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MListTile(
            title: tr(ctx, 'Report this product', 'Ilmoita tuotteesta'),
            subtitle: tr(ctx, 'Unsafe, counterfeit, misleading or illegal', 'Vaarallinen, väärennös, harhaanjohtava tai laiton'),
            icon: Icons.flag_outlined,
            onTap: () {
              Navigator.pop(ctx);
              showReportProductSheet(context, widget.productId);
            },
          ),
        ]),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required String tooltip, required VoidCallback onTap, Color color = AppTheme.ink}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: MPalette.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: kMinTouchTarget, height: kMinTouchTarget, child: Icon(icon, color: color, size: 22)),
        ),
      ),
    );
  }

  Widget _gallery(Map<String, dynamic> p) => ProductGallery(items: GalleryItem.forProduct(p), heroTag: widget.heroTag, heroImage: widget.heroImage, heroPreview: widget.heroPreview);

  /// While the product loads: the tile's photo at the size the gallery will have, then placeholders.
  Widget _loadingWithPhoto() {
    final width = MediaQuery.of(context).size.width;
    return Stack(
      children: [
        ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: width * 1.2,
              child: Hero(
                tag: widget.heroTag!,
                flightShuttleBuilder: widget.heroPreview == null ? null : photoShuttle(widget.heroPreview!),
                child: AppImage(widget.heroImage, previewUrl: widget.heroPreview),
              ),
            ),
            const MSkeleton(
              child: Padding(
                padding: EdgeInsets.fromLTRB(MSpace.xl, MSpace.xl, MSpace.xl, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MSkeletonBox(width: 220, height: 26),
                    SizedBox(height: MSpace.md),
                    MSkeletonBox(width: 90, height: 20),
                    SizedBox(height: 22),
                    MSkeletonBox(height: 14),
                    SizedBox(height: MSpace.sm),
                    MSkeletonBox(width: 240, height: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MSpace.sm),
            child: _circleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
        ),
      ],
    );
  }

  bool _isCosmetic(Map<String, dynamic> p) {
    final t = '${p['template'] ?? ''}';
    return t.startsWith('COSMETIC') || t == 'FRAGRANCE';
  }

  List<Widget> _details(Map<String, dynamic> p) {
    final c = context.mColors;
    final store = (p['store'] as Map?)?.cast<String, dynamic>();
    final variants = productVariants(p);
    final chosen = _selected;
    final path = ((p['categoryPath'] as List?) ?? const []).whereType<Map>().toList();
    // One soft chip per fact: condition, second hand, handmade
    final chips = <(String, MBadgeTone)>[
      if (_conditionLabel(p['condition']).isNotEmpty && !_isCosmetic(p)) (_conditionLabel(p['condition']), MBadgeTone.brand),
      if (p['isSecondHand'] == true) (tr(context, 'Second-hand', 'Käytetty'), MBadgeTone.sunshine),
      if (p['isHandmade'] == true) (tr(context, 'Handmade', 'Käsintehty'), MBadgeTone.neutral),
    ];

    return [
      RecallBanner(product: p),
      if (path.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: MSpace.xs),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < path.length; i++) ...[
              if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: c.onSurfaceVariant),
              InkWell(
                borderRadius: MRadius.brXs,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(slug: '${path[i]['slug']}'))),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: Align(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: MSpace.xs),
                      child: Text(catalogName(context, path[i]['name']), style: MType.label.copyWith(color: c.primary)),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      Text(p['name'] ?? '', style: MType.displayM.copyWith(color: c.onSurface)),
      if ('${p['attributes']?['brand'] ?? ''}'.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: MSpace.xs),
          child: Text('${p['attributes']['brand']}', style: MType.bodyM.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: MSpace.sm),
      productPrice(p, chosen, size: MPriceSize.lg, showReferenceLabel: true),
      const SizedBox(height: MSpace.xs),
      Text(tr(context, 'Price includes VAT where the seller is VAT-registered', 'Hinta sisältää ALV:n, jos myyjä on arvonlisäverovelvollinen'),
          style: MType.caption.copyWith(color: c.onSurfaceVariant)),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: MSpace.md),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [for (final ch in chips) MBadge(ch.$1, tone: ch.$2)]),
      ],
      if (variants.isNotEmpty) ...[
        const SizedBox(height: MSpace.xl),
        optionPicker(
          context,
          variants: variants,
          selectedId: _variantId,
          onChanged: (id) => setState(() => _variantId = id),
          onSizeGuide: hasSizeGuide(p) ? () => showSizeGuideSheet(context, p) : null,
        ),
        if (isShadeProduct(variants))
          Padding(
            padding: const EdgeInsets.only(top: MSpace.xs),
            child: Text(tr(context, 'Colours vary by screen.', 'Näytön värit voivat poiketa.'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
          ),
      ] else if (hasSizeGuide(p))
        MListTile(title: tr(context, 'Size guide', 'Kokotaulukko'), icon: Icons.straighten_rounded, onTap: () => showSizeGuideSheet(context, p)),
      if (p['hygieneSealed'] == true) ...[
        const SizedBox(height: MSpace.lg),
        HygieneSealNotice(product: p),
      ],
      if ('${p['description'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: MSpace.lg),
        Text(p['description'], style: MType.bodyL.copyWith(color: c.onSurface)),
      ],
      ProductMaterialsSection(product: p),
      if (_isCosmetic(p)) CosmeticsSection(product: p, variant: chosen),
      CertificateChips(product: p),
      const SizedBox(height: MSpace.lg),
      ProductSafetyRow(product: p),
      if (store != null) ...[
        const SizedBox(height: MSpace.sm),
        InkWell(
          borderRadius: MRadius.brMd,
          onTap: () {
            Haptics.selection();
            Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
          },
          child: Ink(
            padding: const EdgeInsets.all(MSpace.md),
            decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: c.primarySoft,
                  backgroundImage: store['logoUrl'] != null ? sizedImageProvider(context, store['logoUrl'], 44) : null,
                  child: store['logoUrl'] == null ? Icon(Icons.storefront_rounded, color: c.onPrimarySoft) : null,
                ),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store['name'] ?? '', style: MType.bodyL.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
                      Text(
                        [
                          store['sellerType'] == 'PRIVATE' ? tr(context, 'Private seller', 'Yksityinen myyjä') : tr(context, 'Business seller', 'Yritysmyyjä'),
                          if ((asInt(store['totalReviews']) ?? 0) > 0) '★ ${store['rating']} (${store['totalReviews']})',
                        ].join(' · '),
                        style: MType.caption.copyWith(color: c.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const SizedBox(height: MSpace.sm),
        MListTile(title: tr(context, 'Seller information', 'Myyjän tiedot'), icon: Icons.info_outline_rounded, onTap: () => _showTraderInfo(store)),
      ],
      MListTile(
        title: tr(context, 'Report this product', 'Ilmoita tuotteesta'),
        icon: Icons.flag_outlined,
        onTap: () => showReportProductSheet(context, widget.productId),
      ),
    ];
  }

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
    showMSheet(context, builder: (ctx) {
      final c = ctx.mColors;
      return MSheet(
        title: tr(context, 'Seller information', 'Myyjän tiedot'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store['name'] ?? '', style: MType.bodyL.copyWith(fontWeight: FontWeight.w600, color: c.onSurface)),
            if (!isPrivate && store['businessId'] != null) Text('Y-tunnus ${store['businessId']}', style: MType.bodyM.copyWith(color: c.onSurface)),
            if (!isPrivate && store['address'] != null) Text(store['address'], style: MType.bodyM.copyWith(color: c.onSurface)),
            const SizedBox(height: MSpace.md),
            Text(
              isPrivate
                  ? tr(
                      context,
                      'This seller has told Malvoya they are a private person selling their own items, not a business. EU consumer rights such as the 14-day right of withdrawal do not apply to purchases from private sellers.',
                      'Myyjä on ilmoittanut Malvoyalle olevansa yksityishenkilö, joka myy omia tavaroitaan. EU:n kuluttajansuoja, kuten 14 päivän peruuttamisoikeus, ei koske ostoja yksityisiltä myyjiltä.')
                  : tr(context, 'This seller is a business. Consumer protection law applies, including the 14-day right of withdrawal from delivery.',
                      'Myyjä on yritys. Ostoon sovelletaan kuluttajansuojalakia, mukaan lukien 14 päivän peruuttamisoikeus toimituksesta.'),
              style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ),
      );
    });
  }

  Widget _buyBar(Map<String, dynamic> p) {
    final c = context.mColors;
    final variants = productVariants(p);
    final chosen = _selected;
    final recalled = p['recall'] != null;
    final inStock = !recalled && p['inStock'] != false;
    final needsChoice = variants.isNotEmpty && chosen == null;
    final shades = isShadeProduct(variants);
    return Container(
      padding: EdgeInsets.fromLTRB(MSpace.xl, MSpace.md, MSpace.lg, MSpace.md + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: MRadius.sheetTop,
        boxShadow: context.mTokens.shadow(MElevation.e2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The seal notice right before the product goes in the bag
          if (p['hygieneSealed'] == true && inStock) ...[HygieneSealNotice(product: p, compact: true), const SizedBox(height: MSpace.sm)],
          Row(
            children: [
              Expanded(child: productPrice(p, chosen, size: MPriceSize.lg)),
              const SizedBox(width: MSpace.sm),
              MButton(
                icon: Icons.shopping_bag_outlined,
                size: MButtonSize.md,
                onPressed: !inStock
                    ? null
                    : () async {
                        final added = needsChoice || variants.isEmpty
                            ? (needsChoice ? await showAddToBagSheet(context, p) : await addProductToBag(context, p))
                            : await addProductToBag(context, p, variant: chosen);
                        if (added && context.mounted) showAddedToBag(context);
                      },
                label: recalled
                    ? tr(context, 'Not for sale', 'Ei myynnissä')
                    : !inStock
                        ? tr(context, 'Sold out', 'Loppuunmyyty')
                        : needsChoice
                            ? (shades ? tr(context, 'Choose a shade', 'Valitse sävy') : tr(context, 'Choose', 'Valitse'))
                            : chosen != null && chosen['inStock'] != true
                                ? tr(context, 'Sold out', 'Loppuunmyyty')
                                : tr(context, 'Add to bag', 'Lisää kassiin'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
