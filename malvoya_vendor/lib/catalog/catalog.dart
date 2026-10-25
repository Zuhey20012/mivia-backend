import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// Catalogue data for the store editor (API 2.12): the category tree, the attribute templates, the
/// certificate schemes and the field-level issues of a 422. Everything the form shows comes from the
/// server; the app only knows where each field goes on screen.

typedef Json = Map<String, dynamic>;

/// Session caches: the tree and templates change only with a backend release or an admin rename.
class CatalogCache {
  CatalogCache._();
  static List<Json>? categories;
  static Map<String, Json>? templates;
  static List<Json>? schemes;

  static Future<List<Json>?> loadCategories(ApiClient api, {bool force = false}) async {
    if (categories != null && !force) return categories;
    final res = await api.get('/categories', query: {'includeEmpty': '1'});
    if (!res.ok || res.data['categories'] is! List) return null;
    categories = (res.data['categories'] as List).whereType<Map>().map((m) => Json.from(m)).toList();
    return categories;
  }

  static Future<Map<String, Json>?> loadTemplates(ApiClient api, {bool force = false}) async {
    if (templates != null && !force) return templates;
    final res = await api.get('/categories/templates');
    if (!res.ok || res.data['templates'] is! List) return null;
    templates = {
      for (final t in (res.data['templates'] as List).whereType<Map>()) '${t['template']}': Json.from(t),
    };
    return templates;
  }

  static Future<List<Json>?> loadSchemes(ApiClient api) async {
    if (schemes != null) return schemes;
    final res = await api.get('/categories/certificate-schemes');
    if (!res.ok || res.data['schemes'] is! List) return null;
    schemes = (res.data['schemes'] as List).whereType<Map>().map((m) => Json.from(m)).toList();
    return schemes;
  }

  /// A subcategory by slug, with its top level: (sub, top) or null.
  static (Json, Json)? findSub(String? slug) {
    if (slug == null) return null;
    for (final top in categories ?? const <Json>[]) {
      for (final c in (top['children'] as List? ?? const []).whereType<Map>()) {
        if (c['slug'] == slug) return (Json.from(c), top);
      }
    }
    return null;
  }
}

const cosmeticTemplates = {'COSMETIC_MAKEUP', 'COSMETIC_SKIN', 'COSMETIC_HAIR', 'COSMETIC_NAIL', 'FRAGRANCE'};
bool isCosmeticTemplate(String? t) => t != null && cosmeticTemplates.contains(t);
const shadeTemplates = {'COSMETIC_MAKEUP', 'COSMETIC_NAIL'};
const beautyTops = {'makeup', 'skincare', 'haircare', 'fragrance'};

/// EU and EEA countries (an EU responsible person is needed for a manufacturer elsewhere).
const euEea = {
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL',
  'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE', 'IS', 'LI', 'NO',
};
bool inEu(String? country) => country != null && euEea.contains(country.toUpperCase());

/// The template's label for a value ("Musta" for black), or the value humanised.
String valueLabel(BuildContext context, Json? field, Object? value) {
  for (final v in (field?['values'] as List? ?? const []).whereType<Map>()) {
    if ('${v['value']}' == '$value') return localized(context, v['label']) ?? '$value';
  }
  return '$value'.replaceAll('_', ' ');
}

String fieldLabel(BuildContext context, Json? field, String fallback) => localized(context, field?['label']) ?? fallback;

/// One field-level problem from the API (`{field, code, message: {en, fi}}`).
class FieldIssue {
  final String field;
  final String code;
  final Object? message;
  const FieldIssue(this.field, this.code, this.message);

  String text(BuildContext context) => localized(context, message) ?? field;

  /// Where on screen it belongs: `attributes.fibreComposition.0` → `attributes.fibreComposition`,
  /// `variants.3.size` → `variants`, the size chart (per-size measurements) → `variants`.
  String get anchor => anchorOf(field);

