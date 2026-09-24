import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../cart.dart';
import '../config/theme.dart';
import 'home.dart';
import 'video_feed.dart';
import 'search.dart';
import 'orders.dart';
import 'profile.dart';
import '../checkout.dart';
import '../l10n.dart';
import '../locale_provider.dart';

/**
 * Malvoya Master Navigation Hub
 * Dynamically localized across 25 languages with high-performance IndexedStack,
 * Shoppable High-Fashion Live Drops (TikTok-style 120Hz Reel), and decoupled Floating Bag Island.
 */

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<Widget> _buildScreens(String langCode) => [
    HomeScreen(key: ValueKey('home_$langCode')),
    SearchScreen(key: ValueKey('search_$langCode'), isTab: true),
    VideoFeedScreen(key: ValueKey('drop_$langCode')),
    OrdersScreen(key: ValueKey('orders_$langCode')),
    ProfileScreen(key: ValueKey('profile_$langCode')),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: _buildScreens(localeProvider.locale.languageCode),
              ),

              // Decoupled Floating Bag Island Widget
              Positioned(
                bottom: 84,
                left: 16,
                right: 16,
                child: _buildFloatingBagIsland(l10n),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: isDark ? 0.22 : 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xEB1C1820)
                        : Colors.white.withValues(alpha: 0.94),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(
                        color: isDark ? const Color(0x336D2E8C) : AppTheme.glassBorder,
                        width: 1.2,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      height: 66,
                      child: Row(
                        children: [
                          _navItem(0, Icons.explore_outlined, Icons.explore_rounded, l10n.translate('home')),
                          _navItem(1, Icons.search_outlined, Icons.search_rounded, l10n.translate('search')),
                          _videoNavItem(2, l10n.translate('drop')),
                          _navItem(3, Icons.receipt_long_outlined, Icons.receipt_long_rounded, l10n.translate('orders')),
                          _navItem(4, Icons.person_outline_rounded, Icons.person_rounded, l10n.translate('profile')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingBagIsland(AppLocalizations l10n) {
    return Consumer<CartService>(
      builder: (ctx, cart, _) {
        if (cart.items.isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutPage()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppTheme.irisFuchsiaGradient,
              borderRadius: BorderRadius.circular(22),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 1.2),
                left: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                right: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 1.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${cart.itemCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.translate('viewBag'),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '€${cart.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.translate('checkoutAndDispatch'),
                        style: const TextStyle(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.arrow_forward_rounded, color: AppTheme.primaryDark, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _videoNavItem(int index, String label) {
    final isSelected = _index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _index = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0x246D2E8C) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSelected ? Icons.bolt_rounded : Icons.bolt_outlined,
                color: isSelected ? const Color(0xFF6D2E8C) : AppTheme.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? const Color(0xFF6D2E8C) : AppTheme.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int actualIndex, IconData icon, IconData activeIcon, String label) {
    final isSelected = _index == actualIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _index = actualIndex);
          _pageController.animateToPage(
            actualIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                size: 23,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
