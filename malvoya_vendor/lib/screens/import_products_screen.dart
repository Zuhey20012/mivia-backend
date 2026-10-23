import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';

enum _Source { shopify, csv }

/// Brings a shop's products in at once, from its Shopify shop or from a CSV spreadsheet, so it
/// does not have to add them one by one. The server does the import in the background; this
/// screen follows the job every 2 s. Imported products arrive hidden as drafts, and "Publish"
/// makes the ones with a photo and a price visible.
class ImportProductsScreen extends StatefulWidget {
  /// False while the store is still in review: published products only show once it is approved.
  final bool storeApproved;
  const ImportProductsScreen({super.key, this.storeApproved = true});

  @override
  State<ImportProductsScreen> createState() => _ImportProductsScreenState();
}

class _ImportProductsScreenState extends State<ImportProductsScreen> {
  static const _maxCsvBytes = 1024 * 1024; // the server accepts at most 1 MB of CSV text
  static const _pollEvery = Duration(seconds: 2);

  final _scroll = ScrollController();
  final _shopUrl = TextEditingController();

  _Source _source = _Source.shopify;
  String? _csvName;
  String? _csvText;
  int? _csvRows;
  String? _fileError;
  bool _picking = false;

  bool _rights = false;
  bool _starting = false;
  String? _startError;
  bool _unavailable = false; // the server does not offer importing (404)

  List<Map<String, dynamic>> _jobs = [];
  bool _loadingJobs = true;
  String? _jobsError;

  Map<String, dynamic>? _job; // the import shown at the top
  String? _pollError;
  Timer? _poll;
  bool _polling = false;

  bool _publishing = false;
  final Map<String, int> _published = {}; // job id → products published from this screen

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _loadJobs(resumeRunning: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _shopUrl.dispose();
    super.dispose();
  }

  // ── Jobs ─────────────────────────────────────────────────────────────────

  static bool _isRunning(Map job) => job['status'] == 'QUEUED' || job['status'] == 'RUNNING';
  static String _id(Map job) => '${job['id']}';

  String get _notAvailableText => tr(context,
      'Importing is not available yet: the Malvoya server does not offer it at the moment. Please try again later. Meanwhile you can add products one by one.',
      'Tuonti ei ole vielä käytettävissä: Malvoyan palvelin ei tarjoa sitä tällä hetkellä. Yritä myöhemmin uudelleen. Sillä välin voit lisätä tuotteita yksitellen.');

  Future<void> _loadJobs({bool resumeRunning = false}) async {
    final res = await _api.get('/products/import');
    if (!mounted) return;
    setState(() {
      _loadingJobs = false;
      if (res.status == 404) {
        _unavailable = true;
        _jobsError = null;
        return;
      }
      _unavailable = false;
      _jobsError = res.ok ? null : res.error;
      if (res.ok) {
        _jobs = ((res.data['jobs'] as List?) ?? []).whereType<Map>().map((j) => Map<String, dynamic>.from(j)).toList();
      }
    });
    // Coming back while an import is still running: keep following it
    if (resumeRunning && _job == null) {
      final running = _jobs.where(_isRunning).firstOrNull;
      if (running != null) _watch(running);
    }
  }

