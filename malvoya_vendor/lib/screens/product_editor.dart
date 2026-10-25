import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../catalog/catalog.dart';
import '../core/agreements.dart';
import '../core/images.dart';
import '../core/media_upload.dart';
import 'editor/category_picker.dart';
import 'editor/shade_colour_picker.dart';
import 'safety/certificates_screen.dart';
import 'safety/operators_screen.dart';
import 'safety/safety_pledge_screen.dart';

part 'editor/editor_fields.dart';
part 'editor/editor_basics.dart';
part 'editor/editor_variants.dart';
part 'editor/editor_materials.dart';
part 'editor/editor_beauty.dart';
part 'editor/editor_safety.dart';
part 'editor/editor_photos.dart';

/// Create or edit a product (API 2.12), built around the category:
///
/// 1. Step 1 picks the category (two-level, searchable) and who it is for.
/// 2. The form shows only that category's template (GET /categories/templates), in sections: Basics,
///    Variants, Materials & care or Ingredients & label, Safety, Photos. Required fields carry a tag
///    saying whether the law or Malvoya asks for them, with the reason on tap.
///
/// Drafts save with missing information. Publishing runs the server's rules: a 422
/// PUBLISH_REQUIREMENTS lists every missing field, shown next to the field with "Fix next" to walk
/// through them. Locked listings (recalls, PRODUCT_LOCKED) can be edited but never shown again.
class ProductEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  /// `GET /stores/my` (seller type and the safety pledge). Read from the server when not given.
  final Map<String, dynamic>? store;

  /// Problems to show at once (an import's "missing before publishing" list); else the product's own
  /// `publishCheck.missing`.
  final List<FieldIssue>? initialIssues;

  /// Scroll to this field when the form opens (e.g. `attributes.fibreComposition`).
  final String? focusField;

  const ProductEditorScreen({super.key, this.product, this.store, this.initialIssues, this.focusField});

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _Photo {
  String? url;
  double progress = 0;
  String? error;
  _Photo({this.url});
}

/// A product video: already on the product ([id] set), or uploaded and waiting to be attached on save.
class _Video {
  int? id;
  String? poster;
  String status; // UPLOADING | PENDING (uploaded, attached on save) | PROCESSING | READY | FAILED
  UploadedMedia? upload;
  double progress = 0;
  String? error;
  _Video({this.id, this.poster, this.status = 'UPLOADING'});
}

/// One option (ProductVariant): a size × colour, a shade, or a content size.
class _Option {
  int? id;
  String? size;
  String? color;
  String? sku;
  int priceAdjustCents;
  String? colourFamily;
  String? shadeHex;
  String? shadeFamily;
  String? undertone;
  String? finish;
  String? contentUnit;
  final Map<String, num> measurements;
  final TextEditingController stockCtl;
  final TextEditingController shadeCtl;
  final TextEditingController contentCtl;
  final TextEditingController priceCtl;

  _Option({
    this.id,
    this.size,
    this.color,
    this.sku,
    this.priceAdjustCents = 0,
    this.colourFamily,
    String? shadeName,
    this.shadeHex,
    this.shadeFamily,
    this.undertone,
    this.finish,
    num? contentAmount,
    this.contentUnit,
    Map<String, num>? measurements,
    int stock = 1,
    String price = '',
  })  : measurements = measurements ?? {},
        stockCtl = TextEditingController(text: '$stock'),
        shadeCtl = TextEditingController(text: shadeName ?? ''),
        contentCtl = TextEditingController(text: contentAmount == null ? '' : _numText(contentAmount)),
        priceCtl = TextEditingController(text: price);

  factory _Option.fromJson(Map v, int? basePrice) {
    final m = <String, num>{};
    if (v['measurements'] is Map) {
      (v['measurements'] as Map).forEach((k, val) {
        if (val is num) m['$k'] = val;
      });
    }
    final adjust = asInt(v['priceAdjustCents']) ?? 0;
    return _Option(
      id: asInt(v['id']),
      size: v['size'] as String?,
      color: v['color'] as String?,
      sku: v['sku'] as String?,
      priceAdjustCents: adjust,
      colourFamily: v['colourFamily'] as String?,
      shadeName: v['shadeName'] as String?,
      shadeHex: v['shadeHex'] as String?,
      shadeFamily: v['shadeFamily'] as String?,
      undertone: v['undertone'] as String?,
      finish: v['finish'] as String?,
      contentAmount: v['contentAmount'] as num?,
      contentUnit: v['contentUnit'] as String?,
      measurements: m,
      stock: asInt(v['stock']) ?? 0,
      price: adjust != 0 && basePrice != null ? _centsText(basePrice + adjust) : '',
    );
  }

  int get stock => int.tryParse(stockCtl.text.trim()) ?? 0;
  String get shadeName => shadeCtl.text.trim();
  num? get contentAmount => _parseNum(contentCtl.text);

  void dispose() {
    stockCtl.dispose();
    shadeCtl.dispose();
    contentCtl.dispose();
    priceCtl.dispose();
  }
}

