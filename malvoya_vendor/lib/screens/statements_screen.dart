import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/loading_states.dart';

/// Monthly statement (GET /stores/my/statements?month=YYYY-MM): every order delivered or collected in
/// the month, with sales, refunds, commission and payout. Shown in the app; the printable HTML version
/// needs the sign-in token, so it is not opened in a browser.
class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key});

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  bool get _isCurrentMonth => _month.year == DateTime.now().year && _month.month == DateTime.now().month;

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
    final key = _monthKey;
    final res = await _api.get('/stores/my/statements', query: {'month': key});
    if (!mounted || key != _monthKey) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.errorMessage;
      _data = res.ok ? res.data : null;
    });
  }

  void _shift(int months) {
    HapticFeedback.selectionClick();
    final next = DateTime(_month.year, _month.month + months);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    setState(() => _month = next);
    _load();
  }

  String _monthName() {
    const fi = ['tammikuu', 'helmikuu', 'maaliskuu', 'huhtikuu', 'toukokuu', 'kesäkuu', 'heinäkuu', 'elokuu', 'syyskuu', 'lokakuu', 'marraskuu', 'joulukuu'];
    const en = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final names = isFinnish(context) ? fi : en;
    final name = names[_month.month - 1];
    return '${isFinnish(context) ? name[0].toUpperCase() + name.substring(1) : name} ${_month.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Monthly statements', 'Kuukausiraportit'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
              child: Row(children: [
                IconButton(
                  tooltip: tr(context, 'Previous month', 'Edellinen kuukausi'),
                  icon: const Icon(Icons.chevron_left_rounded),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => _shift(-1),
                ),
                Expanded(child: Text(_monthName(), textAlign: TextAlign.center, style: AppTheme.display(size: 18))),
                IconButton(
                  tooltip: tr(context, 'Next month', 'Seuraava kuukausi'),
                  icon: const Icon(Icons.chevron_right_rounded),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _isCurrentMonth ? null : () => _shift(1),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading) ...[for (var i = 0; i < 2; i++) const SkeletonCard(lines: 4)],
            if (!_loading && _error != null) ErrorState(message: _error, onRetry: _load, top: 24),
            if (!_loading && _error == null && _data != null) ..._content(_data!),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> data) {
    final totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals']) : <String, dynamic>{};
    final orders = ((data['orders'] as List?) ?? const []).whereType<Map>().toList();
    final sent = asInt(totals['payoutsSentCents']) ?? 0;
    final pending = asInt(totals['payoutsPendingCents']) ?? 0;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2), border: Border.all(color: AppTheme.divider)),
        child: Column(children: [
          _line(tr(context, 'Sales', 'Myynti'), euro(context, totals['salesCents'])),
          _line(tr(context, 'Refunds (returned goods)', 'Hyvitykset (palautetut tuotteet)'), '−${euro(context, totals['refundsCents'])}'),
          _line(tr(context, 'Malvoya commission', 'Malvoyan provisio'), '−${euro(context, totals['commissionCents'])}'),
          const Divider(height: 20),
          _line(tr(context, 'Payouts', 'Tilitykset'), euro(context, sent + pending), bold: true),
          _line(tr(context, '· sent to Stripe', '· siirretty Stripeen'), euro(context, sent)),
          _line(tr(context, '· still to come', '· tulossa'), euro(context, pending)),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        tr(context,
            'Orders delivered or collected in this month (Finnish time). Sales are at full item prices: Malvoya pays for promo-code discounts. Delivery fees and tips are not your sales. This is a summary for your records, not a VAT invoice.',
            'Tässä kuussa toimitetut tai noudetut tilaukset (Suomen aikaa). Myynti on tuotteiden täysi hinta: Malvoya maksaa tarjouskoodien alennukset. Toimitusmaksut ja tipit eivät ole myyntiäsi. Tämä on yhteenveto kirjanpitoasi varten, ei ALV-lasku.'),
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 16),
      Text(tr(context, 'Orders', 'Tilaukset'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 8),
      if (orders.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(tr(context, 'No orders were delivered in this month.', 'Tässä kuussa ei toimitettu tilauksia.'),
              textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
        ),
      for (final o in orders) _orderRow(o),
      if (data['truncated'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr(context, 'Only the first 5000 orders are listed.', 'Vain 5000 ensimmäistä tilausta näytetään.'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ),
    ];
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? AppTheme.textPrimary : AppTheme.textSecondary))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w700, fontSize: bold ? 17 : 14)),
        ]),
      );

  Widget _orderRow(Map o) {
    final delivered = DateTime.tryParse('${o['deliveredAt'] ?? ''}')?.toLocal();
    final refunds = asInt(o['refundsCents']) ?? 0;
    final status = switch ('${o['payoutStatus'] ?? ''}') {
      'PAID' => tr(context, 'Paid', 'Maksettu'),
      'SCHEDULED' => tr(context, 'Scheduled', 'Ajastettu'),
      'WAITING_FOR_ACCOUNT' => tr(context, 'Waiting for payout setup', 'Odottaa tilitysten käyttöönottoa'),
      'FAILED' => tr(context, 'Failed — Malvoya retries', 'Epäonnistui — Malvoya yrittää uudelleen'),
      'CANCELLED' => tr(context, 'None (refunded)', 'Ei tilitystä (hyvitetty)'),
      _ => tr(context, 'Pending', 'Odottaa'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr(context, 'Order', 'Tilaus')} #${o['id']}${delivered != null ? ' · ${delivered.day}.${delivered.month}.' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              [
                '${tr(context, 'Sales', 'Myynti')} ${euro(context, o['itemsCents'])}',
                if (refunds > 0) '${tr(context, 'refunds', 'hyvitykset')} −${euro(context, refunds)}',
                '${tr(context, 'commission', 'provisio')} −${euro(context, o['commissionCents'])}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            Text(status, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(euro(context, o['payoutCents']), style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
