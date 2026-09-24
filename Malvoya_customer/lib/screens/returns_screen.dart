import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';

/// Returns under the 14-day right of withdrawal (Kuluttajansuojalaki 6 luku).
/// Everything shown here comes from the server; nothing is stored only on the phone.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

const _reasons = <String, String>{
  'CHANGED_MIND': 'Muutin mieleni / Changed my mind',
  'WRONG_ITEM': 'Väärä tuote / Wrong item',
  'DAMAGED_ON_ARRIVAL': 'Saapui vaurioituneena / Arrived damaged',
  'NOT_AS_DESCRIBED': 'Ei vastaa kuvausta / Not as described',
  'OTHER': 'Muu syy / Other',
};

const _statusLabels = <String, String>{
  'REQUESTED': 'Pyydetty / Requested',
  'APPROVED': 'Hyväksytty / Approved',
  'IN_TRANSIT': 'Matkalla / On its way back',
  'RECEIVED': 'Vastaanotettu / Received by store',
  'REFUNDED': 'Hyvitetty / Refunded',
  'REJECTED': 'Hylätty / Rejected',
};

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<dynamic> _returns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _headers(AuthService auth) => {
        'Authorization': 'Bearer ${auth.accessToken}',
        'Content-Type': 'application/json',
      };

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() { _loading = false; _error = 'Kirjaudu sisään nähdäksesi palautukset. Sign in to see your returns.'; });
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
        setState(() => _error = 'Palautuksia ei voitu ladata. Could not load returns.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Ei yhteyttä. No connection.');
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
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Sinulla ei ole palautettavia tilauksia. Tuotteen voi palauttaa 14 päivän kuluessa toimituksesta.\n\n'
                    'You have no orders that can be returned. Items can be returned within 14 days of delivery.',
                    style: TextStyle(fontSize: 15, height: 1.4),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Aloita palautus / Start a return',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedOrder,
                      decoration: const InputDecoration(labelText: 'Tilaus / Order'),
                      items: orders
                          .map((o) => DropdownMenuItem<int>(
                                value: o['id'] as int,
                                child: Text('#${o['id']} • ${o['store']?['name'] ?? ''} • €${((o['totalCents'] ?? 0) / 100).toStringAsFixed(2)}'),
                              ))
                          .toList(),
                      onChanged: (v) => setSheet(() => selectedOrder = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: const InputDecoration(labelText: 'Syy / Reason'),
                      items: _reasons.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setSheet(() => reason = v ?? reason),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Lisätiedot (valinnainen) / Details (optional)'),
                    ),
                    const Text(
                      'Peruuttamisoikeus: sinun ei tarvitse kertoa syytä. Hyvitys tehdään alkuperäiselle maksutavalle 14 päivän kuluessa.\n'
                      'Right of withdrawal: no reason is required. The refund goes to your original payment method within 14 days.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(sheetError!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
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
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('Palautuspyyntö lähetetty. Return request sent.'),
                                      ));
                                    }
                                  } else {
                                    String msg = 'Palautusta ei voitu luoda. Could not create the return.';
                                    try { msg = jsonDecode(res.body)['error'] ?? msg; } catch (_) {}
                                    setSheet(() { submitting = false; sheetError = msg; });
                                  }
                                } catch (_) {
                                  setSheet(() { submitting = false; sheetError = 'Ei yhteyttä. No connection.'; });
                                }
                              },
                        child: submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Lähetä palautuspyyntö / Send return request'),
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
      appBar: AppBar(title: const Text('Palautukset / Returns')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startReturn,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.undo_rounded),
        label: const Text('Aloita palautus'),
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
                'Voit palauttaa tuotteen 14 päivän kuluessa siitä, kun olet vastaanottanut sen.\n'
                'You can return an item within 14 days of receiving it.',
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
                    Text('Ei palautuksia / No returns yet', style: TextStyle(color: secondary, fontSize: 15)),
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
                              'Tilaus / Order #${r['orderId'] ?? '-'} • ${r['order']?['store']?['name'] ?? ''}',
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
                            child: Text(_statusLabels[status]?.split(' / ').last ?? status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_reasons[r['reason']] ?? r['reason'].toString(), style: TextStyle(color: secondary, fontSize: 13)),
                      if (refunded != null && status == 'REFUNDED') ...[
                        const SizedBox(height: 6),
                        Text('Hyvitetty / Refunded €${(refunded / 100).toStringAsFixed(2)}',
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
