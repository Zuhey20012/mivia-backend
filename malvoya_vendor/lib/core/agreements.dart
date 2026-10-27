import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// Versioned agreements (API 2.11). The store's Seller Terms are "blocking": until the version in force
/// is accepted, the server answers 428 AGREEMENT_REQUIRED when the store accepts an order or publishes a
/// product. [withAgreement] catches that answer, shows [showAgreementSheet] and repeats the action once
/// the terms are accepted, so the store never has to start over (the incoming-order countdown keeps
/// running behind the sheet). An announced update never blocks before it takes effect.

/// What the sheet reports after a successful acceptance.
class AgreementAccepted {
  final bool emailed;
  final bool alreadyAccepted;
  const AgreementAccepted({required this.emailed, required this.alreadyAccepted});
}

/// "1 November 2026" / "1.11.2026" in the phone's time zone.
String longDate(BuildContext context, DateTime d) => dateText(context, d);

/// The short "Seller Terms accepted" line shown after an acceptance made on the way to another action.
String acceptedNotice(BuildContext context, String title, AgreementAccepted a) => a.emailed
    ? tr(context, '$title accepted. A copy was emailed to you.', '$title hyväksytty. Kopio lähetettiin sähköpostiisi.')
    : tr(context, '$title accepted.', '$title hyväksytty.');

/// Runs [call]; on 428 AGREEMENT_REQUIRED shows the agreement sheet and, once accepted, runs [call]
/// again. Returns the last answer (still the 428 when the sheet was closed without accepting; its
/// error is the server's own "Please read and accept…" sentence).
///
/// With [announce] the "accepted" line is shown as a snackbar; callers that show their own message
/// afterwards pass false and add [ApiResult.notice] to it.
Future<ApiResult> withAgreement(
  BuildContext context,
  ApiClient api,
  Future<ApiResult> Function() call, {
  bool announce = true,
}) async {
  var res = await call();
  String? notice;
  // Normally one round; a second only if the terms changed again in between
  for (var round = 0; round < 2 && res.agreementRequired && context.mounted; round++) {
    final need = AgreementRequired.from(res);
    final doc = need?.doc ?? AgreementDocs.sellerTerms;
    final title = agreementTitle(context, need?.title, doc);
    final accepted = await showAgreementSheet(
      context,
      api: api,
      doc: doc,
      version: need?.version,
      url: need?.url,
      title: need?.title,
      urgent: true,
    );
    if (accepted == null || !context.mounted) break;
    notice = acceptedNotice(context, title, accepted);
    res = await call();
  }
  if (notice != null && announce && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice), duration: const Duration(seconds: 3)));
  }
  return res.withNotice(notice);
}

/// The agreement sheet: a summary, what changes (for updates), the full text, a required checkbox and
/// Accept. [version] and [url] come from a 428 answer, so the sheet is ready at once; without them it
/// asks `GET /me/agreements` first. [pending] accepts the announced update instead of the version in
/// force. [urgent] (an action waits behind the sheet) closes it right after acceptance; otherwise the
/// sheet confirms the acceptance itself.
Future<AgreementAccepted?> showAgreementSheet(
  BuildContext context, {
  required ApiClient api,
  String doc = 'seller-terms',
  String? version,
  String? url,
  Object? title,
  bool pending = false,
  bool urgent = false,
}) {
  Haptics.selection();
  return showMSheet<AgreementAccepted>(context, builder: (_) => _AgreementSheet(api: api, doc: doc, version: version, url: url, title: title, pending: pending, urgent: urgent), isScrollControlled: true, useSafeArea: true);
}

class _AgreementSheet extends StatefulWidget {
  final ApiClient api;
  final String doc;
  final String? version;
  final String? url;
  final Object? title;
  final bool pending;
  final bool urgent;
  const _AgreementSheet({required this.api, required this.doc, this.version, this.url, this.title, required this.pending, required this.urgent});

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  static const _red = MPalette.red;

  late String? _version = widget.version;
  late String? _url = widget.url;
  late Object? _title = widget.title;
  DateTime? _effectiveAt;
  DateTime? _terminateBefore;
  Map? _changeSummary;
  bool _isUpdate = false;
  bool _infoLoading = false;
  bool _checked = false;
  bool _busy = false;
  String? _error;
  AgreementAccepted? _done;

  bool get _privacy => widget.doc == 'privacy';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  /// The details around the version: whether it replaces one the store accepted, what changes, and for
  /// an announced update when it takes effect. Loaded in the background when the sheet came from a 428.
  Future<void> _loadInfo() async {
    setState(() => _infoLoading = true);
    final agreements = AgreementsApi(widget.api);
    final (mine, rows) = await (agreements.load(), agreements.versions(widget.doc)).wait;
    if (!mounted) return;
    final item = mine.docOf(widget.doc);
    setState(() {
      _infoLoading = false;
      if (item != null) {
        _title ??= item.title;
        if (widget.pending && item.pendingVersion != null) {
          _version = item.pendingVersion;
          _url = item.pendingUrl ?? _url;
          _effectiveAt = item.pendingEffectiveAt;
          _terminateBefore = item.canTerminateBefore;
          if (item.summary != null) _changeSummary = item.summary;
        } else {
          _version ??= item.currentVersion;
          _url ??= item.url;
        }
      }
      _isUpdate = widget.pending || mine.acceptedEarlier(widget.doc, _version);
      // What changes in the version in force (the first version has nothing to compare with)
      if (!widget.pending && _isUpdate) {
        final index = rows.indexWhere((r) => r.version == _version);
        if (index >= 0 && index < rows.length - 1 && rows[index].summary != null) _changeSummary = rows[index].summary;
      }
      if (_version == null && !mine.ok) _error = mine.error;
    });
  }

