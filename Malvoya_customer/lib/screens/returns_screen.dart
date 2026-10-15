import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/skeleton.dart';

/// Returns. Purchases from business sellers have the 14-day right of withdrawal (Kuluttajansuojalaki
/// 6 luku); purchases from private sellers do not, but a request can still be sent to the seller.
/// The customer can return the whole order or pick items and quantities. Everything shown here
/// comes from the server; nothing is stored only on the phone.
class ReturnsScreen extends StatefulWidget {
  /// Opens the return sheet for this order straight away (from the order page).
  final Map<String, dynamic>? order;
  const ReturnsScreen({super.key, this.order});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

Map<String, String> _reasons(BuildContext context) => {
      'CHANGED_MIND': tr(context, 'Changed my mind', 'Muutin mieleni'),
      'WRONG_ITEM': tr(context, 'Wrong item', 'Väärä tuote'),
      'DAMAGED_ON_ARRIVAL': tr(context, 'Arrived damaged', 'Saapui vaurioituneena'),
      'NOT_AS_DESCRIBED': tr(context, 'Not as described', 'Ei vastaa kuvausta'),
      'OTHER': tr(context, 'Other', 'Muu syy'),
    };

Map<String, String> _statusLabels(BuildContext context) => {
      'REQUESTED': tr(context, 'Requested', 'Pyydetty'),
      'APPROVED': tr(context, 'Approved', 'Hyväksytty'),
      'IN_TRANSIT': tr(context, 'On its way back', 'Matkalla takaisin'),
      'RECEIVED': tr(context, 'Received by the store', 'Kauppa vastaanotti'),
      'REFUNDED': tr(context, 'Refunded', 'Hyvitetty'),
      'REJECTED': tr(context, 'Rejected', 'Hylätty'),
    };

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame: the messages are localised, which needs the context
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted && widget.order != null && _error == null) _startReturn(preselected: widget.order);
    });
  }

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() {
        _loading = false;
        _error = tr(context, 'Sign in to see your returns.', 'Kirjaudu sisään nähdäksesi palautukset.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.get('/returns');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _returns = ((res.data['returns'] as List?) ?? []).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
      } else {
        _error = res.errorText(context) ?? tr(context, 'Could not load returns.', 'Palautuksia ei voitu ladata.');
      }
    });
  }

  // ── What can still be returned ──────────────────────────────────────────

  /// Order lines; `_key` is the line id (orderItemId), or a stand-in on older servers without ids.
  List<Map<String, dynamic>> _items(Map<String, dynamic> order) {
    final lines = ((order['items'] as List?) ?? []).whereType<Map>().toList();
    return [
      for (var n = 0; n < lines.length; n++) {...Map<String, dynamic>.from(lines[n]), '_key': asInt(lines[n]['id']) ?? -(n + 1)},
    ];
  }

  /// The server takes item-level returns: newer order payloads carry `fulfilment` and line ids.
  bool _itemReturnsSupported(Map<String, dynamic> order) {
    final items = _items(order);
    return items.isNotEmpty && items.every((i) => asInt(i['id']) != null) && (order.containsKey('fulfilment') || _returns.any((r) => r['items'] is List));
  }

  /// Quantity of each order line still returnable: bought − what open or finished returns cover.
  /// A return without item rows (made before item returns existed) covers the whole order.
  Map<int, int> _remaining(Map<String, dynamic> order) {
    final orderId = asInt(order['id']);
    final items = _items(order);
    final left = {for (final i in items) i['_key'] as int: asInt(i['quantity']) ?? 0};
    for (final r in _returns) {
      if (asInt(r['orderId']) != orderId || r['status'] == 'REJECTED') continue;
      final lines = (r['items'] as List?) ?? const [];
      if (lines.isEmpty) return {for (final k in left.keys) k: 0};
      for (final l in lines.whereType<Map>()) {
        final id = asInt(l['orderItemId']);
        if (id != null && left.containsKey(id)) left[id] = math.max(0, left[id]! - (asInt(l['quantity']) ?? 0));
      }
    }
    return left;
  }

  bool _hasSomethingLeft(Map<String, dynamic> order) => _remaining(order).values.any((q) => q > 0);

  /// Delivered orders still inside the 14-day window with something left to return, newest first.
  Future<(List<Map<String, dynamic>>, String?)> _eligibleOrders() async {
    final res = await _api.get('/orders');
    if (!mounted) return (const <Map<String, dynamic>>[], null);
    if (!res.ok) return (const <Map<String, dynamic>>[], res.errorText(context));
    final orders = ((res.data['orders'] as List?) ?? []).whereType<Map>().map((o) => Map<String, dynamic>.from(o));
    return (
      orders.where((o) {
        if (o['status'] != 'DELIVERED' || o['deliveredAt'] == null) return false;
        final delivered = DateTime.tryParse(o['deliveredAt'].toString());
        return delivered != null && DateTime.now().difference(delivered).inDays < 14 && _hasSomethingLeft(o);
      }).toList(),
      null,
    );
  }

  /// The refund the customer can expect, mirroring the server's default refund:
  /// some items → Σ unit price × quantity less the order discount in proportion;
  /// the return that completes the order → also the delivery, service and small-order fees.
  ({int goods, int discountShare, int fees, bool completes, int total}) _estimate(Map<String, dynamic> order, Map<int, int> picked) {
    final items = _items(order);
    final byId = {for (final i in items) i['_key'] as int: i};
    var goods = 0;
    var pickedQty = 0;
    picked.forEach((id, q) {
      goods += (asInt(byId[id]?['unitCents']) ?? 0) * q;
      pickedQty += q;
    });
    final left = _remaining(order).values.fold<int>(0, (s, q) => s + q);
    final completes = pickedQty > 0 && pickedQty >= left;
    final subtotal = asInt(order['subtotalCents']) ?? items.fold<int>(0, (s, i) => s + (asInt(i['unitCents']) ?? 0) * (asInt(i['quantity']) ?? 0));
    final discount = asInt(order['discountCents']) ?? 0;
    final share = subtotal > 0 ? (discount * goods / subtotal).round() : 0;
    final fees = completes ? (asInt(order['deliveryFeeCents']) ?? 0) + (asInt(order['serviceFeeCents']) ?? 0) + (asInt(order['smallOrderFeeCents']) ?? 0) : 0;
    final total = math.max(0, goods - share + fees);
    return (goods: goods, discountShare: share, fees: fees, completes: completes, total: total);
  }

  String _itemName(Map<String, dynamic> i) =>
      [i['product']?['name'] ?? i['name'], i['variant']?['size'], i['variant']?['color']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

  // ── Start a return ─────────────────────────────────────────────────────

  Future<void> _startReturn({Map<String, dynamic>? preselected}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) return;
    HapticFeedback.selectionClick();

    List<Map<String, dynamic>> orders;
    String? loadError;
    if (preselected != null && _hasSomethingLeft(preselected)) {
      orders = [preselected];
    } else if (preselected != null) {
      orders = [];
    } else {
      (orders, loadError) = await _eligibleOrders();
    }
    if (!mounted) return;

    var selected = orders.isNotEmpty ? orders.first : null;
    Map<int, int> picked = selected == null ? {} : Map.of(_remaining(selected));
    var reason = 'CHANGED_MIND';
    final noteCtrl = TextEditingController();
    var submitting = false;
    String? sheetError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (orders.isEmpty || selected == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Text(
                loadError ??
                    (preselected != null
                        ? tr(context, 'Everything from this order is already in a return.', 'Kaikki tämän tilauksen tuotteet ovat jo palautuksessa.')
                        : tr(
                            context,
                            'You have no delivered orders from the last 14 days with items left to return. Return requests can be sent within 14 days of delivery.',
                            'Sinulla ei ole viimeisen 14 päivän aikana toimitettuja tilauksia, joista voisi vielä palauttaa tuotteita. Palautuspyynnön voi lähettää 14 päivän kuluessa toimituksesta.')),
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            );
          }
          final order = selected!;
          final perItem = _itemReturnsSupported(order);
          final remaining = _remaining(order);
          final items = _items(order).where((i) => (remaining[i['_key']] ?? 0) > 0).toList();
          final pickedQty = picked.values.fold<int>(0, (s, q) => s + q);
          final est = _estimate(order, picked);
          final everything = est.completes;
          final muted = AppTheme.secondaryText(context);

          Widget stepper(int id, int max) {
            final q = picked[id] ?? 0;
            Widget btn(IconData icon, String label, int? next) => IconButton(
                  tooltip: label,
                  visualDensity: VisualDensity.compact,
                  onPressed: next == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          setSheet(() => picked[id] = next);
                        },
                  icon: Icon(icon, size: 18),
                );
            return Container(
              decoration: BoxDecoration(color: AppTheme.inputBackground(context), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                btn(Icons.remove_rounded, tr(context, 'Fewer', 'Vähemmän'), q > 0 ? q - 1 : null),
                SizedBox(
                  width: 34,
                  child: Text('$q/$max',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primaryText(context))),
                ),
                btn(Icons.add_rounded, tr(context, 'More', 'Lisää'), q < max ? q + 1 : null),
              ]),
            );
          }

          Widget line(String label, String value, {bool bold = false}) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(label,
                          style: TextStyle(
                              fontSize: bold ? 15 : 13,
                              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                              color: bold ? AppTheme.primaryText(context) : muted))),
                  Text(value,
                      style: TextStyle(fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: AppTheme.primaryText(context))),
                ]),
              );

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Text(tr(context, 'Start a return', 'Aloita palautus'), style: AppTheme.display(context, size: 20)),
                    const SizedBox(height: 16),
                    if (orders.length > 1) ...[
                      DropdownButtonFormField<int>(
                        initialValue: asInt(order['id']),
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr(context, 'Order', 'Tilaus')),
                        items: orders
                            .map((o) => DropdownMenuItem<int>(
                                  value: asInt(o['id']),
                                  child:
                                      Text('#${o['id']} · ${o['store']?['name'] ?? ''} · ${euro(context, o['totalCents'])}', overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setSheet(() {
                          selected = orders.firstWhere((o) => asInt(o['id']) == v, orElse: () => order);
                          picked = Map.of(_remaining(selected!));
                        }),
                      ),
                      const SizedBox(height: 16),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${tr(context, 'Order', 'Tilaus')} #${order['id']} · ${order['store']?['name'] ?? ''}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                      ),
                    Row(children: [
                      Expanded(child: Text(tr(context, 'What are you returning?', 'Mitä palautat?'), style: AppTheme.display(context, size: 16))),
                      if (perItem)
                        TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setSheet(() => picked = everything ? {for (final k in remaining.keys) k: 0} : Map.of(remaining));
                          },
                          child: Text(everything ? tr(context, 'Clear', 'Tyhjennä') : tr(context, 'Everything', 'Kaikki')),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    for (final i in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_itemName(i),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                              Text('${euro(context, i['unitCents'])} ${tr(context, 'each', '/ kpl')}', style: TextStyle(fontSize: 12.5, color: muted)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          if (perItem)
                            stepper(i['_key'] as int, remaining[i['_key']] ?? 0)
                          else
                            Text('${remaining[i['_key']] ?? i['quantity']}×', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    if (!perItem) Text(tr(context, 'The whole order is returned.', 'Koko tilaus palautetaan.'), style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration:
                          BoxDecoration(color: AppTheme.pastel(context, AppTheme.mint, AppTheme.moss), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        line(tr(context, 'Items', 'Tuotteet'), euro(context, est.goods)),
                        if (est.discountShare > 0)
                          line(tr(context, 'Share of the order discount', 'Osuus tilauksen alennuksesta'), '−${euro(context, est.discountShare)}'),
                        if (est.fees > 0) line(tr(context, 'Delivery and fees', 'Toimitus ja maksut'), euro(context, est.fees)),
                        const Divider(height: 18),
                        line(tr(context, 'Expected refund', 'Odotettu hyvitys'), euro(context, est.total), bold: true),
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (!everything && (asInt(order['deliveryFeeCents']) ?? 0) > 0)
                              tr(context, 'The delivery fee is refunded only when everything from the order is returned.',
                                  'Toimitusmaksu hyvitetään vain, jos koko tilaus palautetaan.'),
                            if ((asInt(order['discountCents']) ?? 0) > 0)
                              tr(context, 'Your order had a discount, so the refund reflects it.',
                                  'Tilauksessasi oli alennus, joten hyvitys ottaa sen huomioon.'),
                            if ((asInt(order['tipCents']) ?? 0) > 0) tr(context, 'The courier tip is not refunded.', 'Kuriirin tippiä ei hyvitetä.'),
                            tr(context, 'The store confirms the final amount when the items are back.',
                                'Kauppa vahvistaa lopullisen summan, kun tuotteet ovat palanneet.'),
                          ].join(' '),
                          style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.primaryText(context)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: InputDecoration(labelText: tr(context, 'Reason', 'Syy')),
                      items: _reasons(context).entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setSheet(() => reason = v ?? reason),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: tr(context, 'Details (optional)', 'Lisätiedot (valinnainen)')),
                    ),
                    Text(
                      tr(
                          context,
                          'From a business seller: no reason is needed. The refund goes to your original payment method within 14 days, but it may wait until the item is back with the seller. From a private seller: there is no legal right of withdrawal, so the seller decides.',
                          'Yritysmyyjältä: syytä ei tarvitse kertoa. Hyvitys tehdään alkuperäiselle maksutavalle 14 päivän kuluessa, mutta se voi odottaa, kunnes tuote on palannut myyjälle. Yksityismyyjältä: lakisääteistä peruuttamisoikeutta ei ole, joten myyjä päättää.'),
                      style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(sheetError!, style: const TextStyle(color: Color(0xFFD93025), fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: submitting || pickedQty == 0
                            ? null
                            : () async {
                                HapticFeedback.mediumImpact();
                                setSheet(() {
                                  submitting = true;
                                  sheetError = null;
                                });
                                // Everything that is left = no item list (the server returns what remains)
                                final lines = [
                                  for (final e in picked.entries)
                                    if (e.value > 0) {'orderItemId': e.key, 'quantity': e.value},
                                ];
                                final res = await _api.post('/returns', {
                                  'orderId': asInt(order['id']),
                                  'reason': reason,
                                  if (noteCtrl.text.trim().isNotEmpty) 'conditionNote': noteCtrl.text.trim(),
                                  if (perItem && !everything) 'items': lines,
                                });
                                if (!mounted) return;
                                if (res.ok) {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _load();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(tr(context, 'Return request sent to the store.', 'Palautuspyyntö lähetetty kaupalle.')),
                                  ));
                                } else {
                                  setSheet(() {
                                    submitting = false;
                                    sheetError = res.errorText(context) ?? tr(context, 'Could not create the return.', 'Palautusta ei voitu luoda.');
                                  });
                                }
                              },
                        child: submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(everything
                                ? tr(context, 'Return everything', 'Palauta kaikki')
                                : tr(context, 'Return $pickedQty ${pickedQty == 1 ? 'item' : 'items'}',
                                    'Palauta $pickedQty ${pickedQty == 1 ? 'tuote' : 'tuotetta'}')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    noteCtrl.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cardColor = AppTheme.cardBackground(context);
    final secondary = AppTheme.secondaryText(context);

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Returns', 'Palautukset'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startReturn(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.undo_rounded),
        label: Text(tr(context, 'Start a return', 'Aloita palautus')),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: cardColor, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.cardBorder(context))),
              child: Text(
                tr(
                    context,
                    'Bought from a business seller? You can withdraw from the purchase within 14 days of receiving it, without giving a reason (Consumer Protection Act, chapter 6). A faulty item is also covered by the seller\'s liability for defects. You can return the whole order or only some items.\n\n'
                        'Bought from a private seller? The legal right of withdrawal does not apply, but you can still send a return request and the seller decides. Each store page says which kind of seller it is.\n\n'
                        'Unless the seller has agreed otherwise, you pay the cost of sending the item back.',
                    'Ostitko yritysmyyjältä? Voit perua oston 14 päivän kuluessa tuotteen vastaanottamisesta syytä kertomatta (kuluttajansuojalaki, 6 luku). Viallisesta tuotteesta myyjä vastaa lisäksi virhevastuun perusteella. Voit palauttaa koko tilauksen tai vain osan tuotteista.\n\n'
                        'Ostitko yksityismyyjältä? Lakisääteinen peruuttamisoikeus ei koske ostoa, mutta voit silti lähettää palautuspyynnön ja myyjä päättää. Jokaisella kauppasivulla kerrotaan, millainen myyjä on kyseessä.\n\n'
                        'Ellei myyjä ole toisin sopinut, maksat tuotteen palautuskulut.'),
                style: TextStyle(fontSize: 14, height: 1.4, color: secondary),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SizedBox(height: 360, child: SkeletonCardList(count: 3, thumbHeight: 40, padding: EdgeInsets.zero))
            else if (_error != null)
              SizedBox(height: 380, child: StateMessage.error(message: _error!, onRetry: _load, top: 40))
            else if (_returns.isEmpty)
              SizedBox(
                height: 320,
                child: StateMessage(icon: Icons.inventory_2_outlined, message: tr(context, 'No returns yet', 'Ei palautuksia'), top: 40),
              )
            else
              ..._returns.map((r) => _returnCard(r, cardColor, secondary)),
          ],
        ),
      ),
    );
  }

  Widget _returnCard(Map<String, dynamic> r, Color cardColor, Color secondary) {
    final status = r['status']?.toString() ?? 'REQUESTED';
    final refunded = asInt(r['refundCents']);
    final expected = asInt(r['expectedRefundCents']);
    final lines = ((r['items'] as List?) ?? const []).whereType<Map>().toList();
    final badge = status == 'REFUNDED'
        ? AppTheme.success
        : status == 'REJECTED'
            ? const Color(0xFFD93025)
            : AppTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.cardBorder(context))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr(context, 'Order', 'Tilaus')} #${r['orderId'] ?? '-'} · ${r['order']?['store']?['name'] ?? ''}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primaryText(context)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: badge.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(_statusLabels(context)[status] ?? status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badge)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_reasons(context)[r['reason']] ?? '${r['reason'] ?? ''}', style: TextStyle(color: secondary, fontSize: 13)),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Expanded(
                    child: Text('${asInt(l['quantity']) ?? 1}×  ${l['name'] ?? ''}',
                        style: TextStyle(fontSize: 13, color: AppTheme.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (l['unitCents'] != null)
                    Text(euro(context, (asInt(l['unitCents']) ?? 0) * (asInt(l['quantity']) ?? 1)), style: TextStyle(fontSize: 13, color: secondary)),
                ]),
              ),
          ],
          if (refunded != null && status == 'REFUNDED') ...[
            const SizedBox(height: 6),
            Text('${tr(context, 'Refunded', 'Hyvitetty')} ${euro(context, refunded)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.success)),
          ] else if (expected != null && status != 'REJECTED') ...[
            const SizedBox(height: 6),
            Text('${tr(context, 'Expected refund', 'Odotettu hyvitys')} ${euro(context, expected)}',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primaryText(context))),
          ],
        ],
      ),
    );
  }
}
