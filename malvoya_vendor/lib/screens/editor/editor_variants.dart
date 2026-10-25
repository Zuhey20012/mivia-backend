part of '../product_editor.dart';

/// How a template's options look: sizes × colours (clothing, shoes, bags, jewellery…), beauty
/// shades (make-up, nails), content sizes with their own price (skin, hair, fragrance), or colours
/// only (beauty and hair tools).
enum _VMode { size, shade, content, colour }

/// Option value lists the API accepts (catalog/attributes.ts), with their labels.
const _colourFamilies = {
  'black': ['Black', 'Musta'], 'white': ['White', 'Valkoinen'], 'grey': ['Grey', 'Harmaa'], 'beige': ['Beige', 'Beige'],
  'brown': ['Brown', 'Ruskea'], 'blue': ['Blue', 'Sininen'], 'navy': ['Navy', 'Tummansininen'], 'green': ['Green', 'Vihreä'],
  'red': ['Red', 'Punainen'], 'pink': ['Pink', 'Pinkki'], 'purple': ['Purple', 'Violetti'], 'yellow': ['Yellow', 'Keltainen'],
  'orange': ['Orange', 'Oranssi'], 'gold': ['Gold', 'Kulta'], 'silver': ['Silver', 'Hopea'], 'multi': ['Multicolour', 'Monivärinen'],
};
const _shadeFamilies = {
  'very_fair': ['Very fair', 'Hyvin vaalea'], 'fair': ['Fair', 'Vaalea'], 'light': ['Light', 'Kevyt / vaalea'], 'light_medium': ['Light–medium', 'Vaalea–keskisävy'],
  'medium': ['Medium', 'Keskisävy'], 'medium_tan': ['Medium–tan', 'Keskisävy–ruskettunut'], 'tan': ['Tan', 'Ruskettunut'], 'deep': ['Deep', 'Tumma'],
  'very_deep': ['Very deep', 'Hyvin tumma'], 'nude': ['Nude', 'Nude'], 'pink': ['Pink', 'Pinkki'], 'red': ['Red', 'Punainen'], 'coral': ['Coral', 'Koralli'],
  'berry': ['Berry', 'Marja'], 'plum': ['Plum', 'Luumu'], 'brown': ['Brown', 'Ruskea'], 'orange': ['Orange', 'Oranssi'], 'purple': ['Purple', 'Violetti'],
  'blue': ['Blue', 'Sininen'], 'green': ['Green', 'Vihreä'], 'black': ['Black', 'Musta'], 'white': ['White', 'Valkoinen'], 'clear': ['Clear', 'Kirkas'],
  'glitter': ['Glitter', 'Glitter'], 'metallic': ['Metallic', 'Metallinen'],
};
const _undertones = {'cool': ['Cool', 'Viileä'], 'neutral': ['Neutral', 'Neutraali'], 'warm': ['Warm', 'Lämmin'], 'olive': ['Olive', 'Oliivi']};
const _finishes = {
  'matte': ['Matte', 'Mattapintainen'], 'satin': ['Satin', 'Satiini'], 'natural': ['Natural', 'Luonnollinen'], 'dewy': ['Dewy', 'Kostea / hehkuva'],
  'glossy': ['Glossy', 'Kiiltävä'], 'shimmer': ['Shimmer', 'Shimmer'], 'metallic': ['Metallic', 'Metallinen'],
};

extension _EditorVariants on _ProductEditorScreenState {
  _VMode get _variantMode {
    if (shadeTemplates.contains(_template)) return _VMode.shade;
    if (_cosmetic) return _VMode.content;
    if (_template == 'BEAUTY_TOOL' || _template == 'HAIR_TOOL') return _VMode.colour;
    return _VMode.size;
  }

  String _lbl(Map<String, List<String>> m, String? key) => key == null ? '' : (m[key] == null ? key : tr(context, m[key]![0], m[key]![1]));

  // ── Reading and writing the size chart and the composition ────────────

