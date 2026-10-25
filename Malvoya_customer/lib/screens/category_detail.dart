import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../core/catalog.dart';
import '../core/delivery_location.dart';
import '../widgets/product_tile.dart';

/// A category (API 2.12): breadcrumbs, subcategory chips with "All <category>" first, the
/// category's own filters from `GET /categories/:slug` in an [MFilterBar] with a sort sheet, and
/// the products from `/products/search?category=…` with infinite scroll.
class CategoryScreen extends StatefulWidget {
  final String slug;

  /// The audience chosen on Home (Women, Men, Kids + age group, Teens).
  final AudienceChoice audience;

  const CategoryScreen({super.key, required this.slug, this.audience = AudienceChoice.all});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late String _slug = widget.slug;
  final _scroll = ScrollController();

  /// The node whose children are the chips (the top level, or the leaf's parent).
  Map<String, dynamic>? _chipsNode;
  List<Map<String, dynamic>> _chips = [];

  /// The node shown: its breadcrumbs and facets.
  Map<String, dynamic>? _detail;
  bool _detailLoading = true;
  String? _detailError;

  /// Chosen filter values per facet key, and the order they were added (newest last).
  final Map<String, Set<String>> _chosen = {};
  final List<String> _addedOrder = [];
  String _sort = 'relevance';

  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _request = 0;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  Map<String, String> get _place => {...DeliveryLocation.instance.query, ...widget.audience.query};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(_slug, first: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic list) => (list is List ? list : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  /// Shows [slug]: its details and facets, then its products. Filters belong to one category, so
  /// they are cleared when the category changes.
  Future<void> _open(String slug, {bool first = false}) async {
    await DeliveryLocation.instance.load();
    if (!mounted) return;
    setState(() {
      _slug = slug;
      _detailLoading = true;
      _detailError = null;
      if (!first) {
        _chosen.clear();
        _addedOrder.clear();
      }
    });
    final res = await _api.get('/categories/$slug', query: _place);
    if (!mounted || _slug != slug) return;
    if (!res.ok) {
      setState(() {
        _detailLoading = false;
        _detailError = res.errorText(context) ?? tr(context, 'Could not load this category.', 'Kategoriaa ei voitu ladata.');
      });
      return;
    }
    final detail = res.data;
    final cat = detail['category'] is Map ? Map<String, dynamic>.from(detail['category']) : <String, dynamic>{};
    final children = _maps(detail['children']);
    final parent = cat['parent'] is Map ? Map<String, dynamic>.from(cat['parent']) : null;
    if (children.isNotEmpty || parent == null) {
      _chipsNode = cat;
      _chips = children;
    } else if (_chipsNode?['slug'] != parent['slug']) {
      // A leaf: its siblings come from the parent
      final up = await _api.get('/categories/${parent['slug']}', query: _place);
      if (!mounted || _slug != slug) return;
      if (up.ok && up.data['category'] is Map) {
        _chipsNode = Map<String, dynamic>.from(up.data['category']);
        _chips = _maps(up.data['children']);
      } else {
        _chipsNode = parent;
        _chips = [];
      }
    }
    setState(() {
      _detail = detail;
      _detailLoading = false;
    });
    _search();
  }

  List<Map<String, dynamic>> get _facets => _maps(_detail?['facets']);

  // With a pinned address the API lists only shops within delivery reach
  Map<String, String> get _params => {
        ...DeliveryLocation.instance.query,
        ...widget.audience.query,
        'category': _slug,
        ...facetQuery(_chosen),
        'sort': _sort,
        'limit': '24',
      };

  Future<void> _search() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _page = 1;
    });
    final res = await _api.get('/products/search', query: {..._params, 'page': '1'});
    if (!mounted || request != _request) return;
    if (_dropUnavailableFilter(res)) return;
    setState(() {
      _loading = false;
      _items.clear();
      if (res.ok) {
        _items.addAll(_maps(res.data['products']));
        _total = asInt(res.data['total']) ?? _items.length;
      } else {
        _error = res.errorText(context) ?? tr(context, 'Could not load products.', 'Tuotteita ei voitu ladata.');
      }
    });
  }

  /// 400 FILTER_NOT_AVAILABLE: the filter does not apply in this category, so it is removed and the
  /// search runs again. Returns true when it handled the answer.
  bool _dropUnavailableFilter(ApiResult res) {
    if (res.status != 400 || res.data['code'] != 'FILTER_NOT_AVAILABLE' || _addedOrder.isEmpty) return false;
    final message = res.rawError ?? '';
    String key = _addedOrder.last;
    for (final f in _facets) {
      final label = f['label'];
      final en = label is Map ? '${label['en'] ?? ''}' : '';
      if (en.isNotEmpty && message.contains('"$en"') && _chosen.containsKey(f['key'])) key = '${f['key']}';
    }
    _chosen.remove(key);
    _addedOrder.remove(key);
    MSnack.show(context, tr(context, 'That filter is not available in this category, so it was removed.', 'Suodatin ei ole käytössä tässä kategoriassa, joten se poistettiin.'));
    _search();
    return true;
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    _loadingMore = true;
    final request = _request;
    final res = await _api.get('/products/search', query: {..._params, 'page': '${_page + 1}'});
    if (!mounted || request != _request) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        _page++;
        final more = _maps(res.data['products']);
        _items.addAll(more);
        if (more.isEmpty) _total = _items.length;
      }
    });
  }

  // ── Filters ──────────────────────────────────────────────────────────────

  String _facetLabel(String key) {
    final f = _facets.where((f) => f['key'] == key).firstOrNull;
    return catalogName(context, f?['label']);
  }

  String _valueLabel(String key, String value) {
    final f = _facets.where((f) => f['key'] == key).firstOrNull;
    final v = _maps(f?['values']).where((v) => v['value'] == value).firstOrNull;
    final text = catalogName(context, v?['label']);
    return text.isEmpty ? value : text;
  }

  List<MFilterOption> get _active => [
        for (final e in _chosen.entries)
          for (final v in e.value) MFilterOption(id: '${e.key}|$v', label: '${_facetLabel(e.key)}: ${_valueLabel(e.key, v)}', selected: true),
      ];

  void _remove(String id) {
    final i = id.indexOf('|');
    if (i < 0) return;
    final key = id.substring(0, i);
    final value = id.substring(i + 1);
    setState(() {
      _chosen[key]?.remove(value);
      if (_chosen[key]?.isEmpty ?? false) {
        _chosen.remove(key);
        _addedOrder.remove(key);
      }
    });
    _search();
  }

  void _clearAll() {
    setState(() {
      _chosen.clear();
      _addedOrder.clear();
    });
    _search();
  }

  Future<void> _openFilters() async {
    final draft = {for (final e in _chosen.entries) e.key: {...e.value}};
    final order = [..._addedOrder];
    final applied = await showMSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final c = ctx.mColors;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: MSheet(
            title: tr(context, 'Filters', 'Suodattimet'),
            actions: [
              MButton(label: tr(context, 'Show results', 'Näytä tulokset'), expand: true, onPressed: () => Navigator.pop(ctx, true)),
              if (draft.values.any((s) => s.isNotEmpty))
                MButton(
                  label: tr(context, 'Clear all', 'Tyhjennä kaikki'),
                  variant: MButtonVariant.text,
                  expand: true,
                  onPressed: () => setSheet(() {
                    draft.clear();
                    order.clear();
                  }),
                ),
            ],
            child: _facets.isEmpty
                ? Text(tr(context, 'This category has no filters yet.', 'Tässä kategoriassa ei ole vielä suodattimia.'), style: MType.bodyM.copyWith(color: c.onSurfaceVariant))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final f in _facets) ...[
                      Semantics(
                        header: true,
                        child: Text(catalogName(context, f['label']), style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
                      ),
                      const SizedBox(height: MSpace.xs),
                      Wrap(spacing: MSpace.sm, children: [
                        for (final v in _maps(f['values']))
                          MChip(
                            label: catalogName(context, v['label']).isEmpty ? '${v['value']}' : catalogName(context, v['label']),
                            count: asInt(v['count']),
                            selected: draft['${f['key']}']?.contains('${v['value']}') ?? false,
                            onSelected: (on) => setSheet(() {
                              final key = '${f['key']}';
                              final set = draft.putIfAbsent(key, () => <String>{});
                              if (on) {
                                if (facetIsSingle(key)) set.clear();
                                set.add('${v['value']}');
                                order.remove(key);
                                order.add(key);
                              } else {
                                set.remove('${v['value']}');
                                if (set.isEmpty) {
                                  draft.remove(key);
                                  order.remove(key);
                                }
                              }
                            }),
                          ),
                      ]),
                      const SizedBox(height: MSpace.lg),
                    ],
                  ]),
          ),
        );
      }),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _chosen
        ..clear()
        ..addAll({for (final e in draft.entries) if (e.value.isNotEmpty) e.key: e.value});
      _addedOrder
        ..clear()
        ..addAll(order.where(_chosen.containsKey));
    });
    _search();
  }

  Future<void> _openSort() async {
    final labels = sortLabels(context);
    final picked = await showMSheet<String>(
      context,
      builder: (ctx) => MSheet(
        title: tr(context, 'Sort by', 'Järjestä'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in labels.entries)
            MListTile(
              title: e.value,
              icon: e.key == _sort ? Icons.check_rounded : Icons.swap_vert_rounded,
              chevron: false,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    _search();
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cat = _detail?['category'] as Map?;
    final title = catalogName(context, cat?['name']);
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? tr(context, 'Category', 'Kategoria') : title)),
      body: _detailLoading && _detail == null
          ? const MSkeletonProductGrid()
          : _detailError != null && _detail == null
              ? MStateMessage.error(message: _detailError!, onRetry: () => _open(_slug, first: true))
              : RefreshIndicator(
                  onRefresh: _search,
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    cacheExtent: 800,
                    slivers: [
                      SliverToBoxAdapter(child: _breadcrumbs()),
                      SliverToBoxAdapter(child: _subcategoryChips()),
                      SliverToBoxAdapter(
                        child: MFilterBar(
                          onOpenFilters: _facets.isEmpty ? null : _openFilters,
                          sortLabel: sortLabels(context)[_sort],
                          onSort: _openSort,
                          active: _active,
                          onRemove: _remove,
                          onClearAll: _clearAll,
                        ),
                      ),
                      if (!_loading && _error == null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xs, MSpace.lg, 0),
                            child: Text(
                              tr(context, '$_total ${_total == 1 ? 'item' : 'items'}', '$_total ${_total == 1 ? 'tuote' : 'tuotetta'}'),
                              style: MType.caption.copyWith(color: context.mColors.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ..._results(),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _results() {
    if (_loading) return [const SliverToBoxAdapter(child: SizedBox(height: 560, child: MSkeletonProductGrid(count: 4)))];
    if (_error != null) {
      return [SliverToBoxAdapter(child: MStateMessage.error(message: _error!, onRetry: _search, scrollable: false, top: MSpace.x4l))];
    }
    if (_items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MStateMessage(
            art: MArtKind.search,
            scrollable: false,
            top: MSpace.x4l,
            message: _chosen.isEmpty
                ? tr(context, 'Nothing in this category near you yet.', 'Tässä kategoriassa ei ole vielä mitään lähelläsi.')
                : tr(context, 'No matches with these filters. Try removing one.', 'Näillä suodattimilla ei löytynyt mitään. Kokeile poistaa jokin.'),
            actionLabel: _chosen.isEmpty ? null : tr(context, 'Clear filters', 'Poista suodattimet'),
            onAction: _chosen.isEmpty ? null : _clearAll,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
          delegate: SliverChildBuilderDelegate((_, i) => ProductTile(product: _items[i]), childCount: _items.length),
        ),
      ),
      if (_items.length < _total)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.only(bottom: MSpace.x4l), child: Center(child: CircularProgressIndicator())),
        ),
    ];
  }

  Widget _breadcrumbs() {
    final crumbs = _maps(_detail?['breadcrumbs']);
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final c = context.mColors;
    final parts = <Widget>[
      _crumb(tr(context, 'Home', 'Etusivu'), () => Navigator.of(context).popUntil((r) => r.isFirst)),
      for (var i = 0; i < crumbs.length; i++) ...[
        Icon(Icons.chevron_right_rounded, size: 18, color: c.onSurfaceVariant),
        i == crumbs.length - 1
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.xs),
                child: Text(catalogName(context, crumbs[i]['name']), style: MType.label.copyWith(color: c.onSurface)),
              )
            : _crumb(catalogName(context, crumbs[i]['name']), () => _open('${crumbs[i]['slug']}')),
      ],
    ];
    return Semantics(
      label: tr(context, 'You are here', 'Olet tässä'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MSpace.sm),
        child: Row(children: parts),
      ),
    );
  }

  Widget _crumb(String label, VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget), padding: const EdgeInsets.symmetric(horizontal: MSpace.sm)),
        onPressed: () {
          Haptics.selection();
          onTap();
        },
        child: Text(label, style: MType.label),
      );

  Widget _subcategoryChips() {
    final node = _chipsNode;
    if (node == null || _chips.isEmpty) return const SizedBox.shrink();
    final nodeName = catalogName(context, node['name']);
    final chips = <Widget>[
      MChip(
        label: tr(context, 'All $nodeName', 'Kaikki: $nodeName'),
        selected: _slug == node['slug'],
        onSelected: (_) {
          if (_slug != node['slug']) _open('${node['slug']}');
        },
      ),
      for (final ch in _chips)
        MChip(
          label: catalogName(context, ch['name']),
          count: (asInt(ch['count']) ?? 0) > 0 ? asInt(ch['count']) : null,
          selected: _slug == ch['slug'],
          onSelected: (_) {
            if (_slug != ch['slug']) _open('${ch['slug']}');
          },
        ),
    ];
    return SizedBox(
      height: 52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: MSpace.sm),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }
}

