part of '../product_editor.dart';

/// Safety: the pledge reminder, manufacturer and EU responsible person (picked from the store's
/// records), model, EAN, batch, warnings in Finnish and Swedish, the hygiene seal, children's safety
/// and certificates.
extension _EditorSafety on _ProductEditorScreenState {
  bool get _needsRp => _cosmetic || (_manufacturer != null && !inEu(operatorCountry(_manufacturer))) || _rpId != null;

  Future<void> _chooseOperator({required bool responsible}) async {
    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => OperatorsScreen(
          pick: true,
          selectedId: responsible ? _rpId : _manufacturerId,
          title: responsible ? tr(context, 'Choose the responsible person', 'Valitse vastuuhenkilö') : tr(context, 'Choose the manufacturer', 'Valitse valmistaja'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _update(() {
      if (responsible) {
        _rpId = asInt(picked['id']);
        _rp = Json.from(picked);
      } else {
        _manufacturerId = asInt(picked['id']);
        _manufacturer = Json.from(picked);
      }
    });
    _touch(responsible ? 'responsiblePersonId' : 'manufacturerId');
    if (!responsible) _touch('responsiblePersonId');
  }

  Widget _operatorTile({required bool responsible}) {
    final c = context.mColors;
    final o = responsible ? _rp : _manufacturer;
    final anchor = responsible ? 'responsiblePersonId' : 'manufacturerId';
    final label = responsible
        ? (_cosmetic ? tr(context, 'Responsible person (cosmetics)', 'Vastuuhenkilö (kosmetiikka)') : tr(context, 'EU responsible person', 'Vastuuhenkilö EU:ssa'))
        : tr(context, 'Manufacturer', 'Valmistaja');
    final hasIssue = _issues.containsKey(anchor);
    return _anchor(
      anchor,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(label, anchor,
            helper: responsible
                ? (_cosmetic
                    ? tr(context, 'The company in the EU named on the pack.', 'Pakkauksessa mainittu yritys EU:ssa.')
                    : tr(context, 'Needed because the manufacturer is outside the EU.', 'Tarvitaan, koska valmistaja on EU:n ulkopuolella.'))
                : (_business ? null : tr(context, 'Optional for private sellers.', 'Valinnainen yksityismyyjille.'))),
        Container(
          decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: MRadius.brSm, border: Border.all(color: hasIssue ? c.danger : c.outline)),
          child: MListTile(
            icon: Icons.factory_outlined,
            title: o == null ? tr(context, 'Choose or add', 'Valitse tai lisää') : '${o['name']}',
            subtitle: o == null ? null : operatorAddress(o),
            trailing: o == null
                ? null
                : IconButton(
                    tooltip: tr(context, 'Clear', 'Tyhjennä'),
                    constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
                    onPressed: () => _update(() {
                      if (responsible) {
                        _rpId = null;
                        _rp = null;
                      } else {
                        _manufacturerId = null;
                        _manufacturer = null;
                      }
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
            onTap: () => _chooseOperator(responsible: responsible),
          ),
        ),
        if (!responsible && o != null && !inEu(operatorCountry(o)) && !_cosmetic)
          _issueLine(tr(context, 'This manufacturer is outside the EU: add the EU responsible person below.', 'Valmistaja on EU:n ulkopuolella: lisää alle vastuuhenkilö EU:ssa.'), danger: false),
      ]),
      showIssues: true,
    );
  }

  Widget _warningsBox() {
    final c = context.mColors;
    return _anchor(
      'warnings',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tr(context, 'Warnings and safety information', 'Varoitukset ja turvallisuustiedot'), 'warnings',
            helper: _cosmetic
                ? tr(context, 'The precautions under Ingredients and label count as the warnings for cosmetics.', 'Kosmetiikassa varoituksina toimivat Ainesosat ja merkinnät -kohdan varotoimet.')
                : tr(context, 'As on the label or in the instructions. Finnish and Swedish are needed.', 'Kuten merkinnöissä tai ohjeissa. Suomi ja ruotsi tarvitaan.')),
        if (!_cosmetic) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _noWarnings,
            onChanged: (v) {
              _touch('warnings');
              _update(() => _noWarnings = v);
            },
            title: Text(tr(context, 'The label has no warnings', 'Merkinnöissä ei ole varoituksia'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (!_noWarnings) ...[
            for (final (ctl, name) in [
              (_warnFi, tr(context, 'Finnish', 'Suomeksi')),
              (_warnSv, tr(context, 'Swedish', 'Ruotsiksi')),
              (_warnEn, tr(context, 'English (optional)', 'Englanniksi (valinnainen)')),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: MSpace.sm),
                child: MTextField(controller: ctl, label: name, maxLines: 4, minLines: 2, maxLength: 2000, onChanged: (_) => _touch('warnings')),
              ),
          ],
        ] else
          Text(tr(context, 'Nothing more to add here.', 'Tähän ei tarvitse lisätä muuta.'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
      ]),
    );
  }

  Widget _certificatesBox() {
    final c = context.mColors;
    final certs = _certs;
    return _anchor(
      'certificateIds',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tr(context, 'Certificates', 'Sertifikaatit'), 'certificateIds',
            helper: tr(context, 'Only verified, valid certificates show on the product, with the scheme and licence number. Instead of words like "eco", add a certificate.',
                'Tuotteessa näkyvät vain todennetut, voimassa olevat sertifikaatit järjestelmän ja lisenssinumeron kanssa. Lisää sertifikaatti sanojen kuten "eko" sijaan.')),
        if (certs == null)
          const MSkeletonBox(height: 48)
        else ...[
          for (final cert in certs)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _certIds.contains(asInt(cert['id'])),
              onChanged: certStateOf(cert) == CertState.rejected
                  ? null
                  : (v) {
                      _touch('certificateIds');
                      _update(() => v == true ? _certIds.add(asInt(cert['id'])!) : _certIds.remove(asInt(cert['id'])));
                    },
              title: Text(localized(context, cert['label']) ?? '${cert['scheme']}', style: MType.bodyM),
              subtitle: Align(alignment: Alignment.centerLeft, child: certBadge(context, cert)),
            ),
          if (certs.isEmpty) Text(tr(context, 'No certificates yet.', 'Ei vielä sertifikaatteja.'), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
          Align(
            alignment: Alignment.centerLeft,
            child: MButton(
              label: tr(context, 'Manage certificates', 'Hallitse sertifikaatteja'),
              variant: MButtonVariant.text,
              size: MButtonSize.sm,
              icon: Icons.workspace_premium_outlined,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CertificatesScreen()));
                if (mounted) _loadCertificates();
              },
            ),
          ),
        ],
      ]),
    );
  }

  Widget _safetySection() {
    final c = context.mColors;
    final gtin = _gtin.text.trim();
    return _section(tr(context, 'Safety', 'Turvallisuus'), Icons.health_and_safety_outlined, [
      if (_pledged != true)
        _anchor(
          'safetyPledge',
          _notice(
            Icons.verified_user_outlined,
            tr(context, 'Before your first publish, confirm once that you only offer products that comply with EU law.',
                'Vahvista ennen ensimmäistä julkaisua kerran, että tarjoat vain EU-lainsäädännön mukaisia tuotteita.'),
            action: MButton(
              label: tr(context, 'Read and confirm', 'Lue ja vahvista'),
              size: MButtonSize.sm,
              variant: MButtonVariant.outline,
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SafetyPledgeScreen()));
                if (ok == true && mounted) {
                  _update(() {
                    _pledged = true;
                    _issues.remove('safetyPledge');
                  });
                }
              },
            ),
          ),
        ),
      if (!_business)
        Text(
          tr(context, 'As a private seller you give the manufacturer and warnings if you have them. Business sellers must give them by law.',
              'Yksityismyyjänä annat valmistajan ja varoitukset, jos sinulla on ne. Yritysmyyjien on annettava ne lain mukaan.'),
          style: MType.caption.copyWith(color: c.onSurfaceVariant),
        ),
      _operatorTile(responsible: false),
      if (_needsRp) _operatorTile(responsible: true),
      _anchor(
        'productModel',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title(tr(context, 'Model or type', 'Malli tai tyyppi'), 'productModel'),
          MTextField(
            controller: _model,
            hint: tr(context, 'As on the label, e.g. "Hilla parka 2" or art. 1234', 'Kuten merkinnöissä, esim. "Hilla parka 2" tai tuotenro 1234'),
            errorText: _err('productModel'),
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            onChanged: (_) => _touch('productModel'),
          ),
        ]),
        showIssues: false,
      ),
      _anchor(
        'gtin',
        MTextField(
          controller: _gtin,
          label: tr(context, 'EAN code (recommended)', 'EAN-koodi (suositeltava)'),
          helper: tr(context, 'The barcode number. It helps with recalls and safety checks.', 'Viivakoodin numero. Se auttaa takaisinvedoissa ja turvallisuustarkistuksissa.'),
          errorText: _err('gtin') ?? (gtin.isNotEmpty && gtin.length >= 8 && !validGtin(gtin) ? tr(context, 'Check the digits: this is not a valid EAN', 'Tarkista numerot: tämä ei ole kelvollinen EAN') : null),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
          onChanged: (_) {
            _touch('gtin');
            _update(() {});
          },
        ),
        showIssues: false,
      ),
      MTextField(controller: _batch, label: tr(context, 'Batch or serial number (optional)', 'Erä- tai sarjanumero (valinnainen)'), inputFormatters: [LengthLimitingTextInputFormatter(80)]),
      _warningsBox(),
      if (_sealAllowed)
        _anchor(
          'hygieneSealed',
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sealed,
            onChanged: (v) => _update(() => _sealed = v),
            title: Text(tr(context, 'Hygiene seal', 'Hygieniasinetti'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(
              tr(context, 'Sold sealed: it can\'t be returned once the seal is opened. Unopened it can be returned within 14 days.',
                  'Myydään sinetöitynä: sitä ei voi palauttaa, jos sinetti avataan. Avaamattoman voi palauttaa 14 päivän kuluessa.'),
              style: MType.caption,
            ),
          ),
        ),
      if (_sealAllowed && _sealed) _attr('hygieneSealDescription'),
      if (_kids) ..._attrList(['ageRange', 'cordsDrawstrings', 'smallParts', 'costumeIsToy']),
      _certificatesBox(),
    ]);
  }
}
