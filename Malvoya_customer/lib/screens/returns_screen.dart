import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../core/strings.dart';

/// Returns. Purchases from business sellers have the 14-day right of withdrawal (Kuluttajansuojalaki
/// 6 luku); purchases from private sellers do not, but a request can still be sent to the seller.
/// Everything shown here comes from the server; nothing is stored only on the phone.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

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
  List<dynamic> _returns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame: the messages are localised, which needs the context
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Map<String, String> _headers(AuthService auth) => {
        'Authorization': 'Bearer ${auth.accessToken}',
        'Content-Type': 'application/json',
      };

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() { _loading = false; _error = tr(context, 'Sign in to see your returns.', 'Kirjaudu sisään nähdäksesi palautukset.'); });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/returns'), headers: _headers(auth))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _returns = jsonDecode(res.body)['returns'] ?? []);
      } else {
        setState(() => _error = tr(context, 'Could not load returns.', 'Palautuksia ei voitu ladata.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'No connection.', 'Ei yhteyttä.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Delivered orders still inside the 14-day window, newest first.
  Future<List<dynamic>> _eligibleOrders(AuthService auth) async {
    final res = await http
        .get(Uri.parse('${AppConstants.apiBase}/orders'), headers: _headers(auth))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final orders = (jsonDecode(res.body)['orders'] as List?) ?? [];
    final alreadyReturned = _returns.map((r) => r['orderId']).toSet();
    return orders.where((o) {
      if (o['status'] != 'DELIVERED' || o['deliveredAt'] == null) return false;
      if (alreadyReturned.contains(o['id'])) return false;
      final delivered = DateTime.tryParse(o['deliveredAt'].toString());
      return delivered != null && DateTime.now().difference(delivered).inDays < 14;
    }).toList();
  }

  Future<void> _startReturn() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) return;
    HapticFeedback.selectionClick();

    List<dynamic> orders;
    try {
      orders = await _eligibleOrders(auth);
    } catch (_) {
      orders = [];
    }
    if (!mounted) return;

    int? selectedOrder = orders.isNotEmpty ? orders.first['id'] as int : null;
    String reason = 'CHANGED_MIND';
    final noteCtrl = TextEditingController();
    bool submitting = false;
    String? sheetError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    tr(context, 'You have no delivered orders from the last 14 days. Return requests can be sent within 14 days of delivery.',
                        'Sinulla ei ole viimeisen 14 päivän aikana toimitettuja tilauksia. Palautuspyynnön voi lähettää 14 päivän kuluessa toimituksesta.'),
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr(context, 'Start a return', 'Aloita palautus'), style: AppTheme.display(context, size: 20)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedOrder,
                      decoration: InputDecoration(labelText: tr(context, 'Order', 'Tilaus')),
                      items: orders
                          .map((o) => DropdownMenuItem<int>(
                                value: o['id'] as int,
                                child: Text('#${o['id']} • ${o['store']?['name'] ?? ''} • ${euro(context, o['totalCents'])}'),
                              ))
                          .toList(),
                      onChanged: (v) => setSheet(() => selectedOrder = v),
                    ),
                    const SizedBox(height: 12),
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
                      tr(context,
                          'From a business seller: no reason is needed. The refund goes to your original payment method within 14 days, but it may wait until the item is back with the seller. From a private seller: there is no legal right of withdrawal, so the seller decides.',
                          'Yritysmyyjältä: syytä ei tarvitse kertoa. Hyvitys tehdään alkuperäiselle maksutavalle 14 päivän kuluessa, mutta se voi odottaa, kunnes tuote on palannut myyjälle. Yksityismyyjältä: lakisääteistä peruuttamisoikeutta ei ole, joten myyjä päättää.'),
                      style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.secondaryText(context)),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(sheetError!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: submitting || selectedOrder == null
                            ? null
                            : () async {
                                setSheet(() { submitting = true; sheetError = null; });
                                try {
                                  final res = await http
                                      .post(
                                        Uri.parse('${AppConstants.apiBase}/returns'),
                                        headers: _headers(auth),
                                        body: jsonEncode({
                                          'orderId': selectedOrder,
                                          'reason': reason,
                                          if (noteCtrl.text.trim().isNotEmpty) 'conditionNote': noteCtrl.text.trim(),
                                        }),
                                      )
                                      .timeout(const Duration(seconds: 15));
                                  if (res.statusCode == 201) {
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _load();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(tr(context, 'Return request sent to the store.', 'Palautuspyyntö lähetetty kaupalle.')),
                                      ));
                                    }
                                  } else {
                                    String msg = tr(context, 'Could not create the return.', 'Palautusta ei voitu luoda.');
                                    try { msg = jsonDecode(res.body)['error'] ?? msg; } catch (_) {}
                                    setSheet(() { submitting = false; sheetError = msg; });
                                  }
                                } catch (_) {
                                  setSheet(() { submitting = false; sheetError = tr(context, 'No connection.', 'Ei yhteyttä.'); });
                                }
                              },
                        child: submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(tr(context, 'Send return request', 'Lähetä palautuspyyntö')),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final secondary = isDark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Returns', 'Palautukset'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startReturn,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.undo_rounded),
        label: Text(tr(context, 'Start a return', 'Aloita palautus')),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
              child: Text(
                tr(context,
                    'Bought from a business seller? You can withdraw from the purchase within 14 days of receiving it, without giving a reason (Consumer Protection Act, chapter 6). A faulty item is also covered by the seller\'s liability for defects.\n\n'
                        'Bought from a private seller? The legal right of withdrawal does not apply, but you can still send a return request and the seller decides. Each store page says which kind of seller it is.\n\n'
                        'Unless the seller has agreed otherwise, you pay the cost of sending the item back.',
                    'Ostitko yritysmyyjältä? Voit perua oston 14 päivän kuluessa tuotteen vastaanottamisesta syytä kertomatta (kuluttajansuojalaki, 6 luku). Viallisesta tuotteesta myyjä vastaa lisäksi virhevastuun perusteella.\n\n'
                        'Ostitko yksityismyyjältä? Lakisääteinen peruuttamisoikeus ei koske ostoa, mutta voit silti lähettää palautuspyynnön ja myyjä päättää. Jokaisella kauppasivulla kerrotaan, millainen myyjä on kyseessä.\n\n'
                        'Ellei myyjä ole toisin sopinut, maksat tuotteen palautuskulut.'),
                style: TextStyle(fontSize: 14, height: 1.4, color: secondary),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 48), child: Center(child: CircularProgressIndicator.adaptive()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: secondary)),
              )
            else if (_returns.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: secondary),
                    const SizedBox(height: 12),
                    Text(tr(context, 'No returns yet', 'Ei palautuksia'), style: TextStyle(color: secondary, fontSize: 15)),
                  ],
                ),
              )
            else
              ..._returns.map((r) {
                final status = r['status']?.toString() ?? 'REQUESTED';
                final refunded = r['refundCents'] as int?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${tr(context, 'Order', 'Tilaus')} #${r['orderId'] ?? '-'} • ${r['order']?['store']?['name'] ?? ''}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (status == 'REFUNDED' ? const Color(0xFF34C759) : status == 'REJECTED' ? Colors.redAccent : AppTheme.primary)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_statusLabels(context)[status] ?? status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_reasons(context)[r['reason']] ?? r['reason'].toString(), style: TextStyle(color: secondary, fontSize: 13)),
                      if (refunded != null && status == 'REFUNDED') ...[
                        const SizedBox(height: 6),
                        Text('${tr(context, 'Refunded', 'Hyvitetty')} ${euro(context, refunded)}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
