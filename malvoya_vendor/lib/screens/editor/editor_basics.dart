part of '../product_editor.dart';

/// Basics: name, brand, description (with the claims check), price with the unit price preview,
/// condition (second-hand with defects), handmade, and the template's descriptive fields.
extension _EditorBasics on _ProductEditorScreenState {
  static const _basicsKeys = [
    'productType', 'colourFamily', 'colourName', 'pattern', 'season', 'occasion', 'fitCollection', 'fit', 'lengthType', 'sleeveLength',
    'neckline', 'modelHeightCm', 'modelSizeWorn', 'concentration', 'olfactoryFamily', 'notesTop', 'notesHeart', 'notesBase', 'launchYear',
    'refillable', 'giftSet', 'skinType', 'skinConcern', 'hairType', 'spf', 'coverage', 'formulation', 'finish',
  ];

  /// Keys that other sections draw; anything else in the template lands under "More details".
  static const _placedKeys = {
    'brand', 'countryOfManufacture', 'originDeclared', ..._basicsKeys,
    'defectsNote', 'hasTags', 'originalSizeLabel', 'authenticity', 'brandTier', 'vintage',
    'sizeSystem', 'sizeChart',
    'fibreComposition', 'containsAnimalNonTextile', 'fibreCompositionUnknown', 'textileUnder80', 'lining', 'careInstructions',
    'materialUpper', 'materialLiningSock', 'materialOuterSole', 'materialDetail', 'width', 'heelHeightCm', 'closure', 'waterproof', 'linedWarm',
    'mainMaterial', 'dimensionsCm', 'strap', 'laptopFitsInch', 'metalSkinContact', 'uvFilterCategory', 'ceMarked', 'ratedVoltage', 'plugType',
    'polarised', 'frameMaterial', 'movement', 'caseMaterial', 'strapMaterial', 'waterResistance', 'containsBattery',
    'metal', 'fineness', 'plating', 'nickelBasis', 'leadCadmiumBasis', 'stone', 'chainLengthCm', 'forPiercing', 'hallmarked',
    'ingredientsInci', 'keyIngredients', 'freeFrom', 'countryOfOrigin', 'durabilityType', 'paoMonths', 'bestBefore', 'function', 'howToUse',
    'precautions', 'noPrecautions', 'sealedUnused', 'isTesterOrSample', 'professionalUse',
    'ageRange', 'cordsDrawstrings', 'smallParts', 'costumeIsToy', 'hygieneSealDescription',
  };

