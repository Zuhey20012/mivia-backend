import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';
import '../widgets/product_tile.dart';

/// Items you saved with the heart button.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

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
    final res = await ApiClient(auth).get('/me/favorites');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.error;
      if (res.ok) _items = ((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Provider.of<AuthService>(context).isAuthenticated;
    final muted = AppTheme.secondaryText(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Favourites', 'Suosikit'))),
      body: !signedIn
          ? Center(child: Text(tr(context, 'Sign in to save favourites.', 'Kirjaudu sisään tallentaaksesi suosikkeja.'), style: TextStyle(color: muted)))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(40, 120, 40, 40),
                            child: Column(children: [
                              Icon(Icons.favorite_border_rounded, size: 56, color: muted),
                              const SizedBox(height: 12),
                              Text(
                                _error ?? tr(context, 'Tap the heart on any item to save it here.', 'Tallenna tuotteita tänne sydämellä.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: muted, fontSize: 15),
                              ),
                            ]),
                          ),
                        ])
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => ProductTile(product: _items[i]),
                        ),
                ),
    );
  }
}