  String _readMeasuredOn() {
    final chart = _attrs['sizeChart'];
    if (chart is List && chart.isNotEmpty && chart.first is Map) return '${(chart.first as Map)['measuredOn'] ?? 'garment'}';
    return 'garment';
  }

  /// Older products kept measurements only in the size chart: copy them onto the sizes.
  void _mergeSizeChart() {
    final chart = _attrs['sizeChart'];
    if (chart is! List) return;
    for (final row in chart.whereType<Map>()) {
      for (final o in _options.where((o) => o.size == row['size'] && o.measurements.isEmpty)) {
        row.forEach((k, v) {
          if (k != 'size' && k != 'measuredOn' && v is num) o.measurements['$k'] = v;
        });
      }
    }
  }

  List<Json>? _sizeChartJson() {
    final rows = <Json>[];
    for (final s in _sizes.whereType<String>()) {
      final m = _options.where((o) => o.size == s && o.measurements.isNotEmpty).firstOrNull?.measurements;
      if (m == null || m.isEmpty) continue;
      rows.add({'size': s.length > 20 ? s.substring(0, 20) : s, 'measuredOn': _measuredOn, ...m});
    }
    return rows.isEmpty ? null : rows;
  }

  // ── Sizes × colours ────────────────────────────────────────────────────

  List<String?> get _sizes => _options.map((o) => o.size).toSet().toList();
  List<String?> get _colours => _options.map((o) => o.color).toSet().toList();

  List<String> _presetSizes() {
    List<String> range(int a, int b, [int step = 1]) => [for (var i = a; i <= b; i += step) '$i'];
    if (_slug == 'jewellery-rings') return range(14, 22);
    final sys = _attrs['sizeSystem'] ?? (_template == 'FOOTWEAR' ? (_kids ? 'kids_eu' : 'eu') : (_kids && _template == 'APPAREL' ? 'kids_height' : 'letter'));
    return switch (sys) {
      'letter' => ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL'],
      'eu_numeric' => range(32, 58, 2),
      'jeans_wl' => [for (final w in range(24, 40, 2)) 'W$w'],
      'kids_height' => const ['50', '56', '62', '68', '74', '80', '86', '92', '98', '104', '110', '116', '122', '128', '134', '140', '146', '152', '158', '164', '170', '176'],
      'one_size' => [tr(context, 'One size', 'Yksi koko')],
      'bra' => const ['70A', '70B', '70C', '75A', '75B', '75C', '75D', '80B', '80C', '80D', '85B', '85C', '85D'],
      'eu' => range(35, 46),
      'kids_eu' => range(18, 39),
      'uk' => range(3, 12),
      'us_w' => range(5, 11),
      'us_m' => range(7, 13),
      'head_cm' => range(48, 62),
      'glove' => const ['6', '6.5', '7', '7.5', '8', '8.5', '9', '9.5', '10', '10.5', '11'],
      _ => const [],
    };
  }

  void _addSize(String size) {
    final s = size.trim();
    if (s.isEmpty || s.length > 20 || _sizes.contains(s)) return;
    _update(() {
      final colours = _colours.isEmpty ? <String?>[null] : _colours;
      for (final col in colours) {
        _options.add(_Option(size: s, color: col, colourFamily: _familyOf(col)));
      }
      // The first size of a product sold as one piece takes over its stock
      if (_options.length == colours.length) _options.first.stockCtl.text = _stock.text.trim().isEmpty ? '1' : _stock.text.trim();
    });
    _touch('variants');
  }

  void _removeSize(String? size) {
    _update(() {
      final gone = _options.where((o) => o.size == size).toList();
      if (_sizes.length == 1 && _colours.whereType<String>().isNotEmpty) {
        for (final o in gone) {
          o.size = null;
        }
        return;
      }
      for (final o in gone) {
        _options.remove(o);
        o.dispose();
      }
    });
  }

  String? _familyOf(String? colour) => colour == null ? null : _options.where((o) => o.color == colour).firstOrNull?.colourFamily;

