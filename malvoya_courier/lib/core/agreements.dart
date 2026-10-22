import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'api_client.dart';
import 'legal_links.dart';
import 'strings.dart';

/// Versioned agreements (API 2.11).
///
/// The server refuses going online and taking jobs with 428 `AGREEMENT_REQUIRED` until the Courier
/// Agreement in force is accepted ([AgreementRequired]); the caller shows [Agreements.resolve] and
/// then retries by itself. Going offline is never blocked, and the privacy notice never blocks.
/// An announced (pending) version can be accepted early but never blocks before its date.

/// The body of a 428 `AGREEMENT_REQUIRED` answer.
class AgreementRequired {
  final String doc;
  final String version;
  final Map? title;
  final String? url;
  final String? message;

  const AgreementRequired({required this.doc, required this.version, this.title, this.url, this.message});

  /// Null when [res] is anything else.
  static AgreementRequired? from(ApiResult res) {
    if (res.status != 428 || res.data['code'] != 'AGREEMENT_REQUIRED') return null;
    final doc = res.data['doc'];
    final version = res.data['version'];
    if (doc is! String || version is! String) return null;
    return AgreementRequired(
      doc: doc,
      version: version,
      title: res.data['title'] is Map ? res.data['title'] as Map : null,
      url: res.data['url'] is String ? res.data['url'] as String : null,
      message: res.error,
    );
  }
}

/// One document of `GET /me/agreements` → `required`.
class AgreementDoc {
  final Map<String, dynamic> raw;
  const AgreementDoc(this.raw);

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

  String get doc => '${raw['doc'] ?? ''}';
  Map? get title => raw['title'] is Map ? raw['title'] as Map : null;
  bool get blocking => raw['blocking'] != false;
  String? get currentVersion => raw['currentVersion'] as String?;
  DateTime? get effectiveAt => _date(raw['effectiveAt']);
  bool get accepted => raw['accepted'] == true;
  DateTime? get acceptedAt => _date(raw['acceptedAt']);
  String? get url => raw['url'] as String?;
  String? get pendingVersion => raw['pendingVersion'] as String?;
  DateTime? get pendingEffectiveAt => _date(raw['pendingEffectiveAt']);
  bool get pendingAccepted => raw['pendingAccepted'] == true;
  String? get pendingUrl => raw['pendingUrl'] as String?;
  Map? get summary => raw['summary'] is Map ? raw['summary'] as Map : null;

  /// An announced version the courier has not accepted yet.
  bool get hasOpenUpdate => pendingVersion != null && !pendingAccepted;
}

class AgreementState {
  /// 0 = no connection, 404 = a server without agreements (before 2.11).
  final int status;
  final String? error;
  final List<AgreementDoc> required;
  final List<Map<String, dynamic>> history;

  const AgreementState({required this.status, this.error, this.required = const [], this.history = const []});

  bool get ok => error == null;
  bool get unsupported => status == 404;

  AgreementDoc? docOf(String doc) => required.where((d) => d.doc == doc).firstOrNull;
}

class Agreements {
  Agreements._();

  static const courierAgreement = 'courier-agreement';

