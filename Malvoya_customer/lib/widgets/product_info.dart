import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../core/catalog.dart';
import '../screens/size_shade_help_screen.dart';
import 'app_image.dart';

/// The API 2.12 product facts shown on the product page: materials and care, the cosmetics label
/// facts (INCI, how to use, precautions, content, PAO), product safety and the manufacturer,
/// verified certificates, the recall banner, the hygiene-seal notice, the shop's size chart and
/// "Report this product". Everything comes from the product payload; a block without data is not
/// shown.

Map<String, dynamic> _attrs(Map<String, dynamic> p) => p['attributes'] is Map ? Map<String, dynamic>.from(p['attributes']) : const {};

bool _filled(dynamic v) => v != null && '$v'.trim().isNotEmpty;

/// The app-language text of an `{fi, sv, en}` value (Finnish or English, the other as fallback).
String? appLanguageText(BuildContext context, dynamic m) {
  if (m is String) return m.trim().isEmpty ? null : m;
  if (m is! Map) return null;
  final fi = isFinnish(context);
  for (final k in fi ? ['fi', 'en'] : ['en', 'fi']) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// The Swedish text of an `{fi, sv, en}` value, when there is one.
String? swedishText(dynamic m) {
  final v = m is Map ? m['sv'] : null;
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) MSnack.error(context, tr(context, 'Could not open the link.', 'Linkkiä ei voitu avata.'));
}

/// "50 ml", "200 g", "3 pcs" / "3 kpl".
String? contentText(BuildContext context, dynamic amount, dynamic unit) {
  if (amount is! num || amount <= 0 || unit is! String) return null;
  final n = amount == amount.roundToDouble() ? '${amount.toInt()}' : (isFinnish(context) ? '$amount'.replaceAll('.', ',') : '$amount');
  return switch (unit) {
    'ml' => '$n ml',
    'g' => '$n g',
    'pcs' => tr(context, '$n pcs', '$n kpl'),
    _ => null,
  };
}

/// A section title on the product page.
class InfoHeading extends StatelessWidget {
  final String text;
  const InfoHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: MSpace.xl, bottom: MSpace.sm),
        child: Semantics(header: true, child: Text(text, style: MType.title.copyWith(color: context.mColors.onSurface))),
      );
}

Widget _fact(BuildContext context, String label, String value) {
  final c = context.mColors;
  return Padding(
    padding: const EdgeInsets.only(bottom: MSpace.sm),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: MType.caption.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      SelectableText(value, style: MType.bodyM.copyWith(color: c.onSurface)),
    ]),
  );
}

// ── Recall ───────────────────────────────────────────────────────────────

