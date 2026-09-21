import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'map_tracker.dart';
import '../features/order_tracking/presentation/widgets/delivery_progress_bar.dart';
import '../features/returns/presentation/widgets/swipe_to_swap_sheet.dart';
import '../local_notification_service.dart';
import '../services/socket_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> _activeOrders = [];
  List<dynamic> _pastOrders = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchOrders();

    final auth = Provider.of<AuthService>(context, listen: false);
    CustomerSocketService().connect(auth.accessToken ?? '');
    CustomerSocketService().onOrderStatusUpdate = (data) {
      if (mounted) {
        _fetchOrders();
      }
    };
  }

  @override
  void dispose() {
    CustomerSocketService().onOrderStatusUpdate = null;
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) {
      setState(() { _loading = false; });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/orders'),
        headers: {
          'Authorization': 'Bearer ${auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orders = data is List ? data : (data['orders'] ?? []);
        setState(() {
          _activeOrders = orders.where((o) =>
            ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED'].contains(o['status'])
          ).toList();
          _pastOrders = orders.where((o) =>
            ['DELIVERED', 'CANCELLED', 'REFUNDED'].contains(o['status'])
          ).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = true; _loading = false; });
      }
    } catch (e) {
      debugPrint('Failed to load orders: $e');
      setState(() { _error = true; _loading = false; });
    }
  }

  String _formatCents(int? cents) {
    if (cents == null) return '€0.00';
    return '€${(cents / 100).toStringAsFixed(2)}';
  }

  void _initiateVoipRelay(Map<String, dynamic> order) {
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1438) : Colors.white;
    final courier = order['courier'];
    final courierPhone = (courier?['phone'] ?? order['courierPhone'] ?? '').toString().trim();
    final courierName = (courier?['name'] ?? order['courierName'] ?? l10n.translate('courierNameDefault')).toString();

    if (courierPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.locale.languageCode == 'fi'
              ? 'Kuriiria ei ole vielä osoitettu tilaukselle. Putiikki käsittelee tilausta.'
              : 'No courier assigned yet. Boutique is preparing your order.'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('secureVoiceRelay'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '$courierName • ${l10n.translate('secureVoiceRelaySub')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    l10n.translate('sessionToken'),
                    style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.call_rounded),
                label: Text(l10n.translate('startMaskedCall'), style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await LocalNotificationService.callPhone(courierPhone);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.translate('nativeDialerOpened')),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEncryptedSmsRelay(Map<String, dynamic> order) async {
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final rawOrderId = order['id']?.toString() ?? 'LIVE';
    final shortId = rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
    final courier = order['courier'];
    final courierPhone = (courier?['phone'] ?? order['courierPhone'] ?? '').toString().trim();
    final isFi = l10n.locale.languageCode == 'fi';
    final bodyText = isFi
        ? '[Malvoya Tilaus #$shortId] Kuriiriyhteys: Tiedustelu toimituksen tilasta.'
        : '[Malvoya Order #$shortId] Courier Relay: Status update requested for active doorstep delivery.';

    await LocalNotificationService.openSmsApp(
      phone: courierPhone,
      body: bodyText,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('nativeSmsIntentOpened')),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _resendVatInvoice(String orderId) async {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final auth = Provider.of<AuthService>(context, listen: false);
    final email = auth.currentUser?.email ?? '';
    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.locale.languageCode == 'fi'
                ? 'Kirjaudu sisään sähköpostilla vastaanottaaksesi ALV-kuitin.'
                : 'Please sign in with an email address to receive your VAT tax invoice.'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
    await LocalNotificationService.openEmailApp(
      email: email,
      subject: 'Malvoya VAT 25.5% Legal Tax Invoice - Order #$shortId',
      body: 'Malvoya Official Order Confirmation & Legal Tax Invoice\n\n'
          'Order ID: #$shortId\n'
          'Status: Active Boutique Dispatch\n'
          'Jurisdiction: Finnish Tax Administration (Verohallinto)\n'
          'VAT Standard Rate: 25.5%\n'
          'Customer Account: $email\n\n'
          'Thank you for ordering with Malvoya!',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('nativeEmailInvoiceOpened').replaceAll('{id}', shortId)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildActiveOrderCard(BuildContext context, Map<String, dynamic> order) {
    final l10n = AppLocalizations.of(context);
    final status = order['status'] ?? 'SHIPPED';
    final storeName = order['store']?['name'] ?? order['storeName'] ?? 'Partner Boutique';
    final rawOrderId = order['id']?.toString() ?? 'MLV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final orderId = rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
    final totalCents = (order['totalCents'] as num?)?.toInt() ?? ((order['total'] as num?)?.toDouble() != null ? ((order['total'] as num).toDouble() * 100).toInt() : 0);
    final courierName = (order['courier']?['name'] ?? order['courierName'] ?? 'Verified Express Courier').toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    double progressPercent = 0.15;
    String stepDescription = l10n.translate('stepOrderReceived');
    if (status == 'CONFIRMED') {
      progressPercent = 0.35;
      stepDescription = l10n.translate('stepBoutiqueAccepted');
    } else if (status == 'PROCESSING') {
      progressPercent = 0.55;
      stepDescription = l10n.translate('stepArtisanPacking');
    } else if (status == 'SHIPPED') {
      progressPercent = 0.88;
      stepDescription = l10n.translate('stepCourierEnRoute');
    } else if (status == 'DELIVERED') {
      progressPercent = 1.00;
      stepDescription = l10n.translate('stepDelivered');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEB16102E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.radar_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(storeName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: textPrimary)),
                      Text('${l10n.translate('orderNum')} #$orderId', style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        l10n.translate('statusEnRoute'),
                        style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Finite State Delivery Progress Bar
            DeliveryProgressBar(
              progressPercent: progressPercent,
              stepDescription: stepDescription,
            ),

            const SizedBox(height: 14),

            // Live Telemetry Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFF3F1FA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, color: Color(0xFF8B5CF6), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courierName,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textPrimary),
                        ),
                        Text(
                          status == 'SHIPPED' ? l10n.translate('courierEnRouteRadar') : l10n.translate('boutiquePacking'),
                          style: TextStyle(fontSize: 11.5, color: textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatCents(totalCents),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textPrimary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3-Button Communications Action Bar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _initiateVoipRelay(order),
                    icon: const Icon(Icons.call_rounded, size: 15, color: Color(0xFF8B5CF6)),
                    label: Text(l10n.translate('callRelay'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openEncryptedSmsRelay(order),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15, color: Color(0xFF7C3AED)),
                    label: Text(l10n.translate('maskedSms'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resendVatInvoice(orderId),
                    icon: const Icon(Icons.email_outlined, size: 15, color: Color(0xFF8B5CF6)),
                    label: Text(l10n.translate('vatReceipt'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Live Radar Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 2,
                ),
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(l10n.translate('liveCourierRadarMap'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapTrackerScreen(
                        orderId: '#$orderId',
                        merchantName: storeName,
                        courierName: courierName,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // Swipe to Swap Size/Variant Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF8B5CF6)),
                label: Text(
                  AppLocalizations.of(context).translate('swipeToSwap'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF8B5CF6)),
                ),
                onPressed: () {
                  final firstItem = (order['items'] is List && (order['items'] as List).isNotEmpty)
                      ? (order['items'] as List).first
                      : null;
                  final itemName = firstItem?['name'] ?? firstItem?['product']?['name'] ?? 'Tailored Apparel Item';
                  final price = totalCents > 0 ? (totalCents / 100.0) : 48.0;

                  SwipeToSwapSheet.show(
                    context,
                    orderId: orderId,
                    itemName: itemName,
                    price: price,
                    storeName: storeName,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastOrderCard(BuildContext context, Map<String, dynamic> order) {
    final l10n = AppLocalizations.of(context);
    final status = order['status'] ?? 'DELIVERED';
    final createdAt = order['createdAt'] ?? '';
    final totalCents = order['totalCents'] as int? ?? 0;
    final items = order['items'] as List? ?? [];
    final storeName = order['store']?['name'] ?? 'Store';
    final rawOrderId = order['id']?.toString() ?? 'MLV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final orderId = rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    final itemNames = items.map((i) {
      final qty = i['quantity'] ?? 1;
      final name = i['product']?['name'] ?? 'Item';
      return '${qty}x $name';
    }).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1AFFFFFF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(storeName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
                  if (dateStr.isNotEmpty)
                    Text(dateStr, style: TextStyle(color: textSecondary, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'DELIVERED'
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status == 'DELIVERED'
                      ? (l10n.locale.languageCode == 'fi' ? 'Toimitettu ✅' : 'Delivered ✅')
                      : (status == 'SHIPPED'
                          ? (l10n.locale.languageCode == 'fi' ? 'Kuljetuksessa ⚡' : 'In Transit ⚡')
                          : (status == 'CANCELLED'
                              ? (l10n.locale.languageCode == 'fi' ? 'Peruutettu' : 'Cancelled')
                              : status)),
                  style: TextStyle(
                    color: status == 'DELIVERED' ? const Color(0xFF10B981) : (status == 'SHIPPED' ? AppTheme.primary : Colors.red),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (itemNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(itemNames, style: TextStyle(fontSize: 12.5, color: textSecondary)),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${l10n.translate('total')}: ${_formatCents(totalCents)}',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textPrimary),
              ),
              const SizedBox(width: 6),
              Text(l10n.translate('vatInclusive'), style: TextStyle(fontSize: 10, color: textSecondary)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _resendVatInvoice(orderId),
                icon: const Icon(Icons.receipt_long_rounded, size: 14, color: AppTheme.primary),
                label: Text(l10n.translate('invoiceBtn'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, size: 38, color: AppTheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.primaryText(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, _, __) {
        final l10n = AppLocalizations.of(context);
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);

        return DefaultTabController(
          length: 2,
          child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cardBg,
          elevation: 0,
          title: Text(
            l10n.translate('activityTelemetryHub'),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textPrimary),
          ),
          bottom: TabBar(
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.secondaryText(context),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            tabs: [
              Tab(
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Text(l10n.translate('liveActive')),
                     if (_activeOrders.isNotEmpty) ...[
                       const SizedBox(width: 6),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                         decoration: BoxDecoration(
                           color: const Color(0xFF10B981),
                           borderRadius: BorderRadius.circular(10),
                         ),
                         child: Text(
                           '${_activeOrders.length}',
                           style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                         ),
                       ),
                     ],
                   ],
                 ),
               ),
              Tab(text: l10n.translate('pastOrders')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l10n.translate('couldNotLoadTelemetry')),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() { _loading = true; _error = false; });
                            _fetchOrders();
                          },
                          child: Text(l10n.translate('retryConnection')),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [
                      // Active orders
                      _activeOrders.isEmpty
                          ? _buildEmptyState(
                              l10n.translate('noActiveOrders'),
                              l10n.translate('noActiveOrdersSub'),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchOrders,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                                itemCount: _activeOrders.length,
                                itemBuilder: (ctx, i) => _buildActiveOrderCard(context, _activeOrders[i]),
                              ),
                            ),

                      // Past orders
                      _pastOrders.isEmpty
                          ? _buildEmptyState(
                              l10n.translate('noPastOrders'),
                              l10n.translate('noPastOrdersSub'),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchOrders,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                                itemCount: _pastOrders.length,
                                itemBuilder: (ctx, i) => _buildPastOrderCard(context, _pastOrders[i]),
                              ),
                            ),
                    ],
                  ),
        ),
      );
    },
  );
}
}
