import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import 'store_detail.dart';
import 'category_detail.dart';
import 'map_tracker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List stores = [];
  bool loading = true;
  bool error = false;
  bool hasActiveOrder = false;
  Map<String, dynamic>? _activeOrderData;

  final List<Map<String, dynamic>> categories = [
    {'name': 'Apparel', 'icon': Icons.checkroom},
    {'name': 'Cosmetics', 'icon': Icons.face},
    {'name': 'Skincare', 'icon': Icons.spa},
    {'name': 'Facial Products', 'icon': Icons.face_retouching_natural},
    {'name': 'Accessories', 'icon': Icons.watch},
    {'name': 'Pets', 'icon': Icons.pets},
    {'name': 'Eco Friendly', 'icon': Icons.eco},
    {'name': 'Home Based', 'icon': Icons.home_work},
    {'name': 'Small Sellers', 'icon': Icons.storefront},
    {'name': 'Boutiques', 'icon': Icons.style},
    {'name': 'Brand Stores', 'icon': Icons.verified},
    {'name': 'Thrift', 'icon': Icons.recycling},
    {'name': 'Second-hand', 'icon': Icons.sync_alt},
    {'name': 'Rentals', 'icon': Icons.handshake},
    {'name': 'Returns', 'icon': Icons.assignment_return},
  ];

  @override
  void initState() {
    super.initState();
    fetchStores();
  }

  Future<void> fetchStores() async {
    try {
      final res = await http.get(Uri.parse('${AppConstants.apiBase}/stores'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          stores = data['stores'] ?? [];
          loading = false;
        });
      } else {
        setState(() {
          error = true;
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = true;
        loading = false;
      });
    }
  }

  Widget _buildCategoryItem(Map<String, dynamic> cat) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryDetailScreen(categoryName: cat['name'] as String)));
      },
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(cat['icon'] as IconData, color: Theme.of(context).primaryColor, size: 28),
            ),
            const SizedBox(height: 8),
            Text(cat['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> store) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 20),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).primaryColor.withOpacity(0.8), Theme.of(context).primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(Icons.storefront, size: 64, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          store['name'] ?? 'Premium Malvoya Store',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.star, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 4),
                            Text('${store['rating'] ?? '4.9'}', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    store['description'] ?? store['category'] ?? 'Exquisite local goods',
                    style: TextStyle(color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.delivery_dining, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      const Text('15-25 min', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 16),
                      const Icon(Icons.attach_money, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      const Text('\$2.99 delivery', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Active Delivery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                child: const Text('Arriving in 15m', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(child: Text('Courier Mikael K. is on the way', style: TextStyle(color: Colors.white70))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(80, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MapTrackerScreen()));
                },
                child: const Text('Track Map'),
              )
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: 0.6, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), borderRadius: BorderRadius.circular(4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivering to', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).primaryColor)),
            const Row(
              children: [
                Text('Home - Helsinki', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Icon(Icons.keyboard_arrow_down, size: 20),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: () {}),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchStores,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasActiveOrder) _buildActiveOrderBanner(),
                Text('Categories', style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    itemBuilder: (context, index) => _buildCategoryItem(categories[index]),
                  ),
                ),
                const SizedBox(height: 32),
                Text('Stores Near You', style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 16),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
                else if (error)
                  const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('Failed to load stores. Pull to refresh.')))
                else if (stores.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No stores found.')))
                else
                  ...stores.map((s) => _buildStoreCard(s)).toList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