/// A red banner on a recalled product (GPSR): what it is and a link to the public notice.
class RecallBanner extends StatelessWidget {
  final Map<String, dynamic> product;
  const RecallBanner({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final recall = product['recall'];
    if (recall is! Map) return const SizedBox.shrink();
    final c = context.mColors;
    final url = '${recall['url'] ?? ''}';
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: MSpace.lg),
        padding: const EdgeInsets.all(MSpace.lg),
        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: MRadius.brMd, border: Border.all(color: c.danger, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.report_rounded, color: c.onDangerSoft),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Text(tr(context, 'Product safety recall', 'Tuotteen turvallisuuteen liittyvä takaisinveto'),
                  style: MType.bodyL.copyWith(fontWeight: FontWeight.w800, color: c.onDangerSoft)),
            ),
          ]),
          if (_filled(recall['title'])) ...[
            const SizedBox(height: MSpace.xs),
            Text('${recall['title']}', style: MType.bodyM.copyWith(color: c.onDangerSoft)),
          ],
          const SizedBox(height: MSpace.xs),
          Text(
            tr(context, 'This product can no longer be bought. If you have one, stop using it and read the notice for what to do.',
                'Tuotetta ei voi enää ostaa. Jos sinulla on tämä tuote, lopeta sen käyttö ja lue ohjeet tiedotteesta.'),
            style: MType.bodyM.copyWith(color: c.onDangerSoft),
          ),
          if (url.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: MButton(
                label: tr(context, 'Read the recall notice', 'Lue takaisinvetotiedote'),
                variant: MButtonVariant.danger,
                size: MButtonSize.sm,
                icon: Icons.open_in_new_rounded,
                onPressed: () => _openLink(context, url),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Hygiene seal ─────────────────────────────────────────────────────────

/// Shown before the product goes in the bag, for hygiene-sealed items (KSL 6:16).
class HygieneSealNotice extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool compact;
  const HygieneSealNotice({super.key, required this.product, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (product['hygieneSealed'] != true) return const SizedBox.shrink();
    final c = context.mColors;
    final body = localized(context, product['hygieneSealNotice']);
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(MSpace.md),
        decoration: BoxDecoration(color: c.sunshineSoft, borderRadius: MRadius.brMd),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline_rounded, size: 20, color: c.onSunshineSoft),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'Hygiene-sealed: cannot be returned once opened', 'Hygieniasinetöity: ei palautettavissa avaamisen jälkeen'),
                  style: MType.label.copyWith(color: c.onSunshineSoft, fontWeight: FontWeight.w800)),
              if (!compact && body != null) ...[
                const SizedBox(height: 2),
                Text(body, style: MType.caption.copyWith(color: c.onSunshineSoft)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Materials and care ───────────────────────────────────────────────────

const _materialWords = <String, List<String>>{
  'leather': ['Leather', 'Nahka'],
  'coated_leather': ['Coated leather', 'Pinnoitettu nahka'],
  'textile': ['Textile', 'Tekstiili'],
  'synthetic_leather': ['Synthetic leather', 'Tekonahka'],
  'plastic': ['Plastic', 'Muovi'],
  'metal': ['Metal', 'Metalli'],
  'wood': ['Wood', 'Puu'],
  'straw': ['Straw', 'Olki'],
  'other': ['Other', 'Muu'],
};

String _material(BuildContext context, dynamic list) => (list is List ? list : [list])
    .whereType<String>()
    .map((k) => _materialWords[k] == null ? k.replaceAll('_', ' ') : tr(context, _materialWords[k]![0], _materialWords[k]![1]))
    .join(', ');

const _care = <String, Map<String, List<String>>>{
  'wash': {
    'W95': ['Machine wash 95 °C', 'Konepesu 95 °C'],
    'W60': ['Machine wash 60 °C', 'Konepesu 60 °C'],
    'W40': ['Machine wash 40 °C', 'Konepesu 40 °C'],
    'W40_MILD': ['Machine wash 40 °C, gentle', 'Konepesu 40 °C, hienopesu'],
    'W30': ['Machine wash 30 °C', 'Konepesu 30 °C'],
    'W30_MILD': ['Machine wash 30 °C, gentle', 'Konepesu 30 °C, hienopesu'],
    'W30_VERY_MILD': ['Machine wash 30 °C, very gentle', 'Konepesu 30 °C, erittäin hellävarainen'],
    'HAND': ['Hand wash', 'Käsinpesu'],
    'NO_WASH': ['Do not wash', 'Ei saa pestä'],
  },
  'bleach': {
    'ANY': ['Bleach allowed', 'Valkaisu sallittu'],
    'OXYGEN_ONLY': ['Oxygen bleach only', 'Vain happivalkaisu'],
    'NO_BLEACH': ['Do not bleach', 'Ei valkaisua'],
  },
  'tumble': {
    'NORMAL': ['Tumble dry, normal heat', 'Rumpukuivaus, normaali lämpö'],
    'LOW': ['Tumble dry, low heat', 'Rumpukuivaus, matala lämpö'],
    'NO_TUMBLE': ['Do not tumble dry', 'Ei rumpukuivausta'],
  },
  'naturalDry': {
    'LINE': ['Line dry', 'Kuivaus narulla'],
    'DRIP_LINE': ['Drip dry on a line', 'Kuivaus narulla linkoamatta'],
    'FLAT': ['Dry flat', 'Kuivaus tasolla'],
    'DRIP_FLAT': ['Drip dry flat', 'Kuivaus tasolla linkoamatta'],
    'LINE_SHADE': ['Line dry in the shade', 'Kuivaus narulla varjossa'],
    'FLAT_SHADE': ['Dry flat in the shade', 'Kuivaus tasolla varjossa'],
  },
  'iron': {
    'HIGH': ['Iron at high heat', 'Silitys korkealla lämmöllä'],
    'MEDIUM': ['Iron at medium heat', 'Silitys keskilämmöllä'],
    'LOW': ['Iron at low heat', 'Silitys matalalla lämmöllä'],
    'NO_IRON': ['Do not iron', 'Ei saa silittää'],
  },
  'professional': {
    'P': ['Professional dry clean', 'Ammattimainen kuivapesu'],
    'P_MILD': ['Professional dry clean, gentle', 'Ammattimainen kuivapesu, hellävarainen'],
    'F': ['Professional dry clean (hydrocarbon)', 'Ammattimainen kuivapesu (hiilivety)'],
    'F_MILD': ['Professional dry clean (hydrocarbon), gentle', 'Ammattimainen kuivapesu (hiilivety), hellävarainen'],
    'NO_DRY_CLEAN': ['Do not dry clean', 'Ei kuivapesua'],
    'W': ['Professional wet clean', 'Ammattimainen märkäpesu'],
    'W_MILD': ['Professional wet clean, gentle', 'Ammattimainen märkäpesu, hellävarainen'],
    'W_VERY_MILD': ['Professional wet clean, very gentle', 'Ammattimainen märkäpesu, erittäin hellävarainen'],
    'NO_WET_CLEAN': ['Do not wet clean', 'Ei ammattimaista märkäpesua'],
  },
};

List<String> _careLines(BuildContext context, dynamic care) {
  if (care is! Map) return const [];
  final out = <String>[];
  for (final group in ['wash', 'bleach', 'tumble', 'naturalDry', 'iron', 'professional']) {
    final words = _care[group]?[care[group]];
    if (words != null) out.add(tr(context, words[0], words[1]));
  }
  return out;
}

/// Materials (fibre composition as on the label, footwear parts, bag material), care, and the
/// condition notes of second-hand items.
class ProductMaterialsSection extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductMaterialsSection({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final a = _attrs(product);
    final c = context.mColors;
    final facts = <Widget>[];
    final composition = localized(context, product['materials']);
    if (composition != null) facts.add(_fact(context, tr(context, 'Material', 'Materiaali'), composition));
    final animal = localized(context, product['animalOriginNotice']);
    if (animal != null) facts.add(Padding(padding: const EdgeInsets.only(bottom: MSpace.sm), child: Text(animal, style: MType.bodyM.copyWith(color: c.onSurface))));
    if (a['fibreCompositionUnknown'] == true && composition == null) {
      facts.add(_fact(context, tr(context, 'Material', 'Materiaali'), tr(context, 'The seller could not give the material.', 'Myyjä ei tiedä materiaalia.')));
    }
    for (final (key, en, fi) in [
      ('materialUpper', 'Upper', 'Päällinen'),
      ('materialLiningSock', 'Lining and insole', 'Vuori ja sisäpohja'),
      ('materialOuterSole', 'Outer sole', 'Ulkopohja'),
      ('mainMaterial', 'Material', 'Materiaali'),
    ]) {
      final v = a[key];
      if (v is List && v.isNotEmpty) facts.add(_fact(context, tr(context, en, fi), _material(context, v)));
    }
    if (_filled(a['materialDetail'])) facts.add(_fact(context, tr(context, 'Material details', 'Materiaalitiedot'), '${a['materialDetail']}'));
    final dims = a['dimensionsCm'];
    if (dims is Map && dims['w'] is num && dims['h'] is num) {
      final d = dims['d'] is num ? ' × ${dims['d']}' : '';
      facts.add(_fact(context, tr(context, 'Size (W × H × D)', 'Mitat (L × K × S)'), '${dims['w']} × ${dims['h']}$d cm'));
    }
    final care = _careLines(context, a['careInstructions']);
    if (care.isNotEmpty) facts.add(_fact(context, tr(context, 'Care', 'Hoito-ohjeet'), care.join('\n')));
    if (_filled(a['defectsNote'])) facts.add(_fact(context, tr(context, 'Condition notes from the seller', 'Myyjän huomiot kunnosta'), '${a['defectsNote']}'));
    if (facts.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoHeading(tr(context, 'Materials and care', 'Materiaalit ja hoito')),
      ...facts,
    ]);
  }
}

// ── Cosmetics ────────────────────────────────────────────────────────────

/// The label facts of cosmetics and fragrance (Reg. 1223/2009 Art. 19): what it is for, content,
/// shelf life after opening, how to use, precautions and the full INCI list.
class CosmeticsSection extends StatelessWidget {
  final Map<String, dynamic> product;

  /// The chosen option (its content may differ from the product's).
  final Map<String, dynamic>? variant;
  const CosmeticsSection({super.key, required this.product, this.variant});

  @override
  Widget build(BuildContext context) {
    final a = _attrs(product);
    final c = context.mColors;
    final facts = <Widget>[];
    final purpose = appLanguageText(context, a['function']);
    if (purpose != null) facts.add(_fact(context, tr(context, 'What it is for', 'Käyttötarkoitus'), purpose));
    final v = variant ?? const <String, dynamic>{};
    final ownContent = v['contentAmount'] != null;
    final content = contentText(context, ownContent ? v['contentAmount'] : product['contentAmount'], ownContent ? v['contentUnit'] : product['contentUnit']);
    if (content != null) facts.add(_fact(context, tr(context, 'Content', 'Sisältö'), content));
    final pao = asInt(a['paoMonths']);
    if (pao != null && a['durabilityType'] != 'best_before' && a['durabilityType'] != 'not_relevant') {
      facts.add(Padding(
        padding: const EdgeInsets.only(bottom: MSpace.sm),
        child: Row(children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: c.onSurfaceVariant),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: Text(tr(context, 'Use within $pao months of opening', 'Käytä $pao kk:n kuluessa avaamisesta'), style: MType.bodyM.copyWith(color: c.onSurface)),
          ),
        ]),
      ));
    }
    if (a['durabilityType'] == 'best_before' && _filled(a['bestBefore'])) {
      facts.add(_fact(context, tr(context, 'Best before', 'Parasta ennen'), monthText(context, '${a['bestBefore']}')));
    }
    if (_filled(a['countryOfOrigin'])) facts.add(_fact(context, tr(context, 'Country of origin', 'Alkuperämaa'), '${a['countryOfOrigin']}'));
    for (final (key, en, fi) in [('notesTop', 'Top notes', 'Lähtötuoksut'), ('notesHeart', 'Heart notes', 'Sydäntuoksut'), ('notesBase', 'Base notes', 'Pohjatuoksut')]) {
      final v = a[key];
      if (v is List && v.isNotEmpty) facts.add(_fact(context, tr(context, en, fi), v.whereType<String>().join(', ')));
    }

    final howTo = a['howToUse'];
    final precautions = a['precautions'];
    final inci = '${a['ingredientsInci'] ?? ''}'.trim();
    final hasAny = facts.isNotEmpty || appLanguageText(context, howTo) != null || appLanguageText(context, precautions) != null || inci.isNotEmpty || a['noPrecautions'] == true;
    if (!hasAny) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoHeading(tr(context, 'Product details', 'Tuotetiedot')),
      ...facts,
      if (appLanguageText(context, howTo) != null) _MultilingualBlock(title: tr(context, 'How to use', 'Käyttöohje'), value: howTo),
      if (appLanguageText(context, precautions) != null)
        _MultilingualBlock(title: tr(context, 'Precautions', 'Varotoimet'), value: precautions, warning: true)
      else if (a['noPrecautions'] == true)
        _fact(context, tr(context, 'Precautions', 'Varotoimet'), tr(context, 'No precautions on the label.', 'Pakkauksessa ei ole varotoimia.')),
      if (inci.isNotEmpty) IngredientsPanel(inci: inci),
    ]);
  }
}