/// Every top-level category with its subcategories (from Home's "All categories").
class AllCategoriesScreen extends StatelessWidget {
  /// The tree from `GET /categories`.
  final List<Map<String, dynamic>> categories;
  final AudienceChoice audience;
  const AllCategoriesScreen({super.key, required this.categories, this.audience = AudienceChoice.all});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    void open(String slug) {
      Haptics.selection();
      Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(slug: slug, audience: audience)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'All categories', 'Kaikki kategoriat'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, MSpace.sm, 0, MSpace.x4l),
        children: [
          for (final top in categories) ...[
            Builder(builder: (context) {
              final tile = catalogTile(context, top['tileColor'] as String?);
              return MListTile(
                title: catalogName(context, top['name']),
                subtitle: (asInt(top['count']) ?? 0) > 0 ? tr(context, '${top['count']} items near you', '${top['count']} tuotetta lähelläsi') : null,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: tile.fill, borderRadius: MRadius.brSm),
                  child: Icon(catalogIcon(top['icon'] as String?), color: tile.ink),
                ),
                onTap: () => open('${top['slug']}'),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, MSpace.lg, MSpace.md),
              child: Wrap(spacing: MSpace.sm, children: [
                for (final ch in ((top['children'] as List?) ?? const []).whereType<Map>())
                  MChip(
                    label: catalogName(context, ch['name']),
                    count: (asInt(ch['count']) ?? 0) > 0 ? asInt(ch['count']) : null,
                    onSelected: (_) => open('${ch['slug']}'),
                  ),
              ]),
            ),
            Divider(height: 1, color: c.outline),
          ],
        ],
      ),
    );
  }
}

