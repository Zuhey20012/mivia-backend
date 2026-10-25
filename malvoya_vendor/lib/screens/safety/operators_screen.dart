import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import '../../catalog/catalog.dart';

/// One address line of a manufacturer / responsible person record.
String operatorAddress(Map o) {
  final a = o['address'] is Map ? o['address'] as Map : const {};
  return [a['line'], [a['postalCode'], a['city']].where((x) => x != null && '$x'.isNotEmpty).join(' '), a['countryCode']]
      .where((x) => x != null && '$x'.trim().isNotEmpty)
      .join(', ');
}

String? operatorCountry(Map? o) => o == null ? null : ((o['address'] as Map?)?['countryCode'] as String?);

/// Manufacturer and EU responsible person records (GPSR Art. 19(a)–(b), cosmetics Art. 4), CRUD
/// /stores/my/operators. Add a company once and pick it in every product. With [pick] the screen
/// returns the record tapped.
class OperatorsScreen extends StatefulWidget {
  final bool pick;
  final String? title;
  final int? selectedId;
  const OperatorsScreen({super.key, this.pick = false, this.title, this.selectedId});

  @override
  State<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends State<OperatorsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.get('/stores/my/operators');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _items = ((res.data['operators'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      } else {
        _error = res.errorMessage;
      }
    });
  }

  Future<void> _edit([Map<String, dynamic>? o]) async {
    final saved = await showOperatorForm(context, api: _api, existing: o);
    if (saved == null || !mounted) return;
    await _load();
    if (widget.pick && o == null && mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete(Map<String, dynamic> o) async {
    final ok = await showMSheet<bool>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Remove ${o['name']}?', 'Poistetaanko ${o['name']}?'),
          actions: [
            MButton(label: tr(ctx, 'Remove', 'Poista'), variant: MButtonVariant.danger, expand: true, onPressed: () => Navigator.pop(ctx, true)),
            MButton(label: tr(ctx, 'Keep', 'Säilytä'), variant: MButtonVariant.text, expand: true, onPressed: () => Navigator.pop(ctx, false)),
          ],
          child: Text(tr(ctx, 'Products that use this record must be changed first.', 'Tätä tietoa käyttävät tuotteet on ensin vaihdettava toiseen.')),
        ));
    if (ok != true || !mounted) return;
    final res = await _api.delete('/stores/my/operators/${o['id']}');
    if (!mounted) return;
    if (!res.ok) {
      MSnack.error(context, res.status == 409
          ? tr(context, 'Products still use this record. Pick another manufacturer for them first.', 'Tuotteet käyttävät vielä tätä tietoa. Valitse niille ensin toinen valmistaja.')
          : res.errorMessage);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(widget.title ?? tr(context, 'Manufacturers and responsible persons', 'Valmistajat ja vastuuhenkilöt'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'Add a company', 'Lisää yritys')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const MSkeletonList(count: 3)
            : _error != null
                ? MStateMessage.error(message: _error, onRetry: _load)
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 100),
                    children: [
                      Text(
                        tr(context,
                            'EU product safety law requires the manufacturer\'s name, postal address and an email or web address on every listing by a business seller. A manufacturer outside the EU also needs an EU responsible person; cosmetics always do. Add each company once and pick it in your products.',
                            'EU:n tuoteturvallisuusasetus edellyttää, että yritysmyyjän jokaisessa tuotteessa on valmistajan nimi, postiosoite ja sähköposti- tai verkko-osoite. EU:n ulkopuolisella valmistajalla on oltava myös vastuuhenkilö EU:ssa, ja kosmetiikalla aina. Lisää jokainen yritys kerran ja valitse se tuotteisiisi.'),
                        style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: MSpace.lg),
                      if (_items.isEmpty)
                        MStateMessage(
                          scrollable: false,
                          top: MSpace.xl,
                          icon: Icons.factory_outlined,
                          message: tr(context, 'No companies yet. If you make the products yourself, add your own business as the manufacturer.',
                              'Ei vielä yrityksiä. Jos valmistat tuotteet itse, lisää oma yrityksesi valmistajaksi.'),
                          actionLabel: tr(context, 'Add a company', 'Lisää yritys'),
                          onAction: () => _edit(),
                        )
                      else
                        for (final o in _items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: MSpace.sm),
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: MRadius.brMd,
                                border: Border.all(color: widget.selectedId == asInt(o['id']) ? c.primary : c.outline, width: widget.selectedId == asInt(o['id']) ? 2 : 1),
                              ),
                              child: MListTile(
                                icon: Icons.factory_outlined,
                                title: '${o['name']}',
                                subtitle: [operatorAddress(o), if (o['email'] != null) '${o['email']}' else if (o['url'] != null) '${o['url']}'].join('\n'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (o['inEu'] == false) MBadge(tr(context, 'Outside EU', 'EU:n ulkopuolella'), tone: MBadgeTone.warning),
                                  PopupMenuButton<String>(
                                    tooltip: tr(context, 'More', 'Lisää'),
                                    onSelected: (v) => v == 'edit' ? _edit(o) : _delete(o),
                                    itemBuilder: (_) => [
                                      PopupMenuItem(value: 'edit', child: Text(tr(context, 'Edit', 'Muokkaa'))),
                                      PopupMenuItem(value: 'delete', child: Text(tr(context, 'Remove', 'Poista'))),
                                    ],
                                  ),
                                ]),
                                onTap: () => widget.pick ? Navigator.pop(context, o) : _edit(o),
                              ),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }
}