/// A label text in the app language, plus the Swedish text when the shop gave one.
class _MultilingualBlock extends StatelessWidget {
  final String title;
  final dynamic value;
  final bool warning;
  const _MultilingualBlock({required this.title, required this.value, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final main = appLanguageText(context, value);
    final sv = swedishText(value);
    if (main == null && sv == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.all(MSpace.md),
      decoration: BoxDecoration(color: warning ? c.warningSoft : c.surfaceVariant, borderRadius: MRadius.brMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (warning) ...[Icon(Icons.warning_amber_rounded, size: 18, color: c.onWarningSoft), const SizedBox(width: MSpace.xs)],
          Expanded(child: Text(title, style: MType.label.copyWith(color: warning ? c.onWarningSoft : c.onSurface))),
        ]),
        if (main != null) ...[const SizedBox(height: MSpace.xs), SelectableText(main, style: MType.bodyM.copyWith(color: warning ? c.onWarningSoft : c.onSurface))],
        if (sv != null) ...[
          const SizedBox(height: MSpace.sm),
          Text('På svenska', style: MType.caption.copyWith(color: warning ? c.onWarningSoft : c.onSurfaceVariant, fontWeight: FontWeight.w700)),
          SelectableText(sv, style: MType.bodyM.copyWith(color: warning ? c.onWarningSoft : c.onSurface)),
        ],
      ]),
    );
  }
}