  static Future<AgreementState> load(AuthService auth) async {
    final res = await ApiClient(auth).get('/me/agreements');
    if (!res.ok) return AgreementState(status: res.status, error: res.error);
    List<Map<String, dynamic>> maps(dynamic v) => ((v as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return AgreementState(
      status: res.status,
      required: maps(res.data['required']).map(AgreementDoc.new).toList(),
      history: maps(res.data['history']),
    );
  }

  /// "Courier Agreement" / "Lähettisopimus" from a server title, with a fallback per document.
  static String titleOf(BuildContext context, String doc, [Map? title]) {
    final fromServer = localizedText(context, title);
    if (fromServer != null) return fromServer;
    return switch (doc) {
      courierAgreement => tr(context, 'Courier Agreement', 'Lähettisopimus'),
      'privacy' => tr(context, 'Privacy Policy', 'Tietosuojaseloste'),
      _ => tr(context, 'Agreement', 'Sopimus'),
    };
  }

  /// Opens a document (an exact version when [url] is given) in the in-app browser.
  static Future<void> openDocument(String? url, String doc) async {
    final uri = url == null ? null : Uri.tryParse(url);
    await launchUrl(uri ?? legalUrl(doc), mode: LaunchMode.inAppBrowserView);
  }

  /// A 428 from going online or taking a job: shows the agreement the server named. True when it
  /// was accepted, so the caller can retry straight away.
  static Future<bool> resolve(BuildContext context, AuthService auth, AgreementRequired need) async {
    HapticFeedback.selectionClick();
    final result = await _show(context, auth, doc: need.doc, version: need.version, title: need.title, url: need.url, blocking: true);
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
      if (!state.ok) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(state.unsupported ? tr(context, 'Opening the agreement.', 'Avataan sopimus.') : state.error!)));
      if (state.unsupported) await openDocument(null, doc);
      return false;
    }
    if (d.accepted && !d.hasOpenUpdate) return true;
    return review(context, auth, d);
  }

  /// Opens the copy of an accepted version through a 10-minute signed link.
  static Future<void> openCopy(BuildContext context, AuthService auth, int id) async {
    final res = await ApiClient(auth).get('/me/agreements/$id/copy/link');
    if (!context.mounted) return;
    final url = res.ok ? Uri.tryParse('${res.data['url'] ?? ''}') : null;
    if (url == null || !url.hasScheme) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(res.error ?? tr(context, 'Could not open the copy. Please try again.', 'Kopiota ei voitu avata. Yritä uudelleen.'))));
      return;
    }
    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
  }

  static void _confirmed(BuildContext context, String doc, bool emailed) {
    final privacy = doc == 'privacy';
    final done = privacy ? tr(context, 'Marked as read.', 'Merkitty luetuksi.') : tr(context, 'Accepted.', 'Hyväksytty.');
    // Only when the server says the email really went out
    final text = emailed ? '$done ${tr(context, 'A copy has been emailed to you.', 'Kopio on lähetetty sinulle sähköpostilla.')}' : done;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
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
  }) =>
      showModalBottomSheet<_AcceptResult>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AgreementSheet(
          auth: auth,
          doc: doc,
          version: version,
          title: title,
          url: url,
          blocking: blocking,
          pendingAt: pendingAt,
          changeSummary: changeSummary,
        ),
      );
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

  const _AgreementSheet({
    required this.auth,
    required this.doc,
    required this.version,
    required this.blocking,
    this.title,
    this.url,
    this.pendingAt,
    this.changeSummary,
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
  bool _accepting = false;
  String? _error;

  bool get _pending => _pendingAt != null;
  bool get _privacy => widget.doc == 'privacy';
  ApiClient get _api => ApiClient(widget.auth);

  @override
  void initState() {
    super.initState();
    // The sheet opens at once with what the caller knows; the version details follow
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final results = await Future.wait([_api.get('/legal/${widget.doc}/versions'), _api.get('/me/agreements')]);
    if (!mounted) return;
    final versions = results[0];
    final mine = results[1];
    setState(() {
      if (versions.ok) {
        final list = ((versions.data['versions'] as List?) ?? const []).whereType<Map>().toList();
        final row = list.where((v) => v['version'] == _version).firstOrNull;
        if (row != null) {
          _changeSummary ??= row['summary'] is Map ? row['summary'] as Map : null;
          _effectiveAt = DateTime.tryParse('${row['effectiveAt'] ?? ''}');
          _url ??= row['url'] as String?;
          if (row['status'] == 'pending') _pendingAt ??= _effectiveAt;
        }
        // The very first published version has no "what changed"
        _firstVersion = list.length <= 1 || (list.isNotEmpty && list.last['version'] == _version);
      }
      if (mine.ok) {
        final history = ((mine.data['history'] as List?) ?? const []).whereType<Map>();
        _changed = history.any((h) => h['doc'] == widget.doc && h['version'] != _version);
      }
    });
  }

  Future<void> _accept() async {
    if (!_checked || _accepting) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _accepting = true;
      _error = null;
    });
    final res = await _api.post('/me/agreements/accept', {'doc': widget.doc, 'version': _version});
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, _AcceptResult(res.data['emailed'] == true));
      return;
    }
    setState(() {
      _accepting = false;
      _error = res.error;
    });
    if (res.status == 409) {
      // A newer version came into force meanwhile: show that one and ask again
      final current = res.data['currentVersion'] as String?;
      final pending = res.data['pendingVersion'] as String?;
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
    final change = (_pending || _changed) && !_firstVersion ? localizedText(context, _changeSummary) : null;
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
                child: Icon(_privacy ? Icons.shield_outlined : Icons.gavel_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
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
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
                  const SizedBox(height: 4),
                  Text(change, style: const TextStyle(height: 1.4, color: AppTheme.textPrimary)),
                ]),
              ),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(tr(context, 'In short', 'Lyhyesti'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              for (final line in summary)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: CircleAvatar(radius: 3, backgroundColor: AppTheme.primary),
                    ),
                    Expanded(child: Text(line, style: const TextStyle(height: 1.4, fontSize: 14))),
                  ]),
                ),
              Text(tr(context, 'This summary does not replace the agreement; the full text applies.', 'Tämä tiivistelmä ei korvaa sopimusta; koko teksti on voimassa.'),
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: () => Agreements.openDocument(_url, widget.doc),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(tr(context, 'Read the full $title', 'Lue koko $titleFiLower')),
            ),
            Text(
              [
                '${tr(context, 'Version', 'Versio')} $_version',
                if (!_pending && _effectiveAt != null) tr(context, 'in force since ${dateText(context, _effectiveAt!)}', 'voimassa ${dateText(context, _effectiveAt!)} alkaen'),
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Material(
              color: AppTheme.sand,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: CheckboxListTile(
                value: _checked,
                onChanged: _accepting ? null : (v) => setState(() => _checked = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                title: Text(checkLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _checked && !_accepting ? _accept : null,
                child: _accepting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(_privacy ? tr(context, 'Mark as read', 'Merkitse luetuksi') : tr(context, 'Accept', 'Hyväksy')),
              ),
            ),
            const SizedBox(height: 4),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      child: Row(children: [
        const Icon(Icons.gavel_rounded, color: Color(0xFF8A5A00), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            when == null ? tr(context, 'The $title is changing.', '$title muuttuu.') : tr(context, 'The $title changes on $when.', '$title muuttuu $when.'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
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