/// Add or edit one record. Returns the saved record.
Future<Map<String, dynamic>?> showOperatorForm(BuildContext context, {required ApiClient api, Map<String, dynamic>? existing}) =>
    showMSheet<Map<String, dynamic>>(context, builder: (_) => _OperatorForm(api: api, existing: existing));

class _OperatorForm extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic>? existing;
  const _OperatorForm({required this.api, this.existing});

  @override
  State<_OperatorForm> createState() => _OperatorFormState();
}

class _OperatorFormState extends State<_OperatorForm> {
  late final Map<String, dynamic> _a = widget.existing?['address'] is Map ? Map<String, dynamic>.from(widget.existing!['address']) : {};
  late final _name = TextEditingController(text: '${widget.existing?['name'] ?? ''}');
  late final _line = TextEditingController(text: '${_a['line'] ?? ''}');
  late final _postal = TextEditingController(text: '${_a['postalCode'] ?? ''}');
  late final _city = TextEditingController(text: '${_a['city'] ?? ''}');
  late final _country = TextEditingController(text: '${_a['countryCode'] ?? 'FI'}');
  late final _email = TextEditingController(text: '${widget.existing?['email'] ?? ''}');
  late final _url = TextEditingController(text: '${widget.existing?['url'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.existing?['phone'] ?? ''}');
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _line, _postal, _city, _country, _email, _url, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _check() {
    _errors.clear();
    if (_name.text.trim().length < 2) _errors['name'] = tr(context, 'Give the company name', 'Anna yrityksen nimi');
    if (_line.text.trim().length < 2) _errors['line'] = tr(context, 'Give the street address', 'Anna katuosoite');
    if (_postal.text.trim().length < 2) _errors['postal'] = tr(context, 'Give the postcode', 'Anna postinumero');
    if (_city.text.trim().isEmpty) _errors['city'] = tr(context, 'Give the city', 'Anna kaupunki');
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(_country.text.trim())) _errors['country'] = tr(context, 'Two letters, e.g. FI, SE, CN', 'Kaksi kirjainta, esim. FI, SE, CN');
    final email = _email.text.trim();
    final url = _url.text.trim();
    if (email.isEmpty && url.isEmpty) {
      _errors['email'] = tr(context, 'Give an email or a web address (the law asks for an electronic contact)', 'Anna sähköposti tai verkko-osoite (laki edellyttää sähköisen yhteystiedon)');
    } else if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _errors['email'] = tr(context, 'Check the email address', 'Tarkista sähköpostiosoite');
    }
    if (url.isNotEmpty && !url.startsWith('https://')) _errors['url'] = tr(context, 'Start with https://', 'Aloita osoite https://');
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_check()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final body = {
      'name': _name.text.trim(),
      'addressLine': _line.text.trim(),
      'postalCode': _postal.text.trim(),
      'city': _city.text.trim(),
      'countryCode': _country.text.trim().toUpperCase(),
      'email': opt(_email),
      'url': opt(_url),
      'phone': opt(_phone),
    };
    final id = widget.existing?['id'];
    final res = id == null ? await widget.api.post('/stores/my/operators', body) : await widget.api.patch('/stores/my/operators/$id', body);
    if (!mounted) return;
    if (!res.ok || res.data['operator'] is! Map) {
      setState(() {
        _saving = false;
        _error = res.errorMessage;
      });
      return;
    }
    Haptics.success();
    Navigator.pop(context, Map<String, dynamic>.from(res.data['operator']));
  }

  @override
  Widget build(BuildContext context) {
    final outside = _country.text.trim().length == 2 && !inEu(_country.text.trim());
    return MSheet(
      title: widget.existing == null ? tr(context, 'Add a company', 'Lisää yritys') : tr(context, 'Edit company', 'Muokkaa yritystä'),
      subtitle: tr(context, 'As printed on the product or its label', 'Kuten tuotteessa tai sen merkinnöissä'),
      actions: [MButton(label: tr(context, 'Save', 'Tallenna'), expand: true, loading: _saving, onPressed: _saving ? null : _save)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MTextField(controller: _name, label: tr(context, 'Company name', 'Yrityksen nimi'), errorText: _errors['name'], textCapitalization: TextCapitalization.words),
        const SizedBox(height: MSpace.md),
        MTextField(controller: _line, label: tr(context, 'Street address', 'Katuosoite'), errorText: _errors['line']),
        const SizedBox(height: MSpace.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: MTextField(controller: _postal, label: tr(context, 'Postcode', 'Postinumero'), errorText: _errors['postal'])),
          const SizedBox(width: MSpace.sm),
          Expanded(flex: 2, child: MTextField(controller: _city, label: tr(context, 'City', 'Kaupunki'), errorText: _errors['city'])),
        ]),
        const SizedBox(height: MSpace.md),
        MTextField(
          controller: _country,
          label: tr(context, 'Country code', 'Maakoodi'),
          hint: 'FI',
          errorText: _errors['country'],
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')), LengthLimitingTextInputFormatter(2)],
          onChanged: (_) => setState(() {}),
        ),
        if (outside)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.xs),
            child: Text(
              tr(context, 'Outside the EU: products from this manufacturer also need an EU responsible person.',
                  'EU:n ulkopuolella: tämän valmistajan tuotteille tarvitaan myös vastuuhenkilö EU:ssa.'),
              style: MType.caption.copyWith(color: context.mColors.onWarningSoft),
            ),
          ),
        const SizedBox(height: MSpace.md),
        MTextField(controller: _email, label: tr(context, 'Email', 'Sähköposti'), errorText: _errors['email'], keyboardType: TextInputType.emailAddress),
        const SizedBox(height: MSpace.md),
        MTextField(controller: _url, label: tr(context, 'Web address (optional)', 'Verkko-osoite (valinnainen)'), hint: 'https://', errorText: _errors['url'], keyboardType: TextInputType.url),
        const SizedBox(height: MSpace.md),
        MTextField(controller: _phone, label: tr(context, 'Phone (optional)', 'Puhelin (valinnainen)'), keyboardType: TextInputType.phone),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.md),
            child: Text(_error!, style: MType.bodyM.copyWith(color: context.mColors.danger, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
