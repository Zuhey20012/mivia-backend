import 'package:flutter/material.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Widget _buildOrderItem(BuildContext context, String status, String date, String total, String items) {
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
                Text(date, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'Delivered' ? Colors.green.withOpacity(0.1) : Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status, style: TextStyle(
                    color: status == 'Delivered' ? Colors.green : Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(items, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {},
                  child: const Text('View Receipt'),
                )
              ],
            )
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
        body: TabBarView(
          children: [
            // Active
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOrderItem(context, 'Processing', 'Today, 14:30', '\$45.99', '2x Rose Hip Face Serum'),
              ],
            ),
            // Past
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOrderItem(context, 'Delivered', '12 Apr 2026', '\$120.00', '1x Vintage Levi\'s Denim Jacket'),
                _buildOrderItem(context, 'Delivered', '05 Mar 2026', '\$34.50', '1x Bamboo Lip Palette\n1x Argan Oil'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
