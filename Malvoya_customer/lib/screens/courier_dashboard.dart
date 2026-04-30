import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';

class CourierDashboard extends StatelessWidget {
  const CourierDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courier Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).primaryColor,
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.blue)),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mikael K.', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Online & Looking for gigs', style: TextStyle(color: Colors.white70)),
                  ],
                ),
                const Spacer(),
                Switch(value: true, onChanged: (v) {}, activeColor: Colors.green),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.grey.shade200,
              child: Stack(
                children: [
                  const Center(child: Icon(Icons.map, size: 200, color: Colors.black12)), // Map Placeholder
                  Positioned(
                    bottom: 24, left: 16, right: 16,
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('New Delivery Available', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 8),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Pickup: Sakura Boutique'),
                                Text('2.5 km', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                            const Divider(),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Dropoff: Home - Helsinki'),
                                Text('Estimated: \$8.50', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                child: const Text('Swipe to Accept'),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
