import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../admin_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<AdminStats?> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = Provider.of<AdminService>(context, listen: false).getStats();
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Malvoya Owner Dashboard'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _statsFuture = Provider.of<AdminService>(context, listen: false).getStats();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Provider.of<AuthService>(context, listen: false).logout();
            },
          )
        ],
      ),
      body: FutureBuilder<AdminStats?>(
        future: _statsFuture,
        builder: (context, snapshot) {
          final stats = snapshot.data;
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Platform Metrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context, 
                      'Total Sales', 
                      isLoading ? '...' : '\$${stats?.totalSales.toStringAsFixed(0) ?? '0'}', 
                      Icons.attach_money
                    )
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      context, 
                      'Active Orders', 
                      isLoading ? '...' : '${stats?.activeOrders ?? '0'}', 
                      Icons.receipt_long
                    )
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context, 
                      'Active Couriers', 
                      isLoading ? '...' : '${stats?.activeCouriers ?? '0'}', 
                      Icons.delivery_dining
                    )
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricCard(
                      context, 
                      'Stores', 
                      isLoading ? '...' : '${stats?.totalStores ?? '0'}', 
                      Icons.store
                    )
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text('Platform Controls', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.approval),
                title: const Text('Pending Store Approvals'),
                subtitle: const Text('Manage new vendor requests'),
                trailing: const Icon(Icons.chevron_right),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  // Navigate to Approvals Screen
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Live Courier Map'),
                subtitle: const Text('Track active deliveries in real-time'),
                trailing: const Icon(Icons.chevron_right),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {},
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('User Management'),
                subtitle: const Text('View and manage platform users'),
                trailing: const Icon(Icons.chevron_right),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {},
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.payments),
                title: const Text('Stripe Payouts'),
                subtitle: const Text('Review platform financial health'),
                trailing: const Icon(Icons.chevron_right),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {},
              ),
            ],
          );
        },
      ),
    );
  }
}