  void _addColour(String name, String? family) {
    final n = name.trim();
    if (n.isEmpty || n.length > 40 || _colours.contains(n)) return;
    _update(() {
      if (_options.isNotEmpty && _options.every((o) => o.color == null)) {
        for (final o in _options) {
          o.color = n;
          o.colourFamily = family;
        }
        return;
      }
      final sizes = _sizes.isEmpty ? <String?>[null] : _sizes;
      for (final s in sizes) {
        final m = _options.where((o) => o.size == s).firstOrNull?.measurements;
        _options.add(_Option(size: s, color: n, colourFamily: family, measurements: m == null ? null : Map.of(m)));
      }
    });
    _touch('variants');
  }

  void _removeColour(String? colour) {
    _update(() {
      final colours = _colours;
      final gone = _options.where((o) => o.color == colour).toList();
      if (colours.length == 1 && _sizes.whereType<String>().isNotEmpty) {
        for (final o in gone) {
          o.color = null;
          o.colourFamily = null;
        }
        return;
      }
      for (final o in gone) {
        _options.remove(o);
        o.dispose();
      }
    });
  }

  Future<void> _askColour() async {
    final result = await showMSheet<(String, String?)>(context, builder: (_) => const _ColourSheet());
    if (result != null) _addColour(result.$1, result.$2);
  }

