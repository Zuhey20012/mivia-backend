import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Versioned agreements (API 2.11).
///
/// The server refuses going online and taking jobs with 428 `AGREEMENT_REQUIRED` until the Courier
/// Agreement in force is accepted ([AgreementRequired]); the caller shows [Agreements.resolve] and
/// then retries by itself. Going offline is never blocked, and the privacy notice never blocks.
/// An announced (pending) version can be accepted early but never blocks before its date.

class Agreements {
  Agreements._();

  static const courierAgreement = AgreementDocs.courierAgreement;

  /// `GET /me/agreements` (malvoya_core's data layer).
  static Future<AgreementState> load(AuthService auth) => AgreementsApi(ApiClient(auth)).load();

  /// "Courier Agreement" / "Lähettisopimus" from a server title, with a fallback per document.
  static String titleOf(BuildContext context, String doc, [Map? title]) => agreementTitle(context, title, doc);

  /// Opens a document (an exact version when [url] is given) in the in-app browser.
  static Future<void> openDocument(String? url, String doc) async {
    final uri = url == null ? null : Uri.tryParse(url);
    await launchUrl(uri ?? legalUrl(doc), mode: LaunchMode.inAppBrowserView);
  }

  /// A 428 from going online or taking a job: shows the agreement the server named. True when it
  /// was accepted, so the caller can retry straight away.
  static Future<bool> resolve(BuildContext context, AuthService auth, AgreementRequired need) async {
    HapticFeedback.selectionClick();
    final result = await _show(context, auth, doc: need.doc, version: need.version, title: need.title, url: need.url, blocking: true, ageRequired: need.ageConfirmationRequired);
    if (result == null || !context.mounted) return false;
    _confirmed(context, need.doc, result.emailed);
    return true;
  }

  /// Shows the agreement for [d]: the version in force when it is not accepted yet, otherwise
  /// the announced one ([pending]). True when the courier accepted.
  static Future<bool> review(BuildContext context, AuthService auth, AgreementDoc d, {bool? pending}) async {
    final usePending = pending ?? (d.accepted && d.hasOpenUpdate);
    final version = usePending ? d.pendingVersion : d.currentVersion;
    if (version == null) return false;
    final result = await _show(
      context,
      auth,
      doc: d.doc,
      version: version,
      title: d.title,
      url: usePending ? d.pendingUrl : d.url,
      blocking: d.blocking,
      pendingAt: usePending ? d.pendingEffectiveAt : null,
      changeSummary: usePending ? d.summary : null,
    );
    if (result == null || !context.mounted) return false;
    _confirmed(context, d.doc, result.emailed);
    return true;
  }

  /// The onboarding step "accept_agreement": loads what is in force and shows it.
  /// True when something was accepted (or nothing was left to accept).
  static Future<bool> reviewDoc(BuildContext context, AuthService auth, String doc) async {
    final state = await load(auth);
    if (!context.mounted) return false;
    final d = state.docOf(doc);
    if (d == null) {
      // An older server, or no network: the text can still be read
      if (!state.ok) MSnack.show(context, state.unsupported ? tr(context, 'Opening the agreement.', 'Avataan sopimus.') : state.error!);
      if (state.unsupported) await openDocument(null, doc);
      return false;
    }
    // Accepted, but "I am 18 or older" not confirmed yet (API 2.16): the sheet asks for it with the agreement
    if (d.accepted && !d.hasOpenUpdate && !state.ageConfirmationRequired) return true;
    return review(context, auth, d);
  }

  /// Opens the copy of an accepted version through a 10-minute signed link.
  static Future<void> openCopy(BuildContext context, AuthService auth, int id) async {
    final (url, res) = await AgreementsApi(ApiClient(auth)).copyLink(id);
    if (!context.mounted) return;
    if (url == null) {
      MSnack.show(context, res.error ?? tr(context, 'Could not open the copy. Please try again.', 'Kopiota ei voitu avata. Yritä uudelleen.'));
      return;
    }
    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
  }

  static void _confirmed(BuildContext context, String doc, bool emailed) {
    final privacy = doc == 'privacy';
    final done = privacy ? tr(context, 'Marked as read.', 'Merkitty luetuksi.') : tr(context, 'Accepted.', 'Hyväksytty.');
    // Only when the server says the email really went out
    final text = emailed ? '$done ${tr(context, 'A copy has been emailed to you.', 'Kopio on lähetetty sinulle sähköpostilla.')}' : done;
    MSnack.show(context, text);
  }

