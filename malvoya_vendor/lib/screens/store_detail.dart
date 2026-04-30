import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import '../config/constants.dart';
import '../cart.dart';
import '../models.dart';
import '../checkout.dart';

class StoreDetailScreen extends StatefulWidget {
  final Map<String, dynamic> store;

  const StoreDetailScreen({super.key, required this.store});

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  List products = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final res = await http.get(Uri.parse('${AppConstants.apiBase}/stores/${widget.store['id']}/products'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          products = data['products'] ?? [];
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    final cart = Provider.of<CartService>(context, listen: false);
    final priceCents = product['salePriceCents'] ?? product['rentalDayCents'] ?? 0;
    
    cart.add(CartItem(
      productId: product['id'],
      name: product['name'],
      price: priceCents / 100.0,
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} added to cart'),
        duration: const Duration(seconds: 1),
        action: SnackBarAction(
          label: 'VIEW CART',
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
          },
        ),
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final imageUrl = (product['images'] != null && product['images'].isNotEmpty) 
        ? product['images'][0] 
        : 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800';
    final priceCents = product['salePriceCents'] ?? product['rentalDayCents'] ?? 0;
    final price = priceCents / 100.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: Image.network(
              imageUrl,
              height: 120,
              width: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 120,
                width: 120,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'], style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    product['description'] ?? product['category'] ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('\$${price.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 16)),
                      ElevatedButton(
                        onPressed: () => _addToCart(product),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.store['bannerUrl'] ?? 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800';
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.store['name'] ?? 'Store', style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black54)])),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withOpacity(0.5)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.store, size: 100, color: Colors.white24),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 24),
                      const SizedBox(width: 8),
                      Text('${widget.store['rating'] ?? 0.0} (${widget.store['totalReviews'] ?? 0}+ ratings)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      const Icon(Icons.info_outline, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(widget.store['description'] ?? 'No description available.', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Products', style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 16),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (products.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No products available right now.')))
                  else
                    ...products.map((p) => _buildProductItem(p)).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<CartService>(
        builder: (context, cart, child) {
          if (cart.items.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
            },
            label: Text('View Cart (\$${cart.total.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            backgroundColor: Theme.of(context).primaryColor,
          );
        },
      ),
    );
  }
}