/// The INCI list exactly as the shop typed it, collapsed by default, with a search that highlights
/// an ingredient.
class IngredientsPanel extends StatefulWidget {
  final String inci;
  const IngredientsPanel({super.key, required this.inci});

  @override
  State<IngredientsPanel> createState() => _IngredientsPanelState();
}

class _IngredientsPanelState extends State<IngredientsPanel> {
  bool _open = false;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<TextSpan> _spans(Color highlight, Color onHighlight) {
    final q = _query.text.trim();
    final text = widget.inci;
    if (q.length < 2) return [TextSpan(text: text)];
    final lower = text.toLowerCase();
    final needle = q.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final at = lower.indexOf(needle, i);
      if (at < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
      spans.add(TextSpan(text: text.substring(at, at + needle.length), style: TextStyle(backgroundColor: highlight, color: onHighlight, fontWeight: FontWeight.w800)));
      i = at + needle.length;
    }
    return spans;
  }

  int get _matches {
    final q = _query.text.trim().toLowerCase();
    if (q.length < 2) return 0;
    return RegExp(RegExp.escape(q)).allMatches(widget.inci.toLowerCase()).length;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final q = _query.text.trim();
    return Container(
      margin: const EdgeInsets.only(top: MSpace.sm),
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: MRadius.brMd,
            onTap: () {
              Haptics.selection();
              setState(() => _open = !_open);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.sm),
                child: Row(children: [
                  Icon(Icons.science_outlined, color: c.onSurface),
                  const SizedBox(width: MSpace.md),
                  Expanded(child: Text(tr(context, 'Ingredients (INCI)', 'Ainesosat (INCI)'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w600, color: c.onSurface))),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: MMotion.of(context, MMotion.base),
          curve: MMotion.standard,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MTextField(
                      controller: _query,
                      label: tr(context, 'Find an ingredient', 'Etsi ainesosaa'),
                      hint: tr(context, 'e.g. linalool', 'esim. linalool'),
                      prefixIcon: Icons.search_rounded,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (q.length >= 2)
                      Padding(
                        padding: const EdgeInsets.only(top: MSpace.xs),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _matches == 0
                                ? tr(context, 'Not in the list', 'Ei luettelossa')
                                : tr(context, '$_matches ${_matches == 1 ? 'match' : 'matches'} highlighted', '$_matches osuma${_matches == 1 ? '' : 'a'} korostettu'),
                            style: MType.caption.copyWith(color: c.onSurfaceVariant),
                          ),
                        ),
                      ),
                    const SizedBox(height: MSpace.md),
                    SelectableText.rich(TextSpan(style: MType.bodyM.copyWith(color: c.onSurface), children: _spans(c.sunshine, c.onSunshine))),
                    const SizedBox(height: MSpace.md),
                    Text(
                      tr(context, 'The ingredient list is provided by the seller. Always check the label on the pack. This is not medical advice.',
                          'Ainesosaluettelo on myyjän antama. Tarkista aina pakkauksen merkinnät. Tämä ei ole lääketieteellistä neuvontaa.'),
                      style: MType.caption.copyWith(color: c.onSurfaceVariant),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

// ── Product safety & manufacturer ────────────────────────────────────────

bool _hasSafetyData(Map<String, dynamic> p) {
  final s = p['safety'];
  if (s is! Map) return false;
  return s['manufacturer'] is Map || s['responsiblePerson'] is Map || _filled(s['productModel']) || _filled(s['gtin']) || _filled(s['batchOrSerial']) ||
      s['warnings'] is Map || s['noWarnings'] == true || (s['images'] is List && (s['images'] as List).isNotEmpty);
}

/// The "Product safety & manufacturer" row; opens the details (GPSR Art. 19).
class ProductSafetyRow extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductSafetyRow({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    if (!_hasSafetyData(product)) return const SizedBox.shrink();
    return MListTile(
      title: tr(context, 'Product safety & manufacturer', 'Tuoteturvallisuus ja valmistaja'),
      icon: Icons.verified_user_outlined,
      onTap: () => _showSafety(context, product),
    );
  }
}

Widget _operator(BuildContext context, String title, Map op) {
  final c = context.mColors;
  final addr = op['address'] is Map ? op['address'] as Map : const {};
  final lines = [
    '${op['name'] ?? ''}',
    '${addr['line'] ?? ''}',
    [addr['postalCode'], addr['city']].where(_filled).join(' '),
    '${addr['countryCode'] ?? ''}',
  ].where((x) => x.trim().isNotEmpty).join('\n');
  return Padding(
    padding: const EdgeInsets.only(bottom: MSpace.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: MType.caption.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      SelectableText(lines, style: MType.bodyM.copyWith(color: c.onSurface)),
      if (_filled(op['email']))
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget), padding: EdgeInsets.zero),
          onPressed: () => _openLink(context, 'mailto:${op['email']}'),
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: Text('${op['email']}'),
        ),
      if (_filled(op['url']))
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget), padding: EdgeInsets.zero),
          onPressed: () => _openLink(context, '${op['url']}'),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text('${op['url']}', overflow: TextOverflow.ellipsis),
        ),
      if (_filled(op['phone'])) SelectableText('${op['phone']}', style: MType.bodyM.copyWith(color: c.onSurface)),
    ]),
  );
}

