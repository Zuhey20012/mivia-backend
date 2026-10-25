part of '../product_editor.dart';

/// Shared pieces of the editor form: sections, anchors (so "Fix next" can scroll to a field and the
/// API's field errors show next to it), required tags and the generic field types of a template.
extension _EditorFields on _ProductEditorScreenState {
  // ── Sections and anchors ───────────────────────────────────────────────

  Widget _section(String title, IconData icon, List<Widget?> children, {String? subtitle}) {
    final c = context.mColors;
    final visible = children.whereType<Widget>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.lg),
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.sm),
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brLg, border: Border.all(color: c.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          child: Row(children: [
            CircleAvatar(radius: 18, backgroundColor: c.primarySoft, child: Icon(icon, size: 20, color: c.onPrimarySoft)),
            const SizedBox(width: MSpace.md),
            Expanded(child: Text(title, style: MType.title)),
          ]),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: MSpace.xs),
          Text(subtitle, style: MType.caption.copyWith(color: c.onSurfaceVariant)),
        ],
        const SizedBox(height: MSpace.md),
        for (final w in visible) Padding(padding: const EdgeInsets.only(bottom: MSpace.md), child: w),
      ]),
    );
  }

  /// Registers [anchor] for "Fix next" and shows its problems (red) and notes (amber) under [child].
  Widget _anchor(String anchor, Widget child, {bool showIssues = true}) {
    _anchorOrder.add(anchor);
    final key = _anchorKeys.putIfAbsent(anchor, () => GlobalKey());
    final issues = showIssues ? _issues[anchor] ?? const <FieldIssue>[] : const <FieldIssue>[];
    final notes = showIssues ? _notes[anchor] ?? const <FieldIssue>[] : const <FieldIssue>[];
    return KeyedSubtree(
      key: key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        child,
        for (final i in issues) _issueLine(i.text(context), danger: true),
        for (final n in notes) _issueLine(n.text(context), danger: false),
      ]),
    );
  }

  Widget _issueLine(String text, {required bool danger}) {
    final c = context.mColors;
    return Padding(
      padding: const EdgeInsets.only(top: MSpace.xs),
      child: Semantics(
        liveRegion: danger,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(danger ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 16, color: danger ? c.danger : c.onWarningSoft),
          const SizedBox(width: MSpace.xs),
          Expanded(child: Text(text, style: MType.caption.copyWith(color: danger ? c.danger : c.onWarningSoft, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  /// A field's own problem as an error text (for MTextField), or null.
  String? _err(String anchor) {
    final l = _issues[anchor];
    return l == null || l.isEmpty ? null : l.first.text(context);
  }

  /// Clears the problems of [anchor] once the store changes it.
  void _touch(String anchor) {
    if (_issues.containsKey(anchor) || _notes.containsKey(anchor)) {
      _update(() {
        _issues.remove(anchor);
        _notes.remove(anchor);
      });
    }
  }

  // ── Required tags ──────────────────────────────────────────────────────

  /// "law" | "malvoya" | null for a field, as the template says (GPSR fields for business sellers).
  String? _levelOf(String key) {
    switch (key) {
      case 'manufacturerId':
      case 'productModel':
      case 'warnings':
        return _business ? 'law' : null;
      case 'responsiblePersonId':
      case 'contentAmount':
        return 'law';
      case 'defectsNote':
        return _secondHand && ['GOOD', 'FAIR', 'POOR'].contains(_condition) ? 'malvoya' : null;
    }
    final l = _f(key)?['level'];
    return l == 'law' || l == 'malvoya' ? '$l' : null;
  }

  String _reasonFor(String key) {
    String law(String en, String fi) => tr(context, en, fi);
    return switch (key) {
      'fibreComposition' || 'containsAnimalNonTextile' => law('EU textile labelling regulation (EU) No 1007/2011: the fibre composition must be shown before purchase.',
          'EU:n tekstiilimerkintäasetus (EU) N:o 1007/2011: kuitukoostumus on näytettävä ennen ostoa.'),
      'materialUpper' || 'materialLiningSock' || 'materialOuterSole' => law('Footwear labelling directive 94/11/EC: upper, lining and sole materials.',
          'Jalkineiden merkintädirektiivi 94/11/EY: päällisen, vuorin ja pohjan materiaalit.'),
      'manufacturerId' || 'productModel' || 'warnings' => law('EU General Product Safety Regulation (EU) 2023/988, Art. 19: online listings by traders show the manufacturer, the type and the warnings.',
          'EU:n yleinen tuoteturvallisuusasetus (EU) 2023/988, 19 artikla: elinkeinonharjoittajan verkkotuotteessa näytetään valmistaja, tyyppi ja varoitukset.'),
      'responsiblePersonId' => law('Cosmetics need an EU responsible person (Regulation (EC) No 1223/2009); other products from outside the EU need one under GPSR.',
          'Kosmetiikalla on oltava vastuuhenkilö EU:ssa (asetus (EY) N:o 1223/2009); muilla EU:n ulkopuolelta tulevilla tuotteilla tuoteturvallisuusasetuksen mukaan.'),
      'contentAmount' => law('Cosmetics regulation Art. 19 and the Finnish unit price decree 553/2013: the content gives the price per litre or kilogram.',
          'Kosmetiikka-asetuksen 19 artikla ja yksikköhinta-asetus 553/2013: sisällön perusteella näytetään litra- tai kilohinta.'),
      'durabilityType' || 'paoMonths' || 'bestBefore' || 'function' || 'precautions' || 'ingredientsInci' => law('EU cosmetics regulation (EC) No 1223/2009, Art. 19: the label facts the buyer needs, in Finnish and Swedish.',
          'EU:n kosmetiikka-asetus (EY) N:o 1223/2009, 19 artikla: ostajan tarvitsemat pakkausmerkinnät suomeksi ja ruotsiksi.'),
      'nickelBasis' || 'leadCadmiumBasis' => law('REACH Annex XVII (entries 23, 27, 63): limits for nickel, lead and cadmium in jewellery.',
          'REACH-asetuksen liite XVII (kohdat 23, 27, 63): nikkelin, lyijyn ja kadmiumin raja-arvot koruissa.'),
      'uvFilterCategory' || 'ceMarked' => law('Personal protective equipment regulation (EU) 2016/425 (sunglasses) and the CE rules for electrical appliances.',
          'Henkilönsuojainasetus (EU) 2016/425 (aurinkolasit) ja sähkölaitteiden CE-säännöt.'),
      'cordsDrawstrings' => law('Product safety for children\'s clothes (EN 14682): no cords in the hood or neck area for under-7s.',
          'Lastenvaatteiden turvallisuus (EN 14682): alle 7-vuotiaiden vaatteissa ei saa olla nyörejä hupussa tai kaulan alueella.'),
      _ => tr(context, 'Malvoya needs this so shoppers can find, filter and compare products.', 'Malvoya tarvitsee tämän, jotta asiakkaat voivat löytää, suodattaa ja vertailla tuotteita.'),
    };
  }

  Widget _reqTag(String key) {
    final level = _levelOf(key);
    if (level == null) return const SizedBox.shrink();
    final law = level == 'law';
    final label = law ? tr(context, 'Required by law', 'Lakisääteinen') : tr(context, 'Required', 'Pakollinen');
    return Semantics(
      button: true,
      label: tr(context, '$label: why?', '$label: miksi?'),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: MRadius.pillRadius,
        onTap: () => showMSheet<void>(context, builder: (ctx) => MSheet(
              title: label,
              actions: [MButton(label: tr(ctx, 'Got it', 'Selvä'), expand: true, onPressed: () => Navigator.pop(ctx))],
              child: Text(_reasonFor(key), style: MType.bodyL),
            )),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget, minWidth: kMinTouchTarget),
          child: Center(child: MBadge(label, tone: law ? MBadgeTone.danger : MBadgeTone.brand, icon: law ? Icons.gavel_rounded : null)),
        ),
      ),
    );
  }

  /// A field's title row: label, then its required tag.
  Widget _title(String label, String key, {String? helper}) {
    final c = context.mColors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(label, style: MType.label)),
        _reqTag(key),
      ]),
      if (helper != null) Padding(padding: const EdgeInsets.only(bottom: MSpace.xs), child: Text(helper, style: MType.caption.copyWith(color: c.onSurfaceVariant))),
    ]);
  }

  // ── Generic attribute fields ───────────────────────────────────────────

  TextEditingController _tc(String key, String initial) => _ctl.putIfAbsent(key, () => TextEditingController(text: initial));

  void _setAttr(String key, Object? value) {
    _update(() {
      if (value == null) {
        _attrs.remove(key);
      } else {
        _attrs[key] = value;
      }
    });
    _touch('attributes.$key');
  }

  /// One template field by key, drawn by its type; nothing when the template has no such field.
  Widget? _attr(String key, {String? label, String? helper}) {
    final f = _f(key);
    if (f == null) return null;
    final name = label ?? fieldLabel(context, f, key);
    final anchor = 'attributes.$key';
    final w = switch ('${f['type']}') {
      'enum' => _enumField(f, key, name, helper),
      'enums' => _enumsField(f, key, name, helper),
      'bool' => _boolField(key, name, helper),
      'int' || 'number' => _numberField(f, key, name, helper),
      'i18n' => _i18nField(key, name, helper),
      'month' => _monthField(key, name, helper),
      'strings' => _stringsField(f, key, name, helper),
      'dimensions' => _dimensionsField(key, name),
      'care' => _careField(key, name),
      'composition' || 'sizeChart' => null,
      _ => _textField(f, key, name, helper),
    };
    if (w == null) return null;
    return _anchor(anchor, w);
  }

  List<Widget> _attrList(Iterable<String> keys) => [for (final k in keys) _attr(k)].whereType<Widget>().toList();

  Widget _enumField(Json f, String key, String label, String? helper) {
    final values = (f['values'] as List? ?? const []).whereType<Map>().toList();
    final current = _attrs[key];
    if (values.length > 14) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(label, key, helper: helper),
        DropdownButtonFormField<String>(
          value: values.any((v) => '${v['value']}' == '$current') ? '$current' : null,
          isExpanded: true,
          decoration: InputDecoration(hintText: tr(context, 'Choose', 'Valitse')),
          items: [
            DropdownMenuItem<String>(value: null, child: Text(tr(context, 'Not given', 'Ei annettu'))),
            for (final v in values) DropdownMenuItem(value: '${v['value']}', child: Text(localized(context, v['label']) ?? '${v['value']}')),
          ],
          onChanged: (s) => _setAttr(key, s == null ? null : values.firstWhere((v) => '${v['value']}' == s)['value']),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key, helper: helper),
      Wrap(spacing: MSpace.sm, runSpacing: 0, children: [
        for (final v in values)
          MChip(
            label: localized(context, v['label']) ?? '${v['value']}',
            selected: '$current' == '${v['value']}' && current != null,
            onSelected: (sel) => _setAttr(key, sel ? v['value'] : null),
          ),
      ]),
    ]);
  }

  Widget _enumsField(Json f, String key, String label, String? helper) {
    final values = (f['values'] as List? ?? const []).whereType<Map>().toList();
    final max = asInt(f['maxItems']) ?? values.length;
    final current = ((_attrs[key] as List?) ?? const []).map((e) => '$e').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key, helper: helper ?? (max < values.length ? tr(context, 'Choose up to $max', 'Valitse enintään $max') : null)),
      Wrap(spacing: MSpace.sm, runSpacing: 0, children: [
        for (final v in values)
          MChip(
            label: localized(context, v['label']) ?? '${v['value']}',
            selected: current.contains('${v['value']}'),
            onSelected: (sel) {
              final next = [...current];
              if (sel) {
                if (next.length >= max) {
                  MSnack.show(context, tr(context, 'Up to $max can be chosen.', 'Voit valita enintään $max.'));
                  return;
                }
                next.add('${v['value']}');
              } else {
                next.remove('${v['value']}');
              }
              _setAttr(key, next.isEmpty ? null : next);
            },
          ),
      ]),
    ]);
  }

  Widget _boolField(String key, String label, String? helper) {
    return Row(children: [
      Expanded(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _attrs[key] == true,
          onChanged: (v) => _setAttr(key, v),
          title: Text(label, style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
          subtitle: helper == null ? null : Text(helper, style: MType.caption),
        ),
      ),
      _reqTag(key),
    ]);
  }

  Widget _numberField(Json f, String key, String label, String? helper) {
    final isInt = f['type'] == 'int';
    final ctl = _tc(key, _attrs[key] is num ? _numText(_attrs[key] as num) : '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key),
      MTextField(
        controller: ctl,
        helper: helper,
        errorText: _err('attributes.$key'),
        keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(isInt ? r'[0-9]' : r'[0-9.,]'))],
        onChanged: (s) {
          final n = _parseNum(s);
          _setAttr(key, n == null ? null : (isInt ? n.round() : n));
        },
      ),
    ]);
  }

  Widget _textField(Json f, String key, String label, String? helper, {int maxLines = 1}) {
    final max = asInt(f['max']);
    final country = key == 'countryOfManufacture' || key == 'countryOfOrigin';
    final ctl = _tc(key, '${_attrs[key] ?? ''}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key),
      MTextField(
        controller: ctl,
        helper: helper ?? (country ? tr(context, 'Two-letter country code, e.g. FI', 'Kaksikirjaiminen maakoodi, esim. FI') : null),
        hint: country ? 'FI' : null,
        errorText: _err('attributes.$key'),
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : null,
        maxLength: max != null && max > 60 ? max : null,
        textCapitalization: country ? TextCapitalization.characters : TextCapitalization.sentences,
        inputFormatters: [
          if (max != null) LengthLimitingTextInputFormatter(max),
          if (country) FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
        ],
        onChanged: (s) => _setAttr(key, s.trim().isEmpty ? null : (country ? s.trim().toUpperCase() : s)),
      ),
    ]);
  }

  /// A text in Finnish, Swedish and (optionally) English, as on the label.
  Widget _i18nField(String key, String label, String? helper) {
    final cur = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
    Widget lang(String code, String name) {
      final ctl = _tc('$key.$code', '${cur[code] ?? ''}');
      return Padding(
        padding: const EdgeInsets.only(bottom: MSpace.sm),
        child: MTextField(
          controller: ctl,
          label: name,
          maxLines: 5,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (s) {
            final next = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
            if (s.trim().isEmpty) {
              next.remove(code);
            } else {
              next[code] = s;
            }
            _setAttr(key, next.isEmpty ? null : next);
          },
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key, helper: helper ?? tr(context, 'As on the pack. Finnish and Swedish are needed.', 'Kuten pakkauksessa. Suomi ja ruotsi tarvitaan.')),
      lang('fi', tr(context, 'Finnish', 'Suomeksi')),
      lang('sv', tr(context, 'Swedish', 'Ruotsiksi')),
      lang('en', tr(context, 'English (optional)', 'Englanniksi (valinnainen)')),
    ]);
  }

  Widget _monthField(String key, String label, String? helper) {
    final ctl = _tc(key, '${_attrs[key] ?? ''}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key),
      MTextField(
        controller: ctl,
        hint: tr(context, 'YYYY-MM, e.g. 2027-06', 'VVVV-KK, esim. 2027-06'),
        helper: helper,
        errorText: _err('attributes.$key'),
        keyboardType: TextInputType.datetime,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(7)],
        onChanged: (s) => _setAttr(key, RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(s.trim()) ? s.trim() : (s.trim().isEmpty ? null : _attrs[key])),
      ),
    ]);
  }

  Widget _stringsField(Json f, String key, String label, String? helper) {
    final max = asInt(f['maxItems']) ?? 6;
    final ctl = _tc(key, ((_attrs[key] as List?) ?? const []).join(', '));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key),
      MTextField(
        controller: ctl,
        helper: helper ?? tr(context, 'Separate with commas, up to $max', 'Erota pilkuilla, enintään $max'),
        onChanged: (s) {
          final list = s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).take(max).toList();
          _setAttr(key, list.isEmpty ? null : list);
        },
      ),
    ]);
  }

  Widget _dimensionsField(String key, String label) {
    final cur = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
    Widget part(String k, String name) => Expanded(
          child: MTextField(
            controller: _tc('$key.$k', cur[k] is num ? _numText(cur[k] as num) : ''),
            label: name,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (s) {
              final next = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
              final n = _parseNum(s);
              if (n == null || n <= 0) {
                next.remove(k);
              } else {
                next[k] = n;
              }
              _setAttr(key, next['w'] != null && next['h'] != null ? next : (next.isEmpty ? null : next));
            },
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key, helper: tr(context, 'In centimetres', 'Senttimetreinä')),
      Row(children: [
        part('w', tr(context, 'Width', 'Leveys')),
        const SizedBox(width: MSpace.sm),
        part('h', tr(context, 'Height', 'Korkeus')),
        const SizedBox(width: MSpace.sm),
        part('d', tr(context, 'Depth', 'Syvyys')),
      ]),
    ]);
  }

  /// ISO 3758 care: one choice per group, shown as words (drawing the symbols needs a trademark check).
  Widget _careField(String key, String label) {
    final cur = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
    final groups = <String, (String, Map<String, String>)>{
      'wash': (tr(context, 'Washing', 'Pesu'), {
        'W30': tr(context, 'Machine 30 °C', 'Konepesu 30 °C'), 'W30_MILD': tr(context, '30 °C, mild', '30 °C, hienopesu'),
        'W30_VERY_MILD': tr(context, '30 °C, very mild', '30 °C, erittäin hieno'), 'W40': tr(context, 'Machine 40 °C', 'Konepesu 40 °C'),
        'W40_MILD': tr(context, '40 °C, mild', '40 °C, hienopesu'), 'W60': tr(context, 'Machine 60 °C', 'Konepesu 60 °C'),
        'W95': tr(context, 'Machine 95 °C', 'Konepesu 95 °C'), 'HAND': tr(context, 'Hand wash', 'Käsinpesu'), 'NO_WASH': tr(context, 'Do not wash', 'Ei saa pestä'),
      }),
      'bleach': (tr(context, 'Bleaching', 'Valkaisu'), {
        'ANY': tr(context, 'Any bleach', 'Mikä tahansa valkaisu'), 'OXYGEN_ONLY': tr(context, 'Oxygen only', 'Vain happivalkaisu'), 'NO_BLEACH': tr(context, 'Do not bleach', 'Ei valkaisua'),
      }),
      'tumble': (tr(context, 'Tumble drying', 'Rumpukuivaus'), {
        'NORMAL': tr(context, 'Normal', 'Normaali'), 'LOW': tr(context, 'Low heat', 'Matala lämpö'), 'NO_TUMBLE': tr(context, 'Do not tumble dry', 'Ei rumpukuivausta'),
      }),
      'naturalDry': (tr(context, 'Drying', 'Kuivaus'), {
        'LINE': tr(context, 'Line dry', 'Narukuivaus'), 'DRIP_LINE': tr(context, 'Drip dry on a line', 'Valutus narulla'), 'FLAT': tr(context, 'Dry flat', 'Tasokuivaus'),
        'DRIP_FLAT': tr(context, 'Drip dry flat', 'Valutus tasolla'), 'LINE_SHADE': tr(context, 'Line dry in the shade', 'Narukuivaus varjossa'), 'FLAT_SHADE': tr(context, 'Dry flat in the shade', 'Tasokuivaus varjossa'),
      }),
      'iron': (tr(context, 'Ironing', 'Silitys'), {
        'HIGH': tr(context, 'Hot', 'Kuuma'), 'MEDIUM': tr(context, 'Warm', 'Keskilämpö'), 'LOW': tr(context, 'Cool', 'Matala lämpö'), 'NO_IRON': tr(context, 'Do not iron', 'Ei silitystä'),
      }),
      'professional': (tr(context, 'Professional care', 'Ammattihuolto'), {
        'P': tr(context, 'Dry clean (P)', 'Kemiallinen pesu (P)'), 'P_MILD': tr(context, 'Dry clean, mild (P)', 'Kemiallinen pesu, hellävarainen (P)'),
        'F': tr(context, 'Dry clean (F)', 'Kemiallinen pesu (F)'), 'F_MILD': tr(context, 'Dry clean, mild (F)', 'Kemiallinen pesu, hellävarainen (F)'),
        'NO_DRY_CLEAN': tr(context, 'Do not dry clean', 'Ei kemiallista pesua'), 'W': tr(context, 'Wet clean', 'Märkäpesu'),
        'W_MILD': tr(context, 'Wet clean, mild', 'Märkäpesu, hellävarainen'), 'W_VERY_MILD': tr(context, 'Wet clean, very mild', 'Märkäpesu, erittäin hellävarainen'),
        'NO_WET_CLEAN': tr(context, 'Do not wet clean', 'Ei märkäpesua'),
      }),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(label, key, helper: tr(context, 'Optional. Shown to shoppers in words.', 'Valinnainen. Näytetään asiakkaille sanoin.')),
      for (final g in groups.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: DropdownButtonFormField<String>(
            value: g.value.$2.containsKey(cur[g.key]) ? '${cur[g.key]}' : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: g.value.$1),
            items: [
              DropdownMenuItem<String>(value: null, child: Text(tr(context, 'Not given', 'Ei annettu'))),
              for (final o in g.value.$2.entries) DropdownMenuItem(value: o.key, child: Text(o.value)),
            ],
            onChanged: (v) {
              final next = _attrs[key] is Map ? Json.from(_attrs[key]) : <String, dynamic>{};
              if (v == null) {
                next.remove(g.key);
              } else {
                next[g.key] = v;
              }
              _setAttr(key, next.isEmpty ? null : next);
            },
          ),
        ),
    ]);
  }
}
