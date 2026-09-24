import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import 'add_product.dart';
import 'store_setup.dart';
import '../l10n.dart';
import '../services/socket_service.dart';

class VendorDashboard extends StatefulWidget {
  const VendorDashboard({super.key});
  @override
  State<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends State<VendorDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _orders = [];
  List _products = [];
  Map<String, dynamic>? _store;
  bool _loadingOrders = true;
  bool _loadingProducts = true;
  bool _connectionError = false;

  final List<Map<String, dynamic>> _merchantDrops = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
      final auth = Provider.of<AuthService>(context, listen: false);
      VendorSocketService().connect(auth.accessToken ?? '');
    });
    VendorSocketService().addListener(_onSocketUpdate);
  }

  void _onSocketUpdate() {
    _fetchOrders();
  }

  @override
  void dispose() {
    VendorSocketService().removeListener(_onSocketUpdate);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _connectionError = false);
    await Future.wait([_fetchStore(), _fetchOrders(), _loadLocalDrops()]);
  }

  Future<void> _loadLocalDrops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vendor_local_drops');
      if (raw != null) {
        final List list = jsonDecode(raw);
        if (mounted) {
          setState(() {
            _merchantDrops.clear();
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                _merchantDrops.add(item);
              } else if (item is Map) {
                _merchantDrops.add(Map<String, dynamic>.from(item));
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  String _authHeader() {
    final auth = Provider.of<AuthService>(context, listen: false);
    return 'Bearer ${auth.accessToken}';
  }

  Future<void> _fetchStore() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/stores/my'),
        headers: {'Authorization': _authHeader()},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() { _store = body['store'] ?? body; });
        await _fetchProducts();
      } else if (res.statusCode == 404) {
        // No store yet: go through setup (the server is the only source of truth)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StoreSetupScreen()));
        });
      } else {
        setState(() => _connectionError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _connectionError = true);
    }
  }

  Future<void> _fetchOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/orders'),
        headers: {'Authorization': _authHeader()},
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() { _orders = data is List ? data : (data['orders'] ?? []); });
      } else {
        if (mounted) setState(() => _connectionError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _connectionError = true);
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _fetchProducts() async {
    if (_store == null) return;
    setState(() => _loadingProducts = true);
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/stores/${_store!['id']}/products'),
        headers: {'Authorization': _authHeader()},
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() { _products = data['products'] ?? data ?? []; });
      } else {
        if (mounted) setState(() => _connectionError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _connectionError = true);
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Future<void> _updateOrderStatus(int orderId, String status) async {
    try {
      final res = await http.patch(
        Uri.parse('${AppConstants.apiBase}/orders/$orderId/status'),
        headers: {'Authorization': _authHeader(), 'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        _fetchOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'CONFIRMED' ? '✅ Order accepted!' : '❌ Order rejected'),
          ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final l10n = AppLocalizations.of(context);
    final vendorName = auth.currentUser?.name ?? 'Vendor';
    final pendingCount = _orders.where((o) => o['status'] == 'PENDING').length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_store?['name'] ?? AppLocalizations.of(context).translate('yourStoreFallback'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(vendorName, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w400)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => auth.logout(),
            tooltip: 'Sign out',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.translate('orders')),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(10)),
                      child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: l10n.translate('inventory')),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_filled_rounded, size: 15, color: Color(0xFFE0245E)),
                  const SizedBox(width: 4),
                  Text(l10n.translate('videoDrops')),
                ],
              ),
            ),
            Tab(text: l10n.translate('dashboard')),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_connectionError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF6D2E8C),
              child: const Text(
                'No connection. Please check your network and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildOrdersTab(),
                _buildProductsTab(),
                _buildVideoDropsTab(),
                _buildDashboardTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ORDERS TAB ────────────────────────────────────────────────────────────

  Widget _buildOrdersTab() {
    if (_loadingOrders) return _shimmerList();
    if (_connectionError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Could not fetch orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchOrders,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D2E8C), foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) return _emptyState(
      icon: Icons.inbox_outlined,
      title: AppLocalizations.of(context).translate('noOrdersYet'),
      subtitle: 'Your first order will appear here. Share your store to attract customers!',
      color: AppTheme.primary,
    );

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _buildOrderCard(_orders[i]),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? 'PENDING';
    final items = (order['items'] as List?) ?? [];
    final totalCents = order['totalCents'] as int? ?? 0;
    final isPending = status == 'PENDING';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'PENDING': statusColor = AppTheme.warning; statusLabel = 'New Order!'; break;
      case 'CONFIRMED': statusColor = AppTheme.primary; statusLabel = 'Confirmed'; break;
      case 'PROCESSING': statusColor = Colors.blue; statusLabel = 'Preparing'; break;
      case 'SHIPPED': statusColor = Colors.indigo; statusLabel = 'Shipped'; break;
      case 'DELIVERED': statusColor = const Color(0xFF2E6B4F); statusLabel = 'Delivered'; break;
      case 'CANCELLED': statusColor = AppTheme.accent; statusLabel = 'Cancelled'; break;
      default: statusColor = AppTheme.textSecondary; statusLabel = status;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPending ? AppTheme.warning.withOpacity(0.4) : AppTheme.divider),
        boxShadow: isPending ? [BoxShadow(color: AppTheme.warning.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))] : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${order['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.take(3).map((item) {
              final qty = item['quantity'] ?? 1;
              final name = item['product']?['name'] ?? 'Item';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 5, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text('${qty}x $name', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  ],
                ),
              );
            }),
            if (items.length > 3)
              Text('+ ${items.length - 3} more items', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: €${(totalCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                if (order['deliveryAddress'] != null)
                  Expanded(
                    child: Text(order['deliveryAddress'],
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right),
                  ),
              ],
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateOrderStatus(order['id'], 'CANCELLED'),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateOrderStatus(order['id'], 'CONFIRMED'),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (status == 'CONFIRMED') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _updateOrderStatus(order['id'], 'PROCESSING'),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(AppLocalizations.of(context).translate('startPackagingItems')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ] else if (status == 'PROCESSING') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.access_time_rounded, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Packaging ready • Awaiting courier pickup',
                        style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── PRODUCTS TAB ──────────────────────────────────────────────────────────

  Widget _buildProductsTab() {
    if (_loadingProducts) return _shimmerList();
    
    Widget bodyContent;
    if (_connectionError) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Could not fetch products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchProducts,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D2E8C), foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_products.isEmpty) {
      bodyContent = _emptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        subtitle: 'Add your first product to start selling on Malvoya.',
        color: AppTheme.primary,
        actionLabel: 'Add First Product',
        onAction: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => AddProductScreen(storeId: _store?['id'] ?? 0)),
          );
          if (added == true) _fetchProducts();
        },
      );
    } else {
      bodyContent = RefreshIndicator(
        onRefresh: _fetchProducts,
        color: AppTheme.primary,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: _products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) => _buildProductCard(_products[i]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => AddProductScreen(storeId: _store?['id'] ?? 0)),
          );
          if (added == true) _fetchProducts();
        },
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: bodyContent,
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final priceCents = product['salePriceCents'] ?? product['rentalDayCents'] ?? 0;
    final isAvailable = product['isAvailable'] ?? true;
    final stock = product['stockQuantity'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product['name'] ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text('€${(priceCents / 100).toStringAsFixed(2)} · Stock: $stock',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: isAvailable,
            activeColor: AppTheme.primary,
            onChanged: (val) async {
              await http.patch(
                Uri.parse('${AppConstants.apiBase}/products/${product['id']}'),
                headers: {'Authorization': _authHeader(), 'Content-Type': 'application/json'},
                body: jsonEncode({'isAvailable': val}),
              ).timeout(const Duration(seconds: 4));
              _fetchProducts();
            },
          ),
        ],
      ),
    );
  }

  // ── DASHBOARD TAB ─────────────────────────────────────────────────────────

  Widget _buildDashboardTab() {
    final delivered = _orders.where((o) => o['status'] == 'DELIVERED').toList();
    final totalRevenueCents = delivered.fold<int>(0, (s, o) => s + ((o['totalCents'] as int?) ?? 0));
    final totalOrders = _orders.length;
    final pendingCount = _orders.where((o) => o['status'] == 'PENDING').length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _store != null ? _store!['name'] ?? AppLocalizations.of(context).translate('yourStoreFallback') : 'Set up your store',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_store?['category'] ?? 'Malvoya Marketplace',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _statCard('€${(totalRevenueCents / 100).toStringAsFixed(0)}', 'Revenue', Icons.euro_rounded),
                    const SizedBox(width: 12),
                    _statCard('$totalOrders', 'Orders', Icons.receipt_outlined),
                    const SizedBox(width: 12),
                    _statCard('${_products.length}', 'Products', Icons.inventory_2_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: AppTheme.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$pendingCount new order${pendingCount > 1 ? 's' : ''} waiting for your response!',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _tabs.animateTo(0),
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Store status
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Store Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
                const SizedBox(height: 14),
                _statusRow(Icons.check_circle_rounded, 'Store is live', AppTheme.primary),
                _statusRow(Icons.inventory_2_outlined, '${_products.length} products listed', _products.isEmpty ? AppTheme.warning : AppTheme.primary),
                _statusRow(Icons.star_outline_rounded, '${_store?['rating'] ?? 'No'} rating', AppTheme.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick actions
          Row(
            children: [
              Expanded(
                child: _quickAction(Icons.add_box_outlined, 'Add Product', () async {
                  final added = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => AddProductScreen(storeId: _store?['id'] ?? 0)),
                  );
                  if (added == true) _fetchProducts();
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickAction(Icons.edit_outlined, 'Edit Store', () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store editing coming soon!')));
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: color == AppTheme.textSecondary ? AppTheme.textSecondary : AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── VIDEO DROPS TAB (MALVOYA DROPS & LIVE REELS) ─────────────────────────
  Widget _buildVideoDropsTab() {
    final l10n = AppLocalizations.of(context);
    final totalViews = _merchantDrops.fold<int>(0, (sum, d) => sum + (d['views'] as int? ?? 0));
    final totalSales = _merchantDrops.fold<double>(0.0, (sum, d) => sum + (d['salesTotal'] as double? ?? 0.0));

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDropModal,
        backgroundColor: const Color(0xFFE0245E),
        icon: const Icon(Icons.video_call_rounded, color: Colors.white),
        label: Text(l10n.translate('newVideoDrop'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Analytics Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE0245E), Color(0xFFFF6B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE0245E).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 20),
                          SizedBox(width: 6),
                          Text('MALVOYA DROPS MANAGEMENT',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
                        child: Text('${_merchantDrops.length} Active Drops',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Video Drops & Live Stories',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Short-form video drops shown in the Malvoya Customer feed. Customers can browse, select sizes, and purchase instantly with 20–45 min delivery.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, height: 1.35)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${(totalViews / 1000).toStringAsFixed(1)}k',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(l10n.translate('views'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('€${totalSales.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(l10n.translate('videoSales'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Video Drops',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                TextButton.icon(
                  onPressed: _showCreateDropModal,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('Add Drop'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (_merchantDrops.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.video_collection_outlined, size: 48, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    const Text('Ei vielä videopudotuksia / No video drops yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Text('Kun lisäät tuotteita tai videopudotuksia, ne ilmestyvät automaattisesti asiakkaiden Reels-syötteeseen!', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _showCreateDropModal,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Luo ensimmäinen pudotus / Create Drop'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(_merchantDrops.length, (i) => _buildMerchantDropCard(_merchantDrops[i])),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantDropCard(Map<String, dynamic> drop) {
    final sizes = (drop['sizes'] as List?) ?? [];
    final colors = (drop['colors'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: thumbnail + drop details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        drop['image'] ?? '',
                        width: 80,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80, height: 100,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.video_library_rounded, color: Colors.grey),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C54EC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(drop['condition'] ?? '1/1 Unique',
                              style: const TextStyle(color: Color(0xFF6C54EC), fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                          const Spacer(),
                          const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFFF6B35)),
                          const Text('20–45 min', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(drop['title'] ?? '',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('€${(drop['price'] as double).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        children: [
                          ...sizes.map<Widget>((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text('$s', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          )),
                          ...colors.map<Widget>((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(4)),
                            child: Text('$c', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Analytics row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metricItem(Icons.visibility_rounded, '${drop['views'] ?? 0} views'),
                _metricItem(Icons.favorite_rounded, '${drop['likes'] ?? 0} likes', color: const Color(0xFFE0245E)),
                _metricItem(Icons.chat_bubble_rounded, '${drop['commentsCount'] ?? 0} comments'),
                _metricItem(Icons.shopping_bag_rounded, '${drop['salesCount'] ?? 0} sales', color: const Color(0xFF2E6B4F)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricItem(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? AppTheme.textSecondary)),
      ],
    );
  }

  void _showCreateDropModal() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedCondition = '1/1 Unique Drop';
    final Set<String> selectedSizes = {'M', 'L'};
    bool isFastDelivery = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Luo uusi videopudotus', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(modalCtx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tuotteen nimi & kuvaus', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(hintText: 'esim. Vintage Villakangastakki 90s', labelText: 'Pudotuksen otsikko'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: 'Kuvaile tuotetta ja lisää häshtägit #vintage #helsinki', labelText: 'Kuvateksti'),
                      ),
                      const SizedBox(height: 16),
                      const Text('Hinta (€)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'esim. 65.00', prefixText: '€ '),
                      ),
                      const SizedBox(height: 16),
                      const Text('Kuntoluokitus (Malvoya Verified Grade)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['1/1 Unique Drop', 'Uudenveroinen / Pristine', 'Uusi lapuilla'].map((cond) {
                          final isSel = selectedCondition == cond;
                          return ChoiceChip(
                            label: Text(cond),
                            selected: isSel,
                            selectedColor: AppTheme.primaryLight,
                            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: isSel ? AppTheme.primary : AppTheme.textPrimary),
                            onSelected: (val) { if (val) setModalState(() => selectedCondition = cond); },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Saatavilla olevat koot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['XS', 'S', 'M', 'L', 'XL'].map((s) {
                          final isSel = selectedSizes.contains(s);
                          return FilterChip(
                            label: Text(s),
                            selected: isSel,
                            selectedColor: AppTheme.primaryLight,
                            labelStyle: TextStyle(fontWeight: FontWeight.w800, color: isSel ? AppTheme.primary : AppTheme.textPrimary),
                            onSelected: (val) {
                              setModalState(() {
                                if (val) selectedSizes.add(s); else selectedSizes.remove(s);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFF1EC), borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            const Icon(Icons.bolt_rounded, color: Color(0xFFFF6B35), size: 24),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Malvoya Express -valmius (20–45 min)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                  Text('Tuote valmiina noudettavaksi 20–45 min kuluessa tilauksesta.', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            Switch(
                              value: isFastDelivery,
                              activeColor: const Color(0xFFFF6B35),
                              onChanged: (v) => setModalState(() => isFastDelivery = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (titleCtrl.text.trim().isEmpty) return;
                            final price = double.tryParse(priceCtrl.text) ?? 50.0;
                            setState(() {
                              _merchantDrops.insert(0, {
                                'id': DateTime.now().millisecondsSinceEpoch,
                                'title': titleCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'price': price,
                                'originalPrice': price * 1.5,
                                'condition': selectedCondition,
                                'sizes': selectedSizes.toList(),
                                'colors': ['Black', 'Default'],
                                'image': 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800',
                                'views': 1,
                                'likes': 0,
                                'commentsCount': 0,
                                'salesCount': 0,
                                'salesTotal': 0.0,
                                'isFastDelivery': isFastDelivery,
                              });
                            });
                            SharedPreferences.getInstance().then((prefs) {
                              prefs.setString('vendor_local_drops', jsonEncode(_merchantDrops));
                            });
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🎉 Videopudotus julkaistu! Se näkyy heti Malvoya Asiakassovelluksen Reels-syötteessä.'),
                                backgroundColor: Color(0xFF2E6B4F),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0245E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Julkaise videopudotus Asiakassovellukseen',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle, required Color color, String? actionLabel, VoidCallback? onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, height: 1.5), textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _shimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
      ),
    );
  }
}
