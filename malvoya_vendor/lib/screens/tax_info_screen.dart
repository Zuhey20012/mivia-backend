import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/loading_states.dart';
import 'store_setup.dart';

/// Seller tax information for DAC7 (GET/PUT /stores/my/tax-info). Businesses give their legal name,
/// registered address and optional VAT number (the Y-tunnus comes from the store details); private
/// sellers give their legal name, date of birth, tax ID (henkilötunnus in Finland) and home address.
/// Nothing is pre-filled from elsewhere: the seller types it. The saved tax ID is only shown masked.
class TaxInfoScreen extends StatefulWidget {
  const TaxInfoScreen({super.key});

  @override
  State<TaxInfoScreen> createState() => _TaxInfoScreenState();
}

class _TaxInfoScreenState extends State<TaxInfoScreen> {
  final _form = GlobalKey<FormState>();
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  final _postalCode = TextEditingController();
  final _city = TextEditingController();
  final _vat = TextEditingController();
  final _tin = TextEditingController();

  /// EU/EEA countries a seller on a Finnish marketplace is most likely to live or be registered in.
  static const _countries = {
    'FI': ['Finland', 'Suomi'],
    'SE': ['Sweden', 'Ruotsi'],
    'EE': ['Estonia', 'Viro'],
    'NO': ['Norway', 'Norja'],
    'DK': ['Denmark', 'Tanska'],
    'DE': ['Germany', 'Saksa'],
    'LV': ['Latvia', 'Latvia'],
    'LT': ['Lithuania', 'Liettua'],
    'PL': ['Poland', 'Puola'],
    'NL': ['Netherlands', 'Alankomaat'],
    'FR': ['France', 'Ranska'],
    'ES': ['Spain', 'Espanja'],
    'IT': ['Italy', 'Italia'],
  };