void _showSafety(BuildContext context, Map<String, dynamic> p) {
  final s = Map<String, dynamic>.from(p['safety'] as Map);
  final cosmetic = '${p['template'] ?? ''}'.startsWith('COSMETIC') || p['template'] == 'FRAGRANCE';
  final images = (s['images'] as List?)?.whereType<String>().toList() ?? const <String>[];
  showMSheet(
    context,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
      child: MSheet(
        title: tr(ctx, 'Product safety & manufacturer', 'Tuoteturvallisuus ja valmistaja'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s['manufacturer'] is Map) _operator(ctx, tr(ctx, 'Manufacturer', 'Valmistaja'), s['manufacturer'] as Map),
          if (s['responsiblePerson'] is Map)
            _operator(ctx, cosmetic ? tr(ctx, 'Responsible person', 'Vastuuhenkilö') : tr(ctx, 'Responsible person in the EU', 'Vastuuhenkilö EU:ssa'), s['responsiblePerson'] as Map),
          if (_filled(s['productModel'])) _fact(ctx, tr(ctx, 'Model / type', 'Malli / tyyppi'), '${s['productModel']}'),
          if (_filled(s['gtin'])) _fact(ctx, tr(ctx, 'EAN / GTIN', 'EAN-koodi'), '${s['gtin']}'),
          if (_filled(s['batchOrSerial'])) _fact(ctx, tr(ctx, 'Batch / serial', 'Erä / sarjanumero'), '${s['batchOrSerial']}'),
          if (s['warnings'] is Map)
            _MultilingualBlock(title: tr(ctx, 'Warnings and safety information', 'Varoitukset ja turvallisuustiedot'), value: s['warnings'], warning: true)
          else if (s['noWarnings'] == true)
            _fact(ctx, tr(ctx, 'Warnings', 'Varoitukset'), tr(ctx, 'No warnings on the label.', 'Pakkauksessa ei ole varoituksia.')),
          if (images.isNotEmpty) ...[
            Text(tr(ctx, 'Label and safety photos', 'Pakkausmerkintä- ja turvallisuuskuvat'), style: MType.caption.copyWith(color: ctx.mColors.onSurfaceVariant, fontWeight: FontWeight.w700)),
            const SizedBox(height: MSpace.xs),
            Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
              for (final url in images)
                ClipRRect(
                  borderRadius: MRadius.brSm,
                  child: SizedBox(width: 96, height: 96, child: Semantics(image: true, label: tr(ctx, 'Label photo', 'Pakkauskuva'), child: AppImage(url))),
                ),
            ]),
          ],
        ]),
      ),
    ),
  );
}