  static Future<_AcceptResult?> _show(
    BuildContext context,
    AuthService auth, {
    required String doc,
    required String version,
    Map? title,
    String? url,
    required bool blocking,
    DateTime? pendingAt,
    Map? changeSummary,
    bool ageRequired = false,
  }) =>
      showMSheet<_AcceptResult>(context, builder: (_) => _AgreementSheet(
          auth: auth,
          doc: doc,
          version: version,
          title: title,
          url: url,
          blocking: blocking,
          pendingAt: pendingAt,
          changeSummary: changeSummary,
          ageRequired: ageRequired,
        ), isScrollControlled: true, useSafeArea: false);
}

class _AcceptResult {
  final bool emailed;
  const _AcceptResult(this.emailed);
}

class _AgreementSheet extends StatefulWidget {
  final AuthService auth;
  final String doc;
  final String version;
  final Map? title;
  final String? url;
  final bool blocking;
  /// Set for an announced version: when it takes effect.
  final DateTime? pendingAt;
  final Map? changeSummary;
  /// Also ask "I am 18 or older" (API 2.16: social sign-ups and older accounts)
  final bool ageRequired;

  const _AgreementSheet({
    required this.auth,
    required this.doc,
    required this.version,
    required this.blocking,
    this.title,
    this.url,
    this.pendingAt,
    this.changeSummary,
    this.ageRequired = false,
  });

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  late String _version = widget.version;
  late String? _url = widget.url;
  late DateTime? _pendingAt = widget.pendingAt;
  late Map? _changeSummary = widget.changeSummary;
  DateTime? _effectiveAt;
  // True when the courier accepted an earlier version of this document (so this one is an update)
  bool _changed = false;
  bool _firstVersion = false;
  bool _checked = false;
  late bool _ageRequired = widget.ageRequired;
  bool _ageChecked = false;
  bool _accepting = false;
  String? _error;

  bool get _pending => _pendingAt != null;
  bool get _ready => _checked && (!_ageRequired || _ageChecked);
  bool get _privacy => widget.doc == 'privacy';
  ApiClient get _api => ApiClient(widget.auth);

  @override
  void initState() {
    super.initState();
    // The sheet opens at once with what the caller knows; the version details follow
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final api = AgreementsApi(_api);
    final (list, mine) = await (api.versions(widget.doc), api.load()).wait;
    if (!mounted) return;
    setState(() {
      if (list.isNotEmpty) {
        final row = list.where((v) => v.version == _version).firstOrNull;
        if (row != null) {
          _changeSummary ??= row.summary;
          _effectiveAt = row.effectiveAt;
          _url ??= row.url;
          if (row.status == 'pending') _pendingAt ??= _effectiveAt;
        }
        // The very first published version has no "what changed"
        _firstVersion = list.length <= 1 || list.last.version == _version;
      }
      if (mine.ok) _changed = mine.acceptedEarlier(widget.doc, _version);
      if (mine.ok && mine.ageConfirmationRequired && !_privacy && !_pending) _ageRequired = true;
    });
  }

