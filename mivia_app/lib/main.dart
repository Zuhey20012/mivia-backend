// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'cart.dart';
import 'checkout.dart';
import 'models.dart';

void main() => runApp(
  ChangeNotifierProvider(create: (_) => CartService(), child: const MyApp()),
);

/// If you run on Android emulator keep this value.
/// For iOS simulator use 'http://localhost:4000'.
/// For a physical device replace with your PC LAN IP like 'http://192.168.1.100:4000'.
const apiBase = 'http://10.0.2.2:4000';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIVIA',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ProductListPage(),
    );
  }
}

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});
  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  List products = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final res = await http.get(Uri.parse('$apiBase/products'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() {
          products = body['products'] ?? [];
          loading = false;
        });
      } else {
        setState(() {
          loading = false;
          error = 'Failed to load products: ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                loading = true;
                error = null;
              });
              fetchProducts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutPage()),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            )
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(p['name']),
                    subtitle: Text(
                      '\$${p['price']} • ${p['vendor']?['name'] ?? 'Unknown'}',
                    ),
                    trailing: ElevatedButton(
                      child: const Text('Add'),
                      onPressed: () {
                        final cartSvc = Provider.of<CartService>(
                          context,
                          listen: false,
                        );
                        cartSvc.add(
                          CartItem(
                            productId: p['id'],
                            name: p['name'],
                            price: (p['price'] as num).toDouble(),
                            variantId:
                                p['variants'] != null &&
                                    (p['variants'] as List).isNotEmpty
                                ? (p['variants'][0]['id'] as int)
                                : null,
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Added to cart')),
                        );
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailPage(product: p),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class ProductDetailPage extends StatelessWidget {
  final Map product;
  const ProductDetailPage({required this.product, super.key});
  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: Text(product['name'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product['description'] ?? '',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              'Price: \$${product['price']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (product['variants'] != null &&
                (product['variants'] as List).isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Variants',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final v in product['variants'])
                    Text(
                      '- ${v['sku']} ${v['size'] ?? ''} (stock: ${v['stock']})',
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ElevatedButton(
              onPressed: () {
                cart.add(
                  CartItem(
                    productId: product['id'],
                    name: product['name'],
                    price: (product['price'] as num).toDouble(),
                    variantId:
                        product['variants'] != null &&
                            (product['variants'] as List).isNotEmpty
                        ? product['variants'][0]['id'] as int
                        : null,
                  ),
                );
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Added to cart')));
              },
              child: const Text('Add to cart'),
            ),
          ],
        ),
      ),
    );
  }
}
