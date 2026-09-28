import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';

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
              tr(context,
                  'A full refund includes the original delivery fee. You may only deduct for wear beyond what was needed to try the item, and you must explain why.',
                  'Täysi hyvitys sisältää alkuperäisen toimitusmaksun. Voit vähentää vain, jos tuotetta on käsitelty enemmän kuin sen kokeilemiseksi on tarpeen, ja sinun on perusteltava vähennys.'),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.accent)),
                  if (_returns.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Text(tr(context, 'No returns. Customers can return items from businesses within 14 days of delivery.', 'Ei palautuksia. Asiakkaat voivat palauttaa yrityksiltä ostettuja tuotteita 14 päivän kuluessa toimituksesta.'),
                          textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
                    ),
                  for (final r in _returns) _card(r),
                ],
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final order = (r['order'] as Map?) ?? {};
    final items = (order['items'] as List?) ?? [];
    final status = r['status'];
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
            Text(status, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 12)),
          ]),
          Text(reasons[r['reason']] ?? '${r['reason']}', style: const TextStyle(color: AppTheme.textSecondary)),
          if (r['conditionNote'] != null) Text('“${r['conditionNote']}”', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          for (final i in items)
            Text('${i['quantity']}× ${i['product']?['name'] ?? ''}${i['variant'] != null ? ' (${[i['variant']['size'], i['variant']['color']].where((x) => x != null).join(' · ')})' : ''}'),
          if (r['refundCents'] != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr(context, 'Refunded', 'Hyvitetty')} ${euro(context, r['refundCents'])}', style: const TextStyle(fontWeight: FontWeight.w700))),
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
