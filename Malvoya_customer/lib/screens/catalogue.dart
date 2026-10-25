import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
import '../core/catalog.dart';
import 'category_detail.dart';
import '../widgets/product_tile.dart';
import 'store_detail.dart';
import '../widgets/app_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// Search across every store: items with size, price, condition and second-hand filters,
/// or stores by name.
class CatalogueScreen extends StatefulWidget {
  final bool isTab;
  final String? title;
  final String? initialQuery;
  final String? category;
  final bool secondHand;

  const CatalogueScreen({super.key, this.isTab = false, this.title, this.initialQuery, this.category, this.secondHand = false});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  late final _query = TextEditingController(text: widget.initialQuery ?? '');
  final _scroll = ScrollController();
  Timer? _debounce;

  bool _storesTab = false;
  String _sort = 'relevance';
  String? _size;
  String? _condition;
  late bool _secondHand = widget.secondHand;
  late String? _category = widget.category;

  /// Categories the query names ("huulipuna" → Makeup › Lips), from the search answer.
  List<Map<String, dynamic>> _matched = [];

  /// Top-level categories from `GET /categories`, as quick starting points.
  List<Map<String, dynamic>> _tops = [];

  /// Numbers every search, so an older, slower answer never replaces a newer one.
  int _request = 0;
  int? _minPrice;
  int? _maxPrice;

  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _stores = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Searches typed on this phone (newest first), kept only on the phone.
  List<String> _recent = [];
  static const _recentKey = 'recent_searches';