  Future<void> _openFull() async {
    Haptics.selection();
    final uri = Uri.tryParse(_url ?? '');
    var opened = false;
    if (uri != null && uri.scheme == 'https') {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {}
    }
    if (!opened && mounted) {
      setState(() => _error = tr(context, 'Could not open the text. Please try again.', 'Tekstiä ei voitu avata. Yritä uudelleen.'));
    }
  }

  Future<void> _accept() async {
    final version = _version;
    if (version == null || !_checked || _busy) return;
    Haptics.medium();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await AgreementsApi(widget.api).accept(widget.doc, version);
    if (!mounted) return;
    if (res.ok) {
      Haptics.success();
      final accepted = AgreementAccepted(emailed: res.emailed, alreadyAccepted: res.alreadyAccepted);
      if (widget.urgent) {
        Navigator.of(context).pop(accepted);
        return;
      }
      setState(() {
        _busy = false;
        _done = accepted;
      });
      return;
    }
    Haptics.warning();
    setState(() {
      _busy = false;
      if (res.conflict) {
        // Replaced a moment ago: show the version that is now current (or announced) and ask again
        _version = widget.pending ? res.pendingVersion : res.currentVersion;
        _url = null;
        _changeSummary = null;
        _checked = false;
        _error = tr(context, 'These terms were updated a moment ago. Read the new version and accept it again.',
            'Ehtoja päivitettiin juuri. Lue uusi versio ja hyväksy se uudelleen.');
      } else {
        _error = res.result.errorMessage;
      }
    });
    if (res.conflict) _loadInfo();
  }

