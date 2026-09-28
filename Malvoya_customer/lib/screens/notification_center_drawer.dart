import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import 'order_detail.dart';

/// Latest status of your orders. Only real events are listed — nothing is shown as "sent"
/// unless Malvoya actually sent it.
class NotificationCenterDrawer extends StatefulWidget {
  const NotificationCenterDrawer({super.key});

  static void show(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationCenterDrawer(),
    );
  }

  @override
  State<NotificationCenterDrawer> createState() => _NotificationCenterDrawerState();
}

class _NotificationCenterDrawerState extends State<NotificationCenterDrawer> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    final res = await ApiClient(auth).get('/orders');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _orders = ((res.data['orders'] as List?) ?? [])
            .map((o) => Map<String, dynamic>.from(o))
            .where((o) => o['paymentStatus'] != 'PENDING')
            .toList()
          ..sort((a, b) => '${b['updatedAt']}'.compareTo('${a['updatedAt']}'));
      }
    });
  }

  String _message(Map<String, dynamic> o) {
    switch (o['status']) {
      case 'PENDING':
        return tr(context, 'Paid — waiting for the store to accept', 'Maksettu — odottaa kaupan hyväksyntää');
      case 'CONFIRMED':
        return tr(context, 'The store accepted your order', 'Kauppa hyväksyi tilauksesi');
      case 'PROCESSING':
        return tr(context, 'Your order is being packed', 'Tilaustasi pakataan');
      case 'SHIPPED':
        return tr(context, 'Your courier is on the way', 'Kuriiri on matkalla');
      case 'DELIVERED':
        return tr(context, 'Delivered', 'Toimitettu');
      case 'REFUNDED':
        return tr(context, 'Refunded', 'Hyvitetty');
      default:
        return tr(context, 'Cancelled', 'Peruttu');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.cardBorder(context), borderRadius: BorderRadius.circular(2))),
          ListTile(
            title: Text(tr(context, 'Updates', 'Ilmoitukset'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            subtitle: Text(tr(context, 'Your latest order updates', 'Tilaustesi viimeisimmät tapahtumat')),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(tr(context, 'Nothing new yet.', 'Ei uutta.'),
                              style: TextStyle(color: AppTheme.secondaryText(context))),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _orders.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.cardBorder(context)),
                        itemBuilder: (_, i) {
                          final o = _orders[i];
                          final t = DateTime.tryParse('${o['updatedAt']}')?.toLocal();
                          return ListTile(
                            leading: const CircleAvatar(backgroundColor: AppTheme.primaryLight, child: Icon(Icons.receipt_long_rounded, color: AppTheme.primary)),
                            title: Text('${o['store']?['name'] ?? ''} · #${o['id']}'),
                            subtitle: Text(_message(o)),
                            trailing: t == null
                                ? null
                                : Text('${t.day}.${t.month}. ${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context))),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: asInt(o['id'])!)));
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
