import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import '../../catalog/catalog.dart';

/// What step 1 of the editor chose.
class CategoryChoice {
  final String slug;
  final Object? name; // {en, fi}
  final Object? topName;
  final String topSlug;
  final String template;
  final String audience; // WOMEN | MEN | KIDS | UNISEX
  final String? ageGroup; // BABY | TODDLER | KIDS | JUNIOR | TEEN | ADULT
  const CategoryChoice({
    required this.slug,
    required this.name,
    required this.topName,
    required this.topSlug,
    required this.template,
    required this.audience,
    this.ageGroup,
  });
}

/// Step 1 of the product editor: a searchable two-level category list (GET /categories?includeEmpty=1),
/// then who the product is for and, for children, the age group. Recent categories come first.
class CategoryPickerScreen extends StatefulWidget {
  final String? initialSlug;
  final String? initialAudience;
  final String? initialAgeGroup;

  /// True when it opens a new product (the button says "Continue" instead of "Done").
  final bool firstStep;
  const CategoryPickerScreen({super.key, this.initialSlug, this.initialAudience, this.initialAgeGroup, this.firstStep = false});

  @override
  State<CategoryPickerScreen> createState() => _CategoryPickerScreenState();
}

class _CategoryPickerScreenState extends State<CategoryPickerScreen> {
  static const _recentKey = 'editor_recent_categories';
  final _search = TextEditingController();
  List<Json>? _tree;
  bool _loading = true;
  String? _error;
  List<String> _recent = [];
  String? _openTop;

  late String? _slug = widget.initialSlug;
  late String _audience = widget.initialAudience ?? 'WOMEN';
  late String? _ageGroup = widget.initialAgeGroup;