/// A product grid for a saved search: a Home collection, a rail's "See all", or a brand.
class ProductGridScreen extends StatefulWidget {
  final String title;
  final Map<String, String> params;
  final String? note;
  const ProductGridScreen({super.key, required this.title, required this.params, this.note});

  @override
  State<ProductGridScreen> createState() => _ProductGridScreenState();
}

class _ProductGridScreenState extends State<ProductGridScreen> {
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  late String _sort = widget.params['sort'] ?? 'relevance';

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  // With a pinned address the API lists only shops within delivery reach
  Map<String, String> get _params => {...DeliveryLocation.instance.query, ...widget.params, 'sort': _sort, 'limit': '24'};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic list) => (list is List ? list : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    await DeliveryLocation.instance.load();
    if (!mounted) return;
    final res = await _api.get('/products/search', query: {..._params, 'page': '1'});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items.clear();
      if (res.ok) {
        _items.addAll(_maps(res.data['products']));
        _total = asInt(res.data['total']) ?? _items.length;
      } else {
        _error = res.errorText(context) ?? tr(context, 'Could not load products.', 'Tuotteita ei voitu ladata.');
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    _loadingMore = true;
    final res = await _api.get('/products/search', query: {..._params, 'page': '${_page + 1}'});
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        _page++;
        final more = _maps(res.data['products']);
        _items.addAll(more);
        if (more.isEmpty) _total = _items.length;
      }
    });
  }

  Future<void> _openSort() async {
    final labels = sortLabels(context);
    final picked = await showMSheet<String>(
      context,
      builder: (ctx) => MSheet(
        title: tr(context, 'Sort by', 'Järjestä'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in labels.entries)
            MListTile(title: e.value, icon: e.key == _sort ? Icons.check_rounded : Icons.swap_vert_rounded, chevron: false, onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 800,
          slivers: [
            SliverToBoxAdapter(child: MFilterBar(sortLabel: sortLabels(context)[_sort], onSort: _openSort)),
            if (widget.note != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.sm),
                  child: Text(widget.note!, style: MType.caption.copyWith(color: c.onSurfaceVariant)),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(child: SizedBox(height: 560, child: MSkeletonProductGrid(count: 4)))
            else if (_error != null)
              SliverToBoxAdapter(child: MStateMessage.error(message: _error!, onRetry: _load, scrollable: false, top: MSpace.x4l))
            else if (_items.isEmpty)
              SliverToBoxAdapter(
                child: MStateMessage(art: MArtKind.search, scrollable: false, top: MSpace.x4l, message: tr(context, 'Nothing here right now.', 'Täällä ei ole juuri nyt mitään.')),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
                  delegate: SliverChildBuilderDelegate((_, i) => ProductTile(product: _items[i]), childCount: _items.length),
                ),
              ),
              if (_items.length < _total)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(bottom: MSpace.x4l), child: Center(child: CircularProgressIndicator()))),
            ],
          ],
        ),
      ),
    );
  }
}

