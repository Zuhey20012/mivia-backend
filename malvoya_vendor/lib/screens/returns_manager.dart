import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/loading_states.dart';

/// Returns from customers: approve, confirm you received the items, then refund through Stripe.
class ReturnsManager extends StatefulWidget {
  const ReturnsManager({super.key});

  @override
  State<ReturnsManager> createState() => _ReturnsManagerState();
}

class _ReturnsManagerState extends State<ReturnsManager> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _api.get('/returns');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok) _returns = ((res.data['returns'] as List?) ?? []).map((r) => Map<String, dynamic>.from(r)).toList();
    });
  }

  Future<void> _update(Map<String, dynamic> r, String status, {String? note, int? deduction}) async {
    HapticFeedback.mediumImpact();
    final res = await _api.patch('/returns/${r['id']}/status', {
      'status': status,
      if (note != null && note.isNotEmpty) 'conditionNote': note,
      if (deduction != null && deduction > 0) 'damageDedCents': deduction,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.ok ? tr(context, 'Updated', 'Päivitetty') : res.error!)));
    _load();
  }

  Future<void> _refund(Map<String, dynamic> r) async {
    final note = TextEditingController();
    final deduction = TextEditingController();
    final whole = _returnedItems(r, ((r['order'] as Map?)?['items'] as List?) ?? const []).whole;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Refund the customer', 'Hyvitä asiakkaalle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              whole
                  ? tr(context,
                      'A full refund includes the original delivery fee. You may only deduct for wear beyond what was needed to try the item, and you must explain why.',
                      'Täysi hyvitys sisältää alkuperäisen toimitusmaksun. Voit vähentää vain, jos tuotetta on käsitelty enemmän kuin sen kokeilemiseksi on tarpeen, ja sinun on perusteltava vähennys.')
                  : tr(context,
                      'Only some items of the order are returned, so the refund covers those items. You may only deduct for wear beyond what was needed to try an item, and you must explain why.',
                      'Tilauksesta palautetaan vain osa, joten hyvitys koskee palautettuja tuotteita. Voit vähentää vain, jos tuotetta on käsitelty enemmän kuin sen kokeilemiseksi on tarpeen, ja sinun on perusteltava vähennys.'),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
            if (_refundAmount(r) != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('${tr(context, 'Refund for this return', 'Tämän palautuksen hyvitys')}: ${euro(context, _refundAmount(r))}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            TextField(controller: deduction, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'Deduction in € (optional)', 'Vähennys euroina (valinnainen)'))),
            TextField(controller: note, maxLength: 500, decoration: InputDecoration(labelText: tr(context, 'Condition note', 'Kuntohuomio'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'Refund now', 'Hyvitä nyt')))),
          ],
        ),
      ),
    );
    if (go != true) return;
    final ded = double.tryParse(deduction.text.trim().replaceAll(',', '.'));
    await _update(r, 'REFUNDED', note: note.text.trim(), deduction: ded == null ? null : (ded * 100).round());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Returns', 'Palautukset'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const SkeletonList(lines: 4, button: true)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null && _returns.isEmpty) ErrorState(message: _error, onRetry: _retry),
                  if (_error != null && _returns.isNotEmpty) ErrorBanner(message: _error!, onRetry: _retry),
                  if (_returns.isEmpty && _error == null)
                    EmptyState(
                      icon: Icons.assignment_return_outlined,
                      message: tr(context, 'No returns. Customers can return items from businesses within 14 days of delivery.',
                          'Ei palautuksia. Asiakkaat voivat palauttaa yrityksiltä ostettuja tuotteita 14 päivän kuluessa toimituksesta.'),
                    ),
                  for (final r in _returns) _card(r),
                ],
              ),
      ),
    );
  }

  void _retry() {
    HapticFeedback.selectionClick();
    setState(() => _loading = true);
    _load();
  }

  /// What was refunded, or before that what refunding now gives back (`expectedRefundCents` on newer
  /// servers). Null when the server does not say.
  int? _refundAmount(Map<String, dynamic> r) =>
      r['status'] == 'REFUNDED' ? asInt(r['refundCents']) : asInt(r['expectedRefundCents'] ?? r['refundCents']);

  String _variantText(Map? variant) {
    if (variant == null) return '';
    final parts = [variant['size'], variant['color']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    return parts.isEmpty ? '' : ' ($parts)';
  }

  /// The returned lines. Newer servers send `items` per return (part of an order can be returned);
  /// older ones do not, and then the whole order is being returned.
  ({List<Widget> lines, bool whole, int returnedCount, int orderCount}) _returnedItems(Map<String, dynamic> r, List orderItems) {
    final returned = ((r['items'] as List?) ?? const []).whereType<Map>().toList();
    final orderCount = orderItems.whereType<Map>().fold<int>(0, (s, i) => s + (asInt(i['quantity']) ?? 1));
    if (returned.isEmpty) {
      return (
        lines: [
          for (final i in orderItems.whereType<Map>())
            _line(asInt(i['quantity']) ?? 1, '${i['product']?['name'] ?? ''}${_variantText(i['variant'] as Map?)}', asInt(i['unitCents'])),
        ],
        whole: true,
        returnedCount: orderCount,
        orderCount: orderCount,
      );
    }
    final byId = {for (final i in orderItems.whereType<Map>().where((i) => i['id'] != null)) '${i['id']}': i};
    final returnedQty = <String, int>{};
    final lines = <Widget>[];
    for (final it in returned) {
      final id = '${it['orderItemId']}';
      final qty = asInt(it['quantity']) ?? 1;
      returnedQty[id] = (returnedQty[id] ?? 0) + qty;
      final orderItem = byId[id];
      final name = '${it['name'] ?? orderItem?['product']?['name'] ?? ''}';
      lines.add(_line(qty, '$name${_variantText(orderItem?['variant'] as Map?)}', asInt(it['unitCents'])));
    }
    final returnedCount = returnedQty.values.fold<int>(0, (s, q) => s + q);
    // Whole order when every line of the order comes back in full (if the order lines are known)
    final whole = byId.isNotEmpty
        ? byId.entries.every((e) => (returnedQty[e.key] ?? 0) >= (asInt(e.value['quantity']) ?? 1))
        : false;
    return (lines: lines, whole: whole, returnedCount: returnedCount, orderCount: orderCount);
  }

  Widget _line(int qty, String name, int? unitCents) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
            child: Text('$qty×', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (unitCents != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('${euro(context, unitCents)} ${tr(context, 'each', '/ kpl')}', style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ),
        ]),
      );

  Widget _card(Map<String, dynamic> r) {
    final order = (r['order'] as Map?) ?? {};
    final items = (order['items'] as List?) ?? [];
    final status = r['status'];
    final returned = _returnedItems(r, items);
    final statusLabel = switch (status) {
      'REQUESTED' => tr(context, 'New request', 'Uusi pyyntö'),
      'APPROVED' => tr(context, 'Approved', 'Hyväksytty'),
      'IN_TRANSIT' => tr(context, 'On its way back', 'Matkalla takaisin'),
      'RECEIVED' => tr(context, 'Received', 'Vastaanotettu'),
      'REFUNDED' => tr(context, 'Refunded', 'Hyvitetty'),
      'REJECTED' => tr(context, 'Rejected', 'Hylätty'),
      _ => '${status ?? ''}',
    };
    final reasons = {
      'WRONG_ITEM': tr(context, 'Wrong item', 'Väärä tuote'),
      'DAMAGED_ON_ARRIVAL': tr(context, 'Damaged on arrival', 'Vaurioitunut'),
      'NOT_AS_DESCRIBED': tr(context, 'Not as described', 'Ei vastannut kuvausta'),
      'CHANGED_MIND': tr(context, 'Changed mind', 'Muutti mieltään'),
      'OTHER': tr(context, 'Other', 'Muu'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${tr(context, 'Order', 'Tilaus')} #${order['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            Text(statusLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 12)),
          ]),
          Text(reasons[r['reason']] ?? '${r['reason']}', style: const TextStyle(color: AppTheme.textSecondary)),
          if (r['conditionNote'] != null) Text('“${r['conditionNote']}”', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: returned.whole ? AppTheme.sand : AppTheme.sunshineLight, borderRadius: BorderRadius.circular(12)),
            child: Text(
              returned.whole
                  ? tr(context, 'Whole order returned', 'Koko tilaus palautetaan')
                  : tr(context, 'Part of the order: ${returned.returnedCount} of ${returned.orderCount} items',
                      'Osa tilauksesta: ${returned.returnedCount}/${returned.orderCount} tuotetta'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: returned.whole ? AppTheme.textPrimary : const Color(0xFF6A4500)),
            ),
          ),
          ...returned.lines,
          if (_refundAmount(r) != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text(status == 'REFUNDED' ? tr(context, 'Refunded', 'Hyvitetty') : tr(context, 'Refund', 'Hyvitys'),
                    style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(euro(context, _refundAmount(r)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'REQUESTED') ...[
                FilledButton(onPressed: () => _update(r, 'APPROVED'), child: Text(tr(context, 'Approve', 'Hyväksy'))),
                OutlinedButton(onPressed: () => _update(r, 'REJECTED'), child: Text(tr(context, 'Reject', 'Hylkää'))),
              ],
              if (status == 'APPROVED' || status == 'IN_TRANSIT')
                FilledButton(onPressed: () => _update(r, 'RECEIVED'), child: Text(tr(context, 'I received the items', 'Sain tuotteet'))),
              if (status == 'RECEIVED') FilledButton(onPressed: () => _refund(r), child: Text(tr(context, 'Refund', 'Hyvitä'))),
            ],
          ),
        ],
      ),
    );
  }
}
