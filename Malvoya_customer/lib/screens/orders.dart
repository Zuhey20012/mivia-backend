import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth_service.dart';
import '../config/constants.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> _activeOrders = [];
  List<dynamic> _pastOrders = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) {
      setState(() { _loading = false; });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/orders'),
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orders = data is List ? data : (data['orders'] ?? []);
        setState(() {
          _activeOrders = orders.where((o) =>
            ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])
          ).toList();
          _pastOrders = orders.where((o) =>
            ['DELIVERED', 'CANCELLED', 'REFUNDED'].contains(o['status'])
          ).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = true; _loading = false; });
      }
    } catch (e) {
      debugPrint('Failed to load orders: $e');
      setState(() { _error = true; _loading = false; });
    }
  }

  String _formatCents(int? cents) {
    if (cents == null) return '\$0.00';
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  Widget _buildOrderItem(BuildContext context, Map<String, dynamic> order) {
    final status = order['status'] ?? 'PENDING';
    final createdAt = order['createdAt'] ?? '';
    final totalCents = order['totalCents'] as int? ?? 0;
    final items = order['items'] as List? ?? [];
    final storeName = order['store']?['name'] ?? 'Store';
    
    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    final itemNames = items.map((i) {
      final qty = i['quantity'] ?? 1;
      final name = i['product']?['name'] ?? 'Item';
      return '${qty}x $name';
    }).join('\n');

    final bool isActive = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : (status == 'DELIVERED' ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status, style: TextStyle(
                    color: isActive
                        ? Theme.of(context).primaryColor
                        : (status == 'DELIVERED' ? Colors.green : Colors.red),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  )),
                ),
              ],
            ),
            if (itemNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(itemNames, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: ${_formatCents(totalCents)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Past Orders'),
            ],
          ),
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Could not load orders'),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () { setState(() { _loading = true; _error = false; }); _fetchOrders(); }, child: const Text('Retry')),
                  ],
                ),
              )
            : TabBarView(
                children: [
                  // Active orders
                  _activeOrders.isEmpty
                    ? _buildEmptyState('No active orders')
                    : RefreshIndicator(
                        onRefresh: _fetchOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _activeOrders.length,
                          itemBuilder: (ctx, i) => _buildOrderItem(context, _activeOrders[i]),
                        ),
                      ),
                  // Past orders
                  _pastOrders.isEmpty
                    ? _buildEmptyState('No past orders yet')
                    : RefreshIndicator(
                        onRefresh: _fetchOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pastOrders.length,
                          itemBuilder: (ctx, i) => _buildOrderItem(context, _pastOrders[i]),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