  Future<void> _askCustomSize() async {
    final ctl = TextEditingController();
    final s = await showMSheet<String>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Add a size', 'Lisää koko'),
          actions: [MButton(label: tr(ctx, 'Add', 'Lisää'), expand: true, onPressed: () => Navigator.pop(ctx, ctl.text))],
          child: MTextField(controller: ctl, label: tr(ctx, 'Size as on the label', 'Koko kuten merkinnöissä'), hint: 'W30 L32', autofocus: true, maxLength: 20),
        ));
    ctl.dispose();
    if (s != null) _addSize(s);
  }

  Future<void> _askStockForAll() async {
    final ctl = TextEditingController(text: '1');
    final s = await showMSheet<String>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Same stock for every option', 'Sama saldo kaikille vaihtoehdoille'),
          actions: [MButton(label: tr(ctx, 'Apply', 'Käytä'), expand: true, onPressed: () => Navigator.pop(ctx, ctl.text))],
          child: MTextField(controller: ctl, label: tr(ctx, 'How many of each', 'Montako kutakin'), keyboardType: TextInputType.number, autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        ));
    ctl.dispose();
    final n = int.tryParse(s ?? '');
    if (n == null) return;
    _update(() {
      for (final o in _options) {
        o.stockCtl.text = '$n';
      }
    });
  }

  /// Measurements that make sense per size for this kind of product (cm, mm for ring sizes).
  Map<String, String> get _measureKeys {
    if (_template == 'FOOTWEAR') return {'footLengthCm': tr(context, 'Foot length (cm)', 'Jalan pituus (cm)')};
    if (_slug == 'jewellery-rings') return {'innerDiameterMm': tr(context, 'Inner diameter (mm)', 'Sisähalkaisija (mm)')};
    if (_slug == 'accessories-hats-beanies') return {'headCircumferenceCm': tr(context, 'Head circumference (cm)', 'Päänympärys (cm)')};
    if (_template != 'APPAREL') return const {};
    return _measuredOn == 'body'
        ? {
            'chest': tr(context, 'Chest', 'Rinnanympärys'),
            'waist': tr(context, 'Waist', 'Vyötärö'),
            'hips': tr(context, 'Hips', 'Lantio'),
            'insideLeg': tr(context, 'Inside leg', 'Sisäsauma'),
            'height': tr(context, 'Height', 'Pituus'),
          }
        : {
            'length': tr(context, 'Length', 'Pituus'),
            'chestWidth': tr(context, 'Chest width', 'Rinnan leveys'),
            'sleeve': tr(context, 'Sleeve', 'Hiha'),
            'waist': tr(context, 'Waist', 'Vyötärö'),
            'hips': tr(context, 'Hips', 'Lantio'),
            'insideLeg': tr(context, 'Inside leg', 'Sisäsauma'),
          };
  }

  // ── Section ────────────────────────────────────────────────────────────

  Widget _variantsSection() {
    final mode = _variantMode;
    final title = switch (mode) {
      _VMode.shade => tr(context, 'Shades', 'Sävyt'),
      _VMode.content => tr(context, 'Sizes and prices', 'Koot ja hinnat'),
      _VMode.colour => tr(context, 'Colours', 'Värit'),
      _VMode.size => tr(context, 'Sizes and colours', 'Koot ja värit'),
    };
    return _section(title, Icons.straighten_rounded, [
      _anchor(
        'variants',
        switch (mode) {
          _VMode.shade => _shadeEditor(),
          _VMode.content => _contentEditor(),
          _VMode.colour => _colourEditor(),
          _VMode.size => _sizeEditor(),
        },
      ),
      if (_options.isEmpty) _singleStock(),
    ]);
  }

  Widget _singleStock() => MTextField(
        controller: _stock,
        label: tr(context, 'How many do you have?', 'Montako kappaletta sinulla on?'),
        helper: tr(context, 'No options: the item is sold as one.', 'Ei vaihtoehtoja: tuotetta myydään yhtenä.'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );

  Widget _stockBox(_Option o, {String? label}) => SizedBox(
        width: 104,
        child: MTextField(
          controller: o.stockCtl,
          label: label ?? tr(context, 'Stock', 'Saldo'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        ),
      );

  Widget _sizeEditor() {
    final c = context.mColors;
    final presets = _presetSizes();
    final sizes = _sizes;
    final colours = _colours.whereType<String>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_has('sizeSystem'))
        _anchor('attributes.sizeSystem', _enumField(_f('sizeSystem')!, 'sizeSystem', fieldLabel(context, _f('sizeSystem'), 'Size system'), null)),
      if (_kids && _template == 'APPAREL' && _attrs['sizeSystem'] != 'kids_height' && _attrs['sizeSystem'] != 'one_size' && _ageGroup != 'TEEN')
        Padding(
          padding: const EdgeInsets.only(top: MSpace.sm),
          child: _notice(
            Icons.child_care_rounded,
            tr(context, 'Children\'s clothes use sizes in cm (height 50–176).', 'Lastenvaatteissa koot ovat senttimetreinä (pituus 50–176).'),
            action: MButton(label: tr(context, 'Use height sizes', 'Käytä pituuskokoja'), size: MButtonSize.sm, variant: MButtonVariant.outline, onPressed: () => _setAttr('sizeSystem', 'kids_height')),
          ),
        ),
      const SizedBox(height: MSpace.md),
      Text(tr(context, 'Tap the sizes you sell', 'Napauta myymäsi koot'), style: MType.label),
      const SizedBox(height: MSpace.xs),
      Wrap(spacing: MSpace.xs, runSpacing: 0, children: [
        for (final s in {...presets, ...sizes.whereType<String>()})
          MChip(label: s, selected: sizes.contains(s), onSelected: (sel) => sel ? _addSize(s) : _removeSize(s)),
        MChip(label: tr(context, 'Other size', 'Muu koko'), icon: Icons.add_rounded, showCheck: false, onSelected: (_) => _askCustomSize()),
      ]),
      const SizedBox(height: MSpace.md),
      Text(tr(context, 'Colours', 'Värit'), style: MType.label),
      const SizedBox(height: MSpace.xs),
      Wrap(spacing: MSpace.xs, runSpacing: 0, children: [
        for (final col in colours)
          MChip(
            label: [col, if (_familyOf(col) != null) '(${_lbl(_colourFamilies, _familyOf(col))})'].join(' '),
            selected: true,
            showCheck: false,
            onRemove: () => _removeColour(col),
          ),
        MChip(label: tr(context, 'Add colour', 'Lisää väri'), icon: Icons.add_rounded, showCheck: false, onSelected: (_) => _askColour()),
      ]),
      if (_options.isNotEmpty) ...[
        const SizedBox(height: MSpace.md),
        Row(children: [
          Expanded(child: Text(tr(context, 'Stock per option', 'Saldo vaihtoehdoittain'), style: MType.label)),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
            onPressed: _askStockForAll,
            child: Text(tr(context, 'Same for all', 'Sama kaikille')),
          ),
        ]),
        if (_template == 'APPAREL' && _measureKeys.isNotEmpty)
          Wrap(spacing: MSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(tr(context, 'Measurements in cm:', 'Mitat senttimetreinä:'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
            MChip(label: tr(context, 'of the garment', 'vaatteesta'), selected: _measuredOn == 'garment', onSelected: (_) => _update(() => _measuredOn = 'garment')),
            MChip(label: tr(context, 'of the body', 'vartalosta'), selected: _measuredOn == 'body', onSelected: (_) => _update(() => _measuredOn = 'body')),
          ]),
        for (final s in sizes) _sizeCard(s),
      ],
    ]);
  }

  Widget _sizeCard(String? size) {
    final c = context.mColors;
    final opts = _options.where((o) => o.size == size).toList();
    final keys = _measureKeys;
    final open = _openSizes.contains(size ?? '');
    final first = opts.first;
    final measured = first.measurements.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: MSpace.sm),
      padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.xs, MSpace.xs, MSpace.sm),
      decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(size ?? tr(context, 'No size', 'Ei kokoa'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w700))),
          if (keys.isNotEmpty && size != null)
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
              onPressed: () => _update(() => open ? _openSizes.remove(size) : _openSizes.add(size)),
              icon: Icon(measured ? Icons.check_circle_outline_rounded : Icons.straighten_rounded, size: 18),
              label: Text(tr(context, 'Measurements', 'Mitat')),
            ),
          if (size != null)
            IconButton(
              tooltip: tr(context, 'Remove size $size', 'Poista koko $size'),
              constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
              onPressed: () => _removeSize(size),
              icon: Icon(Icons.close_rounded, color: c.onSurfaceVariant),
            ),
        ]),
        for (final o in opts)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.xs, right: MSpace.sm),
            child: Row(children: [
              Expanded(child: Text(o.color ?? tr(context, 'In stock', 'Varastossa'), style: MType.bodyM)),
              _stockBox(o),
            ]),
          ),
        if (open && size != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm, right: MSpace.sm),
            child: Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
              for (final k in keys.entries)
                SizedBox(
                  width: 140,
                  child: MTextField(
                    controller: _tc('m|$size|${k.key}', first.measurements[k.key] == null ? '' : _numText(first.measurements[k.key]!)),
                    label: k.value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (s) {
                      final n = _parseNum(s);
                      _update(() {
                        for (final o in opts) {
                          if (n == null || n <= 0 || n > 400) {
                            o.measurements.remove(k.key);
                          } else {
                            o.measurements[k.key] = n;
                          }
                        }
                      });
                    },
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  // ── Colours only (tools) ───────────────────────────────────────────────

  Widget _colourEditor() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final o in _options)
        Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: Row(children: [
            Expanded(child: Text([o.color ?? '—', if (o.colourFamily != null) '(${_lbl(_colourFamilies, o.colourFamily)})'].join(' '), style: MType.bodyM)),
            _stockBox(o),
            IconButton(
              tooltip: tr(context, 'Remove colour', 'Poista väri'),
              constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
              onPressed: () => _removeColour(o.color),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: MButton(label: tr(context, 'Add colour', 'Lisää väri'), icon: Icons.add_rounded, variant: MButtonVariant.outline, size: MButtonSize.sm, onPressed: _askColour),
      ),
    ]);
  }

  // ── Beauty shades ──────────────────────────────────────────────────────

  Widget _shadeEditor() {
    final c = context.mColors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        tr(context, 'One row per shade: name, swatch colour, shade family and stock. Colours vary by screen; shoppers see a note about it.',
            'Yksi rivi sävyä kohden: nimi, sävynäytteen väri, sävyperhe ja saldo. Värit näkyvät eri näytöillä eri tavoin; asiakkaat näkevät siitä huomautuksen.'),
        style: MType.caption.copyWith(color: c.onSurfaceVariant),
      ),
      const SizedBox(height: MSpace.sm),
      for (final o in _options) _shadeRow(o),
      Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
        MButton(
          label: tr(context, 'Add shade', 'Lisää sävy'),
          icon: Icons.add_rounded,
          variant: MButtonVariant.outline,
          size: MButtonSize.sm,
          onPressed: () {
            _update(() => _options.add(_Option()));
            _touch('variants');
          },
        ),
        MButton(label: tr(context, 'Paste a list', 'Liitä luettelo'), icon: Icons.content_paste_rounded, variant: MButtonVariant.outline, size: MButtonSize.sm, onPressed: _pasteShades),
        if (_options.length > 1)
          MButton(label: tr(context, 'Apply to all', 'Kaikille sävyille'), icon: Icons.done_all_rounded, variant: MButtonVariant.text, size: MButtonSize.sm, onPressed: _applyToAllShades),
      ]),
    ]);
  }

  Widget _shadeRow(_Option o) {
    final c = context.mColors;
    final colour = colorFromHex(o.shadeHex);
    Widget pick(String label, Map<String, List<String>> values, String? current, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
          value: values.containsKey(current) ? current : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem<String>(value: null, child: Text(tr(context, 'Not given', 'Ei annettu'))),
            for (final v in values.entries) DropdownMenuItem(value: v.key, child: Text(tr(context, v.value[0], v.value[1]), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _update(() => onChanged(v)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.sm, MSpace.xs, MSpace.sm),
      decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (colour != null)
            MSwatch(color: colour, name: o.shadeName.isEmpty ? (o.shadeHex ?? '') : o.shadeName, size: 44, onTap: () => _pickHex(o))
          else
            IconButton(
              tooltip: tr(context, 'Pick the swatch colour', 'Valitse sävynäytteen väri'),
              constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
              onPressed: () => _pickHex(o),
              icon: Icon(Icons.colorize_rounded, color: c.primary),
            ),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: MTextField(
              controller: o.shadeCtl,
              label: tr(context, 'Shade name', 'Sävyn nimi'),
              hint: '02 Sand',
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              onChanged: (_) => _touch('variants'),
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Remove shade', 'Poista sävy'),
            constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
            onPressed: () => _update(() {
              _options.remove(o);
              o.dispose();
            }),
            icon: Icon(Icons.close_rounded, color: c.onSurfaceVariant),
          ),
        ]),
        if (o.shadeHex != null)
          Padding(padding: const EdgeInsets.only(left: MSpace.xs, top: 2), child: Text(o.shadeHex!, style: MType.caption.copyWith(color: c.onSurfaceVariant))),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          SizedBox(width: 170, child: pick(tr(context, 'Shade family', 'Sävyperhe'), _shadeFamilies, o.shadeFamily, (v) => o.shadeFamily = v)),
          SizedBox(width: 150, child: pick(tr(context, 'Undertone', 'Alasävy'), _undertones, o.undertone, (v) => o.undertone = v)),
          SizedBox(width: 150, child: pick(tr(context, 'Finish', 'Viimeistely'), _finishes, o.finish, (v) => o.finish = v)),
          _stockBox(o),
        ]),
      ]),
    );
  }

  Future<void> _pickHex(_Option o) async {
    final hex = await pickShadeColour(context, initial: o.shadeHex, shadeName: o.shadeName);
    if (hex != null) _update(() => o.shadeHex = hex);
  }

  /// One shade per line: "02 Sand", optionally with "#D4A07A" anywhere on the line (tabs or
  /// semicolons from a spreadsheet are fine: the first column is the name).
  Future<void> _pasteShades() async {
    final ctl = TextEditingController();
    final stock = TextEditingController(text: '1');
    final text = await showMSheet<String>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Paste shade names', 'Liitä sävyjen nimet'),
          subtitle: tr(ctx, 'One shade per line. A hex colour such as #C2414B on the same line becomes the swatch.',
              'Yksi sävy riviä kohden. Samalla rivillä oleva hex-väri, kuten #C2414B, tulee sävynäytteeksi.'),
          actions: [MButton(label: tr(ctx, 'Add shades', 'Lisää sävyt'), expand: true, onPressed: () => Navigator.pop(ctx, ctl.text))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MTextField(controller: ctl, label: tr(ctx, 'Shades', 'Sävyt'), hint: '01 Ivory\n02 Sand #D4A07A\n03 Honey', maxLines: 10, minLines: 5, autofocus: true),
            const SizedBox(height: MSpace.md),
            MTextField(controller: stock, label: tr(ctx, 'Stock for each', 'Saldo kullekin'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          ]),
        ));
    final each = int.tryParse(stock.text) ?? 1;
    ctl.dispose();
    stock.dispose();
    if (text == null) return;
    final existing = _options.map((o) => o.shadeName.toLowerCase()).toSet();
    final hexRe = RegExp(r'#[0-9A-Fa-f]{6}\b');
    var added = 0;
    _update(() {
      for (final raw in const LineSplitter().convert(text)) {
        final hex = hexRe.firstMatch(raw)?.group(0)?.toUpperCase();
        var name = raw.replaceAll(hexRe, '').split(RegExp('[\t;]')).first.trim();
        if (name.length > 40) name = name.substring(0, 40);
        if (name.isEmpty || existing.contains(name.toLowerCase()) || _options.length >= 60) continue;
        existing.add(name.toLowerCase());
        _options.add(_Option(shadeName: name, shadeHex: hex, stock: each));
        added++;
      }
    });
    _touch('variants');
    if (mounted) MSnack.show(context, tr(context, '$added shades added. Pick the swatch colours next.', '$added sävyä lisätty. Valitse seuraavaksi sävynäytteiden värit.'));
  }

  Future<void> _applyToAllShades() async {
    String? family, undertone, finish;
    final apply = await showMSheet<bool>(context, builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) {
            Widget pick(String label, Map<String, List<String>> values, String? cur, ValueChanged<String?> on) => Padding(
                  padding: const EdgeInsets.only(bottom: MSpace.md),
                  child: DropdownButtonFormField<String>(
                    value: cur,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: label),
                    items: [
                      DropdownMenuItem<String>(value: null, child: Text(tr(ctx, 'Keep as is', 'Ennallaan'))),
                      for (final v in values.entries) DropdownMenuItem(value: v.key, child: Text(tr(ctx, v.value[0], v.value[1]))),
                    ],
                    onChanged: (v) => set(() => on(v)),
                  ),
                );
            return MSheet(
              title: tr(ctx, 'Apply to all shades', 'Kaikille sävyille'),
              actions: [MButton(label: tr(ctx, 'Apply', 'Käytä'), expand: true, onPressed: () => Navigator.pop(ctx, true))],
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                pick(tr(ctx, 'Shade family', 'Sävyperhe'), _shadeFamilies, family, (v) => family = v),
                pick(tr(ctx, 'Undertone', 'Alasävy'), _undertones, undertone, (v) => undertone = v),
                pick(tr(ctx, 'Finish', 'Viimeistely'), _finishes, finish, (v) => finish = v),
              ]),
            );
          },
        ));
    if (apply != true) return;
    _update(() {
      for (final o in _options) {
        if (family != null) o.shadeFamily = family;
        if (undertone != null) o.undertone = undertone;
        if (finish != null) o.finish = finish;
      }
    });
  }

  // ── Content sizes (skin, hair, fragrance) ─────────────────────────────

  Widget _contentEditor() {
    final c = context.mColors;
    final base = _parseCents(_price.text);
    final quick = _template == 'FRAGRANCE' ? const [30, 50, 100] : const [50, 100, 200, 250];
    void addRow(num? amount) {
      _update(() => _options.add(_Option(contentAmount: amount, contentUnit: 'ml', price: base == null ? '' : _centsText(base))));
      _touch('variants');
      _touch('contentAmount');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        _options.isEmpty
            ? tr(context, 'Sold in one size? Give its content under Ingredients & label. Several sizes (e.g. 30, 50 and 100 ml)? Add a row for each, with its own price.',
                'Myydäänkö yhtä kokoa? Anna sisältö kohdassa Ainesosat ja merkinnät. Useita kokoja (esim. 30, 50 ja 100 ml)? Lisää jokaiselle rivi omalla hinnallaan.')
            : tr(context, 'The price per litre or kilogram is worked out from each size\'s own price.', 'Litra- tai kilohinta lasketaan kunkin koon omasta hinnasta.'),
        style: MType.caption.copyWith(color: c.onSurfaceVariant),
      ),
      const SizedBox(height: MSpace.sm),
      for (final o in _options) _contentRow(o, base),
      Wrap(spacing: MSpace.xs, runSpacing: 0, children: [
        for (final q in quick)
          MChip(label: '$q ml', icon: Icons.add_rounded, showCheck: false, onSelected: (_) => addRow(q)),
        MChip(label: tr(context, 'Other size', 'Muu koko'), icon: Icons.add_rounded, showCheck: false, onSelected: (_) => addRow(null)),
      ]),
    ]);
  }

  Widget _contentRow(_Option o, int? base) {
    final c = context.mColors;
    final price = _parseCents(o.priceCtl.text) ?? base;
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.sm, MSpace.xs, MSpace.sm),
      decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: MTextField(
              controller: o.contentCtl,
              label: tr(context, 'Content', 'Sisältö'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) {
                _touch('variants');
                _update(() {});
              },
            ),
          ),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: MTextField(
              controller: o.priceCtl,
              label: tr(context, 'Price €', 'Hinta €'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => _update(() {}),
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Remove size', 'Poista koko'),
            constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
            onPressed: () => _update(() {
              _options.remove(o);
              o.dispose();
            }),
            icon: Icon(Icons.close_rounded, color: c.onSurfaceVariant),
          ),
        ]),
        const SizedBox(height: MSpace.xs),
        Wrap(spacing: MSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final u in const ['ml', 'g'])
            MChip(label: u, selected: o.contentUnit == u, onSelected: (_) => _update(() => o.contentUnit = u)),
          _stockBox(o),
        ]),
        _unitPricePreview(price, o.contentAmount, o.contentUnit),
      ]),
    );
  }
}