  @override
  Widget build(BuildContext context) {
    final title = agreementTitle(context, _title, widget.doc);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, MSpace.xl),
        child: _done != null ? _doneView(title) : _askView(title),
      ),
    );
  }

  Widget _doneView(String title) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: MSpace.sm),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 38, color: AppTheme.primary),
          ),
        ),
        const SizedBox(height: MSpace.lg),
        Text(
          _privacy ? tr(context, 'Thank you for reading it', 'Kiitos, että luit sen') : tr(context, '$title accepted', '$title hyväksytty'),
          textAlign: TextAlign.center,
          style: AppTheme.display(size: 22),
        ),
        if (_done!.emailed) ...[
          const SizedBox(height: MSpace.sm),
          Text(
            tr(context, 'A copy was emailed to you. You can also open it any time in Store → Agreements.',
                'Kopio lähetettiin sähköpostiisi. Voit avata sen myös milloin tahansa kohdasta Kauppa → Sopimukset.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
        const SizedBox(height: MSpace.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => Navigator.of(context).pop(_done), child: Text(tr(context, 'Done', 'Valmis'))),
        ),
      ]);

  Widget _askView(String title) {
    final pendingDate = _effectiveAt != null ? longDate(context, _effectiveAt!) : null;
    final summary = _changeSummary == null ? null : '${_changeSummary![isFinnish(context) ? 'fi' : 'en'] ?? _changeSummary!['en'] ?? ''}'.trim();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        widget.pending
            ? tr(context, 'Upcoming change to the $title', 'Tulossa oleva muutos: $title')
            : _isUpdate
                ? (_privacy
                    ? tr(context, 'The $title has been updated', '$title on päivitetty')
                    : tr(context, 'The $title have changed', '$title ovat muuttuneet'))
                : title,
        style: AppTheme.display(size: 22),
      ),
      const SizedBox(height: MSpace.sm),
      Text(
        _privacy
            ? tr(context, 'How Malvoya collects, uses and keeps your data, and what your rights are. You only need to read it; nothing here asks for your consent.',
                'Miten Malvoya kerää, käyttää ja säilyttää tietojasi ja mitkä oikeutesi ovat. Riittää, että luet sen; sinulta ei pyydetä suostumusta.')
            : widget.pending
                ? tr(context, 'Nothing changes before the update takes effect. You can keep selling as before.',
                    'Mikään ei muutu ennen kuin päivitys tulee voimaan. Voit jatkaa myymistä kuten ennenkin.')
                : tr(context, 'Accept them to take orders and publish products. Here are the main points:',
                    'Hyväksy ne, niin voit ottaa vastaan tilauksia ja julkaista tuotteita. Tärkeimmät kohdat:'),
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      if (pendingDate != null) ...[
        const SizedBox(height: MSpace.md),
        _box(
          Icons.event_rounded,
          [
            tr(context, 'Takes effect on $pendingDate.', 'Tulee voimaan $pendingDate.'),
            if (_terminateBefore != null)
              tr(context, 'If you don\'t agree, you can end your contract before ${longDate(context, _terminateBefore!)} (Seller Terms §7a).',
                  'Jos et hyväksy muutosta, voit irtisanoa sopimuksesi ennen ${longDate(context, _terminateBefore!)} (Myyjän ehdot §7a).'),
          ].join(' '),
          bg: AppTheme.sunshineLight,
          fg: MPalette.amberInk,
        ),
      ],
      if (summary != null && summary.isNotEmpty) ...[
        const SizedBox(height: MSpace.md),
        Text(tr(context, 'What changes', 'Mikä muuttuu'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        const SizedBox(height: MSpace.xs),
        Text(summary, style: const TextStyle(color: AppTheme.textPrimary, height: 1.45)),
      ],
      if (!_privacy && !widget.pending) ...[
        const SizedBox(height: MSpace.md),
        Container(
          padding: const EdgeInsets.fromLTRB(14, MSpace.md, 14, MSpace.md),
          decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final point in _sellerTermsPoints(context)) _point(point),
            Text(tr(context, 'This is a summary; the full Seller Terms apply.', 'Tämä on tiivistelmä; sitovat ovat koko myyjän ehdot.'),
                style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
          ]),
        ),
      ],
      const SizedBox(height: MSpace.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _url == null ? null : _openFull,
          icon: const Icon(Icons.open_in_new_rounded, size: 20),
          label: Text(_privacy
              ? tr(context, 'Read the full Privacy Policy', 'Lue koko tietosuojaseloste')
              : widget.pending
                  ? tr(context, 'Read the new Seller Terms', 'Lue uudet myyjän ehdot')
                  : tr(context, 'Read the full Seller Terms', 'Lue koko myyjän ehdot')),
        ),
      ),
      const SizedBox(height: MSpace.xs),
      Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          value: _checked,
          onChanged: _busy ? null : (v) => setState(() => _checked = v == true),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          minTileHeight: 56,
          title: Text(
            _privacy
                ? tr(context, 'I have read the Privacy Policy', 'Olen lukenut tietosuojaselosteen')
                : tr(context, 'I have read and accept the $title', 'Olen lukenut ${title.toLowerCase()} ja hyväksyn ne'),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: MSpace.xs, bottom: MSpace.xs),
          child: Text(_error!, style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: MSpace.sm),
      SizedBox(
        width: double.infinity,
        child: MButton(label: _privacy ? tr(context, 'Confirm', 'Vahvista') : tr(context, 'Accept', 'Hyväksy'), loading: _busy, onPressed: _checked && _version != null && !_busy ? _accept : null),
      ),
      if (_version == null && _infoLoading)
        const Padding(padding: EdgeInsets.only(top: 10), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))),
      const SizedBox(height: MSpace.sm),
      Text(
        tr(context, 'Malvoya records which version you accepted and when, and sends you a copy by email.',
            'Malvoya tallentaa, minkä version hyväksyit ja milloin, ja lähettää sinulle kopion sähköpostitse.'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
      ),
    ]);
  }

  static List<String> _sellerTermsPoints(BuildContext context) => [
        tr(context, 'Orders reach you only once the customer has paid. Accept or decline each one within 10 minutes; declined orders are refunded automatically.',
            'Tilaukset näkyvät sinulle vasta, kun asiakas on maksanut. Hyväksy tai hylkää jokainen tilaus 10 minuutin kuluessa; hylätyt tilaukset hyvitetään automaattisesti.'),
        tr(context, 'You are responsible for accurate listings, prices including VAT, and the safety and legality of what you sell.',
            'Vastaat siitä, että tuotetiedot ovat oikein, hinnat sisältävät arvonlisäveron ja myymäsi tuotteet ovat turvallisia ja laillisia.'),
        tr(context, 'Malvoya takes no commission: it pays your item sales through Stripe 15 days after delivery, less any refunds.',
            'Malvoya ei peri provisiota: se tilittää tuotemyyntisi Stripen kautta 15 päivää toimituksen jälkeen, hyvitykset vähennettyinä.'),
        tr(context, 'Business sellers honour the 14-day right of withdrawal. EU law (DAC7) requires your tax details.',
            'Yritysmyyjät noudattavat 14 päivän peruuttamisoikeutta. EU-laki (DAC7) edellyttää verotietojasi.'),
        tr(context, 'Changes are announced at least 15 days ahead, and you may end the agreement before they take effect.',
            'Muutoksista ilmoitetaan vähintään 15 päivää etukäteen, ja voit päättää sopimuksen ennen kuin ne tulevat voimaan.'),
      ];

  Widget _point(String text) => Padding(
        padding: const EdgeInsets.only(bottom: MSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline_rounded, size: 18, color: AppTheme.primary)),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textPrimary, height: 1.4, fontSize: MTextSize.bodyM))),
        ]),
      );

  Widget _box(IconData icon, String text, {required Color bg, required Color fg}) => Container(
        padding: const EdgeInsets.fromLTRB(MSpace.md, 10, MSpace.md, 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, height: 1.35))),
        ]),
      );
}
