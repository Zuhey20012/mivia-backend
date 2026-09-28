import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';

/// Payouts through Stripe. Stripe collects identity and bank details on its own pages, so
/// none of it passes through this app.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _payouts = [];
  bool _loading = true;
  bool _opening = false;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Stripe's pages: check whether payouts are now switched on
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([_api.get('/payouts/status'), _api.get('/payouts')]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = results[0].ok ? null : results[0].error;
      if (results[0].ok) _status = results[0].data;
      if (results[1].ok) {
        _summary = Map<String, dynamic>.from(results[1].data['summary'] ?? {});
        _payouts = ((results[1].data['payouts'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
      }
    });
  }

  Future<void> _open(String path) async {
    setState(() => _opening = true);
    final res = await _api.post(path);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    await launchUrl(Uri.parse(res.data['url']), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _status?['payoutsEnabled'] == true;
    final hasAccount = _status?['hasAccount'] == true;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Earnings and payouts', 'Ansiot ja tilitykset'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppTheme.accent))),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(enabled ? Icons.check_circle_rounded : Icons.account_balance_outlined, color: enabled ? AppTheme.primary : AppTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              enabled
                                  ? tr(context, 'Payouts are on', 'Tilitykset ovat päällä')
                                  : hasAccount
                                      ? tr(context, 'Finish your payout setup', 'Viimeistele tilitysten käyttöönotto')
                                      : tr(context, 'Set up payouts to get paid', 'Ota tilitykset käyttöön saadaksesi rahat'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          tr(context,
                              'Stripe pays your delivery earnings into your bank account right after each delivery. Stripe checks your identity (EU anti-money-laundering rules). You handle your own taxes as a light entrepreneur or through your company.',
                              'Stripe maksaa toimituspalkkiot pankkitilillesi heti jokaisen toimituksen jälkeen. Stripe tarkistaa henkilöllisyytesi (EU:n rahanpesulainsäädäntö). Hoidat verosi itse kevytyrittäjänä tai yrityksesi kautta.'),
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        if (!enabled && (asInt(_status?['requirementsDue']) ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(tr(context, 'Stripe still needs ${_status!['requirementsDue']} detail(s) from you.', 'Stripe tarvitsee vielä ${_status!['requirementsDue']} tietoa.'),
                                style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
                          ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _opening ? null : () => _open(enabled ? '/payouts/dashboard' : '/payouts/onboarding'),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: Text(enabled ? tr(context, 'Open Stripe dashboard', 'Avaa Stripe-hallinta') : tr(context, 'Set up payouts with Stripe', 'Ota tilitykset käyttöön Stripessä')),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_summary != null) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      _stat(tr(context, 'Paid out', 'Maksettu'), _summary!['paidCents']),
                      const SizedBox(width: 10),
                      _stat(tr(context, 'Coming', 'Tulossa'), (asInt(_summary!['scheduledCents']) ?? 0) + (asInt(_summary!['waitingForAccountCents']) ?? 0)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  for (final p in _payouts) _row(p),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, dynamic cents) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
            Text(euro(context, cents), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> p) {
    final release = DateTime.tryParse('${p['releaseAt']}')?.toLocal();
    final label = switch (p['status']) {
      'PAID' => tr(context, 'Paid', 'Maksettu'),
      'SCHEDULED' => release != null ? tr(context, 'Pays on ${release.day}.${release.month}.', 'Maksetaan ${release.day}.${release.month}.') : tr(context, 'Scheduled', 'Ajastettu'),
      'WAITING_FOR_ACCOUNT' => tr(context, 'Waiting for payout setup', 'Odottaa tilitysten käyttöönottoa'),
      'CANCELLED' => tr(context, 'Cancelled (refunded)', 'Peruttu (hyvitetty)'),
      _ => tr(context, 'Failed — we will retry', 'Epäonnistui — yritämme uudelleen'),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text('${tr(context, 'Order', 'Tilaus')} #${p['orderId']}'),
      subtitle: Text(label),
      trailing: Text(euro(context, p['amountCents']), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