/// The A–Z brand index (`GET /collections/brands`); a brand opens its products.
class BrandsScreen extends StatefulWidget {
  final AudienceChoice audience;
  const BrandsScreen({super.key, this.audience = AudienceChoice.all});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  List<Map<String, dynamic>> _brands = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await DeliveryLocation.instance.load();
    if (!mounted) return;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false))
        .get('/collections/brands', query: {...DeliveryLocation.instance.query, ...widget.audience.query});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _brands = ((res.data['brands'] as List?) ?? const []).whereType<Map>().map((b) => Map<String, dynamic>.from(b)).toList();
      } else {
        _error = res.errorText(context) ?? tr(context, 'Could not load brands.', 'Merkkejä ei voitu ladata.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Brands A–Z', 'Merkit A–Ö'))),
      body: _loading
          ? const MSkeletonList()
          : _error != null
              ? MStateMessage.error(message: _error!, onRetry: _load)
              : _brands.isEmpty
                  ? MStateMessage(message: tr(context, 'No brands near you yet.', 'Lähelläsi ei ole vielä merkkejä.'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: MSpace.x4l),
                      itemCount: _brands.length,
                      itemBuilder: (_, i) {
                        final b = _brands[i];
                        final letter = '${b['letter'] ?? ''}';
                        final newLetter = i == 0 || _brands[i - 1]['letter'] != b['letter'];
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (newLetter)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.xs),
                              child: Semantics(header: true, child: Text(letter, style: MType.title.copyWith(color: c.primary))),
                            ),
                          MListTile(
                            title: '${b['name'] ?? b['value']}',
                            trailing: Text('${b['count'] ?? ''}', style: MType.caption.copyWith(color: c.onSurfaceVariant)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductGridScreen(title: '${b['name'] ?? b['value']}', params: {...widget.audience.query, 'brand': '${b['value']}'}),
                              ),
                            ),
                          ),
                        ]);
                      },
                    ),
    );
  }
}