  Widget _basicsSection() {
    final c = context.mColors;
    final price = _parseCents(_price.text);
    final singleContent = _parseNum(_content.text);
    final extra = _fields.map((f) => '${f['key']}').where((k) => !_placedKeys.contains(k)).toList();
    return _section(tr(context, 'Basics', 'Perustiedot'), Icons.edit_note_rounded, [
      _anchor(
        'name',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MTextField(
            controller: _name,
            label: tr(context, 'Name', 'Nimi'),
            maxLength: 200,
            errorText: _err('name'),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              _touch('name');
              _update(() {});
            },
          ),
          ..._liveClaims(_name.text),
        ]),
        showIssues: false,
      ),
      !_has('brand')
          ? null
          : _anchor(
              'attributes.brand',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _title(fieldLabel(context, _f('brand'), 'Brand'), 'brand', helper: tr(context, 'As on the label, or "No brand".', 'Kuten merkinnöissä, tai "Merkitön".')),
                MTextField(
                  controller: _tc('brand', '${_attrs['brand'] ?? ''}'),
                  hint: tr(context, 'e.g. Marimekko', 'esim. Marimekko'),
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  onChanged: (s) => _setAttr('brand', s.trim().isEmpty ? null : s),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MChip(
                    label: tr(context, 'No brand', 'Merkitön'),
                    selected: _attrs['brand'] == tr(context, 'No brand', 'Merkitön'),
                    onSelected: (sel) {
                      final v = sel ? tr(context, 'No brand', 'Merkitön') : null;
                      _tc('brand', '').text = v ?? '';
                      _setAttr('brand', v);
                    },
                  ),
                ),
              ]),
            ),
      _anchor(
        'description',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MTextField(
            controller: _description,
            label: tr(context, 'Description', 'Kuvaus'),
            helper: tr(context, 'Fit, feel and details. Materials and label facts have their own fields below.',
                'Istuvuus, tuntuma ja yksityiskohdat. Materiaaleille ja pakkausmerkinnöille on omat kenttänsä alempana.'),
            maxLength: 2000,
            maxLines: 6,
            minLines: 3,
            errorText: _err('description'),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              _touch('description');
              _update(() {});
            },
          ),
          ..._liveClaims(_description.text),
        ]),
        showIssues: false,
      ),
      _anchor(
        'salePriceCents',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MTextField(
            controller: _price,
            label: tr(context, 'Price (€, VAT included)', 'Hinta (€, sis. ALV)'),
            prefixIcon: Icons.euro_rounded,
            errorText: _err('salePriceCents'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) {
              _touch('salePriceCents');
              _update(() {});
            },
          ),
          if (_cosmetic && _options.isEmpty) _unitPricePreview(price, singleContent, _contentUnit),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.xs),
              child: Text(
                tr(context, 'When you lower a price, shoppers see a reduction only if the old price was the lowest of the previous 30 days (EU rule).',
                    'Kun lasket hintaa, alennus näytetään vain, jos vanha hinta oli edeltävän 30 päivän alin (EU-sääntö).'),
                style: MType.caption.copyWith(color: c.onSurfaceVariant),
              ),
            ),
        ]),
        showIssues: false,
      ),
      if (_cosmetic && !_business)
        _notice(Icons.storefront_outlined,
            tr(context, 'Cosmetics, skincare, haircare and fragrance can only be sold by business sellers on Malvoya.',
                'Kosmetiikkaa, ihon- ja hiustenhoitotuotteita sekä tuoksuja voivat myydä Malvoyassa vain yritysmyyjät.'),
            danger: true),
      if (!_cosmetic) _conditionBlock(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _handmade,
        onChanged: (v) => _update(() => _handmade = v),
        title: Text(tr(context, 'Handmade', 'Käsintehty'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(tr(context, 'Made by hand by you or a named maker. You are then the manufacturer.', 'Sinun tai nimetyn tekijän käsin tekemä. Olet silloin valmistaja.'), style: MType.caption),
      ),
      ..._attrList(_basicsKeys),
      ..._attrList(['countryOfManufacture']),
      if (_attrs['countryOfManufacture'] != null) _attr('originDeclared'),
      if (extra.isNotEmpty) ...[
        Text(tr(context, 'More details', 'Lisätiedot'), style: MType.label),
        ..._attrList(extra),
      ],
    ]);
  }

  /// Early warnings for generic green words (the server decides; publishing stops on them).
  List<Widget> _liveClaims(String text) {
    final hits = greenClaimsIn(text);
    return [
      for (final h in hits)
        _issueLine(
          tr(context,
              '"$h" is a generic environmental claim, banned without a recognised ecolabel. State a specific fact (e.g. "60 % recycled polyester, GRS") or add a verified certificate. Publishing stops on it.',
              '"$h" on yleinen ympäristöväittämä, joka on kielletty ilman tunnustettua ympäristömerkkiä. Kerro tarkka tieto (esim. "60 % kierrätettyä polyesteriä, GRS") tai lisää todennettu sertifikaatti. Julkaisu estyy siihen.'),
          danger: false,
        ),
    ];
  }

  Widget _unitPricePreview(int? priceCents, num? amount, String? unit) {
    final c = context.mColors;
    final u = UnitPrice.compute(priceCents, amount, unit);
    final String text;
    if (u != null) {
      text = tr(context, 'Shown as: ${u.format(languageCode: 'en')}', 'Näytetään: ${u.format(languageCode: 'fi')}');
    } else if (amount != null && (unit == 'ml' || unit == 'g') && amount < 50) {
      text = tr(context, 'No unit price under 50 ml or 50 g.', 'Alle 50 ml:n tai 50 g:n pakkauksille ei näytetä yksikköhintaa.');
    } else if (unit == 'pcs') {
      text = tr(context, 'Sold by the piece: no unit price.', 'Myydään kappaleittain: ei yksikköhintaa.');
    } else {
      text = tr(context, 'Enter the content (ml or g) to see the price per litre or kg.', 'Anna sisältö (ml tai g), niin näet litra- tai kilohinnan.');
    }
    return Padding(
      padding: const EdgeInsets.only(top: MSpace.xs),
      child: Row(children: [
        Icon(Icons.straighten_rounded, size: 16, color: c.onSurfaceVariant),
        const SizedBox(width: MSpace.xs),
        Expanded(child: Text(text, style: MType.caption.copyWith(color: u != null ? c.onSurface : c.onSurfaceVariant, fontWeight: u != null ? FontWeight.w700 : null))),
      ]),
    );
  }

  Widget _notice(IconData icon, String text, {bool danger = false, Widget? action}) {
    final c = context.mColors;
    return Container(
      padding: const EdgeInsets.all(MSpace.md),
      decoration: BoxDecoration(color: danger ? c.dangerSoft : c.sunshineSoft, borderRadius: MRadius.brSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: danger ? c.onDangerSoft : c.onSunshineSoft),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Text(text, style: MType.bodyM.copyWith(color: danger ? c.onDangerSoft : c.onSunshineSoft))),
        ]),
        if (action != null) Padding(padding: const EdgeInsets.only(top: MSpace.sm), child: action),
      ]),
    );
  }

  /// New or second-hand; for second-hand the condition, defects (note and photos), label size and
  /// authenticity (spec §2.13).
  Widget _conditionBlock() {
    final c = context.mColors;
    final conditions = {
      'LIKE_NEW': (tr(context, 'Like new', 'Kuin uusi'), tr(context, 'No visible wear.', 'Ei näkyvää kulumaa.')),
      'GOOD': (tr(context, 'Good', 'Hyvä'), tr(context, 'Light signs of use. Describe them.', 'Kevyitä käytön jälkiä. Kuvaile ne.')),
      'FAIR': (tr(context, 'Fair', 'Kohtalainen'), tr(context, 'Visible wear. Describe it and photograph each defect.', 'Näkyvää kulumaa. Kuvaile se ja kuvaa jokainen vika.')),
      if (_condition == 'POOR') 'POOR': (tr(context, 'Worn', 'Kulunut'), tr(context, 'Clear wear. Describe it and photograph each defect.', 'Selvää kulumaa. Kuvaile se ja kuvaa jokainen vika.')),
    };
    final needsNote = _secondHand && ['GOOD', 'FAIR', 'POOR'].contains(_condition);
    final needsPhoto = _secondHand && ['FAIR', 'POOR'].contains(_condition);
    return _anchor(
      'condition',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _secondHand,
          onChanged: (v) {
            _touch('condition');
            _update(() {
              _secondHand = v;
              _condition = v ? (_condition == 'NEW' ? 'GOOD' : _condition) : 'NEW';
            });
          },
          title: Text(tr(context, 'Second-hand', 'Käytetty'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(tr(context, 'Used before, or vintage', 'Aiemmin käytetty tai vintage'), style: MType.caption),
        ),
        if (_secondHand) ...[
          _title(tr(context, 'Condition', 'Kunto'), 'condition'),
          Wrap(spacing: MSpace.sm, children: [
            for (final e in conditions.entries)
              MChip(label: e.value.$1, selected: _condition == e.key, onSelected: (_) => _update(() => _condition = e.key)),
          ]),
          if (conditions[_condition] != null)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.xs, bottom: MSpace.sm),
              child: Text(conditions[_condition]!.$2, style: MType.caption.copyWith(color: c.onSurfaceVariant)),
            ),
          _anchor(
            'attributes.defectsNote',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(tr(context, 'Defects and wear', 'Viat ja kuluma'), style: MType.label)),
                if (needsNote) MBadge(tr(context, 'Required', 'Pakollinen'), tone: MBadgeTone.brand),
              ]),
              MTextField(
                controller: _tc('defectsNote', '${_attrs['defectsNote'] ?? ''}'),
                hint: tr(context, 'e.g. small mark on the left sleeve. Or: no defects', 'esim. pieni tahra vasemmassa hihassa. Tai: ei vikoja'),
                maxLines: 3,
                minLines: 2,
                maxLength: 300,
                onChanged: (s) => _setAttr('defectsNote', s.trim().isEmpty ? null : s),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: MChip(
                  label: tr(context, 'No defects', 'Ei vikoja'),
                  selected: _attrs['defectsNote'] == tr(context, 'No defects', 'Ei vikoja'),
                  onSelected: (sel) {
                    final v = sel ? tr(context, 'No defects', 'Ei vikoja') : null;
                    _tc('defectsNote', '').text = v ?? '';
                    _setAttr('defectsNote', v);
                  },
                ),
              ),
            ]),
          ),
          Row(children: [
            Expanded(
              child: Text(
                needsPhoto
                    ? tr(context, 'Add at least one photo of the defects.', 'Lisää vähintään yksi kuva vioista.')
                    : tr(context, 'Photos of any defects help shoppers decide.', 'Kuvat mahdollisista vioista auttavat asiakasta päättämään.'),
                style: MType.caption.copyWith(color: needsPhoto ? c.onSunshineSoft : c.onSurfaceVariant, fontWeight: needsPhoto ? FontWeight.w700 : null),
              ),
            ),
            MButton(
              label: tr(context, 'Defect photo', 'Kuva viasta'),
              icon: Icons.add_a_photo_outlined,
              size: MButtonSize.sm,
              variant: MButtonVariant.outline,
              onPressed: _photos.length >= _ProductEditorScreenState._maxPhotos ? null : () => _addPhoto(),
            ),
          ]),
          ..._attrList(['originalSizeLabel', 'hasTags', 'authenticity', 'brandTier', 'vintage']),
          if (!_business && _has('fibreCompositionUnknown'))
            Text(tr(context, 'No material label? Say so under Materials.', 'Puuttuuko materiaalilappu? Kerro se Materiaalit-kohdassa.'),
                style: MType.caption.copyWith(color: c.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
