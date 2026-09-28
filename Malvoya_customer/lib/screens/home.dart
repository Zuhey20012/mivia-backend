import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'store_detail.dart';
import 'category_detail.dart';
import 'order_detail.dart';
import 'location_selector_modal.dart';
import 'notification_center_drawer.dart';
import 'returns_screen.dart';
import '../core/delivery_location.dart';
import '../core/strings.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List stores = [];
  bool loading = true;
  bool error = false;
  bool hasActiveOrder = false;
  Map<String, dynamic>? activeOrder;
  String _currentDeliveryCity = 'Helsinki (Keskusta)';

  late AnimationController _radarPulseCtrl;
  late Animation<double> _radarPulseAnim;

  final List<Map<String, dynamic>> categories = [
    {'name': 'Clothing', 'icon': Icons.checkroom_rounded, 'color': Color(0xFF6D2E8C)},
    {'name': 'Shoes', 'icon': Icons.snowshoeing_rounded, 'color': Color(0xFF8E4FAE)},
    {'name': 'Bags', 'icon': Icons.shopping_bag_rounded, 'color': Color(0xFF9B5DB8)},
    {'name': 'Accessories', 'icon': Icons.watch_rounded, 'color': Color(0xFFE08A00)},
    {'name': 'Jewelry', 'icon': Icons.diamond_rounded, 'color': Color(0xFF248A52)},
    {'name': 'Vintage', 'icon': Icons.auto_awesome_rounded, 'color': Color(0xFF6D2E8C)},
    {'name': 'Beauty', 'icon': Icons.spa_rounded, 'color': Color(0xFFC2412D)},
    {'name': 'Home', 'icon': Icons.chair_rounded, 'color': Color(0xFF6366F1)},
    {'name': 'Returns', 'icon': Icons.assignment_return_rounded, 'color': Color(0xFF6D2E8C)},
    {'name': 'Eco-Friendly', 'icon': Icons.eco_rounded, 'color': Color(0xFF248A52)},
    {'name': 'Second Hand', 'icon': Icons.recycling_rounded, 'color': Color(0xFF8E4FAE)},
  ];

  @override
  void initState() {
    super.initState();
    _radarPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _radarPulseAnim = Tween<double>(begin: 0.85, end: 1.18).animate(
      CurvedAnimation(parent: _radarPulseCtrl, curve: Curves.easeInOut),
    );
    DeliveryLocation.instance.addListener(_onLocationChanged);
    DeliveryLocation.instance.load().then((_) {
      final addr = DeliveryLocation.instance.address;
      if (addr != null && mounted) setState(() => _currentDeliveryCity = addr);
      fetchStores();
    });
    checkActiveOrders();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() => loading = true);
    fetchStores();
  }

  Future<void> checkActiveOrders() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) return;
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/orders'),
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final list = data is List ? data : (data['orders'] ?? []);
        final activeList = list.where((o) =>
          ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])
        ).toList();
        if (activeList.isNotEmpty) {
          setState(() {
            hasActiveOrder = true;
            activeOrder = Map<String, dynamic>.from(activeList.first);
          });
        } else {
          setState(() {
            hasActiveOrder = false;
            activeOrder = null;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    DeliveryLocation.instance.removeListener(_onLocationChanged);
    _radarPulseCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchStores() async {
    try {
      final q = DeliveryLocation.instance.query;
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/stores').replace(queryParameters: q.isEmpty ? null : q))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            stores = data['stores'] ?? [];
            loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            error = true;
            loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = true;
          loading = false;
        });
      }
    }
  }

  Widget _buildCategoryItem(BuildContext context, Map<String, dynamic> cat, AppLocalizations l10n) {
    final catColor = cat['color'] as Color? ?? AppTheme.primary;
    final catName = cat['name'] as String;
    final localizedName = l10n.translateCategory(catName);
    final textPrimary = AppTheme.primaryText(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (catName == 'Returns') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReturnsScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryDetailScreen(categoryName: catName),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    catColor.withValues(alpha: 0.28),
                    catColor.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: catColor.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(cat['icon'] as IconData, color: catColor, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 72,
              child: Text(
                localizedName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown only while you have a real order on its way.
  Widget _buildRadarBanner(BuildContext context, AppLocalizations l10n, bool isDark) {
    final order = activeOrder;
    if (!hasActiveOrder || order == null) return const SizedBox.shrink();
    final status = order['status'];
    final label = switch (status) {
      'PENDING' => tr(context, 'Waiting for the store', 'Odottaa kauppaa'),
      'CONFIRMED' => tr(context, 'Accepted by the store', 'Kauppa hyväksyi'),
      'PROCESSING' => tr(context, 'Being packed', 'Pakataan'),
      _ => tr(context, 'On its way to you', 'Matkalla sinulle'),
    };
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: asInt(order['id'])!)));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            ScaleTransition(
              scale: _radarPulseAnim,
              child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${order['store']?['name'] ?? ''} · #${order['id']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Text(tr(context, 'Track', 'Seuraa'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreCard(BuildContext context, Map<String, dynamic> store, bool isDark) {
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final reviews = asInt(store['totalReviews']) ?? 0;
    final eta = etaWindow(store);
    final km = store['distanceKm'];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.cardBorder(context), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: store['bannerUrl'] != null
                  ? CachedNetworkImage(imageUrl: store['bannerUrl'], fit: BoxFit.cover)
                  : Container(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6D2E8C), Color(0xFF55226E)])),
                      child: Center(
                        child: store['logoUrl'] != null
                            ? CircleAvatar(radius: 34, backgroundImage: CachedNetworkImageProvider(store['logoUrl']))
                            : const Icon(Icons.storefront_rounded, size: 56, color: Colors.white),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(store['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                      ),
                      if (reviews > 0) ...[
                        const Icon(Icons.star_rounded, size: 17, color: Color(0xFFE08A00)),
                        const SizedBox(width: 3),
                        Text('${store['rating']} ($reviews)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                      ] else
                        Text(tr(context, 'New', 'Uusi'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primary)),
                    ],
                  ),
                  if ((store['description'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(store['description'], maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textSecondary, fontSize: 13, height: 1.3)),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      if (eta != null) _meta(Icons.schedule_rounded, eta, textSecondary),
                      _meta(Icons.delivery_dining_rounded, '${euro(context, store['deliveryFeeCents'])} ${tr(context, 'delivery', 'toimitus')}', textSecondary),
                      if (km != null) _meta(Icons.near_me_outlined, '$km km', textSecondary),
                      if (store['sellerType'] == 'PRIVATE') _meta(Icons.person_outline_rounded, tr(context, 'Private seller', 'Yksityinen myyjä'), textSecondary),
                    ],
                  ),
                  if (!DeliveryLocation.instance.hasCoordinates)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tr(context, 'Pin your address on the map to see the exact delivery fee and time.',
                            'Merkitse osoitteesi kartalle nähdäksesi tarkan toimitusmaksun ja -ajan.'),
                        style: TextStyle(fontSize: 11.5, color: textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ],
      );

  Widget _buildStoresEmptyState(BuildContext context, AppLocalizations l10n, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.cardBorder(context), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D2E8C), Color(0xFF55226E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6D2E8C).withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.translate('launchingCityTitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.primaryText(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('launchingCitySubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(context),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerStoreCard(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder(context), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 140, width: double.infinity, color: Colors.white),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 20, width: 200, color: Colors.white),
                  const SizedBox(height: 6),
                  Container(height: 14, width: 150, color: Colors.white),
                  const SizedBox(height: 12),
                  Container(height: 14, width: 100, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF221C29) : Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => LocationSelectorModal(
                    currentLocation: _currentDeliveryCity,
                    onLocationSelected: (newCity) {
                      setState(() {
                        _currentDeliveryCity = newCity;
                      });
                    },
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('deliveringTo'),
                    style: const TextStyle(
                      color: Color(0xFF6D2E8C),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentDeliveryCity,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: textSecondary),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6D2E8C).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_none_rounded, size: 20, color: Color(0xFF6D2E8C)),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  NotificationCenterDrawer.show(context);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: RefreshIndicator(
            color: const Color(0xFF6D2E8C),
            onRefresh: fetchStores,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Live Courier Radar Banner
                    _buildRadarBanner(context, l10n, isDark),

                    // Categories Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.translate('categories'),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 104,
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        itemBuilder: (context, index) =>
                            _buildCategoryItem(context, categories[index], l10n),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Stores Near You Section
                    Text(
                      l10n.translate('storesNearYou'),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (loading)
                      Column(
                        children: List.generate(3, (index) => _buildShimmerStoreCard(context, isDark)),
                      )
                    else if (error)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 48, color: textSecondary),
                              const SizedBox(height: 16),
                              Text(
                                l10n.translate('couldNotLoadStores'),
                                style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    loading = true;
                                    error = false;
                                  });
                                  fetchStores();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6D2E8C),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (stores.isEmpty)
                      _buildStoresEmptyState(context, l10n, isDark)
                    else
                      ...stores.map((s) => _buildStoreCard(context, s, isDark)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
