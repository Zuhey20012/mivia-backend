import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// Shared helpers for the API 2.12 catalogue: category icons and tile colours sent by the server,
/// the audience switch, and how facet choices become search parameters.

/// The Material icon for an icon name sent by `GET /categories` and `GET /collections`.
/// Unknown names fall back to a neutral hanger.
IconData catalogIcon(String? name) => _icons[name] ?? Icons.checkroom_rounded;

const _icons = <String, IconData>{
  'checkroom': Icons.checkroom_rounded,
  'water_drop': Icons.water_drop_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'spa': Icons.spa_outlined,
  'snowshoeing': Icons.snowshoeing_rounded,
  'redeem': Icons.redeem_rounded,
  'diamond': Icons.diamond_outlined,
  'brush': Icons.brush_outlined,
  'back_hand': Icons.back_hand_outlined,
  'watch': Icons.watch_outlined,
  'visibility': Icons.visibility_outlined,
  'local_florist': Icons.local_florist_outlined,
  'face': Icons.face_outlined,
  'dry_cleaning': Icons.dry_cleaning_outlined,
  'directions_run': Icons.directions_run_rounded,
  'work': Icons.work_outline_rounded,
  'wb_sunny': Icons.wb_sunny_outlined,
  'waves': Icons.waves_rounded,
  'umbrella': Icons.umbrella_outlined,
  'recycling': Icons.recycling_rounded,
  'palette': Icons.palette_outlined,
  'opacity': Icons.opacity_rounded,
  'luggage': Icons.luggage_outlined,
  'hiking': Icons.hiking_rounded,
  'content_cut': Icons.content_cut_rounded,
  'child_care': Icons.child_care_rounded,
  'celebration': Icons.celebration_outlined,
  'auto_awesome': Icons.auto_awesome_outlined,
  'air': Icons.air_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'weekend': Icons.weekend_outlined,
  'verified': Icons.verified_outlined,
  'style': Icons.style_outlined,
  'straighten': Icons.straighten_rounded,
  'sort_by_alpha': Icons.sort_by_alpha_rounded,
  'shower': Icons.shower_outlined,
  'science': Icons.science_outlined,
  'school': Icons.school_outlined,
  'radio_button_unchecked': Icons.radio_button_unchecked_rounded,
  'push_pin': Icons.push_pin_outlined,
  'pregnant_woman': Icons.pregnant_woman_rounded,
  'pool': Icons.pool_rounded,
  'nightlight': Icons.nightlight_outlined,
  'local_mall': Icons.local_mall_outlined,
  'history': Icons.history_rounded,
  'hearing': Icons.hearing_outlined,
  'flag': Icons.flag_outlined,
  'fitness_center': Icons.fitness_center_rounded,
  'festival': Icons.festival_outlined,
  'face_retouching_natural': Icons.face_retouching_natural_outlined,
  'face_6': Icons.face_6_outlined,
  'electrical_services': Icons.electrical_services_outlined,
  'downhill_skiing': Icons.downhill_skiing_rounded,
  'beach_access': Icons.beach_access_outlined,
  'backpack': Icons.backpack_outlined,
  'account_balance_wallet': Icons.account_balance_wallet_outlined,
  'accessible': Icons.accessible_rounded,
};

/// The pastel fill and the icon/text colour of a tile colour name sent by the API
/// (`lilac`, `mint`, `peach`, `sand`, `clay`, `sunshineLight`), for light and dark mode.
({Color fill, Color ink}) catalogTile(BuildContext context, String? tile) {
  final c = context.mColors;
  final p = context.mPastels;
  return switch (tile) {
    'lilac' => (fill: p.lilac, ink: c.onPrimarySoft),
    'mint' => (fill: p.mint, ink: c.onSuccessSoft),
    'peach' => (fill: p.peach, ink: c.sale),
    'clay' => (fill: p.clay, ink: c.isDark ? c.onSurface : p.clayInk),
    'sunshineLight' || 'sunshine' => (fill: c.sunshineSoft, ink: c.onSunshineSoft),
    _ => (fill: p.sand, ink: c.isDark ? c.onSurface : p.clayInk),
  };
}

/// The audience switch at the top of Home (docs/design/category-sections-v2.md §2).
@immutable
class AudienceChoice {
  /// WOMEN, MEN, KIDS or null (All).
  final String? audience;

  /// BABY, TODDLER, KIDS, JUNIOR, TEEN or null.
  final String? ageGroup;

  const AudienceChoice({this.audience, this.ageGroup});

  static const all = AudienceChoice();

  /// The top-level choice: all, women, men, kids, teens.
  String get key => ageGroup == 'TEEN' ? 'teens' : (audience?.toLowerCase() ?? 'all');

  bool get isKids => audience == 'KIDS';

  /// Query parameters for /categories, /collections and /products/search.
  Map<String, String> get query => {
        if (audience != null) 'audience': audience!,
        if (ageGroup != null) 'ageGroup': ageGroup!,
      };

  @override
  bool operator ==(Object other) => other is AudienceChoice && other.audience == audience && other.ageGroup == ageGroup;

  @override
  int get hashCode => Object.hash(audience, ageGroup);
}

/// The audience chosen on Home, shared with the category screens opened from it.
final homeAudience = ValueNotifier<AudienceChoice>(AudienceChoice.all);

/// A `{en, fi}` name from the API in the app language.
String catalogName(BuildContext context, dynamic name) => localized(context, name) ?? '';

/// Facets the search takes as their own parameter (single value).
const _singleParamFacets = {'condition', 'audience', 'ageGroup'};

/// Facets the search takes as their own parameter (comma-separated values).
const _namedFacets = {
  'colourFamily', 'shadeFamily', 'undertone', 'finish', 'skinType', 'hairType', 'concentration', 'metal', 'fibre',
  'brand', 'productType', 'fitCollection', 'certificate',
};

/// Facets with one value at a time (the API takes one condition, audience and age group).
bool facetIsSingle(String key) => _singleParamFacets.contains(key);

/// The search parameters for the chosen facet values: named filters as `key=a,b`, the rest as
/// `attr[key]=a,b`, condition / audience / age group as one value.
Map<String, String> facetQuery(Map<String, Set<String>> chosen) {
  final out = <String, String>{};
  chosen.forEach((key, values) {
    if (values.isEmpty) return;
    if (_singleParamFacets.contains(key)) {
      out[key] = values.first;
    } else if (_namedFacets.contains(key)) {
      out[key] = values.join(',');
    } else {
      out['attr[$key]'] = values.join(',');
    }
  });
  return out;
}

/// Sort choices of the product search.
Map<String, String> sortLabels(BuildContext context) => {
      'relevance': tr(context, 'Recommended', 'Suositellut'),
      'newest': tr(context, 'Newest', 'Uusimmat'),
      'price_asc': tr(context, 'Price: low to high', 'Hinta: halvin ensin'),
      'price_desc': tr(context, 'Price: high to low', 'Hinta: kallein ensin'),
      'rating': tr(context, 'Best rated shops', 'Parhaiten arvioidut kaupat'),
    };

/// "Nov 2026" style month from the API's "YYYY-MM".
String monthText(BuildContext context, String? ym) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(ym ?? '');
  if (m == null) return ym ?? '';
  return '${int.parse(m.group(2)!)}/${m.group(1)}';
}

/// A date the API sent ("2026-10-27T…" or "2026-10-27") as "27.10.2026" / "27/10/2026".
String shortDate(BuildContext context, dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  return isFinnish(context) ? '${d.day}.${d.month}.${d.year}' : '${d.day}/${d.month}/${d.year}';
}
