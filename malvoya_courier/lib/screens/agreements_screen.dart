import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/strings.dart';

/// Account → Agreements: what the courier has accepted (Courier Agreement) or read (Privacy
/// Policy), announced changes, and every acceptance with a copy of the exact text (API 2.11).
class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});

  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  AgreementState? _state;
  bool _loading = true;
  int? _openingCopy;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await Agreements.load(_auth);
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  Future<void> _review(AgreementDoc d, {bool? pending}) async {
    if (await Agreements.review(context, _auth, d, pending: pending)) _load();
  }

  Future<void> _copy(int id) async {
    setState(() => _openingCopy = id);
    await Agreements.openCopy(context, _auth, id);
    if (mounted) setState(() => _openingCopy = null);
  }

  String _method(String? m) => switch (m) {
        'register' => tr(context, 'when you created the account', 'tiliä luodessasi'),
        'admin_import' => tr(context, 'recorded by Malvoya from earlier records', 'Malvoyan aiemmista tiedoista kirjattu'),
        _ => tr(context, 'in the app', 'sovelluksessa'),
      };

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Agreements', 'Sopimukset'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: state == null || !state.ok ? _fallback(state) : _content(state),
              ),
            ),
    );
  }

  /// An older server (404) or no connection: the documents can still be read.
  List<Widget> _fallback(AgreementState? state) => [
        if (state != null && !state.unsupported)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(state.error ?? '', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        _card([
          _readTile(Agreements.courierAgreement, Icons.gavel_rounded),
          const Divider(height: 1),
          _readTile('privacy', Icons.shield_outlined),
        ]),
        if (state != null && !state.unsupported) ...[
          const SizedBox(height: 12),
          Center(child: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'Try again', 'Yritä uudelleen')))),
        ],
      ];

  Widget _readTile(String doc, IconData icon) => ListTile(
        minTileHeight: 56,
        leading: Icon(icon),
        title: Text(Agreements.titleOf(context, doc), style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.open_in_new_rounded, size: 20),
        onTap: () => Agreements.openDocument(null, doc),
      );

  List<Widget> _content(AgreementState state) => [
        Text(
          tr(context,
              'Malvoya records which version you accepted, when and how, and emails you a copy of the full text. Every change is announced with its date and a summary before it takes effect.',
              'Malvoya kirjaa, minkä version hyväksyit, milloin ja miten, ja lähettää sinulle kopion koko tekstistä sähköpostilla. Jokaisesta muutoksesta ilmoitetaan päivämäärän ja tiivistelmän kanssa ennen kuin se tulee voimaan.'),
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (final d in state.required) _docCard(d),
        const SizedBox(height: 10),
        Text(tr(context, 'History', 'Historia'), style: AppTheme.display(size: 19)),
        const SizedBox(height: 8),
        if (state.history.isEmpty)
          Text(tr(context, 'Nothing accepted yet.', 'Ei vielä hyväksyttyjä sopimuksia.'), style: const TextStyle(color: AppTheme.textSecondary))
        else
          _card([
            for (var i = 0; i < state.history.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _historyRow(state.history[i]),
            ],
          ]),
      ];

  Widget _docCard(AgreementDoc d) {
    final title = Agreements.titleOf(context, d.doc, d.title);
    final privacy = d.doc == 'privacy' || !d.blocking;
    final String status;
    if (d.accepted) {
      final at = d.acceptedAt == null ? '' : ' ${dateText(context, d.acceptedAt!)}';
      status = privacy ? tr(context, 'Read$at', 'Luettu$at') : tr(context, 'Accepted$at', 'Hyväksytty$at');
    } else {
      status = privacy
          ? tr(context, 'Not marked as read yet (it never blocks anything)', 'Ei vielä merkitty luetuksi (ei estä mitään)')
          : tr(context, 'Not accepted yet: needed to go online and take jobs', 'Ei vielä hyväksytty: tarvitaan linjoille menemiseen ja keikkojen ottamiseen');
    }
    final pendingAt = d.pendingEffectiveAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg), border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(privacy ? Icons.shield_outlined : Icons.gavel_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTheme.display(size: 18))),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(d.accepted ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: d.accepted ? AppTheme.success : (privacy ? AppTheme.textSecondary : AppTheme.warning)),
          const SizedBox(width: 6),
          Expanded(child: Text(status, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
        ]),
        if (d.effectiveAt != null || d.currentVersion != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (d.currentVersion != null) '${tr(context, 'Version', 'Versio')} ${d.currentVersion}',
                if (d.effectiveAt != null) tr(context, 'in force since ${dateText(context, d.effectiveAt!)}', 'voimassa ${dateText(context, d.effectiveAt!)} alkaen'),
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        if (d.pendingVersion != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                pendingAt == null ? tr(context, 'New version announced', 'Uusi versio ilmoitettu') : tr(context, 'New version from ${dateText(context, pendingAt)}', 'Uusi versio ${dateText(context, pendingAt)} alkaen'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00)),
              ),
              if (localizedText(context, d.summary) != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(localizedText(context, d.summary)!, style: const TextStyle(height: 1.4))),
              const SizedBox(height: 4),
              Text(
                d.pendingAccepted
                    ? tr(context, 'You have already accepted it.', 'Olet jo hyväksynyt sen.')
                    : tr(context, 'Nothing changes before that date. You can accept it now or later.', 'Ennen sitä mikään ei muutu. Voit hyväksyä sen nyt tai myöhemmin.'),
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 4, children: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Agreements.openDocument(d.url, d.doc),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr(context, 'Read', 'Lue')),
          ),
          if (!d.accepted)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _review(d, pending: false),
              child: Text(privacy ? tr(context, 'Mark as read', 'Merkitse luetuksi') : tr(context, 'Review and accept', 'Lue ja hyväksy')),
            ),
          if (d.accepted && d.hasOpenUpdate)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _review(d, pending: true),
              child: Text(tr(context, 'Review the new version', 'Katso uusi versio')),
            ),
        ]),
      ]),
    );
  }

  Widget _historyRow(Map<String, dynamic> h) {
    final id = asInt(h['id']);
    final doc = '${h['doc'] ?? ''}';
    final at = DateTime.tryParse('${h['acceptedAt'] ?? ''}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Agreements.titleOf(context, doc, h['title'] is Map ? h['title'] as Map : null), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          [if (at != null) dateTimeText(context, at), _method(h['method'] as String?)].join(' · '),
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        Text('${tr(context, 'Version', 'Versio')} ${h['version'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        if (id != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _openingCopy == null ? () => _copy(id) : null,
              icon: _openingCopy == id
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.description_outlined, size: 18),
              label: Text(tr(context, 'Open copy', 'Avaa kopio')),
            ),
          ),
      ]),
    );
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg), border: Border.all(color: AppTheme.divider)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}
