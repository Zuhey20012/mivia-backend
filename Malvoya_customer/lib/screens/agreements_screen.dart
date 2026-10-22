import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/api_client.dart';
import '../core/haptics.dart';
import '../core/strings.dart';
import '../widgets/agreement_sheet.dart';

/// Profile → Privacy → Agreements: the documents that apply to the account with their status, and
/// every acceptance on record with a copy of the exact text.
class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});

  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  int? _openingCopy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() => Agreements.instance.load(context.read<AuthService>());

  Future<void> _review(Map<String, dynamic> item, {required bool pending}) async {
    Haptics.light();
    await showAgreementSheet(context, Agreements.instance.promptFor(item, pending: pending));
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    Haptics.light();
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
  }

  /// The copy opens in the phone's browser through a 10-minute link (the browser has no session).
  Future<void> _openCopy(int id) async {
    if (_openingCopy != null) return;
    Haptics.light();
    setState(() => _openingCopy = id);
    final messenger = ScaffoldMessenger.of(context);
    final res = await ApiClient(context.read<AuthService>()).get('/me/agreements/$id/copy/link');
    if (!mounted) return;
    var opened = false;
    final url = res.data['url']?.toString();
    if (res.ok && url != null && url.isNotEmpty) {
      try {
        opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _openingCopy = null);
    if (!opened) {
      messenger.showSnackBar(SnackBar(
        content: Text(res.ok
            ? tr(context, 'The copy could not be opened. Please try again.', 'Kopiota ei voitu avata. Yritä uudelleen.')
            : (res.errorText(context) ?? tr(context, 'The copy could not be opened.', 'Kopiota ei voitu avata.'))),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _methodText(BuildContext context, dynamic method) {
    switch (method) {
      case 'register':
        return tr(context, 'When you created your account', 'Tiliä luotaessa');
      case 'admin_import':
        return tr(context, 'From earlier records', 'Aiemmista tiedoista');
      default:
        return tr(context, 'In the app', 'Sovelluksessa');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Agreements', 'Sopimukset'))),
      body: ListenableBuilder(
        listenable: Agreements.instance,
        builder: (context, _) {
          final a = Agreements.instance;
          if (!a.loaded) {
            if (a.loading || a.error == null) return const Center(child: CircularProgressIndicator());
            return _ErrorState(message: localizeServerMessage(context, a.error!), onRetry: _load);
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  tr(context,
                      'The documents that apply to your account, and a record of what you accepted and when. You can open a copy of the exact text at any time.',
                      'Tiliisi liittyvät asiakirjat ja tieto siitä, mitä olet hyväksynyt ja milloin. Voit avata kopion täsmälleen hyväksymästäsi tekstistä milloin tahansa.'),
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: textSecondary),
                ),
                const SizedBox(height: 18),
                _SectionTitle(tr(context, 'Your documents', 'Asiakirjasi')),
                for (final item in a.required) ...[
                  _DocumentCard(
                    item: item,
                    onRead: () => _openUrl(item['url']?.toString()),
                    onReview: () => _review(item, pending: false),
                    onReviewPending: () => _review(item, pending: true),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                _SectionTitle(tr(context, 'History', 'Historia')),
                if (a.history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr(context, 'Nothing accepted yet.', 'Ei vielä hyväksyntöjä.'),
                        style: TextStyle(fontSize: 13.5, color: textSecondary)),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground(context),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < a.history.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: AppTheme.subtleDivider(context)),
                          _historyRow(context, a.history[i], textPrimary, textSecondary),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _historyRow(BuildContext context, Map<String, dynamic> h, Color textPrimary, Color textSecondary) {
    final id = asInt(h['id']);
    final title = localized(context, h['title']) ?? '${h['doc'] ?? ''}';
    final privacy = h['doc'] == 'privacy';
    final when = agreementDate(context, h['acceptedAt']);
    final opening = id != null && _openingCopy == id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${privacy ? tr(context, 'Read', 'Luettu') : tr(context, 'Accepted', 'Hyväksytty')} $when · ${_methodText(context, h['method'])}',
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
                Text('${tr(context, 'Version', 'Versio')} ${h['version'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: textSecondary)),
              ],
            ),
          ),
          if (id != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: opening ? null : () => _openCopy(id),
              child: opening
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr(context, 'Open copy', 'Avaa kopio')),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppTheme.secondaryText(context))),
        ),
      );
}

class _DocumentCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRead;
  final VoidCallback onReview;
  final VoidCallback onReviewPending;
  const _DocumentCard({required this.item, required this.onRead, required this.onReview, required this.onReviewPending});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final privacy = item['doc'] == 'privacy';
    final accepted = item['accepted'] == true;
    final hasPending = item['pendingVersion'] != null;
    final pendingAccepted = item['pendingAccepted'] == true;
    final pendingDate = agreementDate(context, item['pendingEffectiveAt']);

    final IconData icon;
    final Color color;
    final String status;
    if (!accepted) {
      icon = privacy ? Icons.info_outline_rounded : Icons.error_outline_rounded;
      color = privacy ? AppTheme.secondaryText(context) : const Color(0xFFE08A00);
      status = privacy
          ? tr(context, 'Not marked as read yet', 'Ei vielä merkitty luetuksi')
          : tr(context, 'Needs your acceptance', 'Odottaa hyväksyntääsi');
    } else {
      icon = Icons.check_circle_rounded;
      color = const Color(0xFF248A52);
      final when = agreementDate(context, item['acceptedAt']);
      status = privacy ? tr(context, 'Read on $when', 'Luettu $when') : tr(context, 'Accepted on $when', 'Hyväksytty $when');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localized(context, item['title']) ?? '${item['doc']}', style: AppTheme.display(context, size: 18)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(status, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary))),
            ],
          ),
          if (hasPending) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(pendingAccepted ? Icons.event_available_rounded : Icons.event_rounded, size: 18, color: const Color(0xFFB86E00)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pendingAccepted
                        ? tr(context, 'New version accepted, in force from $pendingDate', 'Uusi versio hyväksytty, voimassa $pendingDate alkaen')
                        : tr(context, 'Update coming on $pendingDate', 'Päivitys tulossa $pendingDate'),
                    style: TextStyle(fontSize: 13.5, color: textPrimary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            privacy
                ? tr(context, 'For your information; nothing to consent to.', 'Tiedoksi; ei vaadi suostumusta.')
                : tr(context, 'Needed to place orders.', 'Tarvitaan tilaamiseen.'),
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onRead,
                child: Text(tr(context, 'Read', 'Lue')),
              ),
              if (!accepted)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onReview,
                  child: Text(privacy ? tr(context, 'Mark as read', 'Merkitse luetuksi') : tr(context, 'Review and accept', 'Lue ja hyväksy')),
                ),
              if (hasPending && !pendingAccepted)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onReviewPending,
                  child: Text(tr(context, 'Review the update', 'Tutustu päivitykseen')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context))),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
            ],
          ),
        ),
      );
}
