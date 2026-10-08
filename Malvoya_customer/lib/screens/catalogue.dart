import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/delivery_location.dart';
import '../core/strings.dart';
import '../widgets/product_tile.dart';
import 'store_detail.dart';

/// Search across every store: items with size, price, condition and second-hand filters,
/// or stores by name.
class CatalogueScreen extends StatefulWidget {
  final bool isTab;
  final String? title;
  final String? initialQuery;
  final String? category;
  final bool secondHand;
  final bool eco;

  const CatalogueScreen({super.key, this.isTab = false, this.title, this.initialQuery, this.category, this.secondHand = false, this.eco = false});

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
  int? _minPrice;
  int? _maxPrice;

  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _stores = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  static const _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size'];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
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
        if (widget.category != null) 'category': widget.category!,
        if (_size != null) 'size': _size!,
        if (_condition != null) 'condition': _condition!,
        if (_secondHand) 'secondHand': 'true',
        if (widget.eco) 'eco': 'true',
        if (_minPrice != null) 'minPrice': '$_minPrice',
        if (_maxPrice != null) 'maxPrice': '$_maxPrice',
        'sort': _sort,
        'limit': '24',
      };

  Future<void> _search() async {
    setState(() {
      _loading = true;
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _stores = res.ok ? ((res.data['stores'] as List?) ?? []).map((s) => Map<String, dynamic>.from(s)).toList() : [];
        _error = res.ok ? null : res.error;
      });
      return;
    }
    final res = await api.get('/products/search', query: {..._params, 'page': '1'});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items.clear();
      if (res.ok) {
        _items.addAll(((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)));
        _total = asInt(res.data['total']) ?? _items.length;
      } else {
        _error = res.error;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_storesTab || _loading || _loadingMore || _items.length >= _total) return;
    _loadingMore = true;
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/products/search', query: {..._params, 'page': '${_page + 1}'});
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        _page++;
        _items.addAll(((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)));
      }
    });
  }

  void _onQuery(String _) {
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
          autofocus: !widget.isTab && widget.category == null && !widget.secondHand && !widget.eco,
          onChanged: _onQuery,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: widget.title ?? tr(context, 'Search items and stores', 'Hae tuotteita ja kauppoja'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr(context, 'Items', 'Tuotteet'))),
                    ButtonSegment(value: true, label: Text(tr(context, 'Stores', 'Kaupat'))),
                  ],
                  selected: {_storesTab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    HapticFeedback.selectionClick();
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _storesTab
                  ? _storeList()
                  : _itemGrid(),
    );
  }

  Widget _filters() {
    Widget chip(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(label),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => onTap(),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      children: [
        chip(sortLabel[_sort]!, _sort != 'relevance', () => _pick(sortLabel.keys.toList(), sortLabel, _sort, (v) => _sort = v ?? 'relevance', allowClear: false)),
        chip(_size == null ? tr(context, 'Size', 'Koko') : '${tr(context, 'Size', 'Koko')} $_size', _size != null,
            () => _pick(_sizes, {for (final s in _sizes) s: s}, _size, (v) => _size = v)),
        chip(_priceLabel(), _minPrice != null || _maxPrice != null, _pickPrice),
        chip(tr(context, 'Second hand', 'Käytetty'), _secondHand, () {
          setState(() => _secondHand = !_secondHand);
          _search();
        }),
        chip(_condition == null ? tr(context, 'Condition', 'Kunto') : _conditionLabel(_condition!), _condition != null,
            () => _pick(['NEW', 'LIKE_NEW', 'GOOD', 'FAIR'], {for (final c in ['NEW', 'LIKE_NEW', 'GOOD', 'FAIR']) c: _conditionLabel(c)}, _condition, (v) => _condition = v)),
      ],
    );
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
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final v in values)
              ListTile(
                title: Text(labels[v] ?? v),
                trailing: v == current ? const Icon(Icons.check_rounded, color: AppTheme.primary) : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
            if (allowClear && current != null)
              ListTile(title: Text(tr(context, 'Clear', 'Tyhjennä')), onTap: () => Navigator.pop(ctx, '')),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => apply(picked.isEmpty ? null : picked));
    _search();
  }

  Future<void> _pickPrice() async {
    final min = TextEditingController(text: _minPrice != null ? '${_minPrice! ~/ 100}' : '');
    final max = TextEditingController(text: _maxPrice != null ? '${_maxPrice! ~/ 100}' : '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(context, 'Price (€)', 'Hinta (€)'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'From', 'Alkaen')))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'To', 'Enintään')))),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Show results', 'Näytä tulokset')))),
          ],
        ),
      ),
    );
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
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr(context, 'Nothing found. Try another word or fewer filters.', 'Ei tuloksia. Kokeile toista hakusanaa tai vähemmän suodattimia.'),
              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context))),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
      itemCount: _items.length,
      itemBuilder: (_, i) => ProductTile(product: _items[i]),
    );
  }

  Widget _storeList() {
    if (_stores.isEmpty) {
      return Center(child: Text(tr(context, 'No stores found.', 'Kauppoja ei löytynyt.'), style: TextStyle(color: AppTheme.secondaryText(context))));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 140),
      itemCount: _stores.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.cardBorder(context)),
      itemBuilder: (_, i) {
        final s = _stores[i];
        final eta = etaWindow(s);
        final reviews = asInt(s['totalReviews']) ?? 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryLight,
            backgroundImage: s['logoUrl'] != null ? CachedNetworkImageProvider(s['logoUrl']) : null,
            child: s['logoUrl'] == null ? const Icon(Icons.storefront_rounded, color: AppTheme.primary) : null,
          ),
          title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            if (reviews > 0) '★ ${s['rating']}',
            if (eta != null) eta,
            '${euro(context, s['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}',
          ].join(' · ')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: s))),
        );
      },
    );
  }
}
