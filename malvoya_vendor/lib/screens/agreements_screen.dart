import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/haptics.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';
import '../widgets/loading_states.dart';

/// Store → Agreements (API 2.11, `GET /me/agreements`): what the store has accepted, announced
/// updates, and every acceptance with a copy of the exact text. Older servers answer 404; then the
/// screen links to the published texts as before.
class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});

  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  bool _loading = true;
  String? _error;
  bool _supported = true;
  List<Map> _required = [];
  List<Map> _history = [];
  final Set<Object?> _opening = {};

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.get('/me/agreements');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _supported = res.status != 404;
      _error = res.ok || res.status == 404 ? null : res.errorMessage;
      if (res.ok) {
        _required = ((res.data['required'] as List?) ?? const []).whereType<Map>().toList();
        _history = ((res.data['history'] as List?) ?? const []).whereType<Map>().toList();
      }
    });
  }

  Future<void> _review(Map item, {required bool pending}) async {
    final doc = '${item['doc']}';
    final version = pending ? item['pendingVersion'] : item['currentVersion'];
    final accepted = await showAgreementSheet(
      context,
      api: _api,
      doc: doc,
      version: version is String ? version : null,
      url: (pending ? item['pendingUrl'] : item['url']) as String?,
      title: item['title'],
      pending: pending,
    );
    if (accepted != null && mounted) _load();
  }

  Future<void> _openUrl(String? url) async {
    Haptics.select();
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
  }

  /// A fresh 10-minute link each time, opened in the browser (where the copy can be printed or saved).
  Future<void> _openCopy(Map h) async {
    Haptics.select();
    final id = h['id'];
    setState(() => _opening.add(id));
    final res = await _api.get('/me/agreements/$id/copy/link');
    if (!mounted) return;
    setState(() => _opening.remove(id));
    final uri = Uri.tryParse('${res.data['url'] ?? ''}');
    var opened = false;
    if (res.ok && uri != null && uri.scheme == 'https') {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok ? tr(context, 'Could not open the browser. Please try again.', 'Selainta ei voitu avata. Yritä uudelleen.') : res.errorMessage),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Agreements', 'Sopimukset'))),
      body: _loading
          ? const SkeletonList(count: 3)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null) ErrorState(message: _error, onRetry: _retry, top: 24),
                  if (_error == null && !_supported) ..._olderServer(),
                  if (_error == null && _supported) ...[
                    for (final item in _required) _statusCard(item),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(tr(context, 'What you have accepted', 'Hyväksymäsi'), style: AppTheme.display(size: 18)),
                    ),
                    if (_history.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(tr(context, 'Nothing recorded yet.', 'Ei vielä kirjauksia.'), style: const TextStyle(color: AppTheme.textSecondary)),
                      ),
                    if (_history.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
                        child: Column(children: [
                          for (var i = 0; i < _history.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _historyRow(_history[i]),
                          ],
                        ]),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        tr(context, 'A copy shows the exact text you accepted. It opens in your browser for 10 minutes, where you can print it or save it as a PDF.',
                            'Kopiossa on täsmälleen hyväksymäsi teksti. Se avautuu selaimeesi 10 minuutiksi, ja voit tulostaa sen tai tallentaa sen PDF-tiedostona.'),
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  void _retry() {
    Haptics.select();
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  List<Widget> _olderServer() => [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.gavel_rounded, color: AppTheme.primary),
              title: Text(tr(context, 'Seller Terms', 'Myyjän ehdot'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => openLegal('sellers'),
            ),
            const Divider(height: 1),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
              title: Text(tr(context, 'Privacy Policy', 'Tietosuojaseloste'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => openLegal('privacy'),
            ),
          ]),
        ),
      ];

  Widget _statusCard(Map item) {
    final doc = '${item['doc']}';
    final title = agreementTitle(context, item['title'], doc);
    final blocking = item['blocking'] == true;
    final accepted = item['accepted'] == true;
    final acceptedAt = parseDate(item['acceptedAt']);
    final effectiveAt = parseDate(item['effectiveAt']);
    final hasPending = item['pendingVersion'] != null;
    final pendingAccepted = item['pendingAccepted'] == true;
    final pendingAt = parseDate(item['pendingEffectiveAt']);
    final terminateBefore = parseDate(item['canTerminateBefore']);
    final summary = item['summary'] is Map ? '${(item['summary'] as Map)[isFinnish(context) ? 'fi' : 'en'] ?? ''}'.trim() : '';
    final privacy = doc == 'privacy';

    final (statusText, statusBg, statusFg, statusIcon) = accepted
        ? (
            acceptedAt != null
                ? (privacy ? tr(context, 'Read on ${longDate(context, acceptedAt)}', 'Luettu ${longDate(context, acceptedAt)}') : tr(context, 'Accepted on ${longDate(context, acceptedAt)}', 'Hyväksytty ${longDate(context, acceptedAt)}'))
                : (privacy ? tr(context, 'Read', 'Luettu') : tr(context, 'Accepted', 'Hyväksytty')),
            AppTheme.primaryLight,
            AppTheme.primary,
            Icons.check_circle_rounded,
          )
        : blocking
            ? (tr(context, 'Needs your acceptance', 'Odottaa hyväksyntääsi'), AppTheme.sunshine, AppTheme.textPrimary, Icons.error_outline_rounded)
            : (tr(context, 'Please read it', 'Lue se'), AppTheme.sand, AppTheme.textPrimary, Icons.info_outline_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2), border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTheme.display(size: 19)),
        if (effectiveAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(tr(context, 'Version in force since ${longDate(context, effectiveAt)}', 'Voimassa oleva versio ${longDate(context, effectiveAt)} alkaen'),
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(statusIcon, size: 16, color: statusFg),
            const SizedBox(width: 6),
            Flexible(child: Text(statusText, style: TextStyle(color: statusFg, fontWeight: FontWeight.w800, fontSize: 13))),
          ]),
        ),
        if (!accepted && blocking)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(context, 'Until you accept, you can\'t accept new orders or publish products. Orders already accepted, returns and payouts carry on.',
                  'Ennen hyväksyntää et voi ottaa vastaan uusia tilauksia etkä julkaista tuotteita. Jo hyväksytyt tilaukset, palautukset ja tilitykset jatkuvat normaalisti.'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
          ),
        if (hasPending) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                pendingAt != null
                    ? tr(context, 'Update announced: takes effect on ${longDate(context, pendingAt)}', 'Muutos ilmoitettu: tulee voimaan ${longDate(context, pendingAt)}')
                    : tr(context, 'Update announced', 'Muutos ilmoitettu'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6A4500)),
              ),
              if (summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(summary, style: const TextStyle(color: AppTheme.textPrimary, height: 1.4)),
                ),
              if (terminateBefore != null && !pendingAccepted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr(context, 'If you don\'t agree, you can end your contract before ${longDate(context, terminateBefore)} (Seller Terms §7a).',
                        'Jos et hyväksy muutosta, voit irtisanoa sopimuksesi ennen ${longDate(context, terminateBefore)} (Myyjän ehdot §7a).'),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6A4500), height: 1.4),
                  ),
                ),
              if (pendingAccepted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr(context, 'You have already accepted this update.', 'Olet jo hyväksynyt tämän muutoksen.'),
                      style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!accepted)
            FilledButton(
              onPressed: () => _review(item, pending: false),
              child: Text(privacy ? tr(context, 'Read and confirm', 'Lue ja vahvista') : tr(context, 'Review and accept', 'Lue ja hyväksy')),
            ),
          if (accepted && hasPending && !pendingAccepted)
            OutlinedButton(
              onPressed: () => _review(item, pending: true),
              child: Text(tr(context, 'Review the update', 'Tutustu muutokseen')),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: item['url'] == null ? null : () => _openUrl(item['url'] as String?),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr(context, 'Read', 'Lue')),
          ),
        ]),
      ]),
    );
  }

  static const _methods = {
    'register': ['when creating the account', 'tiliä luotaessa'],
    'in_app': ['in the app', 'sovelluksessa'],
    'admin_import': ['from earlier records', 'aiemmista tiedoista'],
  };

  Widget _historyRow(Map h) {
    final doc = '${h['doc']}';
    final at = parseDate(h['acceptedAt']);
    final method = _methods[h['method']];
    final how = method == null ? null : (isFinnish(context) ? method[1] : method[0]);
    final opening = _opening.contains(h['id']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(agreementTitle(context, h['title'], doc), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            if (at != null)
              Text([longDate(context, at), if (how != null) how].join(' · '), style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            Text('${h['version'] ?? ''}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
          ]),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: opening ? null : () => _openCopy(h),
          child: opening
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr(context, 'Open copy', 'Avaa kopio')),
        ),
      ]),
    );
  }
}
