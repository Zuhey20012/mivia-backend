part of '../product_editor.dart';

/// Materials & care for clothing, shoes, bags, accessories, eyewear, watches and jewellery: the
/// fibre composition (Reg. 1007/2011 Annex I names, each part totalling 100 %), footwear materials,
/// jewellery metals and the nickel / lead / cadmium basis, CE and UV facts.
extension _EditorMaterials on _ProductEditorScreenState {
  static const _compositionPrefsKey = 'editor_last_composition';
  static const _components = ['main', 'lining', 'filling', 'outer', 'inner', 'trim', 'other'];

  String _componentLabel(String c) => switch (c) {
        'main' => tr(context, 'Main fabric', 'Pääkangas'),
        'lining' => tr(context, 'Lining', 'Vuori'),
        'filling' => tr(context, 'Filling', 'Täyte'),
        'outer' => tr(context, 'Outer', 'Päällinen'),
        'inner' => tr(context, 'Inner', 'Sisäosa'),
        'trim' => tr(context, 'Trim', 'Somiste'),
        _ => tr(context, 'Other part', 'Muu osa'),
      };

  List<_Component> _readComposition(Object? json) {
    if (json is! List) return [];
    return [
      for (final c in json.whereType<Map>())
        _Component('${c['component'] ?? 'main'}', [
          for (final f in (c['fibres'] as List? ?? const []).whereType<Map>()) _Fibre(fibre: f['fibre'] as String?, percent: f['percent'] as num?),
        ]),
    ];
  }

  List<Json>? _compositionJson() {
    final out = <Json>[];
    for (final c in _composition) {
      final fibres = [
        for (final f in c.fibres)
          if (f.fibre != null && f.percent != null && f.percent! > 0) {'fibre': f.fibre, 'percent': f.percent},
      ];
      if (fibres.isNotEmpty) out.add({'component': c.component, 'fibres': fibres});
    }
    return out.isEmpty ? null : out;
  }

  num _total(_Component c) => (c.fibres.fold<num>(0, (s, f) => s + (f.percent ?? 0)) * 10).round() / 10;

