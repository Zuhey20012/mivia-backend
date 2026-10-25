import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import '../../catalog/catalog.dart';
import '../../core/media_upload.dart';

/// The state of a certificate for its owner: waiting, verified (shown to shoppers), expired or rejected.
enum CertState { pending, live, expired, rejected }

CertState certStateOf(Map c) {
  final status = '${c['status'] ?? 'PENDING'}';
  if (status == 'REJECTED') return CertState.rejected;
  final until = DateTime.tryParse('${c['validUntil'] ?? ''}');
  final today = DateTime.now();
  final expired = until != null && DateTime(until.year, until.month, until.day).isBefore(DateTime(today.year, today.month, today.day));
  if (expired) return CertState.expired;
  return status == 'VERIFIED' ? CertState.live : CertState.pending;
}

Widget certBadge(BuildContext context, Map c) => switch (certStateOf(c)) {
      CertState.pending => MBadge(tr(context, 'Waiting for review', 'Odottaa tarkistusta'), tone: MBadgeTone.warning, icon: Icons.hourglass_top_rounded),
      CertState.live => MBadge(tr(context, 'Verified', 'Todennettu'), tone: MBadgeTone.success, icon: Icons.verified_rounded),
      CertState.expired => MBadge(tr(context, 'Expired', 'Vanhentunut'), tone: MBadgeTone.neutral, icon: Icons.event_busy_rounded),
      CertState.rejected => MBadge(tr(context, 'Rejected', 'Hylätty'), tone: MBadgeTone.danger, icon: Icons.block_rounded),
    };

/// Certificates the store holds (EU Ecolabel, Nordic Swan, GOTS, …): submitted with the certificate
/// file, verified by Malvoya, and only then (and while valid) shown on products. They replace the old
/// "eco-friendly" switch, which the law no longer allows.
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
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
    final res = await _api.get('/stores/my/certificates');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _items = ((res.data['certificates'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      } else {
        _error = res.errorMessage;
      }
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CertificateFormScreen()));
    if (saved == true && mounted) _load();
  }

  Future<void> _delete(Map c) async {
    final ok = await showMSheet<bool>(context, builder: (ctx) => MSheet(
          title: tr(ctx, 'Remove this certificate?', 'Poistetaanko sertifikaatti?'),
          actions: [
            MButton(label: tr(ctx, 'Remove', 'Poista'), variant: MButtonVariant.danger, expand: true, onPressed: () => Navigator.pop(ctx, true)),
            MButton(label: tr(ctx, 'Keep', 'Säilytä'), variant: MButtonVariant.text, expand: true, onPressed: () => Navigator.pop(ctx, false)),
          ],
          child: Text(tr(ctx, 'It is also removed from the products that show it.', 'Se poistetaan myös tuotteista, joissa se näkyy.')),
        ));
    if (ok != true || !mounted) return;
    final res = await _api.delete('/stores/my/certificates/${c['id']}');
    if (!mounted) return;
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(tr(context, 'Certificates', 'Sertifikaatit'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: Text(tr(context, 'Add a certificate', 'Lisää sertifikaatti'))),
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
                            'Environmental and other claims need a recognised certificate. Add the certificate with its file: Malvoya checks it, and only verified, valid certificates appear on your products, with the scheme and licence number.',
                            'Ympäristö- ja muut väittämät edellyttävät tunnustettua sertifikaattia. Lisää sertifikaatti tiedostoineen: Malvoya tarkistaa sen, ja tuotteissasi näkyvät vain todennetut, voimassa olevat sertifikaatit järjestelmän nimen ja lisenssinumeron kanssa.'),
                        style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: MSpace.lg),
                      if (_items.isEmpty)
                        MStateMessage(
                          scrollable: false,
                          top: MSpace.xl,
                          icon: Icons.workspace_premium_outlined,
                          message: tr(context, 'No certificates yet.', 'Ei vielä sertifikaatteja.'),
                          actionLabel: tr(context, 'Add a certificate', 'Lisää sertifikaatti'),
                          onAction: _add,
                        )
                      else
                        for (final cert in _items) _tile(cert),
                    ],
                  ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> cert) {
    final c = context.mColors;
    final until = DateTime.tryParse('${cert['validUntil'] ?? ''}');
    final products = asInt(cert['productCount']) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.xs, MSpace.md),
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(localized(context, cert['label']) ?? '${cert['scheme']}', style: MType.bodyL.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: MSpace.xs),
            certBadge(context, cert),
            const SizedBox(height: MSpace.xs),
            Text(
              [
                tr(context, 'Holder: ${cert['holderName']}', 'Haltija: ${cert['holderName']}'),
                if (until != null) tr(context, 'Valid until ${dateText(context, until)}', 'Voimassa ${dateText(context, until)} asti'),
                if (products > 0) tr(context, 'On $products products', '$products tuotteessa'),
              ].join(' · '),
              style: MType.caption.copyWith(color: c.onSurfaceVariant),
            ),
            if (certStateOf(cert) == CertState.rejected && '${cert['rejectionReason'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.xs),
                child: Text(tr(context, 'Reason: ${cert['rejectionReason']}', 'Syy: ${cert['rejectionReason']}'), style: MType.caption.copyWith(color: c.danger)),
              ),
            if (certStateOf(cert) == CertState.expired)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.xs),
                child: Text(tr(context, 'Shoppers no longer see it. Add the renewed certificate.', 'Asiakkaat eivät enää näe sitä. Lisää uusittu sertifikaatti.'),
                    style: MType.caption.copyWith(color: c.onSurfaceVariant)),
              ),
          ]),
        ),
        IconButton(
          tooltip: tr(context, 'Remove', 'Poista'),
          constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
          onPressed: () => _delete(cert),
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
        ),
      ]),
    );
  }
}

