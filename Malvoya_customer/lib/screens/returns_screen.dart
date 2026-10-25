import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/sign_in.dart';

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

/// Reasons that use the 14-day right of withdrawal (the API's WITHDRAWAL_REASONS); faults are
/// always returnable, also with an opened hygiene seal.
const _withdrawal = {'CHANGED_MIND', 'OTHER'};

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

  /// The store of each order with an approved return (name, address, phone from the order), for
  /// "how to send it back".
  Map<int, Map<String, dynamic>> _stores = {};
  bool _loading = true;
  String? _error;

  /// Whether the last load was signed in (signing in from this screen loads the returns).
  bool? _loadedSignedIn;

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
    _loadedSignedIn = auth.isAuthenticated;
    if (!auth.isAuthenticated) {
      setState(() {
        _loading = false;
        _returns = [];
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
    if (res.ok) _loadReturnStores();
  }

  /// Where approved returns go back to: the store's details as the order shows them.
  Future<void> _loadReturnStores() async {
    // Newer servers send the store's details with each return; only older ones need the order
    final ids = _returns
        .where((r) => r['status'] == 'APPROVED' && _storeOf(r).isEmpty)
        .map((r) => asInt(r['orderId']))
        .whereType<int>()
        .toSet();
    if (ids.isEmpty) return;
    final stores = <int, Map<String, dynamic>>{};
    for (final id in ids.take(5)) {
      final res = await _api.get('/orders/$id');
      if (!mounted) return;
      final order = res.data['order'];
      final store = res.ok && order is Map ? order['store'] : null;
      if (store is Map) stores[id] = Map<String, dynamic>.from(store);
    }
    if (mounted && stores.isNotEmpty) setState(() => _stores = stores);
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
    Haptics.selection();

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
    // Hygiene seal (API 2.12): the answer, lines the server says are sealed, and its refusal text
    bool? sealIntact;
    final sealedFromServer = <int>{};
    String? sealRefusal;

    await showMSheet(context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (orders.isEmpty || selected == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.sm, MSpace.xxl, MSpace.x3l),
              child: Text(
                loadError ??
                    (preselected != null
                        ? tr(context, 'Everything from this order is already in a return.', 'Kaikki tämän tilauksen tuotteet ovat jo palautuksessa.')
                        : tr(
                            context,
                            'You have no delivered orders from the last 14 days with items left to return. Return requests can be sent within 14 days of delivery.',
                            'Sinulla ei ole viimeisen 14 päivän aikana toimitettuja tilauksia, joista voisi vielä palauttaa tuotteita. Palautuspyynnön voi lähettää 14 päivän kuluessa toimituksesta.')),
                style: const TextStyle(fontSize: MTextSize.bodyL, height: 1.4),
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
          final sealedNames = [
            for (final i in items)
              if ((picked[i['_key']] ?? 0) > 0 && (i['hygieneSealed'] == true || sealedFromServer.contains(i['_key']))) _itemName(i),
          ];
          final sealAsked = _withdrawal.contains(reason) && sealedNames.isNotEmpty;

          Widget stepper(int id, int max) {
            final q = picked[id] ?? 0;
            Widget btn(IconData icon, String label, int? next) => IconButton(
                  tooltip: label,
                  visualDensity: VisualDensity.compact,
                  onPressed: next == null
                      ? null
                      : () {
                          Haptics.selection();
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
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.label, color: AppTheme.primaryText(context))),
                ),
                btn(Icons.add_rounded, tr(context, 'More', 'Lisää'), q < max ? q + 1 : null),
              ]),
            );
          }

          Widget line(String label, String value, {bool bold = false}) => Padding(
                padding: const EdgeInsets.only(top: MSpace.xs),
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
                  padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.xxl),
                  children: [
                    Text(tr(context, 'Start a return', 'Aloita palautus'), style: AppTheme.display(context, size: 20)),
                    const SizedBox(height: MSpace.lg),
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
                      const SizedBox(height: MSpace.lg),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(bottom: MSpace.md),
                        child: Text('${tr(context, 'Order', 'Tilaus')} #${order['id']} · ${order['store']?['name'] ?? ''}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                      ),
                    Row(children: [
                      Expanded(child: Text(tr(context, 'What are you returning?', 'Mitä palautat?'), style: AppTheme.display(context, size: 16))),
                      if (perItem)
                        TextButton(
                          onPressed: () {
                            Haptics.selection();
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
                              Text('${euro(context, i['unitCents'])} ${tr(context, 'each', '/ kpl')}', style: TextStyle(fontSize: MTextSize.caption, color: muted)),
                            ]),
                          ),
                          const SizedBox(width: MSpace.sm),
                          if (perItem)
                            stepper(i['_key'] as int, remaining[i['_key']] ?? 0)
                          else
                            Text('${remaining[i['_key']] ?? i['quantity']}×', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    if (!perItem) Text(tr(context, 'The whole order is returned.', 'Koko tilaus palautetaan.'), style: TextStyle(fontSize: MTextSize.caption, color: muted)),
                    const SizedBox(height: MSpace.sm),
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
                        const SizedBox(height: MSpace.sm),
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
                          style: TextStyle(fontSize: MTextSize.caption, height: 1.4, color: AppTheme.primaryText(context)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: MSpace.lg),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: InputDecoration(labelText: tr(context, 'Reason', 'Syy')),
                      items: _reasons(context).entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setSheet(() {
                        reason = v ?? reason;
                        sealRefusal = null;
                      }),
                    ),
                    // Sealed items returned under the right of withdrawal: is the seal unbroken?
                    if (sealAsked) ...[
                      const SizedBox(height: MSpace.md),
                      _sealQuestion(
                        names: sealedNames,
                        value: sealIntact,
                        onChanged: (v) => setSheet(() {
                          sealIntact = v;
                          sealRefusal = null;
                        }),
                      ),
                    ],
                    if (sealRefusal != null) ...[
                      const SizedBox(height: MSpace.md),
                      _sealRefusalBox(sealRefusal!),
                    ],
                    const SizedBox(height: MSpace.md),
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
                      style: TextStyle(fontSize: MTextSize.caption, height: 1.4, color: muted),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(sheetError!, style: const TextStyle(color: MPalette.red, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: MSpace.lg),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: MButton(label: everything
                                ? tr(context, 'Return everything', 'Palauta kaikki')
                                : tr(context, 'Return $pickedQty ${pickedQty == 1 ? 'item' : 'items'}',
                                    'Palauta $pickedQty ${pickedQty == 1 ? 'tuote' : 'tuotetta'}'), loading: submitting, onPressed: submitting || pickedQty == 0 || (sealAsked && sealIntact == null)
                            ? null
                            : () async {
                                Haptics.medium();
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
                                  if (sealAsked && sealIntact != null) 'sealIntact': sealIntact,
                                });
                                if (!mounted) return;
                                if (res.ok) {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _load();
                                  MSnack.success(context, tr(context, 'Return request sent to the store.', 'Palautuspyyntö lähetetty kaupalle.'));
                                } else if (res.data['code'] == 'SEAL_STATUS_REQUIRED') {
                                  // The server knows these lines are sealed: ask the question
                                  setSheet(() {
                                    submitting = false;
                                    sealedFromServer.addAll(((res.data['items'] as List?) ?? const []).map(asInt).whereType<int>());
                                    sealIntact = null;
                                    sheetError = localized(context, res.data['question']) ??
                                        tr(context, 'Please answer: is the hygiene seal unbroken?', 'Vastaa ensin: onko hygieniasinetti ehjä?');
                                  });
                                } else if (res.data['code'] == 'HYGIENE_SEAL_OPENED') {
                                  setSheet(() {
                                    submitting = false;
                                    sheetError = null;
                                    sealRefusal = localized(context, res.data['reason']) ?? res.errorText(context);
                                  });
                                } else {
                                  setSheet(() {
                                    submitting = false;
                                    sheetError = res.errorText(context) ?? tr(context, 'Could not create the return.', 'Palautusta ei voitu luoda.');
                                  });
                                }
                              }),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ), isScrollControlled: true, useSafeArea: false);
    noteCtrl.dispose();
  }

  // ── Hygiene seal ────────────────────────────────────────────────────────

  Widget _sealQuestion({required List<String> names, required bool? value, required ValueChanged<bool> onChanged}) {
    final c = context.mColors;
    return Container(
      padding: const EdgeInsets.all(MSpace.md),
      decoration: BoxDecoration(color: c.sunshineSoft, borderRadius: MRadius.brMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, size: 20, color: c.onSunshineSoft),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Text(tr(context, 'Is the hygiene seal unbroken?', 'Onko hygieniasinetti ehjä?'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w800, color: c.onSunshineSoft))),
        ]),
        const SizedBox(height: MSpace.xs),
        Text(
          tr(context, 'Sold hygiene-sealed: ${names.join(', ')}. Unopened, you can return it within 14 days.', 'Myyty hygieniasinetöitynä: ${names.join(', ')}. Avaamattoman tuotteen voit palauttaa 14 päivän kuluessa.'),
          style: MType.bodyM.copyWith(color: c.onSunshineSoft),
        ),
        RadioGroup<bool>(
          groupValue: value,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          child: Column(children: [
            RadioListTile<bool>(value: true, contentPadding: EdgeInsets.zero, title: Text(tr(context, 'Yes, the seal is unbroken', 'Kyllä, sinetti on ehjä'))),
            RadioListTile<bool>(value: false, contentPadding: EdgeInsets.zero, title: Text(tr(context, 'No, it has been opened', 'Ei, se on avattu'))),
          ]),
        ),
        if (value == false)
          Text(
            tr(context, 'An opened item cannot be returned under the 14-day right of withdrawal. If it is faulty, wrong or not as described, choose that reason: faulty items can always be returned.',
                'Avattua tuotetta ei voi palauttaa 14 päivän peruuttamisoikeudella. Jos tuote on virheellinen, väärä tai ei vastaa kuvausta, valitse se syyksi: virheellisen tuotteen voi aina palauttaa.'),
            style: MType.caption.copyWith(color: c.onSunshineSoft),
          ),
      ]),
    );
  }

  /// The server's HYGIENE_SEAL_OPENED answer, in the app language.
  Widget _sealRefusalBox(String text) {
    final c = context.mColors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(MSpace.md),
        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: MRadius.brMd, border: Border.all(color: c.danger)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.block_rounded, size: 20, color: c.onDangerSoft),
          const SizedBox(width: MSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'This item cannot be returned', 'Tätä tuotetta ei voi palauttaa'), style: MType.bodyM.copyWith(fontWeight: FontWeight.w800, color: c.onDangerSoft)),
              const SizedBox(height: 2),
              Text(text, style: MType.bodyM.copyWith(color: c.onDangerSoft)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  Widget _rules() {
    final c = context.mColors;
    Widget rule(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: MSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: c.onPrimarySoft),
            ),
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
                Text(body, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.xs),
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(tr(context, 'Return rules', 'Palautussäännöt'), style: MType.title.copyWith(color: c.onSurface))),
        const SizedBox(height: MSpace.md),
        rule(Icons.event_available_outlined, tr(context, '14 days from delivery', '14 päivää toimituksesta'),
            tr(context, 'Bought from a business seller? You can withdraw within 14 days of receiving the order, without giving a reason (Consumer Protection Act, chapter 6). You can return the whole order or only some items.',
                'Ostitko yritysmyyjältä? Voit perua oston 14 päivän kuluessa tilauksen vastaanottamisesta syytä kertomatta (kuluttajansuojalaki, 6 luku). Voit palauttaa koko tilauksen tai vain osan tuotteista.')),
        rule(Icons.lock_outline_rounded, tr(context, 'Hygiene seal', 'Hygieniasinetti'),
            tr(context, 'Items sold hygiene-sealed (for example cosmetics, perfume and earrings) can be returned only while the seal is unbroken. The product page says when an item is sealed.',
                'Hygieniasinetöityinä myydyt tuotteet (esimerkiksi kosmetiikka, hajuvedet ja korvakorut) voi palauttaa vain, jos sinetti on ehjä. Tuotesivulla kerrotaan, onko tuote sinetöity.')),
        rule(Icons.build_circle_outlined, tr(context, 'Faulty items are always returnable', 'Virheellisen tuotteen voi aina palauttaa'),
            tr(context, 'Wrong, damaged or not as described? Choose that reason. This also applies to opened sealed items. Faults are covered by the seller’s liability for defects; after 14 days, contact Help.',
                'Väärä, vaurioitunut tai ei vastaa kuvausta? Valitse se syyksi. Tämä koskee myös avattuja sinetöityjä tuotteita. Virheistä myyjä vastaa virhevastuun perusteella; 14 päivän jälkeen ota yhteyttä tukeen.')),
        rule(Icons.person_outline_rounded, tr(context, 'Private sellers', 'Yksityiset myyjät'),
            tr(context, 'The legal right of withdrawal does not apply, but you can still send a return request and the seller decides.',
                'Lakisääteinen peruuttamisoikeus ei koske ostoa, mutta voit silti lähettää palautuspyynnön ja myyjä päättää.')),
        rule(Icons.payments_outlined, tr(context, 'Refund', 'Hyvitys'),
            tr(context, 'The refund goes to your original payment method once the shop has the items back. Unless the seller has agreed otherwise, you pay the cost of sending items back.',
                'Hyvitys maksetaan alkuperäiselle maksutavalle, kun kauppa on saanut tuotteet takaisin. Ellei myyjä ole toisin sopinut, maksat palautuskulut.')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = AppTheme.cardBackground(context);
    final secondary = AppTheme.secondaryText(context);
    final signedIn = Provider.of<AuthService>(context).isAuthenticated;
    if (_loadedSignedIn != null && _loadedSignedIn != signedIn && !_loading) {
      _loadedSignedIn = signedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Returns & refunds', 'Palautukset ja hyvitykset'))),
      floatingActionButton: !signedIn
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startReturn(),
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.onBrand,
              icon: const Icon(Icons.undo_rounded),
              label: Text(tr(context, 'Start a return', 'Aloita palautus')),
            ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, 96),
          children: [
            if (!signedIn) ...[
              SignInCard(
                title: tr(context, 'Sign in to return an item', 'Kirjaudu palauttaaksesi tuotteen'),
                message: tr(context, 'Your orders and returns are kept in your account.', 'Tilauksesi ja palautuksesi ovat tililläsi.'),
              ),
              const SizedBox(height: MSpace.lg),
            ],
            _rules(),
            const SizedBox(height: MSpace.lg),
            if (signedIn) MSectionHeader(tr(context, 'Your returns', 'Palautuksesi'), padding: const EdgeInsets.only(bottom: MSpace.sm)),
            if (!signedIn)
              const SizedBox.shrink()
            else if (_loading)
              const SizedBox(height: 360, child: MSkeletonList(thumbnail: true, count: 3, thumbHeight: 40, padding: EdgeInsets.zero))
            else if (_error != null)
              SizedBox(height: 380, child: MStateMessage.error(message: _error!, onRetry: _load, top: 40))
            else if (_returns.isEmpty)
              SizedBox(
                height: 320,
                child: MStateMessage(icon: Icons.inventory_2_outlined, message: tr(context, 'No returns yet', 'Ei palautuksia'), top: 40),
              )
            else
              ..._returns.map((r) => _returnCard(r, cardColor, secondary)),
          ],
        ),
      ),
    );
  }

  /// The store's name, address and phone as the return itself carries them (newer servers).
  Map<String, dynamic> _storeOf(Map<String, dynamic> r) {
    final s = r['store'];
    if (s is Map && ('${s['address'] ?? ''}'.trim().isNotEmpty || '${s['phone'] ?? ''}'.trim().isNotEmpty)) {
      return Map<String, dynamic>.from(s);
    }
    return const {};
  }

  String _storeName(Map<String, dynamic> r) =>
      '${(r['store'] is Map ? r['store']['name'] : null) ?? r['order']?['store']?['name'] ?? ''}';

  /// After approval: send or bring the items back to the store, using the store's own details.
  Widget _nextSteps(Map<String, dynamic> r) {
    final own = _storeOf(r);
    final store = own.isNotEmpty
        ? own
        : _stores[asInt(r['orderId'])] ?? (r['order']?['store'] is Map ? Map<String, dynamic>.from(r['order']['store']) : const {});
    final name = '${store['name'] ?? ''}'.trim();
    final address = '${store['address'] ?? ''}'.trim();
    final phone = '${store['phone'] ?? ''}'.trim();
    final storeEn = name.isEmpty ? 'the store' : name;
    final storeFi = name.isEmpty ? 'kauppaan' : 'kauppaan $name';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'Next: send the items back', 'Seuraavaksi: palauta tuotteet'),
              style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
          const SizedBox(height: 6),
          Text(
            tr(context, 'The store approved your return. Bring or send the items back to $storeEn. The store refunds you once it has received them.',
                'Kauppa hyväksyi palautuksesi. Tuo tai lähetä tuotteet takaisin $storeFi. Kauppa maksaa hyvityksen, kun se on vastaanottanut tuotteet.'),
            style: TextStyle(fontSize: MTextSize.label, height: 1.4, color: AppTheme.primaryText(context)),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: MSpace.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.storefront_rounded, size: 16, color: AppTheme.primaryText(context)),
              const SizedBox(width: 6),
              Expanded(child: SelectableText(address, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: AppTheme.primaryText(context)))),
            ]),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: MSpace.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.phone_outlined, size: 16, color: AppTheme.primaryText(context)),
              const SizedBox(width: 6),
              Expanded(child: SelectableText(phone, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: AppTheme.primaryText(context)))),
            ]),
          ],
          if (address.isEmpty && phone.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              tr(context, 'The store’s address is not shown here. Ask Malvoya support (Profile → Help) how to send it back.',
                  'Kaupan osoite ei näy tässä. Kysy Malvoyan tuelta (Profiili → Apua), miten palautat tuotteet.'),
              style: TextStyle(fontSize: MTextSize.caption, height: 1.35, color: AppTheme.primaryText(context)),
            ),
          ],
        ],
      ),
    );
  }

  /// Where the return is: requested → approved → on its way back → received → refunded.
  Widget _progress(String status) {
    final c = context.mColors;
    if (status == 'REJECTED') {
      return Row(children: [
        Icon(Icons.cancel_outlined, size: 18, color: c.danger),
        const SizedBox(width: MSpace.xs),
        Expanded(child: Text(tr(context, 'The shop rejected this return. No refund.', 'Kauppa hylkäsi palautuksen. Ei hyvitystä.'), style: MType.caption.copyWith(color: c.onSurface))),
      ]);
    }
    const steps = ['REQUESTED', 'APPROVED', 'IN_TRANSIT', 'RECEIVED', 'REFUNDED'];
    final at = steps.indexOf(status).clamp(0, steps.length - 1);
    final labels = _statusLabels(context);
    return Semantics(
      label: tr(context, 'Step ${at + 1} of ${steps.length}: ${labels[status] ?? status}', 'Vaihe ${at + 1}/${steps.length}: ${labels[status] ?? status}'),
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: MSpace.xs),
            Expanded(
              child: Container(height: 6, decoration: BoxDecoration(color: i <= at ? c.primary : c.outline, borderRadius: MRadius.pillRadius)),
            ),
          ],
        ]),
        const SizedBox(height: MSpace.xs),
        Text(
          switch (status) {
            'REQUESTED' => tr(context, 'Waiting for the shop to answer.', 'Odottaa kaupan vastausta.'),
            'APPROVED' => tr(context, 'Approved: send or bring the items back.', 'Hyväksytty: lähetä tai tuo tuotteet takaisin.'),
            'IN_TRANSIT' => tr(context, 'On its way back to the shop.', 'Matkalla takaisin kauppaan.'),
            'RECEIVED' => tr(context, 'The shop has the items. The refund is next.', 'Kauppa sai tuotteet. Seuraavaksi hyvitys.'),
            _ => tr(context, 'Refunded to your payment method.', 'Hyvitetty maksutavallesi.'),
          },
          style: MType.caption.copyWith(color: c.onSurfaceVariant),
        ),
      ]),
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
            ? MPalette.red
            : AppTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(MSpace.lg),
      decoration:
          BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.cardBorder(context))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr(context, 'Order', 'Tilaus')} #${r['orderId'] ?? '-'} · ${_storeName(r)}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL, color: AppTheme.primaryText(context)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.xs),
                decoration: BoxDecoration(color: badge.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(_statusLabels(context)[status] ?? status, style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w700, color: badge)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_reasons(context)[r['reason']] ?? '${r['reason'] ?? ''}', style: TextStyle(color: secondary, fontSize: MTextSize.label)),
          const SizedBox(height: MSpace.sm),
          _progress(status),
          if (r['sealIntact'] == true)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.xs),
              child: Text(tr(context, 'You said the hygiene seal is unbroken.', 'Kerroit, että hygieniasinetti on ehjä.'), style: MType.caption.copyWith(color: secondary)),
            ),
          // Newer servers keep the store's words in storeNote and the customer's own in conditionNote;
          // on older ones conditionNote may hold either, so it is shown as a plain note.
          if ('${r['conditionNote'] ?? ''}'.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MSpace.xs),
              child: Text(
                  '${r.containsKey('storeNote') ? tr(context, 'Your note', 'Oma huomautuksesi') : tr(context, 'Note', 'Huomautus')}: ${'${r['conditionNote']}'.trim()}',
                  style: TextStyle(fontSize: MTextSize.label, color: AppTheme.primaryText(context), height: 1.35)),
            ),
          if ('${r['storeNote'] ?? ''}'.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: MSpace.sm),
              padding: const EdgeInsets.all(MSpace.md),
              decoration: BoxDecoration(
                color: status == 'REJECTED'
                    ? AppTheme.pastel(context, AppTheme.peach, MPalette.red)
                    : AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == 'REJECTED'
                        ? tr(context, 'Why the store declined', 'Miksi kauppa hylkäsi')
                        : tr(context, 'From the store', 'Kaupalta'),
                    style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w800, color: AppTheme.primaryText(context)),
                  ),
                  const SizedBox(height: 2),
                  Text('${r['storeNote']}'.trim(), style: TextStyle(fontSize: MTextSize.label, height: 1.35, color: AppTheme.primaryText(context))),
                ],
              ),
            ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: MSpace.sm),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Expanded(
                    child: Text('${asInt(l['quantity']) ?? 1}×  ${l['name'] ?? ''}',
                        style: TextStyle(fontSize: MTextSize.label, color: AppTheme.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (l['unitCents'] != null)
                    Text(euro(context, (asInt(l['unitCents']) ?? 0) * (asInt(l['quantity']) ?? 1)), style: TextStyle(fontSize: MTextSize.label, color: secondary)),
                ]),
              ),
          ],
          if (refunded != null && status == 'REFUNDED') ...[
            const SizedBox(height: 6),
            Text('${tr(context, 'Refunded', 'Hyvitetty')} ${euro(context, refunded)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label, color: AppTheme.success)),
          ] else if (expected != null && status != 'REJECTED') ...[
            const SizedBox(height: 6),
            Text('${tr(context, 'Expected refund', 'Odotettu hyvitys')} ${euro(context, expected)}',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.label, color: AppTheme.primaryText(context))),
          ],
          if (status == 'APPROVED') ...[
            const SizedBox(height: MSpace.md),
            _nextSteps(r),
          ],
        ],
      ),
    );
  }
}