  Future<void> _rememberComposition() async {
    final json = _compositionJson();
    if (json == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_compositionPrefsKey, jsonEncode(json));
    } catch (_) {}
  }

  Future<void> _useLastComposition() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_compositionPrefsKey);
      if (raw == null) {
        if (mounted) MSnack.show(context, tr(context, 'No earlier composition on this phone yet.', 'Tässä puhelimessa ei ole vielä aiempaa koostumusta.'));
        return;
      }
      final parts = _readComposition(jsonDecode(raw));
      _update(() {
        for (final c in _composition) {
          for (final f in c.fibres) {
            f.pct.dispose();
          }
        }
        _composition
          ..clear()
          ..addAll(parts);
      });
      _touch('attributes.fibreComposition');
    } catch (_) {}
  }

  List<Map> get _fibreList => ((_f('fibreComposition')?['fibres'] as List?) ?? const []).whereType<Map>().toList();

  String _fibreName(String? key) {
    if (key == null) return tr(context, 'Choose fibre', 'Valitse kuitu');
    final f = _fibreList.where((x) => x['value'] == key).firstOrNull;
    return localized(context, f?['label']) ?? key;
  }

  Future<void> _pickFibre(_Fibre row) async {
    final picked = await showMSheet<String>(context, builder: (_) => _FibreSheet(fibres: _fibreList));
    if (picked == null) return;
    _update(() => row.fibre = picked);
    _touch('attributes.fibreComposition');
  }

  /// The label text: "65 % puuvilla, 35 % polyesteri · Vuori: 100 % viskoosi".
  String _compositionPreview() {
    final parts = <String>[];
    for (final c in _composition) {
      final fibres = [...c.fibres.where((f) => f.fibre != null && f.percent != null)]..sort((a, b) => b.percent!.compareTo(a.percent!));
      if (fibres.isEmpty) continue;
      final text = fibres.map((f) => '${isFinnish(context) ? _numText(f.percent!) : '${f.percent}'} % ${_fibreName(f.fibre).toLowerCase()}').join(', ');
      parts.add(c.component == 'main' ? text : '${_componentLabel(c.component)}: $text');
    }
    return parts.join(' · ');
  }

  Widget _compositionEditor() {
    final c = context.mColors;
    final f = _f('fibreComposition')!;
    final unknown = _attrs['fibreCompositionUnknown'] == true && !_business && _secondHand;
    final preview = _compositionPreview();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(fieldLabel(context, f, 'Material'), 'fibreComposition',
          helper: tr(context, 'From the label, by weight. Each part adds up to 100 %. Fibre names come from the EU list: "bamboo" is viscose.',
              'Lapusta, painon mukaan. Jokaisen osan on oltava yhteensä 100 %. Kuitujen nimet ovat EU:n luettelosta: "bambu" on viskoosia.')),
      if (!_business && _secondHand && _has('fibreCompositionUnknown'))
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _attrs['fibreCompositionUnknown'] == true,
          onChanged: (v) => _setAttr('fibreCompositionUnknown', v ? true : null),
          title: Text(fieldLabel(context, _f('fibreCompositionUnknown'), 'Material label missing'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(tr(context, 'Shoppers then see "Seller could not give the material".', 'Asiakkaat näkevät silloin "Myyjä ei tiedä materiaalia".'), style: MType.caption),
        ),
      if (!unknown) ...[
        for (final comp in _composition) _componentCard(comp),
        if (preview.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(MSpace.md),
            decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'Shoppers see', 'Asiakkaat näkevät'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
              Text(preview, style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          MButton(
            label: _composition.isEmpty ? tr(context, 'Add composition', 'Lisää koostumus') : tr(context, 'Add a part (lining, filling…)', 'Lisää osa (vuori, täyte…)'),
            icon: Icons.add_rounded,
            variant: MButtonVariant.outline,
            size: MButtonSize.sm,
            onPressed: () {
              final used = _composition.map((x) => x.component).toSet();
              final next = _components.firstWhere((x) => !used.contains(x), orElse: () => 'other');
              if (_composition.length >= 6) return;
              _update(() => _composition.add(_Component(next, [_Fibre()])));
              _touch('attributes.fibreComposition');
            },
          ),
          if (_composition.isEmpty)
            MButton(
              label: tr(context, 'Same as my last product', 'Sama kuin edellisessä tuotteessa'),
              icon: Icons.history_rounded,
              variant: MButtonVariant.text,
              size: MButtonSize.sm,
              onPressed: _useLastComposition,
            ),
        ]),
      ],
    ]);
  }

  Widget _componentCard(_Component comp) {
    final c = context.mColors;
    final total = _total(comp);
    final ok = total == 100;
    final totalText = isFinnish(context) ? _numText(total) : '$total';
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.xs, MSpace.xs, MSpace.sm),
      decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm, border: Border.all(color: ok ? c.outline : c.warning)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: comp.component,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, 'Part', 'Osa')),
              items: [for (final x in _components) DropdownMenuItem(value: x, child: Text(_componentLabel(x)))],
              onChanged: (v) => _update(() => comp.component = v ?? comp.component),
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Remove part', 'Poista osa'),
            constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
            onPressed: () => _update(() {
              _composition.remove(comp);
              for (final f in comp.fibres) {
                f.pct.dispose();
              }
            }),
            icon: Icon(Icons.close_rounded, color: c.onSurfaceVariant),
          ),
        ]),
        for (final row in comp.fibres)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget), alignment: Alignment.centerLeft),
                  onPressed: () => _pickFibre(row),
                  child: Text(_fibreName(row.fibre), overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: MSpace.sm),
              SizedBox(
                width: 96,
                child: MTextField(
                  controller: row.pct,
                  label: '%',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(5)],
                  onChanged: (_) {
                    _touch('attributes.fibreComposition');
                    _update(() {});
                  },
                ),
              ),
              IconButton(
                tooltip: tr(context, 'Remove fibre', 'Poista kuitu'),
                constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
                onPressed: comp.fibres.length == 1
                    ? null
                    : () => _update(() {
                          comp.fibres.remove(row);
                          row.pct.dispose();
                        }),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                ok
                    ? tr(context, 'Total 100 %', 'Yhteensä 100 %')
                    : tr(context, 'Total $total %: it must be 100 %', 'Yhteensä $totalText %: summan on oltava 100 %'),
                style: MType.label.copyWith(color: ok ? c.success : c.onWarningSoft),
              ),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(kMinTouchTarget, kMinTouchTarget)),
            onPressed: comp.fibres.length >= 10 ? null : () => _update(() => comp.fibres.add(_Fibre(percent: ok ? null : (100 - total).clamp(0, 100)))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr(context, 'Fibre', 'Kuitu')),
          ),
        ]),
      ]),
    );
  }

  Widget _materialsSection() {
    final hasComposition = _has('fibreComposition');
    final precious = const ['gold', 'white_gold', 'rose_gold', 'silver_925', 'sterling_silver', 'platinum', 'palladium'].contains(_attrs['metal']);
    final title = _template == 'JEWELLERY' ? tr(context, 'Metal and safety', 'Metalli ja turvallisuus') : tr(context, 'Materials and care', 'Materiaalit ja hoito');
    return _section(title, Icons.texture_rounded, [
      if (hasComposition) _anchor('attributes.fibreComposition', _compositionEditor()),
      ..._attrList(['containsAnimalNonTextile', 'textileUnder80', 'lining']),
      // Footwear (Directive 94/11/EC): up to two materials per part when none reaches 80 %
      for (final k in const ['materialUpper', 'materialLiningSock', 'materialOuterSole'])
        _attr(k, helper: tr(context, 'One, or two if no material reaches 80 %.', 'Yksi, tai kaksi jos mikään materiaali ei ole 80 %.')),
      ..._attrList(['materialDetail', 'width', 'heelHeightCm', 'closure', 'waterproof', 'linedWarm']),
      ..._attrList(['mainMaterial', 'dimensionsCm', 'strap', 'laptopFitsInch', 'metalSkinContact']),
      ..._attrList(['uvFilterCategory', 'ceMarked', 'polarised', 'frameMaterial', 'ratedVoltage', 'plugType']),
      ..._attrList(['movement', 'caseMaterial', 'strapMaterial', 'waterResistance', 'containsBattery']),
      // Jewellery (REACH Annex XVII)
      _attr('metal'),
      if (precious) _attr('fineness'),
      ..._attrList(['plating', 'nickelBasis', 'leadCadmiumBasis', 'stone', 'chainLengthCm', 'forPiercing', 'hallmarked']),
      _attr('careInstructions'),
    ]);
  }
}

/// Pick a fibre from the Annex I list (search in either language).
class _FibreSheet extends StatefulWidget {
  final List<Map> fibres;
  const _FibreSheet({required this.fibres});

  @override
  State<_FibreSheet> createState() => _FibreSheetState();
}

class _FibreSheetState extends State<_FibreSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = widget.fibres.where((f) {
      final l = f['label'] as Map? ?? const {};
      return q.isEmpty || '${l['en']} ${l['fi']} ${f['value']}'.toLowerCase().contains(q);
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.sm),
              child: MTextField(
                controller: _q,
                label: tr(context, 'Find a fibre', 'Hae kuitua'),
                prefixIcon: Icons.search_rounded,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView(children: [
                for (final f in list)
                  MListTile(
                    title: localized(context, f['label']) ?? '${f['value']}',
                    chevron: false,
                    onTap: () => Navigator.pop(context, '${f['value']}'),
                  ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(MSpace.xl),
                    child: Text(
                      tr(context, 'Not on the EU list. Bamboo is "viscose"; for others choose "other fibres".', 'Ei EU:n luettelossa. Bambu on "viskoosi"; muille valitse "muut kuidut".'),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
