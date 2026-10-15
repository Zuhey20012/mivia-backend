import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../core/api_client.dart';
import '../core/sign_in.dart';
import '../core/strings.dart';
import '../widgets/product_tile.dart';
import '../widgets/skeleton.dart';

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
      _error = res.ok ? null : res.errorText(context);
      if (res.ok) _items = ((res.data['products'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Provider.of<AuthService>(context).isAuthenticated;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Favourites', 'Suosikit'))),
      body: !signedIn
          ? StateMessage(
              icon: Icons.favorite_border_rounded,
              message: tr(context, 'Sign in to save favourites.', 'Kirjaudu sisään tallentaaksesi suosikkeja.'),
              actionLabel: tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili'),
              onRetry: () async {
                if (await openSignIn(context) && mounted) {
                  setState(() => _loading = true);
                  _load();
                }
              },
            )
          : _loading
              ? const SkeletonProductGrid(padding: EdgeInsets.fromLTRB(16, 16, 16, 40))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null && _items.isEmpty
                      ? StateMessage.error(
                          message: _error!,
                          onRetry: () {
                            setState(() => _loading = true);
                            _load();
                          })
                      : _items.isEmpty
                      ? StateMessage(
                          icon: Icons.favorite_border_rounded,
                          message: tr(context, 'Tap the heart on any item to save it here.', 'Tallenna tuotteita tänne sydämellä.'),
                        )
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
