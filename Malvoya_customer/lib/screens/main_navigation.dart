import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../cart.dart';
import '../config/theme.dart';
import '../core/deep_links.dart';
import '../core/strings.dart';
import 'home.dart';
import 'drops_feed.dart';
import 'search.dart';
import 'orders.dart';
import 'profile.dart';
import '../checkout.dart';
import '../l10n.dart';

/// Lets the main screen notice when a screen pushed over it (checkout, an order, a store) closes.
final mainRouteObserver = RouteObserver<ModalRoute<void>>();

/// Five tabs: Home, Search, Drops (shoppable videos), Orders and Profile, in a floating pill bar.
/// A floating bag bar appears whenever the bag has items (hidden on Drops, which has its own buy
/// buttons).
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with RouteAware {
  static const _homeTab = 0;
  static const _dropsTab = 2;
  int _index = 0;

  /// Tabs are built the first time they are opened and then kept alive (scroll position, search,
  /// loaded lists), so switching back is instant.
  final Set<int> _opened = {0};

  /// Tells Home it is visible again, so it refreshes the active order.
  final _homeVisible = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // Links to a drop, store or invite open once the main screen is up
    DeepLinks.instance.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) mainRouteObserver.subscribe(this, route);
  }

  /// Back on the main screen (e.g. after paying): Home checks the active order again.
  @override
  void didPopNext() {
    if (_index == _homeTab) _homeVisible.value++;
  }

  @override
  void dispose() {
    mainRouteObserver.unsubscribe(this);
    DeepLinks.instance.detach();
    _homeVisible.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = index;
      _opened.add(index);
    });
    if (index == _homeTab) _homeVisible.value++;
  }

  Widget _screen(int i) {
    if (!_opened.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => HomeScreen(onOpenDrops: () => _go(_dropsTab), visible: _homeVisible),
      1 => const SearchScreen(isTab: true),
      // The feed pauses its video whenever another tab is showing
      2 => DropsFeedScreen(isActive: _index == _dropsTab),
      3 => const OrdersScreen(),
      _ => const ProfileScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Builder(
      builder: (context) {
        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              IndexedStack(
                index: _index,
                // Hidden tabs keep their state but stop their animations
                children: [for (var i = 0; i < 5; i++) TickerMode(enabled: i == _index, child: _screen(i))],
              ),
              if (_index != _dropsTab)
                // With extendBody the body's bottom padding already includes the tab bar.
                Builder(
                  builder: (ctx) => Positioned(
                    bottom: MediaQuery.of(ctx).padding.bottom + 10,
                    left: 16,
                    right: 16,
                    child: _bagBar(l10n),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Container(
              height: 66,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2331) : AppTheme.night,
                borderRadius: BorderRadius.circular(33),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  _tab(0, Icons.home_outlined, Icons.home_rounded, l10n.translate('home')),
                  _tab(1, Icons.search_rounded, Icons.search_rounded, l10n.translate('search')),
                  _tab(2, Icons.play_circle_outline_rounded, Icons.play_circle_rounded, tr(context, 'Drops', 'Dropit')),
                  _tab(3, Icons.receipt_long_outlined, Icons.receipt_long_rounded, l10n.translate('orders')),
                  _tab(4, Icons.person_outline_rounded, Icons.person_rounded, l10n.translate('profile')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The selected tab grows into a sunny pill with its name; the others show just an icon.
  Widget _tab(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _index == index;
    return Expanded(
      flex: selected ? 7 : 3,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? AppTheme.sunshine : Colors.transparent,
              borderRadius: BorderRadius.circular(27),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? activeIcon : icon, size: 23, color: selected ? AppTheme.ink : Colors.white.withValues(alpha: 0.72)),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.ink, fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bagBar(AppLocalizations l10n) {
    return Consumer<CartService>(
      builder: (ctx, cart, _) {
        if (cart.items.isEmpty) return const SizedBox.shrink();
        return Semantics(
          button: true,
          label: '${l10n.translate('viewBag')}, ${cart.itemCount}, ${euro(ctx, (cart.total * 100).round())}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
            },
            child: Container(
              height: 62,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(31),
                boxShadow: [
                  BoxShadow(color: AppTheme.primary.withValues(alpha: 0.32), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(color: AppTheme.sunshine, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${cart.itemCount}',
                        style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l10n.translate('viewBag'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(euro(ctx, (cart.total * 100).round()),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      ],
                    ),
                  ),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr(ctx, 'Checkout', 'Kassalle'),
                            style: const TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w800, fontSize: 14.5)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryDark, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
