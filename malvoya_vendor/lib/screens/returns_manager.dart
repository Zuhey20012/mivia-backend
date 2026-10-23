import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../services/socket_service.dart';
import '../widgets/error_banner.dart';

/// Returns from customers: approve, confirm you received the items, then refund through Stripe.
class ReturnsManager extends StatefulWidget {
  const ReturnsManager({super.key});

  /// How many Returns screens are open (the dashboard shows no "new return" banner over this screen).
  static int openCount = 0;

  @override
  State<ReturnsManager> createState() => _ReturnsManagerState();
}

class _ReturnsManagerState extends State<ReturnsManager> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  StreamSubscription<Map<String, dynamic>>? _newReturns;

  @override
  void initState() {
    super.initState();
    ReturnsManager.openCount++;
    _load();
    // A new request while this screen is open appears at once
    _newReturns = VendorSocketService().returnsNew.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    ReturnsManager.openCount--;
    _newReturns?.cancel();
    super.dispose();
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

  static const _red = MPalette.red;

  /// [storeNote] is the store's own reason or note (API 2.10 keeps it apart from the customer's
  /// `conditionNote`; a rejection requires it). [conditionNote] is only sent for a refund deduction,
  /// which servers before 2.10 require to be explained there.
  Future<ApiResult> _send(Map<String, dynamic> r, String status, {String? storeNote, String? conditionNote, int? deduction}) =>
      _api.patch('/returns/${r['id']}/status', {
        'status': status,
        if (storeNote != null && storeNote.isNotEmpty) 'storeNote': storeNote,
        if (conditionNote != null && conditionNote.isNotEmpty) 'conditionNote': conditionNote,
        if (deduction != null && deduction > 0) 'damageDedCents': deduction,
      });

  Future<void> _update(Map<String, dynamic> r, String status, {String? storeNote}) async {
    HapticFeedback.mediumImpact();
    final res = await _send(r, status, storeNote: storeNote);
    if (!mounted) return;
    MSnack.show(context, res.ok ? tr(context, 'Updated', 'Päivitetty') : res.errorMessage);
    _load();
  }

  /// Rejecting needs a written reason (sent as `storeNote`; the customer gets it with the rejection). Consumers who bought from a
  /// business have a statutory 14-day right of withdrawal, so a rejection must have a real ground.
  Future<void> _reject(Map<String, dynamic> r) async {
    final reason = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final text = reason.text.trim();
          return AlertDialog(
            title: Text(tr(ctx, 'Reject this return?', 'Hylätäänkö palautus?')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  tr(ctx,
                      'Customers who bought from a business have a statutory 14-day right of withdrawal from delivery. Reject only with a real reason, for example the return period has passed or the item is not the one sold.',
                      'Yritykseltä ostaneella kuluttajalla on lakisääteinen 14 päivän peruuttamisoikeus toimituksesta. Hylkää vain todellisesta syystä, esimerkiksi jos palautusaika on päättynyt tai tuote ei ole myyty tuote.'),
                  style: const TextStyle(fontSize: MTextSize.label, height: 1.4, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: MSpace.md),
                TextField(
                  controller: reason,
                  autofocus: true,
                  maxLength: 500,
                  maxLines: 3,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(labelText: tr(ctx, 'Reason (required)', 'Syy (pakollinen)')),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(ctx, 'Back', 'Takaisin'))),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5), minimumSize: const Size(64, 48)),
                onPressed: text.length < 5 ? null : () => Navigator.pop(ctx, text),
                child: Text(tr(ctx, 'Reject', 'Hylkää')),
              ),
            ],
          );
        },
      ),
    );
    reason.dispose();
    if (note == null || !mounted) return;
    await _update(r, 'REJECTED', storeNote: note);
  }

  /// "12,50" or "12.50" → 1250 cents; null when empty, -1 when not a number.
  int? _cents(String text) {
    final t = text.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return v == null || v < 0 ? -1 : (v * 100).round();
  }

  Future<void> _refund(Map<String, dynamic> r) async {
    final note = TextEditingController();
    final deduction = TextEditingController();
    final whole = _returnedItems(r, ((r['order'] as Map?)?['items'] as List?) ?? const []).whole;
    final expected = _refundAmount(r);
    var busy = false;
    String? error;
    final done = await showMSheet<bool>(context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final ded = _cents(deduction.text);
          final finalCents = expected == null ? null : expected - (ded != null && ded > 0 ? ded : 0);

          Future<void> confirmAndSend() async {
            if (ded == -1) {
              setSheet(() => error = tr(ctx, 'Write the deduction as a number, e.g. 5,00.', 'Kirjoita vähennys numerona, esim. 5,00.'));
              return;
            }
            if (ded != null && ded > 0 && note.text.trim().isEmpty) {
              setSheet(() => error = tr(ctx, 'Explain the deduction in your note on the condition.', 'Perustele vähennys huomiossasi tuotteen kunnosta.'));
              return;
            }
            if (finalCents != null && finalCents <= 0) {
              setSheet(() => error = tr(ctx, 'The deduction cannot be the whole refund.', 'Vähennys ei voi olla koko hyvitys.'));
              return;
            }
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: Text(finalCents != null
                    ? tr(dctx, 'Refund ${euro(dctx, finalCents)} to the customer?', 'Hyvitetäänkö asiakkaalle ${euro(dctx, finalCents)}?')
                    : tr(dctx, 'Refund the customer?', 'Hyvitetäänkö asiakkaalle?')),
                content: Text(tr(dctx, 'The money goes back to the customer\'s card through Stripe. This cannot be undone.',
                    'Rahat palautetaan asiakkaan kortille Stripen kautta. Tätä ei voi perua.')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr(dctx, 'Back', 'Takaisin'))),
                  FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr(dctx, 'Refund', 'Hyvitä'))),
                ],
              ),
            );
            if (ok != true) return;
            setSheet(() {
              busy = true;
              error = null;
            });
            HapticFeedback.mediumImpact();
            final storeNote = note.text.trim();
            final hasDeduction = ded != null && ded > 0;
            var res = await _send(r, 'REFUNDED',
                storeNote: storeNote,
                conditionNote: hasDeduction && !_hasStoreNote(r) ? storeNote : null,
                deduction: hasDeduction ? ded : null);
            // A server that still wants the deduction explained in `conditionNote` refuses before refunding
            // anything, so sending it again that way is safe
            if (!res.ok && hasDeduction && _hasStoreNote(r) && res.data['error'] == 'Explain the deduction in the condition note') {
              res = await _send(r, 'REFUNDED', storeNote: storeNote, conditionNote: storeNote, deduction: ded);
            }
            if (!ctx.mounted) return;
            if (res.ok) {
              Navigator.pop(ctx, true);
            } else {
              setSheet(() {
                busy = false;
                error = res.errorMessage;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(ctx, 'Refund the customer', 'Hyvitä asiakkaalle'), style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w700)),
                  const SizedBox(height: MSpace.sm),
                  Text(
                    whole
                        ? tr(ctx,
                            'A full refund includes the original delivery fee. You may only deduct for wear beyond what was needed to try the item, and you must explain why.',
                            'Täysi hyvitys sisältää alkuperäisen toimitusmaksun. Voit vähentää vain, jos tuotetta on käsitelty enemmän kuin sen kokeilemiseksi on tarpeen, ja sinun on perusteltava vähennys.')
                        : tr(ctx,
                            'Only some items of the order are returned, so the refund covers those items. You may only deduct for wear beyond what was needed to try an item, and you must explain why.',
                            'Tilauksesta palautetaan vain osa, joten hyvitys koskee palautettuja tuotteita. Voit vähentää vain, jos tuotetta on käsitelty enemmän kuin sen kokeilemiseksi on tarpeen, ja sinun on perusteltava vähennys.'),
                    style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: MSpace.md),
                  TextField(
                    controller: deduction,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (_) => setSheet(() => error = null),
                    decoration: InputDecoration(labelText: tr(ctx, 'Deduction in € (optional)', 'Vähennys euroina (valinnainen)'), hintText: '0,00'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 500,
                    onChanged: (_) => setSheet(() => error = null),
                    decoration: InputDecoration(labelText: tr(ctx, 'Your note on the condition', 'Huomiosi tuotteen kunnosta')),
                  ),
                  if (finalCents != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MSpace.sm),
                      child: Row(children: [
                        Expanded(child: Text(tr(ctx, 'The customer gets', 'Asiakas saa'), style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(euro(ctx, finalCents < 0 ? 0 : finalCents), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title)),
                      ]),
                    ),
                  if (error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(MSpace.md),
                      decoration: BoxDecoration(color: MPalette.redLight, borderRadius: BorderRadius.circular(14)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline_rounded, color: _red, size: 20),
                        const SizedBox(width: MSpace.sm),
                        Expanded(child: Text(error!, style: const TextStyle(color: _red, fontWeight: FontWeight.w600, height: 1.35))),
                      ]),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: MButton(label: tr(ctx, 'Refund now', 'Hyvitä nyt'), loading: busy, onPressed: busy ? null : confirmAndSend),
                  ),
                ],
              ),
            ),
          );
        },
      ), isScrollControlled: true, useSafeArea: false);
    note.dispose();
    deduction.dispose();
    if (!mounted) return;
    if (done == true) {
      MSnack.show(context, tr(context, 'Refund sent', 'Hyvitys lähetetty'));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Returns', 'Palautukset'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const MSkeletonList(lines: 4, button: true)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(MSpace.lg),
                children: [
                  if (_error != null && _returns.isEmpty) MStateMessage.error(scrollable: false, top: 56, message: _error, onRetry: _retry),
                  if (_error != null && _returns.isNotEmpty) ErrorBanner(message: _error!, onRetry: _retry),
                  if (_returns.isEmpty && _error == null)
                    MStateMessage(scrollable: false, top: 56, icon: Icons.assignment_return_outlined,
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
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(MRadius.xs)),
            child: Text('$qty×', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (unitCents != null)
            Padding(
              padding: const EdgeInsets.only(left: MSpace.sm),
              child: Text('${euro(context, unitCents)} ${tr(context, 'each', '/ kpl')}', style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
            ),
        ]),
      );

  /// Servers from API 2.10 send `storeNote` (null or text) on every return.
  bool _hasStoreNote(Map<String, dynamic> r) => r.containsKey('storeNote');

  /// The customer's note and the store's note, each with who wrote it. Older servers keep a single
  /// `conditionNote` that either side may have written, so it is shown without a name.
  List<Widget> _notes(Map<String, dynamic> r) {
    final customer = '${r['conditionNote'] ?? ''}'.trim();
    final store = '${r['storeNote'] ?? ''}'.trim();
    if (!_hasStoreNote(r)) {
      return [if (customer.isNotEmpty) Text('“$customer”', style: const TextStyle(fontStyle: FontStyle.italic))];
    }
    Widget note(String who, String text, Color bg) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: MSpace.sm),
          padding: const EdgeInsets.fromLTRB(MSpace.md, MSpace.sm, MSpace.md, 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who, style: const TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w800, color: AppTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(height: 1.35, color: AppTheme.textPrimary)),
          ]),
        );
    return [
      if (customer.isNotEmpty) note(tr(context, "Customer's note", 'Asiakkaan viesti'), customer, AppTheme.sand),
      if (store.isNotEmpty)
        note(r['status'] == 'REJECTED' ? tr(context, 'Your reason for rejecting', 'Hylkäyksen syy') : tr(context, 'Your note', 'Sinun huomiosi'), store,
            AppTheme.primaryLight),
    ];
  }

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
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(MSpace.lg),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.md), border: Border.all(color: AppTheme.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${tr(context, 'Order', 'Tilaus')} #${order['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL)),
            const Spacer(),
            Text(statusLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: MTextSize.caption)),
          ]),
          Text(reasons[r['reason']] ?? '${r['reason']}', style: const TextStyle(color: AppTheme.textSecondary)),
          ..._notes(r),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.only(bottom: MSpace.sm),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.xs),
            decoration: BoxDecoration(color: returned.whole ? AppTheme.sand : AppTheme.sunshineLight, borderRadius: BorderRadius.circular(MRadius.sm)),
            child: Text(
              returned.whole
                  ? tr(context, 'Whole order returned', 'Koko tilaus palautetaan')
                  : tr(context, 'Part of the order: ${returned.returnedCount} of ${returned.orderCount} items',
                      'Osa tilauksesta: ${returned.returnedCount}/${returned.orderCount} tuotetta'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.caption, color: returned.whole ? AppTheme.textPrimary : MPalette.amberInk),
            ),
          ),
          ...returned.lines,
          if (_refundAmount(r) != null)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.xs),
              child: Row(children: [
                Text(status == 'REFUNDED' ? tr(context, 'Refunded', 'Hyvitetty') : tr(context, 'Refund', 'Hyvitys'),
                    style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(euro(context, _refundAmount(r)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
              ]),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'REQUESTED') ...[
                FilledButton(onPressed: () => _update(r, 'APPROVED'), child: Text(tr(context, 'Approve', 'Hyväksy'))),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5)),
                  onPressed: () => _reject(r),
                  child: Text(tr(context, 'Reject', 'Hylkää')),
                ),
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