/// One fibre row of a composition part.
class _Fibre {
  String? fibre;
  final TextEditingController pct;
  _Fibre({this.fibre, num? percent}) : pct = TextEditingController(text: percent == null ? '' : _numText(percent));
  num? get percent => _parseNum(pct.text);
}

/// One part of the fibre composition (main fabric, lining, filling…).
class _Component {
  String component;
  final List<_Fibre> fibres;
  _Component(this.component, this.fibres);
}

String _numText(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.replaceAll('.', ',');
num? _parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final d = double.tryParse(t);
  if (d == null) return null;
  return d == d.roundToDouble() ? d.round() : d;
}

String _centsText(int cents) => (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
int? _parseCents(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.').replaceAll('€', '').replaceAll(' ', ''));
  return v == null || v <= 0 ? null : (v * 100).round();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  Json? get _p => widget.product;
  bool get _editing => _p != null;
  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  /// setState for the part files (extensions may not call the protected member).
  void _update(VoidCallback f) => setState(f);

  // ── Catalogue data ─────────────────────────────────────────────────────
  Map<String, Json>? _templates;
  bool _loadingMeta = true;
  String? _metaError;

  // ── Category ───────────────────────────────────────────────────────────
  late String? _slug = _p?['categorySlug'] as String?;
  late Object? _catName = _p?['categoryName'];
  Object? _topName;
  String? _topSlug;
  late String? _template = _p?['template'] as String?;
  late String _audience = '${_p?['audience'] ?? 'UNISEX'}';
  late String? _ageGroup = _p?['ageGroup'] as String?;

  // ── Values ─────────────────────────────────────────────────────────────
  late final Json _attrs = _p?['attributes'] is Map ? Json.from(_p!['attributes']) : {};
  late final Set<String> _initialAttrKeys = {..._attrs.keys};
  late final _name = TextEditingController(text: '${_p?['name'] ?? ''}');
  late final _description = TextEditingController(text: '${_p?['description'] ?? ''}');
  late final _price = TextEditingController(text: _p?['salePriceCents'] is num ? _centsText((_p!['salePriceCents'] as num).round()) : '');
  late final _stock = TextEditingController(text: '${_p?['stockQuantity'] ?? 1}');
  Json get _safety => _p?['safety'] is Map ? Json.from(_p!['safety']) : const {};
  late final _model = TextEditingController(text: '${_safety['productModel'] ?? ''}');
  late final _gtin = TextEditingController(text: '${_safety['gtin'] ?? ''}');
  late final _batch = TextEditingController(text: '${_safety['batchOrSerial'] ?? ''}');
  late final _warnFi = TextEditingController(text: '${(_safety['warnings'] as Map?)?['fi'] ?? ''}');
  late final _warnSv = TextEditingController(text: '${(_safety['warnings'] as Map?)?['sv'] ?? ''}');
  late final _warnEn = TextEditingController(text: '${(_safety['warnings'] as Map?)?['en'] ?? ''}');
  late final _content = TextEditingController(text: _p?['contentAmount'] is num ? _numText(_p!['contentAmount'] as num) : '');
  late String? _contentUnit = _p?['contentUnit'] as String?;
  late bool _noWarnings = _safety['noWarnings'] == true;
  late bool _sealed = _p?['hygieneSealed'] == true;
  late String _condition = const ['NEW', 'LIKE_NEW', 'GOOD', 'FAIR', 'POOR'].contains(_p?['condition']) ? _p!['condition'] : 'NEW';
  late bool _secondHand = _p?['isSecondHand'] == true;
  late bool _handmade = _p?['isHandmade'] == true;
  late final bool _wasVisible = _p?['isAvailable'] == true;
  late int? _manufacturerId = asInt(_p?['manufacturerId']) ?? asInt((_safety['manufacturer'] as Map?)?['id']);
  late int? _rpId = asInt(_p?['responsiblePersonId']) ?? asInt((_safety['responsiblePerson'] as Map?)?['id']);
  late Json? _manufacturer = _safety['manufacturer'] is Map ? Json.from(_safety['manufacturer']) : null;
  late Json? _rp = _safety['responsiblePerson'] is Map ? Json.from(_safety['responsiblePerson']) : null;
  List<Json>? _certs;
  late final Set<int> _certIds = {
    for (final c in (_p?['certificates'] as List? ?? const []).whereType<Map>())
      if (asInt(c['id']) != null) asInt(c['id'])!,
  };

  late final List<_Photo> _photos = ((_p?['images'] as List?) ?? []).map((u) => _Photo(url: '$u')).toList();
  late final List<_Photo> _safetyPhotos = ((_safety['images'] as List?) ?? []).map((u) => _Photo(url: '$u')).toList();
  late final List<_Video> _videos = ((_p?['videos'] as List?) ?? [])
      .whereType<Map>()
      .map((v) => _Video(id: asInt(v['id']), poster: v['poster'] as String?, status: '${v['status'] ?? 'READY'}'))
      .toList();
  static const _maxVideos = 3;
  static const _maxPhotos = 10;
  late final List<_Option> _options = ((_p?['variants'] as List?) ?? [])
      .whereType<Map>()
      .map((v) => _Option.fromJson(v, asInt(_p?['salePriceCents'])))
      .toList();
  late final List<_Component> _composition = _readComposition(_attrs['fibreComposition']);
  late String _measuredOn = _readMeasuredOn();

  /// Text controllers of attribute fields, by key (`function.fi` for one language of a text).
  final Map<String, TextEditingController> _ctl = {};

  /// Sizes whose measurement fields are open.
  final Set<String> _openSizes = {};

  // ── Problems ───────────────────────────────────────────────────────────
  /// Missing or invalid information, by where it shows (FieldIssue.anchor).
  final Map<String, List<FieldIssue>> _issues = {};

  /// Recommended or "check this" notes (never blocking), by anchor.
  final Map<String, List<FieldIssue>> _notes = {};
  final Map<String, GlobalKey> _anchorKeys = {};
  final List<String> _anchorOrder = [];
  final _summaryKey = GlobalKey();
  int _fixIndex = -1;

  // ── Screen state ───────────────────────────────────────────────────────
  final _scroll = ScrollController();
  bool _saving = false;
  bool _deleting = false;
  late bool _locked = _p?['lockedAt'] != null;
  String? _error;
  late bool? _pledged = (widget.store?['safetyPledge'] as Map?)?['accepted'] as bool?;
  late String _sellerType = '${widget.store?['sellerType'] ?? 'BUSINESS'}';
  bool get _business => _sellerType != 'PRIVATE';
  String? _initial;

  @override
  void initState() {
    super.initState();
    final check = _p?['publishCheck'];
    _setIssues(widget.initialIssues ?? FieldIssue.parse(check is Map ? check['missing'] : null),
        FieldIssue.parse(check is Map ? check['warnings'] : null));
    _mergeSizeChart();
    _loadMeta();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _stock, _model, _gtin, _batch, _warnFi, _warnSv, _warnEn, _content, ..._ctl.values]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    for (final comp in _composition) {
      for (final f in comp.fibres) {
        f.pct.dispose();
      }
    }
    _scroll.dispose();
    super.dispose();
  }

  void _setIssues(List<FieldIssue> missing, List<FieldIssue> warnings) {
    _issues.clear();
    _notes.clear();
    for (final i in missing) {
      (_issues[i.anchor] ??= []).add(i);
    }
    for (final w in warnings) {
      (_notes[w.anchor] ??= []).add(w);
    }
    _fixIndex = -1;
  }

  Future<void> _loadMeta() async {
    setState(() {
      _loadingMeta = true;
      _metaError = null;
    });
    final api = _api;
    final results = await Future.wait([
      CatalogCache.loadTemplates(api),
      CatalogCache.loadCategories(api),
      if (widget.store == null) api.get('/stores/my') else Future.value(null),
    ]);
    if (!mounted) return;
    final templates = results[0] as Map<String, Json>?;
    final store = results[2];
    if (store is ApiResult && store.ok && store.data['store'] is Map) {
      final s = store.data['store'] as Map;
      _sellerType = '${s['sellerType'] ?? 'BUSINESS'}';
      _pledged = (s['safetyPledge'] as Map?)?['accepted'] as bool?;
    }
    setState(() {
      _loadingMeta = false;
      _templates = templates;
      _metaError = templates == null ? tr(context, 'The product form could not be loaded.', 'Tuotelomaketta ei saatu ladattua.') : null;
      final sel = CatalogCache.findSub(_slug);
      if (sel != null) {
        _catName = sel.$1['name'];
        _topName = sel.$2['name'];
        _topSlug = '${sel.$2['slug']}';
        _template = '${sel.$1['template']}';
      }
    });
    if (templates == null) return;
    _loadOperators();
    _loadCertificates();
    _initial = _snapshot();
    // A new product starts with step 1: the category
    if (!_editing && _slug == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final picked = await _pickCategory(firstStep: true);
        if (!picked && mounted) Navigator.pop(context);
      });
    } else if (widget.focusField != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(FieldIssue.anchorOf(widget.focusField!)));
    }
  }

  Future<void> _loadOperators() async {
    final res = await _api.get('/stores/my/operators');
    if (!mounted || !res.ok) return;
    final list = ((res.data['operators'] as List?) ?? const []).whereType<Map>().map((m) => Json.from(m)).toList();
    setState(() {
      _manufacturer = list.where((o) => asInt(o['id']) == _manufacturerId).firstOrNull ?? _manufacturer;
      _rp = list.where((o) => asInt(o['id']) == _rpId).firstOrNull ?? _rp;
    });
  }

  Future<void> _loadCertificates() async {
    final res = await _api.get('/stores/my/certificates');
    if (!mounted) return;
    setState(() => _certs = res.ok ? ((res.data['certificates'] as List?) ?? const []).whereType<Map>().map((m) => Json.from(m)).toList() : const []);
  }

  /// Step 1 (or a change of category). Returns whether a category was chosen.
  Future<bool> _pickCategory({bool firstStep = false}) async {
    final choice = await Navigator.push<CategoryChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryPickerScreen(initialSlug: _slug, initialAudience: _editing || _slug != null ? _audience : null, initialAgeGroup: _ageGroup, firstStep: firstStep),
      ),
    );
    if (choice == null || !mounted) return false;
    final oldMode = _template == null ? null : _variantMode;
    setState(() {
      final templateChanged = choice.template != _template;
      _slug = choice.slug;
      _catName = choice.name;
      _topName = choice.topName;
      _topSlug = choice.topSlug;
      _template = choice.template;
      _audience = choice.audience;
      _ageGroup = choice.ageGroup;
      if (templateChanged) {
        // The seal is on by default for sealed goods; beauty is never second-hand
        _sealed = _sealAllowed && (isCosmeticTemplate(_template) || _slug == 'jewellery-piercing');
        if (isCosmeticTemplate(_template)) {
          _secondHand = false;
          _condition = 'NEW';
        }
      }
      _issues.remove('categorySlug');
      _issues.remove('ageGroup');
    });
    // Options of another kind (e.g. sizes when the product became a lipstick) can't be kept
    if (oldMode != null && oldMode != _variantMode && _options.isNotEmpty) {
      setState(() {
        for (final o in _options) {
          o.dispose();
        }
        _options.clear();
      });
      MSnack.show(context, tr(context, 'This category has different options, so the earlier ones were cleared. Add them again below.',
          'Tällä kategorialla on erilaiset vaihtoehdot, joten aiemmat poistettiin. Lisää ne uudelleen alla.'));
    }
    return true;
  }

  // ── Template helpers ───────────────────────────────────────────────────
  Json? get _tpl => _template == null ? null : _templates?[_template];
  List<Json> get _fields => ((_tpl?['fields'] as List?) ?? const []).whereType<Map>().map((m) => Json.from(m)).toList();
  Json? _f(String key) => _fields.where((f) => f['key'] == key).firstOrNull;
  bool _has(String key) => _f(key) != null;
  bool get _cosmetic => isCosmeticTemplate(_template);
  bool get _sealAllowed => _cosmetic || _slug == 'jewellery-piercing' || _slug == 'jewellery-earrings';
  bool get _kids => _audience == 'KIDS';

  // ── Snapshot (to ask before throwing changes away) ─────────────────────
  String _snapshot() => jsonEncode({
        ..._body(publish: _wasVisible),
        'photos': _photos.map((p) => p.url ?? 'uploading').toList(),
        'videos': _videos.map((v) => v.id ?? v.status).toList(),
      });

  bool get _hasChanges => !_saving && !_deleting && _initial != null && _snapshot() != _initial;

  // ── Request body ───────────────────────────────────────────────────────
  static const _secondHandKeys = {'defectsNote', 'hasTags', 'originalSizeLabel', 'authenticity', 'brandTier', 'vintage'};
  static const _kidsKeys = {'ageRange', 'cordsDrawstrings', 'smallParts', 'costumeIsToy'};

  bool _empty(Object? v) =>
      v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.values.every(_empty));

  Json _attributesForSave() {
    final out = <String, dynamic>{};
    for (final f in _fields) {
      final k = '${f['key']}';
      Object? v = _attrs[k];
      if (k == 'fibreComposition') v = _compositionJson();
      if (k == 'sizeChart') v = _sizeChartJson();
      if (_secondHandKeys.contains(k) && !_secondHand) v = null;
      if (_kidsKeys.contains(k) && !_kids) v = null;
      if (k == 'hygieneSealDescription' && !_sealed) v = null;
      if (v is String) v = v.trim();
      if (v is Map) v = Map.fromEntries(v.entries.where((e) => !_empty(e.value)).map((e) => MapEntry(e.key, e.value is String ? (e.value as String).trim() : e.value)));
      if (_empty(v)) v = null;
      if (v == null && !_initialAttrKeys.contains(k)) continue;
      out[k] = v;
    }
    return out;
  }

  Json _body({required bool publish}) {
    final base = _parseCents(_price.text);
    final content = _parseNum(_content.text);
    final rowsHaveContent = _variantMode == _VMode.content && _options.isNotEmpty;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      if (_slug != null) 'categorySlug': _slug,
      'audience': _audience,
      'ageGroup': _ageGroup,
      if (_template != null) 'attributes': _attributesForSave(),
      'condition': _cosmetic ? 'NEW' : _condition,
      'isSecondHand': !_cosmetic && _secondHand,
      'isHandmade': _handmade,
      'salePriceCents': base,
      'canBeSold': true,
      'images': _photos.where((p) => p.url != null).map((p) => p.url).toList(),
      'safetyImages': _safetyPhotos.where((p) => p.url != null).map((p) => p.url).toList(),
      if (_options.isEmpty) 'stockQuantity': int.tryParse(_stock.text.trim()) ?? 0,
      'variants': [for (final o in _options) _optionJson(o, base)],
      'contentAmount': rowsHaveContent || content == null || _contentUnit == null ? null : content,
      'contentUnit': rowsHaveContent || content == null || _contentUnit == null ? null : _contentUnit,
      'hygieneSealed': _sealAllowed && _sealed,
      'manufacturerId': _manufacturerId,
      'responsiblePersonId': _rpId,
      'productModel': opt(_model),
      'batchOrSerial': opt(_batch),
      'gtin': _gtin.text.trim(),
      'warnings': {'fi': _warnFi.text.trim(), 'sv': _warnSv.text.trim(), 'en': _warnEn.text.trim()},
      'noWarnings': _noWarnings,
      if (_certs != null) 'certificateIds': _certIds.toList(),
      'isAvailable': publish && !_locked,
    };
  }

  Json _optionJson(_Option o, int? base) {
    final mode = _variantMode;
    final optionPrice = _parseCents(o.priceCtl.text);
    final adjust = optionPrice != null && base != null ? optionPrice - base : (mode == _VMode.content ? 0 : o.priceAdjustCents);
    final content = o.contentAmount;
    return {
      if (o.id != null) 'id': o.id,
      if (o.sku != null) 'sku': o.sku,
      'stock': o.stock,
      'priceAdjustCents': adjust,
      if (mode == _VMode.size) ...{
        if (o.size != null) 'size': o.size,
        if (o.color != null) 'color': o.color,
        'colourFamily': o.colourFamily,
        if (o.measurements.isNotEmpty) 'measurements': o.measurements,
      },
      if (mode == _VMode.colour) ...{
        if (o.color != null) 'color': o.color,
        'colourFamily': o.colourFamily,
      },
      if (mode == _VMode.shade) ...{
        if (o.shadeName.isNotEmpty) 'color': o.shadeName.length > 40 ? o.shadeName.substring(0, 40) : o.shadeName,
        'shadeName': o.shadeName.isEmpty ? null : o.shadeName,
        'shadeHex': o.shadeHex,
        'shadeFamily': o.shadeFamily,
        'undertone': o.undertone,
        'finish': o.finish,
      },
      if (mode == _VMode.content) ...{
        // Older app builds read the size label
        if (content != null && o.contentUnit != null) 'size': '${_numText(content)} ${o.contentUnit}',
        'contentAmount': content,
        'contentUnit': content == null ? null : o.contentUnit,
      },
    };
  }

  // ── Saving ─────────────────────────────────────────────────────────────
  bool _checkBasics() {
    final local = <FieldIssue>[];
    if (_name.text.trim().length < 2) local.add(const FieldIssue('name', 'required', {'en': 'Give the product a name.', 'fi': 'Anna tuotteelle nimi.'}));
    if (_parseCents(_price.text) == null) local.add(const FieldIssue('salePriceCents', 'required', {'en': 'Enter a price.', 'fi': 'Anna hinta.'}));
    final g = _gtin.text.trim();
    if (g.isNotEmpty && !validGtin(g)) local.add(const FieldIssue('gtin', 'invalid', {'en': 'This is not a valid EAN code: check the digits.', 'fi': 'EAN-koodi ei ole kelvollinen: tarkista numerot.'}));
    if (_variantMode == _VMode.shade && _options.any((o) => o.shadeName.isEmpty)) {
      local.add(const FieldIssue('variants', 'required', {'en': 'Give every shade a name.', 'fi': 'Anna jokaiselle sävylle nimi.'}));
    }
    if (_variantMode == _VMode.content && _options.any((o) => o.contentAmount == null || o.contentUnit == null)) {
      local.add(const FieldIssue('variants', 'required', {'en': 'Give every size its content in ml or g.', 'fi': 'Anna jokaiselle koolle sisältö millilitroina tai grammoina.'}));
    }
    if (local.isEmpty) return true;
    setState(() {
      for (final i in local) {
        (_issues[i.anchor] ??= []).insert(0, i);
      }
    });
    _goTo(local.first.anchor);
    return false;
  }

  Future<void> _save({required bool publish}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      for (final k in ['name', 'salePriceCents', 'gtin']) {
        _issues[k]?.removeWhere((i) => i.code == 'required' || i.code == 'invalid');
        if (_issues[k]?.isEmpty == true) _issues.remove(k);
      }
    });
    if (!_checkBasics()) return;
    if ([..._photos, ..._safetyPhotos].any((p) => p.url == null && p.error == null)) {
      setState(() => _error = tr(context, 'Wait for the photos to finish uploading.', 'Odota, että kuvat on ladattu.'));
      return;
    }
    if (_videos.any((v) => v.status == 'UPLOADING' && v.error == null)) {
      setState(() => _error = tr(context, 'Wait for the videos to finish uploading.', 'Odota, että videot on ladattu.'));
      return;
    }
    publish = publish && !_locked;
    // The one-time safety pledge comes before the first publish
    if (publish && _pledged != true) {
      final given = await SafetyPledgeScreen.ensure(context);
      if (!mounted) return;
      if (!given) return;
      setState(() {
        _pledged = true;
        _issues.remove('safetyPledge');
      });
    }
    setState(() => _saving = true);
    final body = _body(publish: publish);
    final api = _api;
    final res = await withAgreement(
      context,
      api,
      () => _editing ? api.patch('/products/${_p!['id']}', body) : api.post('/products', body),
    );
    if (!mounted) return;
    if (res.ok) {
      await _afterSaved(res, publish: publish);
      return;
    }
    final code = '${res.data['code'] ?? ''}';
    setState(() {
      _saving = false;
      if (code == 'PUBLISH_REQUIREMENTS' || code == 'INVALID_PRODUCT_DATA') {
        _setIssues(FieldIssue.parse(res.data['fields']), FieldIssue.parse(res.data['warnings']));
        _error = null;
      } else if (code == 'PRODUCT_LOCKED' || res.status == 409 && '${res.rawError}'.contains('recall')) {
        _locked = true;
        _error = res.errorMessage;
      } else {
        _error = res.errorMessage;
      }
    });
    if (code == 'PUBLISH_REQUIREMENTS' || code == 'INVALID_PRODUCT_DATA') {
      Haptics.warning();
      final n = _issueCount;
      MSnack.show(
        context,
        code == 'PUBLISH_REQUIREMENTS'
            ? tr(context, 'Not published yet: $n ${n == 1 ? 'thing' : 'things'} to add. Nothing was saved.',
                'Ei vielä julkaistu: lisättävää $n kohdassa. Mitään ei tallennettu.')
            : tr(context, 'Check the marked fields.', 'Tarkista merkityt kentät.'),
        kind: MSnackKind.error,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _fixNext());
    }
  }

  Future<void> _afterSaved(ApiResult res, {required bool publish}) async {
    final product = res.data['product'] is Map ? Json.from(res.data['product']) : null;
    final productId = _editing ? _p!['id'] : product?['id'];
    final pending = _videos.where((v) => v.status == 'PENDING' && v.error == null).toList();
    String? videoError;
    for (final v in pending) {
      videoError = await _attach(productId, v) ?? videoError;
    }
    _rememberComposition();
    if (!mounted) return;
    final check = product?['publishCheck'];
    final missing = check is Map ? FieldIssue.parse(check['missing']).length : 0;
    final claims = FieldIssue.parse(res.data['warnings']).length;
    final parts = <String>[
      if (publish) tr(context, 'Published.', 'Julkaistu.') else tr(context, 'Saved as a draft.', 'Tallennettu luonnokseksi.'),
      if (!publish && missing > 0)
        tr(context, '$missing ${missing == 1 ? 'thing is' : 'things are'} still needed before publishing.', 'Ennen julkaisua puuttuu vielä $missing ${missing == 1 ? 'tieto' : 'tietoa'}.'),
      if (claims > 0) tr(context, 'Check the wording the claims check flagged.', 'Tarkista sanamuodot, joista väittämätarkistus huomautti.'),
      if (videoError != null) '${tr(context, 'A video could not be added', 'Videota ei voitu lisätä')}: $videoError',
      if (res.notice != null) res.notice!,
    ];
    HapticFeedback.mediumImpact();
    MSnack.show(context, parts.join(' '), kind: MSnackKind.success, duration: Duration(seconds: parts.length > 1 ? 5 : 3));
    Navigator.pop(context, true);
  }

  // ── Fix next ───────────────────────────────────────────────────────────
  int get _issueCount => _issues.values.fold(0, (s, l) => s + l.length);

  /// Every issue's anchor in the order the form shows them (unknown places last).
  List<String> get _orderedIssueAnchors {
    final known = _anchorOrder.where(_issues.containsKey).toList();
    return [...known, ..._issues.keys.where((k) => !known.contains(k))];
  }

  void _fixNext() {
    final anchors = _orderedIssueAnchors;
    if (anchors.isEmpty) return;
    _fixIndex = (_fixIndex + 1) % anchors.length;
    final a = anchors[_fixIndex];
    if (a == 'safetyPledge' && _anchorKeys[a]?.currentContext == null) {
      _save(publish: true);
      return;
    }
    _goTo(a);
  }

  void _goTo(String anchor) {
    final ctx = _anchorKeys[anchor]?.currentContext ?? _summaryKey.currentContext;
    if (ctx == null) return;
    Haptics.selection();
    Scrollable.ensureVisible(ctx, duration: MMotion.of(context, MMotion.base), curve: MMotion.standard, alignment: 0.15);
  }

  // ── Delete ─────────────────────────────────────────────────────────────
  Future<void> _confirmDiscard() async {
    final discard = await showMSheet<bool>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Discard changes?', 'Hylätäänkö muutokset?'),
          actions: [
            MButton(label: tr(ctx, 'Keep editing', 'Jatka muokkausta'), expand: true, onPressed: () => Navigator.pop(ctx, false)),
            MButton(label: tr(ctx, 'Discard', 'Hylkää'), variant: MButtonVariant.danger, expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ],
          child: Text(tr(ctx, 'Your changes to this product have not been saved. To keep them without publishing, save a draft.',
              'Tuotteeseen tekemiäsi muutoksia ei ole tallennettu. Jos haluat säilyttää ne julkaisematta, tallenna luonnos.')),
        ));
    if (discard == true && mounted) Navigator.pop(context);
  }

  /// DELETE /products/:id → `deleted: "hard"` (never ordered, erased) or `"soft"` (kept for past orders).
  Future<void> _delete() async {
    final ok = await showMSheet<bool>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Remove this product?', 'Poistetaanko tuote?'),
          actions: [
            MButton(label: tr(ctx, 'Remove', 'Poista'), variant: MButtonVariant.danger, expand: true, onPressed: () => Navigator.pop(ctx, true)),
            MButton(label: tr(ctx, 'Back', 'Takaisin'), variant: MButtonVariant.text, expand: true, onPressed: () => Navigator.pop(ctx, false)),
          ],
          child: Text(tr(ctx, 'Shoppers will no longer see or buy it. To take it off sale for a while, move it to drafts instead.',
              'Asiakkaat eivät enää näe tai voi ostaa sitä. Jos haluat poistaa sen myynnistä vain väliaikaisesti, siirrä se luonnoksiin.')),
        ));
    if (ok != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final res = await _api.delete('/products/${_p!['id']}');
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _deleting = false;
        _error = res.errorMessage;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    final name = '${_p!['name'] ?? ''}'.trim();
    final message = '${res.data['deleted'] ?? ''}' == 'soft'
        ? tr(context, 'Product removed. It is kept only in the records of past orders.', 'Tuote poistettu. Se säilyy vain aiempien tilausten tiedoissa.')
        : tr(context, 'Product deleted.', 'Tuote poistettu.');
    MSnack.show(context, name.isEmpty ? message : '$name: $message');
    Navigator.pop(context, true);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    _anchorOrder.clear();
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          title: Text(_editing ? tr(context, 'Edit product', 'Muokkaa tuotetta') : tr(context, 'New product', 'Uusi tuote')),
          actions: [
            if (_issueCount > 0)
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
                onPressed: _fixNext,
                icon: const Icon(Icons.arrow_downward_rounded),
                label: Text(tr(context, 'Fix next', 'Korjaa seuraava')),
              ),
          ],
        ),
        bottomNavigationBar: _loadingMeta || _metaError != null ? null : _bottomBar(),
        body: _loadingMeta
            ? const MSkeletonDetail()
            : _metaError != null
                ? MStateMessage.error(message: _metaError, onRetry: _loadMeta)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l),
                    children: [
                      if (_locked) _lockedBanner(),
                      _summary(),
                      _categoryTile(),
                      const SizedBox(height: MSpace.md),
                      if (_template != null) ...[
                        _basicsSection(),
                        _variantsSection(),
                        if (_cosmetic) _beautySection() else _materialsSection(),
                        _safetySection(),
                        _photosSection(),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: MSpace.md),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_error!, style: MType.bodyM.copyWith(color: c.danger, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      if (_editing) ...[
                        const SizedBox(height: MSpace.xl),
                        MButton(
                          label: tr(context, 'Remove product', 'Poista tuote'),
                          icon: Icons.delete_outline_rounded,
                          variant: MButtonVariant.text,
                          loading: _deleting,
                          onPressed: _saving || _deleting ? null : _delete,
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _bottomBar() {
    final c = context.mColors;
    final visible = _wasVisible && !_locked;
    final busy = _saving || _deleting;
    final primary = _locked
        ? MButton(label: tr(context, 'Save', 'Tallenna'), expand: true, loading: _saving, onPressed: busy ? null : () => _save(publish: false))
        : MButton(
            label: visible ? tr(context, 'Save changes', 'Tallenna muutokset') : tr(context, 'Publish', 'Julkaise'),
            icon: visible ? Icons.check_rounded : Icons.visibility_rounded,
            expand: true,
            loading: _saving,
            onPressed: busy || _template == null ? null : () => _save(publish: true),
          );
    final secondary = _locked
        ? null
        : MButton(
            label: visible ? tr(context, 'Move to drafts', 'Siirrä luonnoksiin') : tr(context, 'Save draft', 'Tallenna luonnos'),
            variant: MButtonVariant.outline,
            expand: true,
            onPressed: busy ? null : () => _save(publish: false),
          );
    return Material(
      color: c.surface,
      elevation: 0,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.sm),
          child: Row(children: [
            if (secondary != null) ...[Expanded(child: secondary), const SizedBox(width: MSpace.sm)],
            Expanded(child: primary),
          ]),
        ),
      ),
    );
  }

  /// Recalled or removed by Malvoya: the listing can never be shown again (PRODUCT_LOCKED).
  Widget _lockedBanner() {
    final c = context.mColors;
    final recall = _p?['recall'] is Map ? _p!['recall'] as Map : null;
    final isRecall = _p?['lockedReason'] == 'RECALL' || recall != null;
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: MRadius.brMd),
      child: Semantics(
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_rounded, color: c.onDangerSoft),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Text(
                isRecall ? tr(context, 'Locked: product safety recall', 'Lukittu: tuoteturvallisuuteen liittyvä takaisinveto') : tr(context, 'Locked by Malvoya', 'Malvoyan lukitsema'),
                style: MType.title.copyWith(color: c.onDangerSoft),
              ),
            ),
          ]),
          const SizedBox(height: MSpace.xs),
          Text(
            isRecall
                ? tr(context, 'This product is part of a recall, so it can\'t be shown to shoppers again. You can still edit it for your records.',
                    'Tuote kuuluu takaisinvetoon, joten sitä ei voi enää näyttää asiakkaille. Voit silti muokata sitä omia tietojasi varten.')
                : tr(context, 'Malvoya removed this listing after a notice. It can\'t be shown again. Contact support if you think this is a mistake.',
                    'Malvoya poisti tuotteen ilmoituksen perusteella. Sitä ei voi näyttää uudelleen. Ota yhteyttä tukeen, jos tämä on mielestäsi virhe.'),
            style: MType.bodyM.copyWith(color: c.onDangerSoft),
          ),
          if (recall?['url'] != null)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.sm),
              child: MButton(
                label: tr(context, 'Read the recall notice', 'Lue takaisinvetoilmoitus'),
                variant: MButtonVariant.outline,
                size: MButtonSize.sm,
                icon: Icons.open_in_new_rounded,
                onPressed: () => launchUrl(Uri.parse('${recall!['url']}'), mode: LaunchMode.externalApplication),
              ),
            ),
        ]),
      ),
    );
  }

  /// The completeness meter: what is missing before publishing, each tappable, and "Fix next".
  Widget _summary() {
    final c = context.mColors;
    final count = _issueCount;
    final notes = _notes.values.fold(0, (s, l) => s + l.length);
    if (count == 0 && notes == 0) return SizedBox(key: _summaryKey);
    final all = [for (final a in _orderedIssueAnchors) ..._issues[a]!];
    return Container(
      key: _summaryKey,
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: count > 0 ? c.sunshineSoft : c.surfaceVariant, borderRadius: MRadius.brMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          count > 0
              ? tr(context, 'Before you can publish: $count ${count == 1 ? 'thing' : 'things'} to add', 'Ennen julkaisua: lisättävää $count kohdassa')
              : tr(context, 'Ready to publish', 'Valmis julkaistavaksi'),
          style: MType.title.copyWith(color: count > 0 ? c.onSunshineSoft : c.onSurface),
        ),
        const SizedBox(height: MSpace.xs),
        for (final i in all.take(6))
          InkWell(
            borderRadius: MRadius.brXs,
            onTap: () => _goTo(i.anchor),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, size: 18, color: c.onSunshineSoft),
                const SizedBox(width: MSpace.sm),
                Expanded(child: Text(i.text(context), style: MType.bodyM.copyWith(color: c.onSunshineSoft))),
                Icon(Icons.chevron_right_rounded, color: c.onSunshineSoft),
              ]),
            ),
          ),
        if (all.length > 6)
          Text(tr(context, '…and ${all.length - 6} more', '…ja ${all.length - 6} muuta'), style: MType.caption.copyWith(color: c.onSunshineSoft)),
        if (notes > 0)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.xs),
            child: Text(tr(context, '$notes ${notes == 1 ? 'tip' : 'tips'} to make the listing better, marked in the form.', '$notes ${notes == 1 ? 'vinkki' : 'vinkkiä'} tuotteen parantamiseksi, merkitty lomakkeeseen.'),
                style: MType.caption.copyWith(color: count > 0 ? c.onSunshineSoft : c.onSurfaceVariant)),
          ),
        if (count > 0) ...[
          const SizedBox(height: MSpace.sm),
          MButton(label: tr(context, 'Fix next', 'Korjaa seuraava'), icon: Icons.arrow_downward_rounded, size: MButtonSize.sm, onPressed: _fixNext),
        ],
      ]),
    );
  }

  Widget _categoryTile() {
    final c = context.mColors;
    final path = [localized(context, _topName), localized(context, _catName)].whereType<String>().join(' › ');
    final audience = switch (_audience) {
      'WOMEN' => tr(context, 'Women', 'Naiset'),
      'MEN' => tr(context, 'Men', 'Miehet'),
      'KIDS' => tr(context, 'Kids', 'Lapset'),
      _ => tr(context, 'Unisex', 'Unisex'),
    };
    final age = switch (_ageGroup) {
      'BABY' => tr(context, 'Baby 0–2', 'Vauvat 0–2 v'),
      'TODDLER' => tr(context, 'Toddler 2–4', 'Taaperot 2–4 v'),
      'KIDS' => tr(context, 'Kids 4–8', 'Lapset 4–8 v'),
      'JUNIOR' => tr(context, 'Junior 8–14', 'Juniorit 8–14 v'),
      'TEEN' => tr(context, 'Teens', 'Nuoret'),
      'ADULT' => tr(context, 'Adult', 'Aikuiset'),
      _ => null,
    };
    return _anchor(
      'categorySlug',
      _anchor(
        'ageGroup',
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: MRadius.brMd,
            border: Border.all(color: _issues.containsKey('categorySlug') ? c.danger : c.outline),
          ),
          child: MListTile(
            icon: categoryIcon(CatalogCache.findSub(_slug)?.$1['icon'] as String?),
            title: _slug == null ? tr(context, 'Pick a category', 'Valitse kategoria') : path,
            subtitle: _slug == null
                ? tr(context, 'The form shows the fields of the category', 'Lomake näyttää kategorian kentät')
                : [audience, if (age != null) age].join(' · '),
            trailing: Text(tr(context, 'Change', 'Vaihda'), style: MType.label.copyWith(color: c.primary)),
            onTap: _saving ? null : () => _pickCategory(),
          ),
        ),
      ),
    );
  }
}
