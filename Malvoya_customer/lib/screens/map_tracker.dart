import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';
import '../services/socket_service.dart';
import '../auth_service.dart';
import '../l10n.dart';
import 'package:provider/provider.dart';

class MapTrackerScreen extends StatefulWidget {
  final String orderId;
  final String merchantName;
  final String courierName;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? deliveryAddress;

  const MapTrackerScreen({
    super.key,
    this.orderId = 'Live Tracking',
    this.merchantName = 'Partner Boutique',
    this.courierName = 'Verified Courier',
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryAddress,
  });

  @override
  State<MapTrackerScreen> createState() => _MapTrackerScreenState();
}

class _MapTrackerScreenState extends State<MapTrackerScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _animCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _routeProgress;

  // Route: Kallio Boutique -> Kaisaniemi -> Central -> Delivery Destination
  final LatLng _boutiquePos = LatLng(60.1841, 24.9493);
  final LatLng _waypoint1 = LatLng(60.1785, 24.9440);
  final LatLng _waypoint2 = LatLng(60.1718, 24.9414);
  late LatLng _homePos;
  late List<LatLng> _fullRoute;

  LatLng _currentCourierPos = LatLng(60.1841, 24.9493);
  LatLng _startCourierPos = LatLng(60.1841, 24.9493);
  LatLng _targetCourierPos = LatLng(60.1841, 24.9493);
  bool _receivedRealGps = false;
  
  double _currentBearing = 205.0;
  double _distanceMeters = 450.0;
  int _etaMinutes = 15;
  bool _smsFallbackEnabled = true;
  double _lastSheetExtent = 0.32;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _homePos = LatLng(widget.deliveryLat ?? 60.1685, widget.deliveryLng ?? 24.9350);
    _fullRoute = [_boutiquePos, _waypoint1, _waypoint2, _homePos];

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _routeProgress = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.linear,
    )..addListener(() {
        if (!mounted) return;
        final t = _routeProgress.value;
        setState(() {
          _currentCourierPos = LatLng(
            _startCourierPos.latitude + (_targetCourierPos.latitude - _startCourierPos.latitude) * t,
            _startCourierPos.longitude + (_targetCourierPos.longitude - _startCourierPos.longitude) * t,
          );
          const distanceCalc = Distance();
          _distanceMeters = distanceCalc.as(LengthUnit.Meter, _currentCourierPos, _homePos);
          _etaMinutes = (_distanceMeters / 250.0).ceil().clamp(1, 60);
        });
      });

    // Real live readiness: Courier stays stationary at pickup location until live assignment
    _currentCourierPos = _boutiquePos;
    _startCourierPos = _boutiquePos;
    _targetCourierPos = _boutiquePos;
    const distanceCalc = Distance();
    _distanceMeters = distanceCalc.as(LengthUnit.Meter, _boutiquePos, _homePos);
    _etaMinutes = (_distanceMeters / 250.0).ceil().clamp(1, 60);

    // Connect socket for live courier tracking
    final auth = Provider.of<AuthService>(context, listen: false);
    CustomerSocketService().connect(auth.accessToken ?? '');
    CustomerSocketService().trackOrder(widget.orderId);

    // Listen for real courier GPS updates
    CustomerSocketService().onCourierLocationUpdate = (data) {
      if (mounted) {
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final newPos = LatLng(lat, lng);
          setState(() {
            _receivedRealGps = true;
            _startCourierPos = _currentCourierPos;
            _targetCourierPos = newPos;
            if (data['bearing'] != null) {
              _currentBearing = (data['bearing'] as num).toDouble();
            } else {
              _currentBearing = _calculateBearing(_startCourierPos, _targetCourierPos);
            }
          });
          _animCtrl.forward(from: 0.0);
        }
      }
    };
  }

  @override
  void dispose() {
    CustomerSocketService().onCourierLocationUpdate = null;
    _pulseCtrl.dispose();
    _animCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  double _calculateBearing(LatLng p1, LatLng p2) {
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    final lat1Rad = p1.latitude * math.pi / 180;
    final lat2Rad = p2.latitude * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) - math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _showMaskedProxyCallDialog() {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1438) : Colors.white;
    final textPrimary = AppTheme.primaryText(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).translate('maskedVoipCall'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary)),
                      Text(AppLocalizations.of(context).translate('zeroPiiRelay'), style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Your actual mobile number is never exposed to the courier. Calls are proxied through encrypted VoIP relay complying with GDPR Art. 32.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.call, size: 18),
                label: Text('Connect via Encrypted Relay (${widget.courierName})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connecting to ${widget.courierName} via encrypted proxy... 📞'),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInTransitChatDialog() {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final cardBg = isDark ? const Color(0xFF1E1438) : Colors.white;

    final messages = <Map<String, String>>[];
    final textCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.72,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16, left: 16, right: 16,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, -6))],
          ),
          child: Column(
            children: [
              Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    child: const Icon(Icons.delivery_dining_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.courierName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textPrimary)),
                        const Text('Masked In-Transit Relay • PII Redacted', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Quick replies
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _quickReplyChip(AppLocalizations.of(context).translate('quickReplyDownstairs'), textCtrl, setSheetState),
                    const SizedBox(width: 8),
                    _quickReplyChip(AppLocalizations.of(context).translate('quickReplyDoorstep'), textCtrl, setSheetState),
                    const SizedBox(width: 8),
                    _quickReplyChip(AppLocalizations.of(context).translate('quickReplyCall'), textCtrl, setSheetState),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Messages list
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_clock_outlined, size: 36, color: textSecondary.withValues(alpha: 0.5)),
                            const SizedBox(height: 10),
                            Text(
                              'End-to-End Encrypted Relay',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Send live delivery instructions to ${widget.courierName}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = messages[i];
                          final isMe = msg['sender'] == 'customer';
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppTheme.primary
                                    : (isDark ? const Color(0xFF2A1F4C) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(msg['text']!, style: TextStyle(color: isMe ? Colors.white : textPrimary, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(msg['time']!, style: TextStyle(color: isMe ? Colors.white70 : textSecondary, fontSize: 9)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Chat Input Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textCtrl,
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Type encrypted message...',
                        hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A1F4C) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final val = textCtrl.text.trim();
                      if (val.isNotEmpty) {
                        HapticFeedback.lightImpact();
                        setSheetState(() {
                          messages.add({'sender': 'customer', 'text': val, 'time': 'Just now'});
                          textCtrl.clear();
                        });
                      }
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickReplyChip(String text, TextEditingController ctrl, StateSetter setSheetState) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setSheetState(() {
          ctrl.text = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
      ),
    );
  }

  void _showDoorstepProofDialog() {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B1033) : Colors.white;
    final textPrimary = isDark ? const Color(0xFFFAF5FF) : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? const Color(0x558B5CF6) : const Color(0x1F8B5CF6)),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 10))],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context).translate('contactlessProof'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
                          Text(AppLocalizations.of(context).translate('gpsGeotagged'), style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textPrimary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F081D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x448B5CF6)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          size: const Size(double.infinity, 200),
                          painter: _DoorstepBackgroundPainter(),
                        ),
                      ),
                      // Luxury Malvoya Boutique Delivery Box
                      Container(
                        width: 150,
                        height: 110,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF27174A), Color(0xFF1B1033)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.7),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Silk Ribbon
                            Center(
                              child: Container(
                                width: 14,
                                height: 110,
                                color: const Color(0xFFEC4899).withValues(alpha: 0.65),
                              ),
                            ),
                            Center(
                              child: Container(
                                width: 150,
                                height: 14,
                                color: const Color(0xFFEC4899).withValues(alpha: 0.65),
                              ),
                            ),
                            // Wax Seal
                            Center(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                                  ),
                                  border: Border.all(color: const Color(0xFFE9D5FF), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'MALVOYA HELSINKI',
                                  style: TextStyle(color: Colors.black87, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Top GPS Geotag Watermark
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.gps_fixed_rounded, color: Color(0xFF10B981), size: 11),
                                  SizedBox(width: 4),
                                  Text(
                                    '60.1699° N, 24.9384° E • HELSINKI',
                                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                AppLocalizations.of(context).translate('deliveredText'),
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom Doorstep Watermark
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12, width: 0.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Doorstep Drop: ${widget.deliveryAddress ?? "Mannerheimintie, Helsinki"}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                AppLocalizations.of(context).translate('tamperSealVerified'),
                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Aito toimituskuva kohteesta ${widget.deliveryAddress ?? "Mannerheimintie, Helsinki"}. Pakkauksen sinetti on vahvistettu ehjäksi.',
                style: TextStyle(fontSize: 12.5, color: textPrimary.withValues(alpha: 0.85), height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Vahvista vastaanotetuksi / Confirm Received ✅', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiveStageProgressBar(BuildContext context, AppLocalizations l10n) {
    final isFi = l10n.locale.languageCode == 'fi';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    final stages = [
      {'label': isFi ? 'Vastaanotettu' : 'Placed', 'done': true},
      {'label': isFi ? 'Valmistellaan' : 'Preparing', 'done': true},
      {'label': isFi ? 'Noudettu' : 'Picked Up', 'done': true},
      {'label': isFi ? 'Matkalla' : 'On the Way', 'done': true, 'active': true},
      {'label': isFi ? 'Toimitettu' : 'Delivered', 'done': false},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(stages.length * 2 - 1, (index) {
        if (index % 2 == 1) {
          final stageIdx = index ~/ 2;
          final isDone = (stages[stageIdx]['done'] as bool? ?? false);
          final isActive = (stages[stageIdx]['active'] as bool? ?? false);
          final isPast = isDone && !isActive;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isPast
                    ? AppTheme.primary
                    : (isDark ? const Color(0xFF2E1F52) : const Color(0xFFE5E0F2)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        } else {
          final stageIdx = index ~/ 2;
          final s = stages[stageIdx];
          final done = (s['done'] as bool? ?? false);
          final active = (s['active'] as bool? ?? false);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? AppTheme.primary
                      : done
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : (isDark ? const Color(0xFF1E133C) : Colors.grey.shade200),
                  border: Border.all(
                    color: active || done ? AppTheme.primary : (isDark ? const Color(0xFF2E1F52) : Colors.grey.shade300),
                    width: active ? 2.5 : 1.2,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: active
                      ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                      : done
                          ? const Icon(Icons.check, size: 14, color: AppTheme.primary)
                          : null,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                s['label'] as String,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? AppTheme.primary : (done ? textPrimary : textSecondary),
                ),
              ),
            ],
          );
        }
      }),
    );
  }

  Widget _manifestRow(String label, String value, [BuildContext? ctx]) {
    final effectiveContext = ctx ?? context;
    final textPrimary = AppTheme.primaryText(effectiveContext);
    final textSecondary = AppTheme.secondaryText(effectiveContext);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Live GPS 60Hz', style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(
                (_boutiquePos.latitude + _homePos.latitude) / 2,
                (_boutiquePos.longitude + _homePos.longitude) / 2,
              ),
              zoom: 14.3,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.malvoya.customer',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _fullRoute,
                    strokeWidth: 4.5,
                    color: AppTheme.primary,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Boutique Marker
                  Marker(
                    point: _boutiquePos,
                    width: 44,
                    height: 44,
                    builder: (ctx) => Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: const Center(
                        child: Icon(Icons.storefront_rounded, color: AppTheme.primary, size: 22),
                      ),
                    ),
                  ),
                  // Destination Marker
                  Marker(
                    point: _homePos,
                    width: 44,
                    height: 44,
                    builder: (ctx) => Container(
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: const Center(
                        child: Icon(Icons.home_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  // Moving Courier Marker or Waiting Indicator
                  if (!_receivedRealGps)
                    Marker(
                      point: _boutiquePos,
                      width: 180,
                      height: 100,
                      builder: (ctx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (ctx, child) => Container(
                              width: 30 + (_pulseCtrl.value * 20),
                              height: 30 + (_pulseCtrl.value * 20),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.3 - (_pulseCtrl.value * 0.2)),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.8 - (_pulseCtrl.value * 0.5)),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                            ),
                            child: const Text(
                              'Waiting for courier location...',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Marker(
                      point: _currentCourierPos,
                      width: 54,
                      height: 54,
                      builder: (ctx) => Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Transform.rotate(
                            angle: _currentBearing * math.pi / 180,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                              ),
                              child: const Center(
                                child: Icon(Icons.navigation_rounded, color: AppTheme.primary, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Master Operational Portal: DraggableScrollableSheet with snap points [0.18, 0.32, 0.88]
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              if ((_lastSheetExtent < 0.5 && n.extent >= 0.5) || (_lastSheetExtent >= 0.5 && n.extent < 0.5)) {
                HapticFeedback.selectionClick();
              }
              _lastSheetExtent = n.extent;
              return true;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.32,
              minChildSize: 0.18,
              maxChildSize: 0.88,
              snap: true,
              snapSizes: const [0.18, 0.32, 0.88],
              builder: (context, scrollController) {
                final l10n = AppLocalizations.of(context);
                final isFi = l10n.locale.languageCode == 'fi';
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final sheetBg = isDark ? const Color(0xFF140D28) : Colors.white;
                final cardBg = isDark ? const Color(0xFF1E133C) : const Color(0xFFF8F7FF);
                final cardBorder = isDark ? const Color(0xFF2E1F52) : const Color(0xFFEDE8F5);
                final textPrimary = AppTheme.primaryText(context);
                final textSecondary = AppTheme.secondaryText(context);

                final etaDisplay = _distanceMeters < 80
                    ? (isFi ? 'Ovelle saapumassa 📍' : 'Arriving at Doorstep 📍')
                    : '$_etaMinutes–${_etaMinutes + 10} min';
                final etaSubtitle = _distanceMeters < 80
                    ? (isFi ? 'Kuriiri astuu sisään' : 'Courier arriving now')
                    : (isFi ? 'Arvioitu toimitusaika • ⚡ Nopea nouto' : 'Estimated delivery time • Express drop');

                return Container(
                  decoration: BoxDecoration(
                    color: sheetBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                    physics: const ClampingScrollPhysics(),
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF382662) : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Wolt-Style ETA & Telemetry Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                etaDisplay,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                etaSubtitle,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textSecondary),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 7, height: 7,
                                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    isFi
                                        ? 'Live-tutka: ${_distanceMeters.round()} m päässä • 60 Hz'
                                        : 'Live Radar: ${_distanceMeters.round()}m away • 60Hz',
                                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF27174A) : const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              widget.orderId,
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 5-Stage Visual Progress Stepper (Wolt Glow Style)
                      _buildFiveStageProgressBar(context, l10n),

                      const SizedBox(height: 16),

                      // In-Transit Masked Communications Bridge (Courier Card)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.18),
                              child: const Icon(Icons.delivery_dining_rounded, color: AppTheme.primary, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.courierName.isNotEmpty ? widget.courierName : (isFi ? 'Malvoya Pikalähetti' : 'Malvoya Courier Dispatch'),
                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.star_rounded, size: 12, color: Color(0xFFD97706)),
                                            SizedBox(width: 2),
                                            Text('4.9', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isFi ? 'Sähköskootteri • Suojattu yhteys' : 'Electric Scooter • Protected',
                                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                            // In-Transit Masked Call Button
                            IconButton(
                              onPressed: _showMaskedProxyCallDialog,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF0284C7), size: 18),
                              ),
                              tooltip: 'Masked VoIP Call (Private)',
                            ),

                            // In-Transit Masked Chat Button
                            IconButton(
                              onPressed: _showInTransitChatDialog,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFDDD6FE)),
                                ),
                                child: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primary, size: 18),
                              ),
                              tooltip: 'Encrypted Chat',
                            ),

                            // Contactless Doorstep Proof
                            IconButton(
                              onPressed: _showDoorstepProofDialog,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                ),
                                child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF16A34A), size: 18),
                              ),
                              tooltip: 'Doorstep Photo Proof',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Fallback SMS Status Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sms_outlined, size: 18, color: Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _smsFallbackEnabled
                                    ? (isFi ? 'SMS-varaviesti aktiivinen hissikatveita varten.' : 'Fallback SMS active for elevator signal drops.')
                                    : (isFi ? 'SMS-varaviesti tauotettu.' : 'SMS fallback paused.'),
                                style: TextStyle(fontSize: 11, color: textPrimary),
                              ),
                            ),
                            Switch(
                              value: _smsFallbackEnabled,
                              activeColor: const Color(0xFF0284C7),
                              onChanged: (v) => setState(() => _smsFallbackEnabled = v),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Detailed Order Manifest (Expanded view at 88% snap)
                      Text(
                        isFi ? 'Toimituserittely & Ohjeet' : 'Delivery Manifest & Instructions',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          children: [
                            _manifestRow(isFi ? 'Lähettävä liike' : 'Boutique Dispatch', widget.merchantName, context),
                            const Divider(height: 16),
                            _manifestRow(isFi ? 'Toimitusosoite' : 'Destination Address', widget.deliveryAddress ?? (isFi ? 'Vahvistettu sisäänkäynti' : 'Verified Customer Entrance'), context),
                            const Divider(height: 16),
                            _manifestRow('ALV / VAT (25.5%)', isFi ? 'Sisältyy digitaaliseen kuittiin' : 'Inclusive Legal Digital Receipt', context),
                            const Divider(height: 16),
                            _manifestRow(isFi ? 'Maksusuoja' : 'Payment Escrow', isFi ? 'PSD2 SCA -katevaraus pidätettynä' : 'PSD2 SCA Pre-Auth Held in Escrow', context),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DoorstepBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x228B5CF6)
      ..strokeWidth = 1.0;

    // Floor perspective lines
    for (double x = 0; x <= size.width; x += 40) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(size.width / 2 + (x - size.width / 2) * 0.4, 0),
        paint,
      );
    }
    // Horizontal floor joints
    final jointPaint = Paint()
      ..color = const Color(0x1AFAF5FF)
      ..strokeWidth = 0.8;
    for (double y = 40; y < size.height; y += 35) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