/// Submits one certificate: scheme, licence number, holder, what it covers, valid until, and the
/// certificate file (photo or PDF, uploaded as `certificate_evidence`).
class CertificateFormScreen extends StatefulWidget {
  const CertificateFormScreen({super.key});

  @override
  State<CertificateFormScreen> createState() => _CertificateFormScreenState();
}

class _CertificateFormScreenState extends State<CertificateFormScreen> {
  List<Json>? _schemes;
  String? _scheme;
  final _licence = TextEditingController();
  final _holder = TextEditingController();
  final _component = TextEditingController();
  final _verify = TextEditingController();
  String _scope = 'whole_product';
  DateTime? _validUntil;
  String? _evidenceUrl;
  String? _evidenceName;
  double? _uploading;
  String? _uploadError;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    CatalogCache.loadSchemes(_api).then((s) {
      if (mounted) setState(() => _schemes = s ?? const []);
    });
  }

  @override
  void dispose() {
    for (final c in [_licence, _holder, _component, _verify]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    setState(() {
      _uploadError = null;
      _uploading = 0;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic']);
      if (file == null) {
        if (mounted) setState(() => _uploading = null);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final url = await MediaUpload.uploadBytes(
        api: _api,
        kind: 'certificate_evidence',
        bytes: bytes,
        filename: file.name,
        onProgress: (p) {
          if (mounted) setState(() => _uploading = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _evidenceUrl = url;
        _evidenceName = file.name;
        _uploading = null;
        _errors.remove('evidence');
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = null;
          _uploadError = ServerMessages.localize('$e');
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      helpText: tr(context, 'Valid until', 'Voimassa asti'),
    );
    if (d != null && mounted) setState(() => _validUntil = d);
  }

  Future<void> _submit() async {
    _errors.clear();
    if (_scheme == null) _errors['scheme'] = tr(context, 'Pick the scheme', 'Valitse sertifiointijärjestelmä');
    if (_licence.text.trim().length < 2) _errors['licence'] = tr(context, 'Give the licence or certificate number', 'Anna lisenssi- tai sertifikaattinumero');
    if (_holder.text.trim().length < 2) _errors['holder'] = tr(context, 'Whose licence it is, e.g. the brand or the factory', 'Kenen lisenssi se on, esim. merkki tai tehdas');
    if (_scope == 'component' && _component.text.trim().isEmpty) _errors['component'] = tr(context, 'Say which part it covers, e.g. "cotton shell"', 'Kerro, mitä osaa se koskee, esim. "puuvillainen päällyskangas"');
    if (_validUntil == null) _errors['validUntil'] = tr(context, 'Pick the date', 'Valitse päivämäärä');
    if (_evidenceUrl == null) _errors['evidence'] = tr(context, 'Add the certificate file', 'Lisää sertifikaattitiedosto');
    final verify = _verify.text.trim();
    if (verify.isNotEmpty && !verify.startsWith('https://')) _errors['verify'] = tr(context, 'Start with https://', 'Aloita osoite https://');
    setState(() {});
    if (_errors.isNotEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String two(int n) => n.toString().padLeft(2, '0');
    final d = _validUntil!;
    final res = await _api.post('/stores/my/certificates', {
      'scheme': _scheme,
      'licenceNumber': _licence.text.trim(),
      'holderName': _holder.text.trim(),
      'scope': _scope,
      if (_scope == 'component') 'componentDescription': _component.text.trim(),
      'validUntil': '${d.year}-${two(d.month)}-${two(d.day)}',
      'evidenceUrl': _evidenceUrl,
      if (verify.isNotEmpty) 'publicVerifyUrl': verify,
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _saving = false;
        _error = res.errorMessage;
      });
      return;
    }
    Haptics.success();
    MSnack.success(context, tr(context, 'Sent for review. You will see it as verified once Malvoya has checked it.', 'Lähetetty tarkistettavaksi. Näet sen todennettuna, kun Malvoya on tarkistanut sen.'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(tr(context, 'Add a certificate', 'Lisää sertifikaatti'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.x4l),
        children: [
          Text(tr(context, 'Scheme', 'Sertifiointijärjestelmä'), style: MType.label),
          const SizedBox(height: MSpace.xs),
          if (_schemes == null)
            const MSkeletonBox(height: 48)
          else
            DropdownButtonFormField<String>(
              initialValue: _scheme,
              isExpanded: true,
              decoration: InputDecoration(errorText: _errors['scheme']),
              items: [for (final s in _schemes!) DropdownMenuItem(value: '${s['key']}', child: Text(localized(context, s['name']) ?? '${s['key']}'))],
              onChanged: (v) => setState(() => _scheme = v),
            ),
          const SizedBox(height: MSpace.md),
          MTextField(controller: _licence, label: tr(context, 'Licence or certificate number', 'Lisenssi- tai sertifikaattinumero'), errorText: _errors['licence']),
          const SizedBox(height: MSpace.md),
          MTextField(controller: _holder, label: tr(context, 'Licence holder', 'Lisenssin haltija'), errorText: _errors['holder']),
          const SizedBox(height: MSpace.md),
          Text(tr(context, 'What it covers', 'Mitä se koskee'), style: MType.label),
          const SizedBox(height: MSpace.xs),
          Wrap(spacing: MSpace.sm, children: [
            MChip(label: tr(context, 'The whole product', 'Koko tuotetta'), selected: _scope == 'whole_product', onSelected: (_) => setState(() => _scope = 'whole_product')),
            MChip(label: tr(context, 'One part or material', 'Yhtä osaa tai materiaalia'), selected: _scope == 'component', onSelected: (_) => setState(() => _scope = 'component')),
          ]),
          if (_scope == 'component') ...[
            const SizedBox(height: MSpace.sm),
            MTextField(controller: _component, label: tr(context, 'Which part', 'Mikä osa'), hint: tr(context, 'e.g. cotton shell', 'esim. puuvillainen päällyskangas'), errorText: _errors['component']),
          ],
          const SizedBox(height: MSpace.md),
          MListTile(
            icon: Icons.event_outlined,
            title: tr(context, 'Valid until', 'Voimassa asti'),
            subtitle: _validUntil == null ? (_errors['validUntil'] ?? tr(context, 'Pick the date on the certificate', 'Valitse sertifikaatin päivämäärä')) : dateText(context, _validUntil!),
            onTap: _pickDate,
          ),
          const SizedBox(height: MSpace.md),
          MTextField(controller: _verify, label: tr(context, 'Scheme\'s own lookup page (optional)', 'Järjestelmän oma tarkistussivu (valinnainen)'), hint: 'https://', errorText: _errors['verify'], keyboardType: TextInputType.url),
          const SizedBox(height: MSpace.lg),
          Container(
            padding: const EdgeInsets.all(MSpace.lg),
            decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: _errors['evidence'] != null ? c.danger : c.outline)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr(context, 'Certificate file', 'Sertifikaattitiedosto'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: MSpace.xs),
              Text(tr(context, 'A PDF or a photo of the certificate. Only Malvoya sees it.', 'PDF tai kuva sertifikaatista. Vain Malvoya näkee sen.'),
                  style: MType.caption.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: MSpace.sm),
              if (_uploading != null) LinearProgressIndicator(value: _uploading! > 0 ? _uploading : null),
              if (_evidenceName != null)
                Row(children: [
                  Icon(Icons.check_circle_rounded, color: c.success),
                  const SizedBox(width: MSpace.sm),
                  Expanded(child: Text(_evidenceName!, style: MType.bodyM)),
                  if (_evidenceUrl != null)
                    TextButton(onPressed: () => launchUrl(Uri.parse(_evidenceUrl!), mode: LaunchMode.externalApplication), child: Text(tr(context, 'Open', 'Avaa'))),
                ]),
              const SizedBox(height: MSpace.sm),
              MButton(
                label: _evidenceName == null ? tr(context, 'Choose the file', 'Valitse tiedosto') : tr(context, 'Choose another file', 'Valitse toinen tiedosto'),
                icon: Icons.upload_file_rounded,
                variant: MButtonVariant.outline,
                onPressed: _uploading != null ? null : _pickEvidence,
              ),
              if (_uploadError != null || _errors['evidence'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: MSpace.xs),
                  child: Text(_uploadError ?? _errors['evidence']!, style: MType.caption.copyWith(color: c.danger)),
                ),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.md),
              child: Text(_error!, style: MType.bodyM.copyWith(color: c.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: MSpace.xl),
          MButton(label: tr(context, 'Send for review', 'Lähetä tarkistettavaksi'), expand: true, loading: _saving, onPressed: _saving || _uploading != null ? null : _submit),
        ],
      ),
    );
  }
}
