import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';

class VendorDashboard extends StatelessWidget {
  const VendorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vendor Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Orders'),
              Tab(text: 'Menu/Products'),
              Tab(text: 'Performance'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Orders
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Order #1024', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            Text('2 mins ago', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('1x Vintage Levi\'s Denim Jacket'),
                        const Text('1x Designer Silk Scarf'),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Reject'))),
                            const SizedBox(width: 16),
                            Expanded(child: ElevatedButton(onPressed: () {}, child: const Text('Accept & Prep'))),
                          ],
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
            // Products
            const Center(child: Text('Product Inventory Management')),
            // Performance
            const Center(child: Text('Sales & Payouts')),
          ],
        ),
      ),
    );
  }
}