  Map<String, dynamic>? _data;
  String _sellerType = 'BUSINESS';
  String _country = 'FI';
  DateTime? _dateOfBirth;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;
  bool _saved = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  Map<String, dynamic>? get _info => _data?['taxInfo'] is Map ? Map<String, dynamic>.from(_data!['taxInfo']) : null;
  bool get _private => _sellerType == 'PRIVATE';
  String? get _tinMasked => _info?['tinMasked'] as String?;
  bool get _canSaveTin => _data?['canSaveTin'] != false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_legalName, _address, _postalCode, _city, _vat, _tin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _api.get('/stores/my/tax-info');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = res.ok ? null : res.errorMessage;
      if (!res.ok) return;
      _data = res.data;
      _sellerType = '${res.data['sellerType'] ?? _info?['sellerType'] ?? 'BUSINESS'}';
      final info = _info;
      if (info != null) {
        _legalName.text = '${info['legalName'] ?? ''}';
        _address.text = '${info['addressLine'] ?? ''}';
        _postalCode.text = '${info['postalCode'] ?? ''}';
        _city.text = '${info['city'] ?? ''}';
        _vat.text = '${info['vatNumber'] ?? ''}';
        final country = '${info['country'] ?? 'FI'}'.toUpperCase();
        _country = country.length == 2 ? country : 'FI';
        _dateOfBirth = DateTime.tryParse('${info['dateOfBirth'] ?? ''}');
      }
    });
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fiDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.input,
      helpText: tr(context, 'Date of birth', 'Syntymäaika'),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    if (_private && _dateOfBirth == null) {
      setState(() => _error = tr(context, 'Add your date of birth.', 'Lisää syntymäaikasi.'));
      return;
    }
    if (_private && _tin.text.trim().isEmpty && _tinMasked == null) {
      setState(() => _error = tr(context, 'Add your tax identification number.', 'Lisää verotunnisteesi.'));
      return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'legalName': _legalName.text.trim(),
      'addressLine': _address.text.trim(),
      'postalCode': _postalCode.text.trim(),
      'city': _city.text.trim(),
      'country': _country,
      if (_private) 'dateOfBirth': _ymd(_dateOfBirth!),
      // Empty = keep the saved tax ID
      if (_private && _tin.text.trim().isNotEmpty) 'tin': _tin.text.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
      if (!_private) 'vatNumber': _vat.text.trim().isEmpty ? null : _vat.text.trim().toUpperCase(),
    };
    final res = await _api.put('/stores/my/tax-info', body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      setState(() => _error = res.errorMessage);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _data = res.data;
      _tin.clear();
      _saved = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'Tax information saved', 'Verotiedot tallennettu'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Tax information', 'Verotiedot'))),
      body: _loading
          ? const SkeletonList(count: 2, lines: 5)
          : _data == null
              ? ListView(children: [ErrorState(message: _loadError, onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })])
              : Form(key: _form, child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: _fields())),
    );
  }

  List<Widget> _fields() {
    final complete = _data?['taxInfoComplete'] == true;
    final missing = ((_data?['missing'] as List?) ?? const []).map((e) => '$e').toSet();
    final businessId = _info?['businessId'] ?? _data?['businessId'];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.lilac, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        child: Text(
          tr(context,
              'EU law (DAC7) requires marketplaces to report sellers\' sales to the Finnish Tax Administration once a year. Your tax number is stored encrypted.',
              'EU-laki (DAC7) velvoittaa kauppapaikat ilmoittamaan myyjien myynnit Verohallinnolle kerran vuodessa. Verotunnisteesi tallennetaan salattuna.'),
          style: const TextStyle(height: 1.4, color: AppTheme.textPrimary),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Icon(complete ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: complete ? AppTheme.success : AppTheme.warning, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            complete
                ? tr(context, 'Complete — nothing else is needed.', 'Valmis — muuta ei tarvita.')
                : tr(context, 'Some details are still missing.', 'Joitain tietoja puuttuu vielä.'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Text(
        _private ? tr(context, 'Private seller', 'Yksityinen myyjä') : tr(context, 'Business seller', 'Yritysmyyjä'),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      const SizedBox(height: 2),
      Text(
        tr(context, 'From your store details. To change it, write to the Malvoya team in Help.', 'Kaupan tiedoista. Muuttaaksesi sitä kirjoita Malvoyan tiimille kohdassa Apua.'),
        style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _legalName,
        maxLength: 200,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: _private ? tr(context, 'Full legal name', 'Virallinen koko nimi') : tr(context, 'Company\'s registered name', 'Yrityksen virallinen nimi'),
        ),
        validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'Enter the name', 'Anna nimi') : null,
      ),
      if (!_private) ...[
        _readOnlyRow(
          'Y-tunnus',
          businessId == null || '$businessId'.isEmpty ? tr(context, 'Missing', 'Puuttuu') : '$businessId',
          missing: missing.contains('businessId'),
          action: missing.contains('businessId')
              ? TextButton(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreSetupScreen()));
                    if (mounted) _load();
                  },
                  child: Text(tr(context, 'Add in store details', 'Lisää kaupan tietoihin')),
                )
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _vat,
          maxLength: 20,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr(context, 'VAT number (optional)', 'ALV-numero (valinnainen)'),
            helperText: tr(context, 'Only if your business is VAT-registered, e.g. FI12345678', 'Vain jos yrityksesi on arvonlisäverorekisterissä, esim. FI12345678'),
          ),
        ),
      ],
      if (_private) ...[
        const SizedBox(height: 4),
        Material(
          color: AppTheme.sand,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: _pickBirthDate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'Date of birth', 'Syntymäaika'), style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                      Text(_dateOfBirth == null ? tr(context, 'Choose', 'Valitse') : _fiDate(_dateOfBirth!),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Icon(Icons.calendar_month_outlined, color: AppTheme.textSecondary),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_tinMasked != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _readOnlyRow(tr(context, 'Saved tax ID', 'Tallennettu verotunniste'), _tinMasked!),
          ),
        TextFormField(
          controller: _tin,
          maxLength: 30,
          enabled: _canSaveTin,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _country == 'FI'
                ? tr(context, 'Personal identity code (henkilötunnus)', 'Henkilötunnus')
                : tr(context, 'Tax identification number', 'Verotunniste'),
            helperText: _tinMasked != null
                ? tr(context, 'Leave empty to keep the saved one', 'Jätä tyhjäksi, niin tallennettu säilyy')
                : _country == 'FI'
                    ? tr(context, 'Format 010190-123A', 'Muoto 010190-123A')
                    : tr(context, 'From your country of residence', 'Asuinmaasi verotunniste'),
          ),
        ),
        if (!_canSaveTin)
          Text(
            tr(context, 'Tax IDs cannot be saved right now because secure storage is not set up on the server. Please try again later.',
                'Verotunnistetta ei voi juuri nyt tallentaa, koska palvelimen suojattu tallennus ei ole käytössä. Yritä myöhemmin uudelleen.'),
            style: const TextStyle(fontSize: 12.5, color: AppTheme.accent),
          ),
      ],
      const SizedBox(height: 16),
      Text(_private ? tr(context, 'Home address', 'Kotiosoite') : tr(context, 'Registered address', 'Virallinen osoite'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 8),
      TextFormField(
        controller: _address,
        maxLength: 200,
        decoration: InputDecoration(labelText: tr(context, 'Street address', 'Katuosoite')),
        validator: (v) => (v ?? '').trim().length < 3 ? tr(context, 'Enter the street address', 'Anna katuosoite') : null,
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: TextFormField(
            controller: _postalCode,
            maxLength: 12,
            keyboardType: _country == 'FI' ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: tr(context, 'Postal code', 'Postinumero')),
            validator: (v) {
              final t = (v ?? '').trim();
              if (_country == 'FI' && !RegExp(r'^\d{5}$').hasMatch(t)) return tr(context, '5 digits', '5 numeroa');
              return t.length < 2 ? tr(context, 'Required', 'Pakollinen') : null;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _city,
            maxLength: 100,
            decoration: InputDecoration(labelText: tr(context, 'City', 'Kaupunki')),
            validator: (v) => (v ?? '').trim().isEmpty ? tr(context, 'Required', 'Pakollinen') : null,
          ),
        ),
      ]),
      DropdownButtonFormField<String>(
        value: _countries.containsKey(_country) ? _country : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr(context, 'Country', 'Maa')),
        items: [
          for (final c in _countries.entries) DropdownMenuItem(value: c.key, child: Text(isFinnish(context) ? c.value[1] : c.value[0])),
          if (!_countries.containsKey(_country)) DropdownMenuItem(value: _country, child: Text(_country)),
        ],
        onChanged: (v) => setState(() => _country = v ?? _country),
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
      const SizedBox(height: 20),
      SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_saved ? tr(context, 'Saved — save again', 'Tallennettu — tallenna uudelleen') : tr(context, 'Save', 'Tallenna')),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        tr(context,
            'Malvoya uses these details only for the yearly DAC7 report and your monthly statements, and keeps them for 10 years after the reporting year, as the law requires — also if you delete your account.',
            'Malvoya käyttää näitä tietoja vain vuosittaiseen DAC7-ilmoitukseen ja kuukausiraportteihisi ja säilyttää ne lain edellyttämät 10 vuotta ilmoitusvuoden jälkeen — myös jos poistat tilisi.'),
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
      ),
    ];
  }

  Widget _readOnlyRow(String label, String value, {bool missing = false, Widget? action}) => Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: missing ? AppTheme.accent : AppTheme.textPrimary)),
            ]),
          ),
          if (action != null) action,
        ]),
      );
}