  // The API has no list of sizes in use, so the common clothing and shoe sizes are offered
  static const _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46', 'One Size'];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _search();
    _loadRecent();
    _loadTops();
  }

  Future<void> _loadTops() async {
    await DeliveryLocation.instance.load();
    if (!mounted) return;
    final place = {...DeliveryLocation.instance.query, ...homeAudience.value.query};
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    var res = await api.get('/categories', query: place);
    if (res.ok && ((res.data['categories'] as List?) ?? const []).isEmpty) res = await api.get('/categories', query: {...place, 'includeEmpty': '1'});
    if (!mounted || !res.ok) return;
    setState(() => _tops = ((res.data['categories'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = saved);
    } catch (_) {}
  }

  /// Remembers the current query (when it found something worth opening, or was submitted).
  Future<void> _remember() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    final next = [q, ..._recent.where((r) => r.toLowerCase() != q.toLowerCase())].take(8).toList();
    setState(() => _recent = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, next);
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    Haptics.selection();
    setState(() => _recent = []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) {}
  }

  void _useQuery(String q) {
    Haptics.selection();
    _debounce?.cancel();
    _query.text = q;
    _query.selection = TextSelection.collapsed(offset: q.length);
    FocusScope.of(context).unfocus();
    _search();
    _remember();
  }

  /// Opens a category from the API (its own screen with subcategories and filters).
  void _openCategory(String slug) {
    Haptics.selection();
    FocusScope.of(context).unfocus();
    _remember();
    Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(slug: slug, audience: homeAudience.value)));
  }

  bool get _hasFilters =>
      _category != null || _size != null || _condition != null || _secondHand || _minPrice != null || _maxPrice != null;

  void _clearFilters() {
    Haptics.selection();
    setState(() {
      _category = null;
      _size = null;
      _condition = null;
      _secondHand = false;
      _minPrice = null;
      _maxPrice = null;
      _sort = 'relevance';
    });
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, String> get _params => {
        if (_query.text.trim().isNotEmpty) 'q': _query.text.trim(),
        if (_category != null) 'category': _category!,
        if (_size != null) 'size': _size!,
        if (_condition != null) 'condition': _condition!,
        if (_secondHand) 'secondHand': 'true',
        if (_minPrice != null) 'minPrice': '$_minPrice',
        if (_maxPrice != null) 'maxPrice': '$_maxPrice',
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
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    if (_storesTab) {
      await DeliveryLocation.instance.load();
      final res = await api.get('/stores', query: {
        if (_query.text.trim().isNotEmpty) 'search': _query.text.trim(),
        ...DeliveryLocation.instance.query,
      });
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _stores = res.ok ? ((res.data['stores'] as List?) ?? []).map((s) => Map<String, dynamic>.from(s)).toList() : [];
        _error = res.ok ? null : res.errorText(context);
      });
      return;
    }
    final res = await api.get('/products/search', query: {..._params, 'page': '1'});
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _items.clear();
      if (res.ok) {
        _items.addAll(((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)));
        _total = asInt(res.data['total']) ?? _items.length;
        _matched = ((res.data['categories'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      } else {
        _matched = [];
        _error = res.errorText(context);
      }
    });
  }

  Future<void> _loadMore() async {
    if (_storesTab || _loading || _loadingMore || _items.length >= _total) return;
    _loadingMore = true;
    final request = _request;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/products/search', query: {..._params, 'page': '${_page + 1}'});
    // A new search started meanwhile: this page belongs to the old one
    if (!mounted || request != _request) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        _page++;
        _items.addAll(((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)));
      }
    });
  }

  void _onQuery(String _) {
    setState(() {}); // shows or hides the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        titleSpacing: widget.isTab ? 16 : 0,
        title: TextField(
          controller: _query,
          autofocus: !widget.isTab && widget.category == null && !widget.secondHand,
          onChanged: _onQuery,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            _debounce?.cancel();
            _search();
            _remember();
          },
          decoration: InputDecoration(
            hintText: (_category != null || (widget.secondHand && _secondHand)) && widget.title != null
                ? widget.title
                : tr(context, 'Search items and stores', 'Hae tuotteita ja kauppoja'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr(context, 'Clear search', 'Tyhjennä haku'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      Haptics.selection();
                      _query.clear();
                      _search();
                    }),
            isDense: true,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(26)), borderSide: BorderSide.none),
            enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(26)), borderSide: BorderSide.none),
            focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(26)), borderSide: BorderSide.none),
            filled: true,
            fillColor: AppTheme.inputBackground(context),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr(context, 'Items', 'Tuotteet'))),
                    ButtonSegment(value: true, label: Text(tr(context, 'Stores', 'Kaupat'))),
                  ],
                  selected: {_storesTab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    Haptics.selection();
                    setState(() => _storesTab = s.first);
                    _search();
                  },
                ),
              ),
              SizedBox(height: 48, child: _storesTab ? const SizedBox.shrink() : _filters()),
            ],
          ),
        ),
      ),
      body: _loading
          ? (_storesTab ? const MSkeletonList(thumbnail: true, thumbHeight: 44) : const MSkeletonProductGrid())
          : _error != null
              ? RefreshIndicator(onRefresh: _search, child: MStateMessage.error(message: _error!, onRetry: _search))
              : _storesTab
                  ? _storeList()
                  : _itemGrid(),
    );
  }

  Widget _filters() {
    // Active filters can be removed with their × (the chip itself still opens the choice)
    Widget chip(String label, bool active, VoidCallback onTap, {VoidCallback? onRemove}) => Padding(
          padding: const EdgeInsets.only(right: MSpace.sm),
          child: FilterChip(
            label: Text(label),
            selected: active,
            showCheckmark: false,
            onSelected: (_) {
              Haptics.selection();
              onTap();
            },
            deleteButtonTooltipMessage: tr(context, 'Remove filter', 'Poista suodatin'),
            onDeleted: active && onRemove != null
                ? () {
                    Haptics.selection();
                    setState(onRemove);
                    _search();
                  }
                : null,
          ),
        );
    final sortLabel = {
      'relevance': tr(context, 'Recommended', 'Suositellut'),
      'newest': tr(context, 'Newest', 'Uusimmat'),
      'price_asc': tr(context, 'Price: low to high', 'Hinta: halvin ensin'),
      'price_desc': tr(context, 'Price: high to low', 'Hinta: kallein ensin'),
      'rating': tr(context, 'Best rated stores', 'Parhaat arviot'),
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(MSpace.lg, 6, MSpace.lg, 6),
      children: [
        if (_category != null)
          chip(widget.title ?? _category!, true, () => _clear(() => _category = null), onRemove: () => _category = null),
        chip(sortLabel[_sort]!, _sort != 'relevance', () => _pick(sortLabel.keys.toList(), sortLabel, _sort, (v) => _sort = v ?? 'relevance', allowClear: false),
            onRemove: () => _sort = 'relevance'),
        chip(_size == null ? tr(context, 'Size', 'Koko') : '${tr(context, 'Size', 'Koko')} $_size', _size != null,
            () => _pick(_sizes, {for (final s in _sizes) s: s == 'One Size' ? tr(context, 'One size', 'Yksi koko') : s}, _size, (v) => _size = v),
            onRemove: () => _size = null),
        chip(_priceLabel(), _minPrice != null || _maxPrice != null, _pickPrice, onRemove: () {
          _minPrice = null;
          _maxPrice = null;
        }),
        chip(tr(context, 'Second hand', 'Käytetty'), _secondHand, () {
          setState(() => _secondHand = !_secondHand);
          _search();
        }, onRemove: () => _secondHand = false),
        chip(_condition == null ? tr(context, 'Condition', 'Kunto') : _conditionLabel(_condition!), _condition != null,
            () => _pick(['NEW', 'LIKE_NEW', 'GOOD', 'FAIR'], {for (final c in ['NEW', 'LIKE_NEW', 'GOOD', 'FAIR']) c: _conditionLabel(c)}, _condition, (v) => _condition = v),
            onRemove: () => _condition = null),
      ],
    );
  }

  void _clear(VoidCallback change) {
    setState(change);
    _search();
  }

  String _conditionLabel(String c) => {
        'NEW': tr(context, 'New', 'Uusi'),
        'LIKE_NEW': tr(context, 'Like new', 'Kuin uusi'),
        'GOOD': tr(context, 'Good', 'Hyvä'),
        'FAIR': tr(context, 'Fair', 'Kohtalainen'),
      }[c] ??
      c;

  String _priceLabel() {
    if (_minPrice == null && _maxPrice == null) return tr(context, 'Price', 'Hinta');
    final min = _minPrice != null ? euro(context, _minPrice) : '';
    final max = _maxPrice != null ? euro(context, _maxPrice) : '';
    return '$min – $max';
  }

  Future<void> _pick(List<String> values, Map<String, String> labels, String? current, void Function(String?) apply, {bool allowClear = true}) async {
    final picked = await showMSheet<String>(context, builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final v in values)
              ListTile(
                title: Text(labels[v] ?? v),
                trailing: v == current ? const Icon(Icons.check_rounded, color: AppTheme.primary) : null,
                onTap: () {
                  Haptics.selection();
                  Navigator.pop(ctx, v);
                },
              ),
            if (allowClear && current != null)
              ListTile(title: Text(tr(context, 'Clear', 'Tyhjennä')), onTap: () => Navigator.pop(ctx, '')),
          ],
        ),
      ), isScrollControlled: false, useSafeArea: false);
    if (picked == null) return;
    setState(() => apply(picked.isEmpty ? null : picked));
    _search();
  }

  Future<void> _pickPrice() async {
    final min = TextEditingController(text: _minPrice != null ? '${_minPrice! ~/ 100}' : '');
    final max = TextEditingController(text: _maxPrice != null ? '${_maxPrice! ~/ 100}' : '');
    final ok = await showMSheet<bool>(context, builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(context, 'Price (€)', 'Hinta (€)'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: MSpace.lg),
            Row(children: [
              Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'From', 'Alkaen')))),
              const SizedBox(width: MSpace.md),
              Expanded(child: TextField(controller: max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'To', 'Enintään')))),
            ]),
            const SizedBox(height: MSpace.lg),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Show results', 'Näytä tulokset')))),
          ],
        ),
      ), isScrollControlled: true, useSafeArea: false);
    if (ok != true) return;
    final a = int.tryParse(min.text.trim());
    final b = int.tryParse(max.text.trim());
    setState(() {
      _minPrice = a != null ? a * 100 : null;
      _maxPrice = b != null ? b * 100 : null;
    });
    _search();
  }

  Widget _itemGrid() {
    final idle = _query.text.trim().isEmpty && !_hasFilters;
    return RefreshIndicator(
      onRefresh: _search,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // Builds a screen of tiles ahead, so photos are ready before they scroll in
        cacheExtent: 800,
        slivers: [
          if (idle && (_recent.isNotEmpty || _items.isNotEmpty)) SliverToBoxAdapter(child: _startPoints()),
          if (!idle && _matched.isNotEmpty) SliverToBoxAdapter(child: _matchedCategories()),
          if (_items.isEmpty)
            SliverToBoxAdapter(child: _noResults())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, 140),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ProductTile(product: _items[i], onOpen: _remember),
                  childCount: _items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, 14, MSpace.sm, MSpace.xs),
        child: Row(children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppTheme.secondaryText(context))),
          ),
          if (trailing != null) trailing,
        ]),
      );

  /// Categories the query names, above the products ("huulipuna" → Makeup › Lips).
  Widget _matchedCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(tr(context, 'Categories', 'Kategoriat')),
        for (final m in _matched)
          MListTile(
            icon: catalogIcon(m['icon'] as String?),
            title: ((m['path'] as List?) ?? [m]).whereType<Map>().map((x) => catalogName(context, x['name'])).join(' › '),
            onTap: () => _openCategory('${m['slug']}'),
          ),
      ],
    );
  }

  List<Widget> _topChips(int max) => [
        for (final c in _tops.take(max))
          MChip(label: catalogName(context, c['name']), icon: catalogIcon(c['icon'] as String?), onSelected: (_) => _openCategory('${c['slug']}')),
      ];

  /// Under an empty search box: recent searches and quick categories.
  Widget _startPoints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recent.isNotEmpty) ...[
          _sectionLabel(
            tr(context, 'Recent searches', 'Viimeisimmät haut'),
            trailing: TextButton(onPressed: _clearRecent, child: Text(tr(context, 'Clear', 'Tyhjennä'))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _recent)
                  ActionChip(
                    avatar: const Icon(Icons.history_rounded, size: 18),
                    label: Text(r),
                    onPressed: () => _useQuery(r),
                  ),
              ],
            ),
          ),
        ],
        if (_tops.isNotEmpty) ...[
          _sectionLabel(tr(context, 'Browse by category', 'Selaa kategorioittain')),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
            child: Row(children: [
              for (final chip in _topChips(_tops.length)) Padding(padding: const EdgeInsets.only(right: MSpace.sm), child: chip),
            ]),
          ),
        ],
      ],
    );
  }

  /// Nothing matched: say so kindly and offer ways forward.
  Widget _noResults() {
    final muted = AppTheme.secondaryText(context);
    final suggestions = _recent.where((r) => r.toLowerCase() != _query.text.trim().toLowerCase()).take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, MSpace.x4l, 28, 140),
      child: Column(
        children: [
          const MEmptyArt(MArtKind.search),
          const SizedBox(height: 14),
          Text(
            _query.text.trim().isEmpty ? tr(context, 'Nothing here yet', 'Täällä ei ole vielä mitään') : tr(context, 'No matches', 'Ei osumia'),
            style: AppTheme.display(context, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            _hasFilters
                ? tr(context, 'Try fewer filters or another word.', 'Kokeile vähemmän suodattimia tai toista sanaa.')
                : tr(context, 'Try another word, or look around a category.', 'Kokeile toista sanaa tai katso jotain kategoriaa.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: MTextSize.bodyL, height: 1.4),
          ),
          const SizedBox(height: MSpace.lg),
          if (_hasFilters)
            FilledButton.tonalIcon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 20),
              label: Text(tr(context, 'Clear filters', 'Poista suodattimet')),
            ),
          const SizedBox(height: MSpace.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in suggestions)
                ActionChip(avatar: const Icon(Icons.history_rounded, size: 18), label: Text(r), onPressed: () => _useQuery(r)),
              if (!_hasFilters && _matched.isEmpty) ..._topChips(suggestions.isEmpty ? 6 : 3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storeList() {
    if (_stores.isEmpty) {
      return RefreshIndicator(
        onRefresh: _search,
        child: MStateMessage(icon: Icons.storefront_outlined, message: tr(context, 'No stores found. Try another name.', 'Kauppoja ei löytynyt. Kokeile toista nimeä.')),
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.sm, MSpace.sm, 140),
      itemCount: _stores.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.cardBorder(context)),
      itemBuilder: (_, i) {
        final s = _stores[i];
        final eta = etaWindow(s);
        final reviews = asInt(s['totalReviews']) ?? 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryLight,
            backgroundImage: s['logoUrl'] != null ? sizedImageProvider(context, s['logoUrl'], 40) : null,
            child: s['logoUrl'] == null ? const Icon(Icons.storefront_rounded, color: AppTheme.primary) : null,
          ),
          title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            if (reviews > 0) '★ ${s['rating']}',
            if (eta != null) eta,
            '${euro(context, s['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}',
          ].join(' · ')),
          onTap: () {
            Haptics.selection();
            _remember();
            Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: s)));
          },
        );
      },
      ),
    );
  }
}