  @override
  void initState() {
    super.initState();
    _load();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList(_recentKey) ?? []);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final tree = await CatalogCache.loadCategories(api, force: force);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _tree = tree;
      _error = tree == null ? tr(context, 'The categories could not be loaded.', 'Kategorioita ei saatu ladattua.') : null;
      final sel = CatalogCache.findSub(_slug);
      _openTop ??= sel == null ? null : '${sel.$2['slug']}';
    });
  }

  /// Subcategories the editor can use (collections and nodes without a template are saved filters).
  List<Json> _subsOf(Json top) => (top['children'] as List? ?? const [])
      .whereType<Map>()
      .map((m) => Json.from(m))
      .where((c) => c['collection'] != true && c['template'] != null)
      .toList();

  List<Json> get _tops => (_tree ?? const []).where((t) => _subsOf(t).isNotEmpty).toList();

  String _name(Object? n) => localized(context, n) ?? '';

  bool get _beauty {
    final sel = CatalogCache.findSub(_slug);
    return sel != null && beautyTops.contains(sel.$2['slug']);
  }

  void _select(Json sub, Json top) {
    Haptics.selection();
    setState(() {
      final wasBeauty = _beauty;
      _slug = '${sub['slug']}';
      // Beauty defaults to Unisex; kids' sections never show beauty
      if (_beauty && !wasBeauty && widget.initialAudience == null) _audience = 'UNISEX';
    });
  }

  Future<void> _done() async {
    final sel = CatalogCache.findSub(_slug);
    if (sel == null) return;
    final (sub, top) = sel;
    try {
      final p = await SharedPreferences.getInstance();
      final next = [_slug!, ..._recent.where((s) => s != _slug)].take(5).toList();
      await p.setStringList(_recentKey, next);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(
      context,
      CategoryChoice(
        slug: '${sub['slug']}',
        name: sub['name'],
        topName: top['name'],
        topSlug: '${top['slug']}',
        template: '${sub['template']}',
        audience: _audience,
        ageGroup: _ageValid(_ageGroup) ? _ageGroup : null,
      ),
    );
  }

  static const _kidsAges = ['BABY', 'TODDLER', 'KIDS', 'JUNIOR', 'TEEN'];
  bool _ageValid(String? a) => a == null || (_audience == 'KIDS' ? _kidsAges.contains(a) : (a == 'ADULT' || a == 'TEEN'));

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(tr(context, 'Category', 'Kategoria'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.md),
          child: MButton(
            label: widget.firstStep ? tr(context, 'Continue', 'Jatka') : tr(context, 'Done', 'Valmis'),
            icon: widget.firstStep ? Icons.arrow_forward_rounded : Icons.check_rounded,
            trailingIcon: widget.firstStep,
            expand: true,
            onPressed: _slug == null || CatalogCache.findSub(_slug) == null ? null : _done,
          ),
        ),
      ),
      body: _loading
          ? const MSkeletonList(count: 6)
          : _error != null
              ? MStateMessage.error(message: _error, onRetry: () => _load(force: true))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l),
                  children: [
                    Text(
                      tr(context, 'Pick the category first. The form then asks only what this kind of product needs.',
                          'Valitse ensin kategoria. Lomake kysyy sitten vain sen, mitä tällainen tuote tarvitsee.'),
                      style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
                    ),
                    const SizedBox(height: MSpace.md),
                    MTextField(
                      controller: _search,
                      label: tr(context, 'Search categories', 'Hae kategorioita'),
                      hint: tr(context, 'e.g. dress, lipstick, sneakers', 'esim. mekko, huulipuna, tennarit'),
                      prefixIcon: Icons.search_rounded,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: MSpace.md),
                    ..._list(),
                    const SizedBox(height: MSpace.lg),
                    _audienceBlock(),
                  ],
                ),
    );
  }

  List<Widget> _list() {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hits = <(Json, Json)>[];
      for (final top in _tops) {
        final topWords = '${(top['name'] as Map?)?['en'] ?? ''} ${(top['name'] as Map?)?['fi'] ?? ''}'.toLowerCase();
        for (final s in _subsOf(top)) {
          final words = '${(s['name'] as Map?)?['en'] ?? ''} ${(s['name'] as Map?)?['fi'] ?? ''} ${s['slug']}'.toLowerCase();
          if (words.contains(q) || topWords.contains(q)) hits.add((s, top));
        }
      }
      if (hits.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MSpace.xl),
            child: Text(tr(context, 'No category matches. Try a broader word, like "shoes" or "skincare".', 'Mikään kategoria ei vastaa. Kokeile yleisempää sanaa, kuten "kengät" tai "ihonhoito".'),
                textAlign: TextAlign.center, style: MType.bodyM.copyWith(color: context.mColors.onSurfaceVariant)),
          ),
        ];
      }
      return [for (final h in hits) _subTile(h.$1, h.$2, showPath: true)];
    }
    final recent = _recent.map(CatalogCache.findSub).whereType<(Json, Json)>().toList();
    return [
      if (recent.isNotEmpty) ...[
        MSectionHeader(tr(context, 'Recent', 'Viimeksi käytetyt'), padding: const EdgeInsets.only(bottom: MSpace.sm)),
        for (final r in recent) _subTile(r.$1, r.$2, showPath: true),
        const SizedBox(height: MSpace.md),
        MSectionHeader(tr(context, 'All categories', 'Kaikki kategoriat'), padding: const EdgeInsets.only(bottom: MSpace.sm)),
      ],
      for (final top in _tops) ...[
        _topTile(top),
        if (_openTop == '${top['slug']}')
          Padding(
            padding: const EdgeInsets.only(left: MSpace.lg, bottom: MSpace.sm),
            child: Column(children: [for (final s in _subsOf(top)) _subTile(s, top)]),
          ),
      ],
    ];
  }

  Widget _topTile(Json top) {
    final open = _openTop == '${top['slug']}';
    final hasSelected = _subsOf(top).any((s) => s['slug'] == _slug);
    return MListTile(
      title: _name(top['name']),
      subtitle: hasSelected && !open ? _name(CatalogCache.findSub(_slug)?.$1['name']) : null,
      icon: categoryIcon('${top['icon']}'),
      chevron: false,
      trailing: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
      onTap: () => setState(() => _openTop = open ? null : '${top['slug']}'),
    );
  }

  Widget _subTile(Json sub, Json top, {bool showPath = false}) {
    final selected = sub['slug'] == _slug;
    final c = context.mColors;
    return Semantics(
      selected: selected,
      child: MListTile(
        title: _name(sub['name']),
        subtitle: showPath ? _name(top['name']) : null,
        icon: categoryIcon('${sub['icon']}'),
        iconBackground: selected ? c.primarySoft : null,
        chevron: false,
        trailing: selected ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
        onTap: () => _select(sub, top),
      ),
    );
  }

  Widget _audienceBlock() {
    final c = context.mColors;
    final audiences = {
      'WOMEN': tr(context, 'Women', 'Naiset'),
      'MEN': tr(context, 'Men', 'Miehet'),
      'UNISEX': tr(context, 'Unisex', 'Unisex'),
      if (!_beauty || _audience == 'KIDS') 'KIDS': tr(context, 'Kids', 'Lapset'),
    };
    final ages = _audience == 'KIDS'
        ? {
            'BABY': tr(context, 'Baby 0–2', 'Vauvat 0–2 v'),
            'TODDLER': tr(context, 'Toddler 2–4', 'Taaperot 2–4 v'),
            'KIDS': tr(context, 'Kids 4–8', 'Lapset 4–8 v'),
            'JUNIOR': tr(context, 'Junior 8–14', 'Juniorit 8–14 v'),
            'TEEN': tr(context, 'Teens 13–17', 'Nuoret 13–17 v'),
          }
        : {
            'ADULT': tr(context, 'Adult', 'Aikuiset'),
            'TEEN': tr(context, 'Teens 13–17', 'Nuoret 13–17 v'),
          };
    return Container(
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'Who is it for?', 'Kenelle tuote on?'), style: MType.title),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.xs, children: [
          for (final a in audiences.entries)
            MChip(
              label: a.value,
              selected: _audience == a.key,
              onSelected: (_) => setState(() {
                _audience = a.key;
                if (!_ageValid(_ageGroup)) _ageGroup = null;
              }),
            ),
        ]),
        const SizedBox(height: MSpace.md),
        Text(_audience == 'KIDS' ? tr(context, 'Age group', 'Ikäryhmä') : tr(context, 'Age group (optional)', 'Ikäryhmä (valinnainen)'), style: MType.label),
        const SizedBox(height: MSpace.xs),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.xs, children: [
          for (final a in ages.entries)
            MChip(label: a.value, selected: _ageGroup == a.key, onSelected: (v) => setState(() => _ageGroup = v ? a.key : null)),
        ]),
        if (_audience == 'KIDS')
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Text(
              tr(context, 'Children\'s clothes use sizes in cm (height 50–176) and need the cords and drawstrings check.',
                  'Lastenvaatteissa koot ovat senttimetreinä (pituus 50–176), ja niistä kysytään narut ja kiristysnyörit.'),
              style: MType.caption.copyWith(color: c.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}