  Future<void> _accept() async {
    if (!_ready || _accepting) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _accepting = true;
      _error = null;
    });
    final res = await AgreementsApi(_api).accept(widget.doc, _version, ageConfirmed: _ageRequired);
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, _AcceptResult(res.emailed));
      return;
    }
    setState(() {
      _accepting = false;
      _error = res.error;
    });
    if (res.conflict) {
      // A newer version came into force meanwhile: show that one and ask again
      final current = res.currentVersion;
      final pending = res.pendingVersion;
      final next = _pending ? (pending ?? current) : current;
      if (next != null && next != _version) {
        setState(() {
          _version = next;
          _url = null;
          _changeSummary = null;
          _checked = false;
          if (next != pending) _pendingAt = null;
        });
        _loadDetails();
      }
    }
  }

  List<String> _summary(BuildContext context) => switch (widget.doc) {
        Agreements.courierAgreement => [
            tr(context, 'You deliver as an independent entrepreneur: you decide when you are online, which jobs you take and how you deliver. You may also work for other platforms.',
                'Toimitat itsenäisenä yrittäjänä: päätät itse, milloin olet linjoilla, mitkä keikat otat ja miten toimitat. Voit tehdä keikkoja myös muille alustoille.'),
            tr(context, 'Jobs are offered by distance to the shop only. Ratings, acceptance rates and declines are not used, and declining never counts against you.',
                'Keikat tarjotaan vain etäisyyden perusteella kauppaan. Arvioita, hyväksymisprosenttia tai kieltäytymisiä ei käytetä, eikä kieltäytyminen vaikuta sinuun.'),
            tr(context, 'You see your pay with its breakdown before you accept. Tips go to you in full, and each delivery is paid to your own Stripe account.',
                'Näet palkkiosi erittelyineen ennen kuin hyväksyt. Tipit saat kokonaan, ja jokainen toimitus maksetaan omalle Stripe-tilillesi.'),
            tr(context, 'You handle your own taxes and insurance, through a Y-tunnus or a light-entrepreneur service.',
                'Hoidat itse verosi ja vakuutuksesi Y-tunnuksella tai laskutuspalvelun kautta.'),
            tr(context, 'Your location is shared only while you are online. Decisions about your account are made by a person, with reasons.',
                'Sijaintisi jaetaan vain, kun olet linjoilla. Tiliäsi koskevat päätökset tekee ihminen ja perustelee ne.'),
            tr(context, 'Changes are announced at least 15 days before they take effect. You can stop at any time.',
                'Muutoksista ilmoitetaan vähintään 15 päivää ennen kuin ne tulevat voimaan. Voit lopettaa milloin tahansa.'),
          ],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final title = Agreements.titleOf(context, widget.doc, widget.title);
    final titleFiLower = title.toLowerCase();
    final pendingDate = _pendingAt == null ? null : dateText(context, _pendingAt!);
    final String heading;
    if (_pending) {
      heading = tr(context, 'The $title changes on $pendingDate', '$title muuttuu $pendingDate');
    } else if (_changed) {
      heading = tr(context, 'The $title has changed', '$title on muuttunut');
    } else {
      heading = title;
    }
    final String intro;
    if (_pending) {
      intro = tr(context,
          'Nothing changes for you before then: you can go online and take jobs as usual. You can accept the new version now or later; from $pendingDate it is needed to go online and take jobs.',
          'Siihen asti mikään ei muutu: voit mennä linjoille ja ottaa keikkoja tavalliseen tapaan. Voit hyväksyä uuden version nyt tai myöhemmin; $pendingDate alkaen sitä tarvitaan linjoille menemiseen ja keikkojen ottamiseen.');
    } else if (_privacy || !widget.blocking) {
      intro = tr(context, 'How Malvoya handles your personal data. You confirm that you have read it; it never blocks going online or taking jobs.',
          'Miten Malvoya käsittelee henkilötietojasi. Vahvistat lukeneesi sen; se ei koskaan estä linjoille menemistä tai keikkojen ottamista.');
    } else {
      intro = tr(context,
          'Read and accept it to go online and take jobs. Deliveries you have already accepted, your earnings, payouts and support are not affected.',
          'Lue ja hyväksy se, niin voit mennä linjoille ja ottaa keikkoja. Jo hyväksymäsi toimitukset, ansiosi, tilitykset ja tuki toimivat silti.');
    }
    final change = (_pending || _changed) && !_firstVersion ? localized(context, _changeSummary) : null;
    final summary = _summary(context);
    final String checkLabel = switch (widget.doc) {
      Agreements.courierAgreement => tr(context, 'I have read the Courier Agreement and accept it.', 'Olen lukenut lähettisopimuksen ja hyväksyn sen.'),
      'privacy' => tr(context, 'I have read the Privacy Policy.', 'Olen lukenut tietosuojaselosteen.'),
      _ => tr(context, 'I have read the $title and accept it.', '$title: olen lukenut sen ja hyväksyn sen.'),
    };

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                child: Icon(_privacy ? Icons.shield_outlined : Icons.gavel_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: MSpace.md),
              Expanded(child: Text(heading, style: AppTheme.display(size: 21))),
            ]),
            const SizedBox(height: 10),
            Text(intro, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
            if (change != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_pending ? tr(context, 'What changes', 'Mitä muuttuu') : tr(context, 'What changed', 'Mitä muuttui'),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: MPalette.amberInk)),
                  const SizedBox(height: MSpace.xs),
                  Text(change, style: const TextStyle(height: 1.4, color: AppTheme.textPrimary)),
                ]),
              ),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr(context, 'In short', 'Lyhyesti'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
              const SizedBox(height: 6),
              for (final line in summary)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: CircleAvatar(radius: 3, backgroundColor: AppTheme.primary),
                    ),
                    Expanded(child: Text(line, style: const TextStyle(height: 1.4, fontSize: MTextSize.bodyM))),
                  ]),
                ),
              Text(tr(context, 'This summary does not replace the agreement; the full text applies.', 'Tämä tiivistelmä ei korvaa sopimusta; koko teksti on voimassa.'),
                  style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: MSpace.xs)),
              onPressed: () => Agreements.openDocument(_url, widget.doc),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(tr(context, 'Read the full $title', 'Lue koko $titleFiLower')),
            ),
            Text(
              [
                '${tr(context, 'Version', 'Versio')} $_version',
                if (!_pending && _effectiveAt != null) tr(context, 'in force since ${dateText(context, _effectiveAt!)}', 'voimassa ${dateText(context, _effectiveAt!)} alkaen'),
              ].join(' · '),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: MSpace.sm),
            Material(
              color: AppTheme.sand,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: CheckboxListTile(
                value: _checked,
                onChanged: _accepting ? null : (v) => setState(() => _checked = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                title: Text(checkLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM)),
              ),
            ),
            if (_ageRequired) ...[
              const SizedBox(height: MSpace.sm),
              Material(
                color: AppTheme.sand,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                child: CheckboxListTile(
                  key: const Key('agreement-age-confirm'),
                  value: _ageChecked,
                  onChanged: _accepting ? null : (v) => setState(() => _ageChecked = v == true),
                  controlAffinity: ListTileControlAffinity.leading,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                  title: Text(tr(context, 'I am 18 or older', 'Olen vähintään 18-vuotias'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM)),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: MSpace.md),
            SizedBox(
              width: double.infinity,
              child: MButton(label: _privacy ? tr(context, 'Mark as read', 'Merkitse luetuksi') : tr(context, 'Accept', 'Hyväksy'), loading: _accepting, onPressed: _ready && !_accepting ? _accept : null),
            ),
            const SizedBox(height: MSpace.xs),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(64, 48), foregroundColor: AppTheme.textSecondary),
                onPressed: _accepting ? null : () => Navigator.pop(context),
                child: Text(_pending ? tr(context, 'Later', 'Myöhemmin') : tr(context, 'Not now', 'Ei nyt')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A calm note on the dashboard when a new version of the Courier Agreement has been announced:
/// it never blocks anything before its date. Closing it hides it for that version on this phone.
class AgreementUpdateBanner extends StatefulWidget {
  /// Hidden (but kept loaded) while true, e.g. during a delivery.
  final bool suppressed;
  const AgreementUpdateBanner({super.key, this.suppressed = false});

  @override
  State<AgreementUpdateBanner> createState() => AgreementUpdateBannerState();
}

class AgreementUpdateBannerState extends State<AgreementUpdateBanner> {
  AgreementDoc? _doc;
  static const _dismissedKey = 'agreement_update_dismissed';

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload() async {
    if (!mounted) return;
    final state = await Agreements.load(_auth);
    if (!mounted || !state.ok) return;
    final d = state.docOf(Agreements.courierAgreement);
    var show = d != null && d.accepted && d.hasOpenUpdate;
    if (show) {
      try {
        final dismissed = (await SharedPreferences.getInstance()).getString(_dismissedKey);
        if (dismissed == d.pendingVersion) show = false;
      } catch (_) {}
    }
    if (mounted) setState(() => _doc = show ? d : null);
  }

  Future<void> _dismiss() async {
    final version = _doc?.pendingVersion;
    setState(() => _doc = null);
    if (version == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_dismissedKey, version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    if (d == null || widget.suppressed) return const SizedBox.shrink();
    final when = d.pendingEffectiveAt == null ? null : dateText(context, d.pendingEffectiveAt!);
    final title = Agreements.titleOf(context, d.doc, d.title);
    return Container(
      margin: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, MSpace.xs, 6),
      decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      child: Row(children: [
        const Icon(Icons.gavel_rounded, color: MPalette.amberInk, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            when == null ? tr(context, 'The $title is changing.', '$title muuttuu.') : tr(context, 'The $title changes on $when.', '$title muuttuu $when.'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label, color: AppTheme.textPrimary),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () async {
            if (await Agreements.review(context, _auth, d, pending: true)) reload();
          },
          child: Text(tr(context, 'Review', 'Katso')),
        ),
        IconButton(
          tooltip: tr(context, 'Close', 'Sulje'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: _dismiss,
        ),
      ]),
    );
  }
}
