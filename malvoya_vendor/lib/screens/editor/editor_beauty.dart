part of '../product_editor.dart';

/// Ingredients & label for cosmetics, skin, hair, nails and fragrance (Reg. 1223/2009 Art. 19):
/// the INCI list as printed, content (ml / g) with the unit price, shelf life (PAO or best before),
/// function, how to use and precautions in Finnish and Swedish, and the "sealed and unused" rule.
extension _EditorBeauty on _ProductEditorScreenState {
  /// The INCI list split into names ("Ingredients:" dropped, parentheses kept).
  List<String> _inciNames(String text) {
    final t = text.trim().replaceFirst(RegExp(r'^(ingredients|ainesosat|ingredienser)\s*:\s*', caseSensitive: false), '');
    final out = <String>[];
    var depth = 0;
    final buf = StringBuffer();
    for (final ch in t.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if (ch == ')' || ch == ']') depth = depth > 0 ? depth - 1 : 0;
      if (ch == ',' && depth == 0) {
        if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    final last = buf.toString().trim().replaceAll(RegExp(r'\.$'), '');
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  /// "Free from" choices the INCI list contradicts (spec §2.7.1); the server is the final check.
  List<String> _freeFromConflicts(List<String> names) {
    final lower = names.map((n) => n.toLowerCase()).toList();
    bool any(List<String> words) => lower.any((n) => words.any((w) => n.contains(w)));
    final chosen = ((_attrs['freeFrom'] as List?) ?? const []).map((e) => '$e').toSet();
    return [
      if (chosen.contains('fragrance') && any(const ['parfum', 'fragrance', 'aroma', 'linalool', 'limonene', 'citronellol', 'geraniol', 'coumarin', 'eugenol', 'citral']))
        tr(context, 'The list contains fragrance (e.g. parfum or linalool), so "free from fragrance" isn\'t allowed.', 'Luettelossa on hajustetta (esim. parfum tai linalool), joten "hajusteeton" ei ole sallittu.'),
      if (chosen.contains('alcohol') && any(const ['alcohol denat', 'ethanol']) || chosen.contains('alcohol') && lower.contains('alcohol'))
        tr(context, 'The list contains alcohol, so "free from alcohol" isn\'t allowed.', 'Luettelossa on alkoholia, joten "alkoholiton" ei ole sallittu.'),
      if (chosen.contains('animal_derived') && any(const ['cera alba', 'beeswax', 'lanolin', 'ci 75470', 'carmine', 'mel ', 'honey', 'keratin', 'collagen']))
        tr(context, 'The list contains an ingredient that may be of animal origin (e.g. beeswax, lanolin or carmine). Check before choosing "free from animal-derived".',
            'Luettelossa on mahdollisesti eläinperäinen ainesosa (esim. mehiläisvaha, lanoliini tai karmiini). Tarkista ennen kuin valitset "ei eläinperäisiä ainesosia".'),
      if (chosen.contains('acetone') && any(const ['acetone']))
        tr(context, 'The list contains acetone, so "free from acetone" isn\'t allowed.', 'Luettelossa on asetonia, joten "asetoniton" ei ole sallittu.'),
    ];
  }

  Widget _inciBox() {
    final c = context.mColors;
    final f = _f('ingredientsInci');
    if (f == null) return const SizedBox.shrink();
    final ctl = _tc('ingredientsInci', '${_attrs['ingredientsInci'] ?? ''}');
    final names = _inciNames(ctl.text);
    final conflicts = _freeFromConflicts(names);
    return _anchor(
      'attributes.ingredientsInci',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(fieldLabel(context, f, 'Ingredients'), 'ingredientsInci',
            helper: tr(context, 'Paste the INCI list exactly as printed on the pack, e.g. "Ingredients: Aqua, Glycerin, …". Shoppers can search it for allergens.',
                'Liitä INCI-luettelo täsmälleen pakkauksen mukaan, esim. "Ingredients: Aqua, Glycerin, …". Asiakkaat voivat etsiä siitä allergeeneja.')),
        MTextField(
          controller: ctl,
          hint: 'Ingredients: Aqua, Glycerin, …',
          maxLines: 8,
          minLines: 4,
          maxLength: 6000,
          errorText: _err('attributes.ingredientsInci'),
          onChanged: (s) => _setAttr('ingredientsInci', s.trim().isEmpty ? null : s),
        ),
        if (names.isNotEmpty) ...[
          Text(tr(context, '${names.length} ingredients', '${names.length} ainesosaa'), style: MType.label),
          const SizedBox(height: MSpace.xs),
          Wrap(spacing: MSpace.xs, runSpacing: MSpace.xs, children: [
            for (final n in names.take(14)) MBadge(n, tone: MBadgeTone.neutral),
            if (names.length > 14) MBadge(tr(context, '+${names.length - 14} more', '+${names.length - 14} muuta'), tone: MBadgeTone.neutral),
          ]),
        ],
        for (final x in conflicts) _issueLine(x, danger: false),
        Padding(
          padding: const EdgeInsets.only(top: MSpace.xs),
          child: Text(tr(context, 'A photo of the ingredient panel can go in Label photos, but the typed list is still needed.', 'Kuvan ainesosaluettelosta voit lisätä merkintäkuviin, mutta kirjoitettu luettelo tarvitaan silti.'),
              style: MType.caption.copyWith(color: c.onSurfaceVariant)),
        ),
      ]),
    );
  }

  Widget _contentBox() {
    final rows = _variantMode == _VMode.content && _options.isNotEmpty;
    final c = context.mColors;
    return _anchor(
      'contentAmount',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tr(context, 'Content', 'Sisältö'), 'contentAmount'),
        if (rows)
          Text(tr(context, 'Each size has its own content under Sizes and prices.', 'Jokaisella koolla on oma sisältönsä kohdassa Koot ja hinnat.'), style: MType.bodyM.copyWith(color: c.onSurfaceVariant))
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 140,
              child: MTextField(
                controller: _content,
                hint: '50',
                errorText: _err('contentAmount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) {
                  _touch('contentAmount');
                  _update(() => _contentUnit ??= 'ml');
                },
              ),
            ),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Wrap(spacing: MSpace.xs, children: [
                for (final u in const ['ml', 'g', 'pcs'])
                  MChip(label: u == 'pcs' ? tr(context, 'pcs', 'kpl') : u, selected: _contentUnit == u, onSelected: (_) => _update(() => _contentUnit = u)),
              ]),
            ),
          ]),
          _unitPricePreview(_parseCents(_price.text), _parseNum(_content.text), _contentUnit),
        ],
      ]),
    );
  }

  Widget _beautySection() {
    final durability = _attrs['durabilityType'];
    return _section(tr(context, 'Ingredients and label', 'Ainesosat ja pakkausmerkinnät'), Icons.science_outlined, [
      _inciBox(),
      _contentBox(),
      ..._attrList(['keyIngredients', 'freeFrom']),
      if (_has('freeFrom'))
        Text(
          tr(context, '"Free from parabens", "chemical-free", "non-toxic" and "hypoallergenic" are not offered: they are misleading or need evidence.',
              '"Parabeeniton", "kemikaaliton", "myrkytön" ja "hypoallergeeninen" eivät ole valittavissa: ne ovat harhaanjohtavia tai vaativat näyttöä.'),
          style: MType.caption.copyWith(color: context.mColors.onSurfaceVariant),
        ),
      _attr('durabilityType'),
      if (durability == 'pao') _attr('paoMonths', helper: tr(context, 'The open-jar symbol on the pack, e.g. 12M', 'Pakkauksen avatun purkin merkki, esim. 12M')),
      if (durability == 'best_before') _attr('bestBefore'),
      _attr('function'),
      _attr('howToUse'),
      _attr('noPrecautions'),
      if (_attrs['noPrecautions'] != true) _attr('precautions'),
      _attr('countryOfOrigin', helper: tr(context, 'Needed for products made outside the EU.', 'Tarvitaan EU:n ulkopuolella valmistetuille tuotteille.')),
      _attr('sealedUnused', helper: tr(context, 'Only sealed, unused cosmetics can be sold.', 'Vain avaamatonta ja käyttämätöntä kosmetiikkaa voi myydä.')),
      ..._attrList(['isTesterOrSample', 'professionalUse']),
    ]);
  }
}