  static String anchorOf(String field) {
    final parts = field.split('.');
    if (parts.first == 'variants') return 'variants';
    if (parts.first == 'attributes' && parts.length >= 2) {
      if (parts[1] == 'sizeChart') return 'variants';
      return 'attributes.${parts[1]}';
    }
    if (field == 'tags') return 'description';
    return parts.first;
  }

  static List<FieldIssue> parse(dynamic list) => (list is List ? list : const [])
      .whereType<Map>()
      .map((m) => FieldIssue('${m['field'] ?? ''}', '${m['code'] ?? ''}', m['message']))
      .toList();
}

/// GS1 check digit (GTIN-8/12/13/14), like the API.
bool validGtin(String v) {
  if (!RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(v)) return false;
  final digits = v.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    sum += digits[digits.length - 1 - i] * (i.isEven ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10 == check;
}

/// Material icon names the API uses for categories.
IconData categoryIcon(String? name) => switch (name) {
      'checkroom' => Icons.checkroom_rounded,
      'dry_cleaning' => Icons.dry_cleaning_rounded,
      'snowshoeing' => Icons.snowshoeing_rounded,
      'directions_run' => Icons.directions_run_rounded,
      'shopping_bag' => Icons.shopping_bag_outlined,
      'watch' => Icons.watch_outlined,
      'diamond' => Icons.diamond_outlined,
      'brush' => Icons.brush_outlined,
      'spa' => Icons.spa_outlined,
      'content_cut' => Icons.content_cut_rounded,
      'local_florist' => Icons.local_florist_outlined,
      'recycling' => Icons.recycling_rounded,
      'nightlight' => Icons.nightlight_outlined,
      'pool' => Icons.pool_rounded,
      'umbrella' => Icons.umbrella_outlined,
      'work' => Icons.work_outline_rounded,
      'celebration' => Icons.celebration_outlined,
      'sports' || 'sports_handball' || 'fitness_center' => Icons.fitness_center_rounded,
      'hiking' => Icons.hiking_rounded,
      'downhill_skiing' => Icons.downhill_skiing_rounded,
      'face' || 'face_retouching_natural' => Icons.face_retouching_natural_rounded,
      'wallet' => Icons.account_balance_wallet_outlined,
      'backpack' => Icons.backpack_outlined,
      'luggage' => Icons.luggage_outlined,
      'sunny' || 'wb_sunny' => Icons.wb_sunny_outlined,
      _ => Icons.category_outlined,
    };

/// Generic environmental claims (Directive (EU) 2024/825): a quick check while typing. The server's
/// claims checker is the one that decides; this only warns early.
List<String> greenClaimsIn(String text) {
  final t = text.toLowerCase();
  final hits = <String>[];
  const fi = {
    'ympäristöystävällinen': 'ympäristöystävälli', 'luontoystävällinen': 'luontoystävälli', 'ilmastoystävällinen': 'ilmastoystävälli',
    'ekologinen': 'ekologi', 'vastuullinen': 'vastuulli', 'hiilineutraali': 'hiilineutraal', 'ilmastoneutraali': 'ilmastoneutraal',
    'biohajoava': 'biohajoa', 'kompostoituva': 'kompostoitu',
  };
  fi.forEach((term, stem) {
    if (t.contains(stem)) hits.add(term);
  });
  const en = {
    'eco-friendly': r'eco[- ]?friendly', 'environmentally friendly': r'environment(ally)?[- ]?friendly', 'sustainable': r'\bsustainab',
    'biodegradable': r'\bbiodegradab', 'carbon neutral': r'carbon[- ]?(neutral|negative|positive)', 'climate neutral': r'climate[- ]?neutral',
    'planet-friendly': r'planet[- ]?friendly', 'eco': r'(^|[^a-zäöå0-9])eco(-|$|[^a-zäöå0-9])', 'eko': r'(^|[^a-zäöå0-9])eko(-|$|[^a-zäöå0-9])',
  };
  en.forEach((term, re) {
    if (RegExp(re).hasMatch(t) && !(term == 'eco' && hits.contains('eco-friendly'))) hits.add(term);
  });
  return hits;
}
