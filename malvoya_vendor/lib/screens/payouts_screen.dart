import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/reauth.dart';
import '../core/strings.dart';
import '../widgets/error_banner.dart';

/// Payouts through Stripe. Stripe collects identity and bank details on its own pages, so
/// none of it passes through this app.
class PayoutsScreen extends StatefulWidget {
  /// The store's commission (fraction of the item price) from /stores/my; 0 = none, null = not known.
  final num? commissionRate;
  const PayoutsScreen({super.key, this.commissionRate});

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

  void _retry() {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    _load();
  }

  Future<void> _open(String path) async {
    HapticFeedback.selectionClick();
    setState(() => _opening = true);
    var res = await _api.post(path);
    if (!mounted) return;
    // API 2.16: payout links need the password (or a two-step code) again within 10 minutes, unless
    // this session passed two-step sign-in. Ask once, then repeat the request.
    if (isReauthRequired(res)) {
      setState(() => _opening = false);
      final confirmed = await confirmIdentity(context, Provider.of<AuthService>(context, listen: false));
      if (!confirmed || !mounted) return;
      setState(() => _opening = true);
      res = await _api.post(path);
      if (!mounted) return;
    }
    setState(() => _opening = false);
    final url = res.data['url'];
    if (!res.ok || url is! String || url.isEmpty) {
      MSnack.show(context, res.ok ? tr(context, 'Stripe did not return a link. Please try again.', 'Stripe ei palauttanut linkkiä. Yritä uudelleen.') : res.errorMessage);
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _status?['payoutsEnabled'] == true;
    final hasAccount = _status?['hasAccount'] == true;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Payouts', 'Tilitykset'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const MSkeletonList(count: 3, lines: 5, button: true)
            : _error != null && _status == null
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [MStateMessage.error(scrollable: false, top: 56, message: _error, onRetry: _retry)])
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(MSpace.lg),
                    children: [
                      if (_error != null) ErrorBanner(message: _error!, onRetry: _retry),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
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
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL),
                                ),
                              ),
                            ]),
                            const SizedBox(height: MSpace.sm),
                            Text(
                              tr(
                                  context,
                                  'Malvoya sends each sale to your Stripe account 15 days after delivery, when the 14-day return window has passed, and Stripe pays it into your bank account. ${hasCommission(widget.commissionRate) ? 'Malvoya keeps a commission of ${commissionText(widget.commissionRate)} of the item price (not of the delivery fee); refunds are deducted.' : commissionKnown(widget.commissionRate) ? 'Malvoya takes no commission: you receive the full item price; refunds are deducted.' : 'Malvoya keeps the commission set out in the Seller Terms (not of the delivery fee); refunds are deducted.'} Stripe checks your identity (EU anti-money-laundering rules).',
                                  'Malvoya siirtää jokaisen myynnin Stripe-tilillesi 15 päivää toimituksen jälkeen, kun 14 päivän palautusaika on päättynyt, ja Stripe maksaa sen pankkitilillesi. ${hasCommission(widget.commissionRate) ? 'Malvoya pidättää provisiona ${commissionText(widget.commissionRate)} tuotteiden hinnasta (ei toimitusmaksusta); hyvitykset vähennetään.' : commissionKnown(widget.commissionRate) ? 'Malvoya ei peri provisiota: saat tuotteiden koko hinnan; hyvitykset vähennetään.' : 'Malvoya pidättää myyjän ehdoissa sovitun provision (ei toimitusmaksusta); hyvitykset vähennetään.'} Stripe tarkistaa henkilöllisyytesi (EU:n rahanpesulainsäädäntö).'),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.label, height: 1.4),
                            ),
                            if (!enabled && (asInt(_status?['requirementsDue']) ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(tr(context, 'Stripe still needs ${_status!['requirementsDue']} detail(s) from you.', 'Stripe tarvitsee vielä ${_status!['requirementsDue']} tietoa.'),
                                    style: const TextStyle(color: AppTheme.accent, fontSize: MTextSize.label)),
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
                        const SizedBox(height: MSpace.lg),
                        Row(children: [
                          _stat(tr(context, 'Sent to Stripe', 'Siirretty Stripeen'), _summary!['paidCents']),
                          const SizedBox(width: 10),
                          _stat(tr(context, 'Coming', 'Tulossa'), (asInt(_summary!['scheduledCents']) ?? 0) + (asInt(_summary!['waitingForAccountCents']) ?? 0)),
                        ]),
                      ],
                      const SizedBox(height: MSpace.lg),
                      if (_payouts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: MSpace.xxl),
                          child: Text(tr(context, 'No payouts yet. Each sale is listed here with its payout date.', 'Ei vielä tilityksiä. Jokainen myynti näkyy täällä tilityspäivineen.'),
                              textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
                        ),
                      for (final p in _payouts) _row(p),
                    ],
                  ),
      ),
    );
  }

  Widget _stat(String label, dynamic cents) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.md), border: Border.all(color: AppTheme.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.caption)),
            Text(euro(context, cents), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.displayS)),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> p) {
    final release = DateTime.tryParse('${p['releaseAt']}')?.toLocal();
    final label = switch (p['status']) {
      'PAID' => tr(context, 'Sent to your Stripe account', 'Siirretty Stripe-tilillesi'),
      'SCHEDULED' => release != null ? tr(context, 'Pays on ${release.day}.${release.month}.', 'Maksetaan ${release.day}.${release.month}.') : tr(context, 'Scheduled', 'Ajastettu'),
      'WAITING_FOR_ACCOUNT' => tr(context, 'Waiting for payout setup', 'Odottaa tilitysten käyttöönottoa'),
      'CANCELLED' => tr(context, 'Cancelled (refunded)', 'Peruttu (hyvitetty)'),
      _ => tr(context, 'Failed — the Malvoya team will look into it', 'Epäonnistui — Malvoyan tiimi selvittää asian'),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.xs),
      title: Text('${tr(context, 'Order', 'Tilaus')} #${p['orderId']}'),
      subtitle: Text(label),
      trailing: Text(euro(context, p['amountCents']), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