  void _watch(Map<String, dynamic> job, {bool scrollUp = false}) {
    _poll?.cancel();
    _poll = null;
    setState(() {
      _job = job;
      _pollError = null;
    });
    if (_isRunning(job)) _poll = Timer.periodic(_pollEvery, (_) => _refreshJob());
    if (scrollUp && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _refreshJob() async {
    final current = _job;
    if (_polling || current == null) return;
    _polling = true;
    final id = _id(current);
    final res = await _api.get('/products/import/$id');
    _polling = false;
    if (!mounted || _job == null || _id(_job!) != id) return;
    if (!res.ok || res.data['job'] is! Map) {
      setState(() => _pollError = res.status == 404
          ? tr(context, 'This import could not be found any more.', 'Tätä tuontia ei enää löydy.')
          : (res.error ?? tr(context, 'Could not check the import.', 'Tuonnin tilaa ei saatu.')));
      if (res.status == 404) _poll?.cancel();
      return; // network hiccups: the next tick tries again
    }
    final job = Map<String, dynamic>.from(res.data['job'] as Map);
    setState(() {
      _job = job;
      _pollError = null;
      final i = _jobs.indexWhere((j) => _id(j) == id);
      if (i >= 0) _jobs[i] = job;
    });
    if (!_isRunning(job)) {
      _poll?.cancel();
      _poll = null;
      HapticFeedback.mediumImpact();
      _loadJobs();
    }
  }

  // ── Starting an import ───────────────────────────────────────────────────

  static bool _looksLikeShopAddress(String value) {
    final host = value.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').split('/').first;
    return host.length >= 4 && host.contains('.') && !host.contains(' ') && !host.startsWith('.') && !host.endsWith('.');
  }

  String _megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    final text = mb.toStringAsFixed(1);
    return isFinnish(context) ? '${text.replaceAll('.', ',')} Mt' : '$text MB';
  }

  Future<void> _pickCsv() async {
    setState(() {
      _fileError = null;
      _picking = true;
    });
    String? error;
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null || !mounted) return;
      final ext = (file.extension ?? '').toLowerCase();
      if (ext != 'csv' && ext != 'txt') {
        error = tr(context, 'Choose a .csv file. In Excel or Google Sheets, save or download the sheet as "CSV UTF-8".',
            'Valitse .csv-tiedosto. Tallenna tai lataa taulukko Excelissä tai Google Sheetsissä muodossa "CSV UTF-8".');
        return;
      }
      final known = file.lengthSync() ?? await file.length();
      if (!mounted) return;
      if (known != null && known > _maxCsvBytes) {
        error = _tooBig(known);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxCsvBytes) {
        error = _tooBig(bytes.length);
        return;
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        error = tr(context, 'This file is not UTF-8 text. Save it as "CSV UTF-8" and choose it again.',
            'Tiedosto ei ole UTF-8-tekstiä. Tallenna se muodossa "CSV UTF-8" ja valitse se uudelleen.');
        return;
      }
      if (text.startsWith('﻿')) text = text.substring(1); // Excel's byte-order mark
      final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) {
        error = tr(context, 'The file has no product rows. The first row names the columns, and each row after it is a product.',
            'Tiedostossa ei ole tuoterivejä. Ensimmäinen rivi nimeää sarakkeet, ja jokainen sen jälkeinen rivi on tuote.');
        return;
      }
      final header = lines.first.toLowerCase().split(RegExp('[,;]')).map((c) => c.trim().replaceAll('"', '')).toList();
      if (!header.contains('name')) {
        error = tr(context, 'The first row must name the columns, and one of them must be "name". See the column guide below.',
            'Ensimmäisen rivin on nimettävä sarakkeet, ja yhden niistä on oltava "name". Katso sarakeohje alta.');
        return;
      }
      setState(() {
        _csvName = file.name;
        _csvText = text;
        _csvRows = lines.length - 1;
        _startError = null;
      });
    } catch (_) {
      if (mounted) error = tr(context, 'Could not read the file. Try again or choose another file.', 'Tiedostoa ei voitu lukea. Yritä uudelleen tai valitse toinen tiedosto.');
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          if (error != null) {
            _fileError = error;
            _csvName = null;
            _csvText = null;
            _csvRows = null;
          }
        });
      }
    }
  }

  String _tooBig(int bytes) => tr(context,
      'This file is ${_megabytes(bytes)}. The limit is 1 MB: split it into smaller files and import them one after another.',
      'Tiedosto on ${_megabytes(bytes)}. Enimmäiskoko on 1 Mt: jaa se pienempiin tiedostoihin ja tuo ne yksi kerrallaan.');

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    String? problem;
    if (_source == _Source.shopify && !_looksLikeShopAddress(_shopUrl.text)) {
      problem = tr(context, 'Enter your shop\'s web address, for example yourshop.fi or yourshop.myshopify.com.',
          'Anna kauppasi verkko-osoite, esimerkiksi kauppasi.fi tai kauppasi.myshopify.com.');
    } else if (_source == _Source.csv && _csvText == null) {
      problem = tr(context, 'Choose a .csv file first.', 'Valitse ensin .csv-tiedosto.');
    } else if (!_rights) {
      problem = tr(context, 'Tick the box to confirm you may use these photos and texts.', 'Vahvista rastilla, että saat käyttää näitä kuvia ja tekstejä.');
    }
    if (problem != null) {
      setState(() => _startError = problem);
      return;
    }
    setState(() {
      _starting = true;
      _startError = null;
    });
    final res = _source == _Source.shopify
        ? await _api.post('/products/import/shopify', {'shopUrl': _shopUrl.text.trim(), 'rightsConfirmed': true})
        : await _api.post('/products/import/csv', {'csv': _csvText, 'rightsConfirmed': true});
    if (!mounted) return;
    setState(() => _starting = false);
    if (!res.ok || res.data['job'] is! Map) {
      setState(() {
        if (res.status == 404) {
          _unavailable = true;
        } else if (res.status == 413) {
          _startError = tr(context, 'The file is too big for the server. Split it into smaller files and import them one after another.',
              'Tiedosto on liian suuri palvelimelle. Jaa se pienempiin tiedostoihin ja tuo ne yksi kerrallaan.');
        } else {
          _startError = res.error ?? tr(context, 'The import could not be started.', 'Tuontia ei voitu aloittaa.');
        }
      });
      return;
    }
    HapticFeedback.mediumImpact();
    final job = Map<String, dynamic>.from(res.data['job'] as Map);
    setState(() {
      _jobs = [job, ..._jobs.where((j) => _id(j) != _id(job))];
      _csvName = null;
      _csvText = null;
      _csvRows = null;
    });
    _watch(job, scrollUp: true);
  }

  Future<void> _publish(Map<String, dynamic> job) async {
    setState(() => _publishing = true);
    final api = _api;
    // Publishing needs the Seller Terms in force (428 → agreement sheet → published right after)
    final res = await withAgreement(context, api, () => api.post('/products/import/${_id(job)}/publish'));
    if (!mounted) return;
    setState(() => _publishing = false);
    if (!res.ok) {
      MSnack.show(context, res.status == 404 ? _notAvailableText : (res.error ?? tr(context, 'Could not publish.', 'Julkaisu epäonnistui.')));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _published[_id(job)] = asInt(res.data['published']) ?? 0);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Import products', 'Tuo tuotteita'))),
      body: RefreshIndicator(
        onRefresh: () => _loadJobs(),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.x4l),
          children: [
            if (_unavailable) _notice(Icons.info_outline_rounded, _notAvailableText, AppTheme.sunshineLight, MPalette.amberInk),
            if (_job != null) ...[
              _jobCard(_job!),
              const SizedBox(height: MSpace.xxl),
              Text(tr(context, 'Start another import', 'Aloita uusi tuonti'), style: AppTheme.display(size: 18)),
              const SizedBox(height: MSpace.sm),
            ],
            Text(
              tr(context,
                  'Bring in all your products at once instead of adding them one by one. Imported products arrive hidden, as drafts: shoppers see nothing until you publish.',
                  'Tuo kaikki tuotteesi kerralla sen sijaan, että lisäisit ne yksitellen. Tuodut tuotteet tulevat piilotettuina luonnoksina: asiakkaat eivät näe mitään ennen kuin julkaiset.'),
              style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 14),
            _sourceTile(_Source.shopify, Icons.storefront_outlined, tr(context, 'From my Shopify shop', 'Shopify-kaupastani'),
                tr(context, 'Enter the shop\'s web address', 'Anna kaupan verkko-osoite')),
            const SizedBox(height: 10),
            _sourceTile(_Source.csv, Icons.table_chart_outlined, tr(context, 'From a spreadsheet (CSV)', 'Taulukosta (CSV)'),
                tr(context, 'Excel, Numbers or Google Sheets saved as CSV', 'Excel, Numbers tai Google Sheets CSV-muodossa')),
            const SizedBox(height: MSpace.lg),
            if (_source == _Source.shopify) _shopifyForm() else _csvForm(),
            const SizedBox(height: MSpace.lg),
            _rightsBox(),
            if (_startError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_startError!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, height: 1.35)),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _starting || _unavailable || (_job != null && _isRunning(_job!)) ? null : _start,
                icon: _starting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                    : const Icon(Icons.download_rounded),
                label: Text(tr(context, 'Start import', 'Aloita tuonti')),
              ),
            ),
            if (_job != null && _isRunning(_job!))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr(context, 'You can start another import when this one has finished.', 'Voit aloittaa uuden tuonnin, kun tämä on valmis.'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 28),
            _pastImports(),
          ],
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, height: 1.4))),
        ]),
      );

  Widget _sourceTile(_Source source, IconData icon, String title, String subtitle) {
    final selected = _source == source;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: _starting
            ? null
            : () => setState(() {
                  _source = source;
                  _startError = null;
                }),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            CircleAvatar(backgroundColor: selected ? AppTheme.surface : AppTheme.primaryLight, child: Icon(icon, color: AppTheme.primary)),
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppTheme.primary),
          ]),
        ),
      ),
    );
  }

  Widget _shopifyForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _shopUrl,
          enabled: !_starting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_startError != null) setState(() => _startError = null);
          },
          decoration: InputDecoration(
            labelText: tr(context, 'Your shop\'s web address', 'Kauppasi verkko-osoite'),
            hintText: 'yourshop.myshopify.com',
            prefixIcon: const Icon(Icons.language_rounded),
          ),
        ),
        const SizedBox(height: MSpace.sm),
        Text(
          tr(context,
              'Malvoya reads the products your shop shows publicly: names, descriptions, prices, sizes, colours and photos. You don\'t give us a password, and nothing changes in your Shopify shop. Check prices and stock before you publish.',
              'Malvoya lukee tuotteet, jotka kauppasi näyttää julkisesti: nimet, kuvaukset, hinnat, koot, värit ja kuvat. Et anna meille salasanaa, eikä Shopify-kaupassasi muutu mitään. Tarkista hinnat ja varastosaldot ennen julkaisua.'),
          style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
        ),
      ]);

  Widget _csvForm() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: _picking || _starting ? null : _pickCsv,
          icon: _picking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_csvName == null ? Icons.upload_file_rounded : Icons.check_circle_rounded),
          label: Text(
            _csvName == null ? tr(context, 'Choose a .csv file', 'Valitse .csv-tiedosto') : tr(context, 'Choose another file', 'Valitse toinen tiedosto'),
          ),
        ),
        if (_csvName != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Text(
              '$_csvName · ${tr(context, 'about $_csvRows rows', 'noin $_csvRows riviä')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        if (_fileError != null)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.sm),
            child: Text(_fileError!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, height: 1.35)),
          ),
        const SizedBox(height: MSpace.md),
        _columnGuide(),
      ]);

  Widget _columnGuide() {
    final columns = [
      ('name', tr(context, 'Product name (required)', 'Tuotteen nimi (pakollinen)')),
      ('description', tr(context, 'Description, materials, fit', 'Kuvaus, materiaalit, istuvuus')),
      ('category', tr(context, 'e.g. Clothing, Shoes, Bags', 'esim. Clothing, Shoes, Bags')),
      ('price', tr(context, 'In euros, VAT included, e.g. 49.90', 'Euroina, sis. ALV, esim. 49.90')),
      ('size', tr(context, 'e.g. M or 38', 'esim. M tai 38')),
      ('colour', tr(context, 'e.g. Black', 'esim. Musta')),
      ('stock', tr(context, 'How many you have', 'Montako kappaletta sinulla on')),
      ('image_urls', tr(context, 'Photo web addresses, several separated by |', 'Kuvien verkko-osoitteet, useampi erotettuna merkillä |')),
      ('condition', 'NEW, LIKE_NEW, GOOD, FAIR, POOR'),
      ('gtin', tr(context, 'Barcode (EAN)', 'Viivakoodi (EAN)')),
      ('external_id', tr(context, 'Your own product code', 'Oma tuotekoodisi')),
    ];
    const mono = TextStyle(fontFamily: 'monospace', fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: AppTheme.primaryDark);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'Column guide', 'Sarakeohje'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
        const SizedBox(height: MSpace.xs),
        Text(
          tr(context,
              'The first row names the columns. Separate them with commas or semicolons and save the file as UTF-8 ("CSV UTF-8" in Excel).',
              'Ensimmäinen rivi nimeää sarakkeet. Erota ne pilkuilla tai puolipisteillä ja tallenna tiedosto UTF-8-muodossa (Excelissä "CSV UTF-8").'),
          style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 10),
        for (final c in columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 100, child: Text(c.$1, style: mono)),
              Expanded(child: Text(c.$2, style: const TextStyle(fontSize: MTextSize.caption, height: 1.3))),
            ]),
          ),
        const SizedBox(height: 6),
        Text(
          tr(context,
              'One row per size or colour: rows with the same external_id (or the same name) become one product with several sizes and colours. Products without a photo or a price are kept as drafts you can finish in the app.',
              'Yksi rivi kokoa tai väriä kohden: rivit, joilla on sama external_id (tai sama nimi), yhdistetään yhdeksi tuotteeksi, jolla on useita kokoja ja värejä. Tuotteet ilman kuvaa tai hintaa jäävät luonnoksiksi, jotka voit viimeistellä sovelluksessa.'),
          style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(MRadius.sm)),
          child: const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              'name,price,size,colour,stock,image_urls,external_id\n'
              'Linen shirt,49.90,M,White,3,https://example.com/shirt.jpg,SH-01\n'
              'Linen shirt,49.90,L,White,2,,SH-01',
              style: TextStyle(fontFamily: 'monospace', fontSize: MTextSize.caption, height: 1.5, color: AppTheme.textPrimary),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _rightsBox() => Container(
        padding: const EdgeInsets.fromLTRB(14, MSpace.md, MSpace.sm, MSpace.xs),
        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'Photos and texts', 'Kuvat ja tekstit'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
          const SizedBox(height: MSpace.xs),
          Text(
            tr(context,
                'Product photos and descriptions are protected by copyright. A brand\'s, a photographer\'s or another shop\'s pictures may only be used with their permission. Malvoya shows what you import to shoppers under your store\'s name, so you are responsible for having the right to use it.',
                'Tuotekuvat ja -kuvaukset ovat tekijänoikeuden suojaamia. Brändin, valokuvaajan tai toisen kaupan kuvia saa käyttää vain heidän luvallaan. Malvoya näyttää tuomasi sisällön asiakkaille kauppasi nimellä, joten vastaat siitä, että sinulla on oikeus käyttää sitä.'),
            style: const TextStyle(fontSize: MTextSize.caption, height: 1.4, color: AppTheme.primaryDark),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _rights,
            onChanged: _starting
                ? null
                : (v) => setState(() {
                      _rights = v ?? false;
                      if (_rights && _startError != null) _startError = null;
                    }),
            title: Text(
              tr(context,
                  'I have the right to use these photos and texts: they are my own, or the brand allows me to use them.',
                  'Minulla on oikeus käyttää näitä kuvia ja tekstejä: ne ovat omiani, tai brändi sallii niiden käytön.'),
              style: const TextStyle(fontSize: MTextSize.label, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  // ── One import ───────────────────────────────────────────────────────────

  String _sourceLabel(Map job) =>
      job['source'] == 'SHOPIFY' ? 'Shopify' : tr(context, 'Spreadsheet (CSV)', 'Taulukko (CSV)');

  (String, Color, Color) _statusStyle(Map job) => switch (job['status']) {
        'QUEUED' => (tr(context, 'Waiting to start', 'Odottaa aloitusta'), AppTheme.sunshineLight, MPalette.amberInk),
        'RUNNING' => (tr(context, 'Importing…', 'Tuodaan…'), AppTheme.sunshine, AppTheme.textPrimary),
        'DONE' => (tr(context, 'Finished', 'Valmis'), AppTheme.primaryLight, AppTheme.primary),
        _ => (tr(context, 'Failed', 'Epäonnistui'), MPalette.redLight, MPalette.red),
      };

  String _when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}.${d.month}.${d.year} ${two(d.hour)}.${two(d.minute)}';
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(MRadius.sm)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: MTextSize.caption)),
      );

  Widget _count(String label, int value, Color bg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: MSpace.sm),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('$value', style: AppTheme.display(size: 20)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _jobCard(Map<String, dynamic> job) {
    final running = _isRunning(job);
    final total = asInt(job['total']) ?? 0;
    final created = asInt(job['created']) ?? 0;
    final updated = asInt(job['updated']) ?? 0;
    final skipped = asInt(job['skipped']) ?? 0;
    final handled = created + updated + skipped;
    final errors = ((job['errors'] as List?) ?? []).whereType<Map>().toList();
    final (statusText, statusBg, statusFg) = _statusStyle(job);
    final toPublish = created + updated;
    final published = _published[_id(job)];
    final publishedBefore = published == null && job['publishedAt'] != null;

    return Container(
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
        border: Border.all(color: running ? AppTheme.primary : AppTheme.divider, width: running ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${tr(context, 'Import from', 'Tuonti:')} ${_sourceLabel(job)}', style: AppTheme.display(size: 18))),
          _chip(statusText, statusBg, statusFg),
        ]),
        if (_when(job['createdAt']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: MSpace.xs),
            child: Text('${tr(context, 'Started', 'Aloitettu')} ${_when(job['createdAt'])}', style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
          ),
        const SizedBox(height: 14),
        if (running) ...[
          LinearProgressIndicator(value: total > 0 ? (handled / total).clamp(0.0, 1.0) : null, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text(
            total > 0
                ? tr(context, '$handled of $total handled', '$handled / $total käsitelty')
                : tr(context, 'Reading your products…', 'Luetaan tuotteitasi…'),
            style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: MSpace.md),
        ],
        Row(children: [
          _count(tr(context, 'New', 'Uusia'), created, AppTheme.primaryLight),
          const SizedBox(width: MSpace.sm),
          _count(tr(context, 'Updated', 'Päivitetty'), updated, AppTheme.sand),
          const SizedBox(width: MSpace.sm),
          _count(tr(context, 'Skipped', 'Ohitettu'), skipped, skipped > 0 ? AppTheme.peach : AppTheme.sand),
        ]),
        if (_pollError != null && running)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('$_pollError ${tr(context, 'Trying again…', 'Yritetään uudelleen…')}', style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.accent)),
          ),
        if (errors.isNotEmpty) _errorList(errors),
        if (job['status'] == 'FAILED')
          Padding(
            padding: const EdgeInsets.only(top: MSpace.md),
            child: Text(
              tr(context,
                  'The import stopped before it finished. Fix the problems above and try again. Products already imported stay as hidden drafts.',
                  'Tuonti keskeytyi ennen kuin se valmistui. Korjaa yllä mainitut ongelmat ja yritä uudelleen. Jo tuodut tuotteet jäävät piilotetuiksi luonnoksiksi.'),
              style: const TextStyle(fontSize: MTextSize.label, height: 1.4, color: MPalette.red),
            ),
          ),
        if (job['status'] == 'DONE') ...[
          const SizedBox(height: 14),
          Text(
            tr(context, 'Done: $created new, $updated updated, $skipped skipped.', 'Valmis: $created uutta, $updated päivitetty, $skipped ohitettu.'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (published != null)
            _notice(
              Icons.check_circle_rounded,
              [
                published == 1
                    ? tr(context, '1 product is now published.', '1 tuote on nyt julkaistu.')
                    : tr(context, '$published products are now published.', '$published tuotetta on nyt julkaistu.'),
                if (!widget.storeApproved)
                  tr(context, 'Shoppers see them once your store has been approved.', 'Asiakkaat näkevät ne, kun kauppasi on hyväksytty.'),
                if (published < toPublish)
                  tr(context, 'The rest stay hidden drafts until they have a photo and a price: find them in Products.',
                      'Loput jäävät piilotetuiksi luonnoksiksi, kunnes niillä on kuva ja hinta: löydät ne Tuotteet-välilehdeltä.'),
              ].join(' '),
              AppTheme.primaryLight,
              AppTheme.primaryDark,
            )
          else if (publishedBefore)
            _notice(
              Icons.check_circle_rounded,
              tr(context,
                  'Published ${_when(job['publishedAt'])}. Products that had no photo or price stay hidden drafts: finish them in Products and switch them on.',
                  'Julkaistu ${_when(job['publishedAt'])}. Tuotteet, joilta puuttui kuva tai hinta, jäävät piilotetuiksi luonnoksiksi: viimeistele ne Tuotteet-välilehdellä ja kytke ne näkyviin.'),
              AppTheme.primaryLight,
              AppTheme.primaryDark,
            )
          else if (toPublish > 0) ...[
            Text(
              tr(context,
                  'Publishing shows the products that have at least one photo and a price. Anything you don\'t publish stays a hidden draft that you can edit first in Products.',
                  'Julkaisu näyttää tuotteet, joilla on vähintään yksi kuva ja hinta. Julkaisemattomat jäävät piilotetuiksi luonnoksiksi, joita voit muokata ensin Tuotteet-välilehdellä.'),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: MSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _publishing ? null : () => _publish(job),
                icon: _publishing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                    : const Icon(Icons.visibility_rounded),
                label: Text(toPublish == 1 ? tr(context, 'Publish 1 product', 'Julkaise 1 tuote') : tr(context, 'Publish $toPublish products', 'Julkaise $toPublish tuotetta')),
              ),
            ),
            const SizedBox(height: MSpace.xs),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, 'Not yet — review them in Products first', 'Ei vielä — tarkistan ne ensin Tuotteissa')),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  /// Errors (the item was skipped) first, then warnings (imported, but check it).
  Widget _errorList(List<Map> errors) {
    const shown = 30;
    final sorted = [...errors.where((e) => e['level'] != 'warning'), ...errors.where((e) => e['level'] == 'warning')];
    final warnings = errors.length - errors.where((e) => e['level'] != 'warning').length;
    final problems = errors.length - warnings;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          [
            if (problems > 0) '${tr(context, 'Problems', 'Ongelmat')} ($problems)',
            if (warnings > 0) '${tr(context, 'To check', 'Tarkistettavaa')} ($warnings)',
          ].join(' · '),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        for (final e in sorted.take(shown))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.sm),
            decoration: BoxDecoration(color: e['level'] == 'warning' ? AppTheme.sunshineLight : AppTheme.peach, borderRadius: BorderRadius.circular(MRadius.sm)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(e['level'] == 'warning' ? Icons.info_outline_rounded : Icons.error_outline_rounded,
                  size: 18, color: e['level'] == 'warning' ? MPalette.amberInk : MPalette.red),
              const SizedBox(width: MSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ('${e['item'] ?? ''}'.isNotEmpty) Text('${e['item']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                  Text('${e['message'] ?? ''}', style: const TextStyle(fontSize: MTextSize.caption, height: 1.35)),
                ]),
              ),
            ]),
          ),
        if (errors.length > shown)
          Text(tr(context, '…and ${errors.length - shown} more', '…ja ${errors.length - shown} muuta'), style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
      ]),
    );
  }

  // ── Past imports ─────────────────────────────────────────────────────────

  Widget _pastImports() {
    final past = _jobs.where((j) => _job == null || _id(j) != _id(_job!)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'Past imports', 'Aiemmat tuonnit'), style: AppTheme.display(size: 18)),
      const SizedBox(height: MSpace.sm),
      if (_loadingJobs)
        const Padding(padding: EdgeInsets.all(MSpace.lg), child: Center(child: CircularProgressIndicator()))
      else if (_jobsError != null)
        Row(children: [
          Expanded(child: Text(_jobsError!, style: const TextStyle(color: AppTheme.accent))),
          TextButton(onPressed: () => _loadJobs(), child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
        ])
      else if (past.isEmpty)
        Text(tr(context, 'No earlier imports.', 'Ei aiempia tuonteja.'), style: const TextStyle(color: AppTheme.textSecondary))
      else
        Container(
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            for (var i = 0; i < past.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _pastTile(past[i]),
            ],
          ]),
        ),
    ]);
  }

  Widget _pastTile(Map<String, dynamic> job) {
    final (statusText, statusBg, statusFg) = _statusStyle(job);
    final created = asInt(job['created']) ?? 0;
    final updated = asInt(job['updated']) ?? 0;
    final skipped = asInt(job['skipped']) ?? 0;
    final errors = ((job['errors'] as List?) ?? []).whereType<Map>().where((e) => e['level'] != 'warning').length;
    return ListTile(
      onTap: () => _watch(job, scrollUp: true),
      leading: CircleAvatar(
        backgroundColor: AppTheme.primaryLight,
        child: Icon(job['source'] == 'SHOPIFY' ? Icons.storefront_outlined : Icons.table_chart_outlined, color: AppTheme.primary),
      ),
      title: Text(
        [_sourceLabel(job), if (job['sourceRef'] != null) '${job['sourceRef']}', _when(job['createdAt'])].join(' · '),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: MSpace.xs),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _chip(statusText, statusBg, statusFg),
          Text(
            [
              tr(context, '$created new', '$created uutta'),
              tr(context, '$updated updated', '$updated päivitetty'),
              tr(context, '$skipped skipped', '$skipped ohitettu'),
              if (errors > 0) tr(context, '$errors problems', '$errors ongelmaa'),
              if (job['publishedAt'] != null) tr(context, 'published', 'julkaistu'),
            ].join(' · '),
            style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
          ),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
