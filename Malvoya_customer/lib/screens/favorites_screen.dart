import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../core/sign_in.dart';
import '../widgets/product_tile.dart';
import 'main_navigation.dart';

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
          ? MStateMessage(
              icon: Icons.favorite_border_rounded,
              message: tr(context, 'Sign in to save favourites.', 'Kirjaudu sisään tallentaaksesi suosikkeja.'),
              actionLabel: tr(context, 'Sign in / Create account', 'Kirjaudu / Luo tili'),
              onAction: () async {
                if (await openSignIn(context) && mounted) {
                  setState(() => _loading = true);
                  _load();
                }
              },
            )
          : _loading
              ? const MSkeletonProductGrid(padding: EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.x4l))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _error != null && _items.isEmpty
                      ? MStateMessage.error(
                          message: _error!,
                          onRetry: () {
                            setState(() => _loading = true);
                            _load();
                          })
                      : _items.isEmpty
                      ? MStateMessage(
                          icon: Icons.favorite_border_rounded,
                          title: tr(context, 'No favourites yet', 'Ei vielä suosikkeja'),
                          message: tr(context, 'Tap the heart on any item to save it here.', 'Tallenna tuotteita tänne sydämellä.'),
                          actionLabel: tr(context, 'Discover items', 'Löydä tuotteita'),
                          actionIcon: Icons.search_rounded,
                          onAction: () => openMainTab(context, MainTab.search),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.x4l),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => ProductTile(product: _items[i]),
                        ),
                ),
    );
  }
}
