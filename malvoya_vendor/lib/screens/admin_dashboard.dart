import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Provider.of<AuthService>(context, listen: false).logout();
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Platform Metrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMetricCard(context, 'Total Sales', '\$12,450', Icons.attach_money)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard(context, 'Active Orders', '34', Icons.receipt_long)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMetricCard(context, 'Active Couriers', '12', Icons.delivery_dining)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard(context, 'Stores', '156', Icons.store)),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Platform Controls', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.approval),
            title: const Text('Pending Store Approvals (5)'),
            trailing: const Icon(Icons.chevron_right),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Live Courier Map'),
            trailing: const Icon(Icons.chevron_right),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {},
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.payments),
            title: const Text('Stripe Payouts'),
            trailing: const Icon(Icons.chevron_right),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