// ── Certificates ─────────────────────────────────────────────────────────

/// Admin-verified, unexpired certificates; each chip names the scheme and the licence number.
class CertificateChips extends StatelessWidget {
  final Map<String, dynamic> product;
  const CertificateChips({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final certs = ((product['certificates'] as List?) ?? const []).whereType<Map>().toList();
    if (certs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoHeading(tr(context, 'Certificates', 'Sertifikaatit')),
      Wrap(spacing: MSpace.sm, children: [
        for (final cert in certs)
          MChip(
            label: localized(context, cert['label']) ?? '${localized(context, cert['schemeName']) ?? cert['scheme']} · ${cert['licenceNumber'] ?? ''}',
            icon: Icons.verified_outlined,
            showCheck: false,
            onSelected: (_) => _showCertificate(context, Map<String, dynamic>.from(cert)),
          ),
      ]),
    ]);
  }
}

void _showCertificate(BuildContext context, Map<String, dynamic> cert) {
  final url = '${cert['publicVerifyUrl'] ?? ''}';
  showMSheet(
    context,
    builder: (ctx) => MSheet(
      title: localized(ctx, cert['schemeName']) ?? '${cert['scheme']}',
      actions: [
        if (url.isNotEmpty)
          MButton(
            label: tr(ctx, 'Check it on the scheme’s site', 'Tarkista merkin sivuilta'),
            icon: Icons.open_in_new_rounded,
            variant: MButtonVariant.outline,
            expand: true,
            onPressed: () => _openLink(ctx, url),
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _fact(ctx, tr(ctx, 'Licence number', 'Lisenssinumero'), '${cert['licenceNumber'] ?? ''}'),
        if (_filled(cert['holderName'])) _fact(ctx, tr(ctx, 'Licence holder', 'Lisenssin haltija'), '${cert['holderName']}'),
        _fact(
          ctx,
          tr(ctx, 'Applies to', 'Koskee'),
          cert['scope'] == 'component' && _filled(cert['componentDescription'])
              ? '${cert['componentDescription']}'
              : tr(ctx, 'The whole product', 'Koko tuotetta'),
        ),
        if (_filled(cert['validUntil'])) _fact(ctx, tr(ctx, 'Valid until', 'Voimassa'), shortDate(ctx, cert['validUntil'])),
        Text(tr(ctx, 'Malvoya has checked this certificate.', 'Malvoya on tarkistanut tämän sertifikaatin.'), style: MType.caption.copyWith(color: ctx.mColors.onSurfaceVariant)),
      ]),
    ),
  );
}

// ── Size guide (the shop's own chart) ────────────────────────────────────

