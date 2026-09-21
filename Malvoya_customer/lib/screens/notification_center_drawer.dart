import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../local_notification_service.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'map_tracker.dart';

enum NotificationChannel { all, push, sms, invoice }

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final NotificationChannel channel;
  final String? orderId;
  final String? storeName;
  final String? courierPhone;
  final String? actionLabel;
  final VoidCallback? onAction;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.channel,
    this.orderId,
    this.storeName,
    this.courierPhone,
    this.actionLabel,
    this.onAction,
    this.isRead = false,
  });
}

class NotificationCenterDrawer extends StatefulWidget {
  const NotificationCenterDrawer({super.key});

  static void show(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationCenterDrawer(),
    );
  }

  @override
  State<NotificationCenterDrawer> createState() => _NotificationCenterDrawerState();
}

class _NotificationCenterDrawerState extends State<NotificationCenterDrawer> {
  List<NotificationItem> _notifications = [];
  bool _loading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadRealNotifications();
    }
  }

  Future<void> _loadRealNotifications() async {
    final l10n = AppLocalizations.of(context);
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    List<dynamic> rawOrders = [];

    if (token != null) {
      try {
        final res = await http.get(
          Uri.parse('${AppConstants.apiBase}/orders'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          rawOrders = data is List ? data : (data['orders'] ?? []);
        }
      } catch (_) {}
    }

    final items = <NotificationItem>[];

    for (var i = 0; i < rawOrders.length; i++) {
      final o = rawOrders[i];
      final orderId = (o['id'] ?? '').toString();
      final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
      final status = (o['status'] ?? 'CONFIRMED').toString().toUpperCase();
      final storeName = (o['store']?['name'] ?? o['storeName'] ?? 'Partner Boutique').toString();
      final courierPhone = (o['courier']?['phone'] ?? o['courierPhone'] ?? '').toString();
      final double total = (o['totalCents'] != null)
          ? (o['totalCents'] as num) / 100.0
          : (o['total'] != null ? (o['total'] as num).toDouble() : 0.0);
      final rawDt = o['createdAt']?.toString();
      final dt = rawDt != null ? (DateTime.tryParse(rawDt) ?? DateTime.now()) : DateTime.now();

      // Push Notification based on actual status
      String pushMsg;
      String actionLabel;
      if (status == 'DELIVERED') {
        pushMsg = l10n.translate('statusDeliveredPush');
        actionLabel = l10n.translate('viewProofAction');
      } else if (status == 'SHIPPED') {
        pushMsg = l10n.translate('statusShippedPush');
        actionLabel = l10n.translate('trackLiveAction');
      } else if (status == 'PROCESSING') {
        pushMsg = l10n.translate('statusProcessingPush').replaceAll('{store}', storeName);
        actionLabel = l10n.translate('orderStatusAction');
      } else {
        pushMsg = l10n.translate('statusConfirmedPush');
        actionLabel = l10n.translate('trackLiveAction');
      }

      items.add(NotificationItem(
        id: 'push_$orderId',
        title: '${l10n.translate("orderNum")} #$shortId • $status',
        message: pushMsg,
        timestamp: dt,
        channel: NotificationChannel.push,
        orderId: orderId,
        storeName: storeName,
        actionLabel: actionLabel,
        isRead: i > 0,
      ));

      // SMS Notification
      items.add(NotificationItem(
        id: 'sms_$orderId',
        title: l10n.translate('smsDispatchUpdate'),
        message: l10n.translate('smsDispatchMsg').replaceAll('{id}', shortId),
        timestamp: dt.add(const Duration(seconds: 25)),
        channel: NotificationChannel.sms,
        orderId: orderId,
        storeName: storeName,
        courierPhone: courierPhone,
        actionLabel: l10n.translate('openNativeSmsAction'),
        isRead: i > 0,
      ));

      // VAT 25.5% Invoice Notification
      items.add(NotificationItem(
        id: 'invoice_$orderId',
        title: l10n.translate('legalVatInvoiceTitle'),
        message: l10n.translate('legalVatInvoiceMsg').replaceAll('{id}', shortId).replaceAll('{amount}', total.toStringAsFixed(2)),
        timestamp: dt,
        channel: NotificationChannel.invoice,
        orderId: orderId,
        storeName: storeName,
        actionLabel: l10n.translate('openNativeEmailAction'),
        isRead: true,
      ));
    }

    if (mounted) {
      setState(() {
        _notifications = items;
        _loading = false;
      });
    }
  }

  List<NotificationItem> get _filteredNotifications => _notifications;

  String _formatTimestamp(DateTime dt, AppLocalizations l10n) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.translate('justNow');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, _, __) {
        final l10n = AppLocalizations.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFA120E22) : Colors.white;
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);

        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white24 : AppTheme.glassBorder,
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 20, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.translate('notificationCenter'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                l10n.locale.languageCode == 'fi' ? 'Tilauspäivitykset ja saapuvat ilmoitukset' : 'Order updates and delivery status',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_notifications.any((n) => !n.isRead))
                          TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                for (var n in _notifications) {
                                  n.isRead = true;
                                }
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              l10n.translate('markAllRead'),
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Notification List
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                            ),
                          )
                        : _filteredNotifications.isEmpty
                            ? _buildPristineLiveState(l10n, textPrimary, textSecondary, isDark)
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _filteredNotifications.length,
                                itemBuilder: (ctx, i) {
                                  final item = _filteredNotifications[i];
                                  return _buildNotificationCard(l10n, item, isDark, textPrimary, textSecondary);
                                },
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

  Widget _buildPristineLiveState(AppLocalizations l10n, Color textPrimary, Color textSecondary, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    const Color(0xFF10B981).withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.sensors_rounded,
                size: 36,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.translate('noNotificationsYet'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('noNotificationsYetSub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 13, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  Text(
                    l10n.translate('telemetryStreamActive'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10B981),
                      letterSpacing: 0.5,
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


  Widget _buildNotificationCard(
    AppLocalizations l10n,
    NotificationItem item,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    IconData icon;
    LinearGradient iconGradient;

    switch (item.channel) {
      case NotificationChannel.push:
        icon = Icons.radar_rounded;
        iconGradient = AppTheme.cyberMintGradient;
        break;
      case NotificationChannel.sms:
        icon = Icons.sms_rounded;
        iconGradient = AppTheme.violetGradient;
        break;
      case NotificationChannel.invoice:
        icon = Icons.receipt_long_rounded;
        iconGradient = AppTheme.irisFuchsiaGradient;
        break;
      default:
        icon = Icons.notifications_rounded;
        iconGradient = AppTheme.primaryGradient;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? (item.isRead ? const Color(0x1AFFFFFF) : const Color(0x2E8B5CF6))
            : (item.isRead ? const Color(0xFFF9F8FD) : const Color(0xFFF3EFFF)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.isRead
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : AppTheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: iconGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.isRead ? FontWeight.w700 : FontWeight.w900,
                          fontSize: 14,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _formatTimestamp(item.timestamp, l10n),
                      style: TextStyle(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: item.isRead ? textSecondary : textPrimary.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
                if (item.actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => item.isRead = true);
                        if (item.channel == NotificationChannel.push && item.orderId != null) {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MapTrackerScreen(
                                orderId: '#${item.orderId!.length > 8 ? item.orderId!.substring(0, 8).toUpperCase() : item.orderId}',
                                merchantName: item.storeName ?? 'Partner Boutique',
                              ),
                            ),
                          );
                        } else if (item.channel == NotificationChannel.invoice) {
                          final auth = Provider.of<AuthService>(context, listen: false);
                          final email = auth.currentUser?.email ?? 'support@malvoya.com';
                          final shortId = item.orderId != null && item.orderId!.length > 8
                              ? item.orderId!.substring(0, 8).toUpperCase()
                              : (item.orderId ?? 'LIVE');
                          LocalNotificationService.openEmailApp(
                            email: email,
                            subject: 'Malvoya Official VAT 25.5% Tax Receipt - Order #$shortId',
                            body: 'Malvoya Official Order Confirmation & Legal Tax Invoice\n\n'
                                'Order ID: #$shortId\n'
                                'Merchant: ${item.storeName ?? "Partner Boutique"}\n'
                                'Tax: Included 25.5% Finnish VAT (ALV)\n'
                                'Platform: Malvoya Enterprise Escrow\n'
                                'Support: support@malvoya.com\n\n'
                                'Thank you for shopping with Malvoya!',
                          );
                        } else if (item.channel == NotificationChannel.sms) {
                          final phone = item.courierPhone ?? '';
                          final shortId = item.orderId != null && item.orderId!.length > 8
                              ? item.orderId!.substring(0, 8).toUpperCase()
                              : (item.orderId ?? 'LIVE');
                          LocalNotificationService.openSmsApp(
                            phone: phone,
                            body: '[Malvoya Dispatch] Order #$shortId courier dispatch inquiry for ${item.storeName ?? "Partner Boutique"}. Status: En Route.',
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: Text(
                          item.actionLabel!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