/// "Add colour": the shop's own name and the colour family shoppers filter by.
class _ColourSheet extends StatefulWidget {
  const _ColourSheet();

  @override
  State<_ColourSheet> createState() => _ColourSheetState();
}

class _ColourSheetState extends State<_ColourSheet> {
  final _name = TextEditingController();
  String? _family;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MSheet(
      title: tr(context, 'Add colour', 'Lisää väri'),
      actions: [
        MButton(
          label: tr(context, 'Add', 'Lisää'),
          expand: true,
          onPressed: _name.text.trim().isEmpty && _family == null
              ? null
              : () {
                  final name = _name.text.trim().isEmpty ? tr(context, _colourFamilies[_family]![0], _colourFamilies[_family]![1]) : _name.text.trim();
                  Navigator.pop(context, (name, _family));
                },
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MTextField(
          controller: _name,
          label: tr(context, 'Colour name (your own)', 'Värin nimi (oma)'),
          hint: tr(context, 'e.g. Lingonberry', 'esim. Puolukka'),
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: MSpace.md),
        Text(tr(context, 'Colour family (for filters)', 'Värisävy (suodattimia varten)'), style: MType.label),
        const SizedBox(height: MSpace.xs),
        Wrap(spacing: MSpace.xs, runSpacing: 0, children: [
          for (final f in _colourFamilies.entries)
            MChip(label: tr(context, f.value[0], f.value[1]), selected: _family == f.key, onSelected: (s) => setState(() => _family = s ? f.key : null)),
        ]),
      ]),
    );
  }
}