const _measureWords = <String, List<String>>{
  'chest': ['Chest', 'Rinnanympärys'],
  'bust': ['Bust', 'Rinnanympärys'],
  'waist': ['Waist', 'Vyötärö'],
  'hips': ['Hips', 'Lantio'],
  'insideLeg': ['Inside leg', 'Sisäsauma'],
  'height': ['Height', 'Pituus'],
  'neck': ['Neck', 'Kaula'],
  'length': ['Length', 'Pituus'],
  'chestWidth': ['Chest width', 'Rinnan leveys'],
  'sleeve': ['Sleeve', 'Hiha'],
  'footLengthCm': ['Foot length', 'Jalan pituus'],
  'headCircumferenceCm': ['Head', 'Päänympärys'],
  'innerDiameterMm': ['Inner diameter (mm)', 'Sisähalkaisija (mm)'],
};

/// Rows of the size chart: the product's `sizeChart`, otherwise the options' own measurements.
List<Map<String, dynamic>> _chartRows(Map<String, dynamic> p) {
  final chart = _attrs(p)['sizeChart'];
  if (chart is List && chart.isNotEmpty) return chart.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  final rows = <Map<String, dynamic>>[];
  for (final v in ((p['variants'] as List?) ?? const []).whereType<Map>()) {
    final m = v['measurements'];
    if (m is Map && m.isNotEmpty && _filled(v['size'])) rows.add({'size': v['size'], 'measuredOn': 'garment', ...Map<String, dynamic>.from(m)});
  }
  return rows;
}

/// True when the shop gave a size chart or measurements.
bool hasSizeGuide(Map<String, dynamic> p) => _chartRows(p).isNotEmpty;

/// The shop's size chart in a sheet, with a link to the measuring guide.
void showSizeGuideSheet(BuildContext context, Map<String, dynamic> p) {
  final rows = _chartRows(p);
  final a = _attrs(p);
  showMSheet(
    context,
    builder: (ctx) {
      final c = ctx.mColors;
      final keys = [for (final k in _measureWords.keys) if (rows.any((r) => r[k] is num)) k];
      final garment = rows.any((r) => r['measuredOn'] == 'garment');
      final body = rows.any((r) => r['measuredOn'] == 'body');
      final note = garment && !body
          ? tr(ctx, 'Garment measurements in cm, measured on the item itself.', 'Vaatteen mitat senttimetreinä, mitattu itse tuotteesta.')
          : body && !garment
              ? tr(ctx, 'Body measurements in cm: the body each size is made for.', 'Vartalon mitat senttimetreinä: vartalo, jolle koko on tehty.')
              : tr(ctx, 'Measurements in cm. Each row says whether it is the body or the garment.', 'Mitat senttimetreinä. Rivillä kerrotaan, onko kyse vartalon vai vaatteen mitasta.');
      String fmt(dynamic v) => v is num ? (v == v.roundToDouble() ? '${v.toInt()}' : (isFinnish(ctx) ? '$v'.replaceAll('.', ',') : '$v')) : '–';
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: MSheet(
          title: tr(ctx, 'Size guide', 'Kokotaulukko'),
          subtitle: note,
          actions: [
            MButton(
              label: tr(ctx, 'How to measure', 'Näin mittaat'),
              variant: MButtonVariant.outline,
              icon: Icons.straighten_rounded,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SizeShadeHelpScreen()));
              },
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: MType.label.copyWith(color: c.onSurface),
                dataTextStyle: MType.bodyM.copyWith(color: c.onSurface),
                columnSpacing: MSpace.xl,
                horizontalMargin: 0,
                columns: [
                  DataColumn(label: Text(tr(ctx, 'Size', 'Koko'))),
                  for (final k in keys) DataColumn(label: Text(tr(ctx, _measureWords[k]![0], _measureWords[k]![1])), numeric: true),
                  if (garment && body) DataColumn(label: Text(tr(ctx, 'Measured on', 'Mitattu'))),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(Text('${r['size'] ?? ''}', style: MType.bodyM.copyWith(fontWeight: FontWeight.w800))),
                      for (final k in keys) DataCell(Text(fmt(r[k]))),
                      if (garment && body) DataCell(Text(r['measuredOn'] == 'body' ? tr(ctx, 'Body', 'Vartalo') : tr(ctx, 'Garment', 'Vaate'))),
                    ]),
                ],
              ),
            ),
            if (asInt(a['modelHeightCm']) != null && _filled(a['modelSizeWorn'])) ...[
              const SizedBox(height: MSpace.md),
              Text(
                tr(ctx, 'The model is ${a['modelHeightCm']} cm tall and wears size ${a['modelSizeWorn']}.', 'Malli on ${a['modelHeightCm']} cm ja käyttää kokoa ${a['modelSizeWorn']}.'),
                style: MType.bodyM.copyWith(color: c.onSurface),
              ),
            ],
          ]),
        ),
      );
    },
  );
}

// ── Report this product ──────────────────────────────────────────────────

