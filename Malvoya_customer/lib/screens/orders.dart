import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../services/socket_service.dart';
import 'order_detail.dart';
import 'returns_screen.dart';

/// Your orders: what is on its way first, then everything delivered or cancelled.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  static const _active = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'];

  @override
  void initState() {
    super.initState();
    _load();
    CustomerSocketService().addListener(_onSocket);
  }

  @override
  void dispose() {
    CustomerSocketService().removeListener(_onSocket);
    super.dispose();
  }

  void _onSocket() {
    if (mounted) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    if (!quiet) setState(() => _loading = true);
    final res = await ApiClient(auth).get('/orders');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        // Unpaid, abandoned checkouts are not orders from the customer's point of view
        _orders = ((res.data['orders'] as List?) ?? [])
            .map((o) => Map<String, dynamic>.from(o))
            .where((o) => !(o['status'] == 'CANCELLED' && o['paymentStatus'] == 'PENDING'))
            .toList();
        _error = null;
      } else {
        _error = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final active = _orders.where((o) => _active.contains(o['status']) && o['paymentStatus'] == 'SUCCEEDED').toList();
    final past = _orders.where((o) => !active.contains(o)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Orders', 'Tilaukset')),
        actions: [
          IconButton(
            tooltip: tr(context, 'Returns', 'Palautukset'),
            icon: const Icon(Icons.assignment_return_outlined),
            onPressed: auth.isAuthenticated
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen()))
                : null,
          ),
        ],
      ),
      body: !auth.isAuthenticated
          ? _empty(Icons.receipt_long_outlined, tr(context, 'Sign in to see your orders.', 'Kirjaudu sisään nähdäksesi tilauksesi.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null
                      ? ListView(children: [_empty(Icons.wifi_off_rounded, _error!)])
                      : _orders.isEmpty
                          ? ListView(children: [
                              _empty(Icons.shopping_bag_outlined,
                                  tr(context, 'No orders yet. When you order, you can follow it here live.', 'Ei vielä tilauksia. Kun tilaat, voit seurata sitä täällä reaaliajassa.'))
                            ])
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                              children: [
                                if (active.isNotEmpty) _section(tr(context, 'On its way', 'Tulossa')),
                                ...active.map(_card),
                                if (past.isNotEmpty) _section(tr(context, 'Earlier', 'Aiemmat')),
                                ...past.map(_card),
                              ],
                            ),
                ),
    );
  }

  Widget _empty(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 120, 40, 40),
        child: Column(children: [
          Icon(icon, size: 56, color: AppTheme.secondaryText(context)),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 15, height: 1.4)),
        ]),
      );

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.secondaryText(context), letterSpacing: 0.3)),
      );

  (String, Color) _status(Map<String, dynamic> o) {
    switch (o['status']) {
      case 'PENDING':
        return o['paymentStatus'] == 'SUCCEEDED'
            ? (tr(context, 'Waiting for the store', 'Odottaa kauppaa'), AppTheme.warning)
            : (tr(context, 'Payment not finished', 'Maksu kesken'), AppTheme.warning);
      case 'CONFIRMED':
        return (tr(context, 'Accepted', 'Hyväksytty'), AppTheme.primary);
      case 'PROCESSING':
        return (tr(context, 'Being packed', 'Pakataan'), AppTheme.primary);
      case 'SHIPPED':
        return (tr(context, 'On its way', 'Matkalla'), AppTheme.primary);
      case 'DELIVERED':
        return (tr(context, 'Delivered', 'Toimitettu'), AppTheme.success);
      case 'REFUNDED':
        return (tr(context, 'Refunded', 'Hyvitetty'), AppTheme.secondaryText(context));
      default:
        return (tr(context, 'Cancelled', 'Peruttu'), AppTheme.secondaryText(context));
    }
  }

  Widget _card(Map<String, dynamic> o) {
    final (label, color) = _status(o);
    final items = (o['items'] as List?) ?? [];
    final first = items.isNotEmpty ? items.first : null;
    final images = (first?['product']?['images'] as List?)?.cast<String>() ?? const [];
    final created = DateTime.tryParse('${o['createdAt']}')?.toLocal();
    final count = items.fold<int>(0, (s, i) => s + (asInt(i['quantity']) ?? 0));

    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: asInt(o['id'])!)));
        if (mounted) _load(quiet: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 68,
                child: images.isEmpty
                    ? Container(color: AppTheme.primaryLight, child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary))
                    : CachedNetworkImage(imageUrl: images.first, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o['store']?['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primaryText(context))),
                  const SizedBox(height: 2),
                  Text(
                    '${tr(context, '$count item(s)', '$count tuote(tta)')} · ${euro(context, o['totalCents'])}'
                    '${created != null ? ' · ${created.day}.${created.month}.' : ''}',
                    style: TextStyle(fontSize: 13, color: AppTheme.secondaryText(context)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
          ],
        ),
      ),
    );
  }
}