/// "Report this product" (DSA Art. 16, GPSR): a reason, optional details and, when signed out, an
/// optional email for the outcome. Works without an account.
Future<void> showReportProductSheet(BuildContext context, int productId) async {
  final auth = Provider.of<AuthService>(context, listen: false);
  final reasons = <String, String>{
    'unsafe': tr(context, 'Unsafe product', 'Vaarallinen tuote'),
    'counterfeit': tr(context, 'Counterfeit', 'Väärennös'),
    'misleading': tr(context, 'Misleading information', 'Harhaanjohtavat tiedot'),
    'illegal': tr(context, 'Other illegal product', 'Muu laiton tuote'),
    'other': tr(context, 'Something else', 'Jokin muu'),
  };
  String? reason;
  final details = TextEditingController();
  final email = TextEditingController();
  var sending = false;
  String? error;
  Map<String, dynamic>? done;

  await showMSheet(
    context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final c = ctx.mColors;
      if (done != null) {
        final due = shortDate(ctx, done!['report']?['dueBy']);
        return MSheet(
          title: done!['alreadyReported'] == true ? tr(ctx, 'Already reported', 'Olet jo ilmoittanut') : tr(ctx, 'Thank you, report sent', 'Kiitos, ilmoitus lähetetty'),
          actions: [MButton(label: tr(ctx, 'Done', 'Valmis'), expand: true, onPressed: () => Navigator.pop(ctx))],
          child: Text(
            done!['alreadyReported'] == true
                ? tr(ctx, 'You have already reported this product. Our team reviews it${due.isEmpty ? '' : ' by $due'}.', 'Olet jo ilmoittanut tästä tuotteesta. Tiimimme käsittelee ilmoituksen${due.isEmpty ? '' : ' viimeistään $due'}.')
                : tr(ctx, 'Our team reviews your report${due.isEmpty ? '' : ' by $due'}. If the product breaks the rules or the law, we take it down and tell the shop why.',
                    'Tiimimme käsittelee ilmoituksesi${due.isEmpty ? '' : ' viimeistään $due'}. Jos tuote rikkoo sääntöjä tai lakia, poistamme sen ja kerromme kaupalle syyn.'),
            style: MType.bodyL.copyWith(color: c.onSurface),
          ),
        );
      }
      final needsDetails = reason == 'other' && details.text.trim().length < 5;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: MSheet(
          title: tr(ctx, 'Report this product', 'Ilmoita tuotteesta'),
          subtitle: tr(ctx, 'Tell us what is wrong. Our team reviews every report within three working days.', 'Kerro, mikä on vialla. Tiimimme käsittelee jokaisen ilmoituksen kolmen arkipäivän kuluessa.'),
          actions: [
            MButton(
              label: tr(ctx, 'Send report', 'Lähetä ilmoitus'),
              expand: true,
              loading: sending,
              onPressed: reason == null || needsDetails
                  ? null
                  : () async {
                      setSheet(() {
                        sending = true;
                        error = null;
                      });
                      final res = await ApiClient(auth).post('/products/$productId/report', {
                        'reason': reason,
                        if (details.text.trim().isNotEmpty) 'details': details.text.trim(),
                        if (!auth.isAuthenticated && email.text.trim().isNotEmpty) 'email': email.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      setSheet(() {
                        sending = false;
                        if (res.ok) {
                          done = res.data;
                        } else {
                          error = res.errorText(ctx) ?? tr(ctx, 'Could not send the report.', 'Ilmoitusta ei voitu lähettää.');
                        }
                      });
                    },
            ),
            MButton(label: tr(ctx, 'Cancel', 'Peruuta'), variant: MButtonVariant.text, expand: true, onPressed: () => Navigator.pop(ctx)),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: reason,
              onChanged: (v) => setSheet(() => reason = v),
              child: Column(children: [
                for (final e in reasons.entries) RadioListTile<String>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero),
              ]),
            ),
            const SizedBox(height: MSpace.sm),
            MTextField(
              controller: details,
              label: reason == 'other' ? tr(ctx, 'What is wrong?', 'Mikä on vialla?') : tr(ctx, 'Details (optional)', 'Lisätiedot (valinnainen)'),
              errorText: reason == 'other' && details.text.isNotEmpty && needsDetails ? tr(ctx, 'Write at least a few words', 'Kirjoita ainakin muutama sana') : null,
              maxLines: 4,
              maxLength: 2000,
              onChanged: (_) => setSheet(() {}),
            ),
            if (!auth.isAuthenticated)
              MTextField(
                controller: email,
                label: tr(ctx, 'Your email for the outcome (optional)', 'Sähköpostisi päätöstä varten (valinnainen)'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.sm),
                child: Semantics(liveRegion: true, child: Text(error!, style: MType.bodyM.copyWith(color: c.danger, fontWeight: FontWeight.w600))),
              ),
          ]),
        ),
      );
    }),
  );
  // The controllers are left to the garbage collector: the sheet may still be animating out
}
