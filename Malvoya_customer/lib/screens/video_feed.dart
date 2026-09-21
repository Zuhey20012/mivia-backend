import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cart.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../models.dart';
import 'store_detail.dart';

// Pulsing live badge
class _PulsingBadge extends StatefulWidget {
  final String text;
  final Color color;
  const _PulsingBadge({required this.text, required this.color});
  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.55, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// Main VideoFeedScreen
class VideoFeedScreen extends StatefulWidget {
  final int initialIndex;
  const VideoFeedScreen({super.key, this.initialIndex = 0});
  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;

  String _selectedCategory = 'All';

  final List<Map<String, dynamic>> _merchantDrops = [];
  bool _isLoading = true;

  final Set<int> _likedIds = {};
  final Set<int> _followedMerchantIds = {};
  final Map<int, bool> _isPlayingMap = {};
  bool _isMuted = false;

  bool _showHeartAnim = false;
  Offset _heartAnimPos = Offset.zero;

  // Comments state persisted in memory per drop
  final Map<String, List<Map<String, String>>> _commentsStore = {};

  final List<Map<String, String>> _categoryFilters = const [
    {'key': 'All', 'fi': 'Kaikki', 'en': 'All'},
    {'key': 'Apparel', 'fi': 'Vaatteet', 'en': 'Apparel'},
    {'key': 'Second Hand', 'fi': 'Second Hand', 'en': 'Second Hand'},
    {'key': 'Cosmetics', 'fi': 'Kosmetiikka', 'en': 'Cosmetics'},
    {'key': 'Accessories', 'fi': 'Asusteet', 'en': 'Accessories'},
    {'key': 'Skincare', 'fi': 'Ihonhoito', 'en': 'Skincare'},
  ];

  // Real dynamic delivery dispatch
  static const _standardDelivery = 'Live GPS Courier Radar';

  static const _audioTracks = [
    '\u266b Nordic Ambient Studio',
    '\u266b Helsinki Soundscape',
    '\u266b Minimalist Rhythm',
    '\u266b Pure Acoustic Beats',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadDropsFromAPI();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadDropsFromAPI() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> drops = [];
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.apiBase}/drops/live'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['drops'] ?? data ?? []) as List;
        for (final item in list) {
          if (item['isLiveDrop'] == true && item['videoUrl'] != null) {
            drops.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {}

    // Check for authentic local merchant stream drops created in vendor app
    await _loadLocalVendorDrops(drops);

    // If still empty, load from store products API
    if (drops.isEmpty) {
      try {
        final storeRes = await http
            .get(Uri.parse('${AppConstants.apiBase}/stores'))
            .timeout(const Duration(seconds: 3));
        if (storeRes.statusCode == 200) {
          final sData = jsonDecode(storeRes.body);
          final sList = (sData['stores'] ?? sData ?? []) as List;
          for (final s in sList.take(3)) {
            final pRes = await http
                .get(Uri.parse('${AppConstants.apiBase}/stores/${s['id']}/products'))
                .timeout(const Duration(seconds: 3));
            if (pRes.statusCode == 200) {
              final pData = jsonDecode(pRes.body);
              final pList = (pData['products'] ?? pData ?? []) as List;
              for (final p in pList) {
                final price = ((p['priceCents'] ?? 4500) as int) / 100.0;
                drops.add({
                  'id': 'api_p_${p['id']}',
                  'productId': p['id'],
                  'storeId': s['id'],
                  'merchant': s['name'] ?? 'Nordic Boutique',
                  'handle': '@${(s['name'] ?? 'boutique').toString().toLowerCase().replaceAll(' ', '')}',
                  'avatar': s['logoUrl'] ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200',
                  'title': p['name'] ?? 'Curated Garment',
                  'description': p['description'] ?? 'Nordic luxury apparel drop with 30-minute instant delivery.',
                  'tags': '#nordic #fashion #drop #malvoya',
                  'category': p['category'] ?? 'Apparel',
                  'gender': p['gender'] ?? 'All',
                  'condition': 'New Drop',
                  'price': price,
                  'originalPrice': price * 1.18,
                  'discountPct': 15,
                  'sizes': ['XS', 'S', 'M', 'L', 'XL'],
                  'colors': ['Noir', 'Oatmeal', 'Sage'],
                  'stockLeft': p['stock'] ?? 3,
                  'image': p['imageUrl'] ?? 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=900',
                  'likes': 142,
                  'audio': _audioTracks[0],
                  'deliveryTime': _standardDelivery,
                  'isLiveStore': true,
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    // Zero mock drops — purely real backend drops or pitch-black onboarding state

    final seen = <dynamic>{};
    final unique = drops.where((d) => seen.add(d['id'])).toList();
    if (mounted) {
      setState(() {
        _merchantDrops
          ..clear()
          ..addAll(unique);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocalVendorDrops(List<Map<String, dynamic>> drops) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vendor_local_drops');
      if (raw == null) return;
      final localDrops = jsonDecode(raw) as List;
      int idx = 0;
      for (final d in localDrops) {
        final price = ((d['salePriceCents'] ?? 3000) as int) / 100.0;
        drops.add({
          'id': 'local_${d['id'] ?? idx}',
          'productId': d['id'] ?? 999,
          'storeId': d['storeId'] ?? 101,
          'merchant': d['storeName'] ?? 'Malvoya Partner Store',
          'handle': '@localboutique',
          'avatar':
              'https://ui-avatars.com/api/?name=Local+Boutique&background=EC4899&color=fff&size=128',
          'title': d['name'] ?? 'Product',
          'description': d['description'] ?? 'Malvoya Partner Item',
          'tags': '#malvoya #boutique #express',
          'category': d['category'] ?? 'Apparel',
          'gender': 'All',
          'condition': 'Uutuus',
          'price': price,
          'originalPrice': price * 1.15,
          'discountPct': 15,
          'sizes': ['XS', 'S', 'M', 'L', 'XL'],
          'colors': ['Musta / Black', 'Valkoinen / White'],
          'stockLeft': 2,
          'image': 'https://images.unsplash.com/photo-1556905055-8f358a7a47b2?w=800',
          'likes': 0,
          'audio': _audioTracks[1],
          'deliveryTime': _standardDelivery,
          'isLiveStore': true,
        });
        idx++;
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filteredMerchantDrops {
    return _merchantDrops.where((d) {
      final catOk = _selectedCategory == 'All' ||
          (d['category'] as String).toLowerCase() == _selectedCategory.toLowerCase();
      return catOk;
    }).toList();
  }

  void _onDoubleTap(TapDownDetails details, dynamic dropId) {
    HapticFeedback.heavyImpact();
    setState(() {
      _likedIds.add(dropId.hashCode);
      _showHeartAnim = true;
      _heartAnimPos = details.localPosition;
    });
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeartAnim = false);
    });
  }

  void _togglePlayPause(dynamic dropId) {
    setState(() {
      final current = _isPlayingMap[dropId.hashCode] ?? true;
      _isPlayingMap[dropId.hashCode] = !current;
    });
  }

  void _openCheckoutSheet(
      BuildContext context, Map<String, dynamic> drop, AppLocalizations l10n) {
    HapticFeedback.mediumImpact();
    String selectedSize = (drop['sizes'] as List).first;
    String selectedColor = (drop['colors'] as List).first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            top: 16,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      drop['image'],
                      width: 90,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 110,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.checkroom, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              drop['condition'] ?? 'Uutuus',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '-${drop['discountPct']}% OFF',
                              style: const TextStyle(
                                color: Color(0xFF16A34A),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          drop['title'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          drop['merchant'],
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text(
                            '\u20ac${drop['price'].toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\u20ac${drop['originalPrice'].toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  '${l10n.translate('selectSize')} / Koko',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: (drop['sizes'] as List).map<Widget>((size) {
                    final isSelected = selectedSize == size;
                    return ChoiceChip(
                      label: Text(size),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: const Color(0xFFF4F4F8),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primary : Colors.transparent,
                      ),
                      onSelected: (_) => setModal(() => selectedSize = size),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  '${l10n.translate('color')} / V\u00e4ri',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: (drop['colors'] as List).map<Widget>((color) {
                    final isSelected = selectedColor == color;
                    return ChoiceChip(
                      label: Text(color),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: const Color(0xFFF4F4F8),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primary : Colors.transparent,
                      ),
                      onSelected: (_) => setModal(() => selectedColor = color),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 16, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${l10n.translate('deliveryEst')}: ${drop['deliveryTime']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if ((drop['stockLeft'] ?? 10) <= 5)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: Color(0xFFEA580C)),
                      const SizedBox(width: 6),
                      Text(
                        'Only ${drop['stockLeft']} left in stock',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      final cart = Provider.of<CartService>(context, listen: false);
                      cart.add(
                        CartItem(
                          productId: (drop['productId'] ?? 0) as int,
                          storeId: (drop['storeId'] ?? 0) as int,
                          name: drop['title'] ?? 'Product',
                          price: (drop['price'] as double),
                        ),
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${drop['title']} ${l10n.translate('addedToCart')}'),
                          backgroundColor: AppTheme.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.translate('addToCart'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCommentsSheet(
      BuildContext context, Map<String, dynamic> drop, AppLocalizations l10n) {
    final dropKey = drop['id'].toString();
    final TextEditingController commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final comments = _commentsStore[dropKey] ?? [];
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.72,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.translate('comments'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${comments.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'Be the first to comment',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        itemCount: comments.length,
                        itemBuilder: (ctx, idx) {
                          final c = comments[idx];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                                  child: Text(
                                    (c['name'] ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c['name'] ?? 'User',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c['text'] ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: const Color(0xFFF4F4F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      final text = commentCtrl.text.trim();
                      if (text.isEmpty) return;
                      setState(() {
                        _commentsStore[dropKey] = [
                          ...(_commentsStore[dropKey] ?? []),
                          {'name': 'You', 'text': text},
                        ];
                      });
                      setModal(() {});
                      commentCtrl.clear();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildStrictEmptyStateCard(BuildContext context, AppLocalizations l10n) {
    return Container(
      color: const Color(0xFF000000),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing signature violet/purple emblem
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                        blurRadius: 32,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  l10n.translate('dropsComingSoon'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.translate('dropsComingSoonSub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8B5CF6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.translate('secRunwayDrops'),
                        style: const TextStyle(
                          color: Color(0xFFDDD6FE),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReelCard(
      BuildContext context, Map<String, dynamic> drop, AppLocalizations l10n) {
    final dropId = drop['id'];
    final isLiked = _likedIds.contains(dropId.hashCode);
    final isFollowed = _followedMerchantIds.contains(drop['storeId'].hashCode);
    final isPlaying = _isPlayingMap[dropId.hashCode] ?? true;

    return GestureDetector(
      onDoubleTapDown: (details) => _onDoubleTap(details, dropId),
      onDoubleTap: () {},
      onTap: () => _togglePlayPause(dropId),
      child: Stack(fit: StackFit.expand, children: [
        // Background image
        Image.network(
          drop['image'],
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(color: const Color(0xFF14141E));
          },
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2E1065), Color(0xFF0F172A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: const Center(
              child: Icon(Icons.videocam_outlined, size: 80, color: Colors.white24),
            ),
          ),
        ),
        // Dark gradient overlay
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Color(0xCC000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.4, 1.0],
            ),
          ),
        ),
        // Play/pause indicator
        if (!isPlaying)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pause_rounded,
                  color: Colors.white, size: 40),
            ),
          ),
        // Bottom content: merchant info + product info
        Positioned(
          left: 16,
          right: 80,
          bottom: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Merchant row
              Row(children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoreDetailScreen(store: {
                          'id': drop['storeId'],
                          'name': drop['merchant'],
                          'category': drop['category'] ?? 'Apparel',
                          'imageUrl': drop['avatar'],
                        }),
                      ),
                    );
                  },
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(drop['avatar']),
                      onBackgroundImageError: (_, __) {},
                      backgroundColor: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        drop['merchant'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        drop['handle'],
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      if (isFollowed) {
                        _followedMerchantIds.remove(drop['storeId'].hashCode);
                      } else {
                        _followedMerchantIds.add(drop['storeId'].hashCode);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: isFollowed
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
                      color: isFollowed
                          ? Colors.white.withValues(alpha: 0.15)
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      border: isFollowed
                          ? Border.all(color: Colors.white30)
                          : null,
                    ),
                    child: Text(
                      isFollowed ? 'Following' : 'Follow',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // Product title
              Text(
                drop['title'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 4)
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Tags
              Text(
                drop['tags'],
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              // Price row
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '\u20ac${drop['price'].toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '\u20ac${drop['originalPrice'].toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white38,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '-${drop['discountPct']}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              // Delivery row
              Row(children: [
                const Icon(Icons.local_shipping_outlined,
                    size: 14, color: Colors.white60),
                const SizedBox(width: 5),
                Text(
                  drop['deliveryTime'],
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                if (drop['audio'] != null)
                  Row(children: [
                    const Icon(Icons.music_note_rounded,
                        size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      drop['audio'],
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ]),
              ]),
            ],
          ),
        ),
        // Right side action buttons
        Positioned(
          right: 12,
          bottom: 110,
          child: Column(
            children: [
              // Like button
              _SideAction(
                icon: isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                iconColor:
                    isLiked ? const Color(0xFFEF4444) : Colors.white,
                label: isLiked ? '1' : '',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (isLiked) {
                      _likedIds.remove(dropId.hashCode);
                    } else {
                      _likedIds.add(dropId.hashCode);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              // Comments button
              _SideAction(
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: Colors.white,
                label: '${(_commentsStore[dropId.toString()] ?? []).length}',
                onTap: () => _openCommentsSheet(context, drop, l10n),
              ),
              const SizedBox(height: 16),
              // Share button
              _SideAction(
                icon: Icons.share_outlined,
                iconColor: Colors.white,
                label: '',
                onTap: () => HapticFeedback.lightImpact(),
              ),
              const SizedBox(height: 16),
              // Buy now button
              GestureDetector(
                onTap: () => _openCheckoutSheet(context, drop, l10n),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shopping_bag_outlined,
                      color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
        ),
        // Sizes preview strip at bottom
        Positioned(
          left: 16,
          right: 16,
          bottom: 56,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text(
                'Sizes: ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              ...(drop['sizes'] as List).map((s) => Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildFilterRail(AppLocalizations l10n) {
    final lang = Localizations.localeOf(context).languageCode;
    String label(Map<String, String> f) => f[lang] ?? f['en']!;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        // Category filters
        ..._categoryFilters.map((f) {
          final isSelected = _selectedCategory == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = f['key']!),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF8B5CF6) : Colors.white24,
                  ),
                ),
                child: Text(
                  label(f),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final merchantDrops = _filteredMerchantDrops;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFEC4899)),
              const SizedBox(height: 20),
              Text(
                Localizations.localeOf(context).languageCode == 'fi'
                    ? 'Ladataan pudotuksia...'
                    : 'Loading drops...',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // STRICT EMPTY STATE — no merchants yet, show clean empty card only
    if (merchantDrops.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          _buildStrictEmptyStateCard(context, l10n),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(children: [
                      Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'MALVOYA DROPS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ]),
                  ),
                  IconButton(
                    onPressed: _loadDropsFromAPI,
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ]),
      );
    }

    // MERCHANT DROPS AVAILABLE — show real content
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: merchantDrops.length,
          itemBuilder: (context, index) {
            return _buildReelCard(context, merchantDrops[index], l10n);
          },
        ),
        SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(children: [
                      Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'MALVOYA DROPS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ]),
                  ),
                  Row(children: [
                    IconButton(
                      onPressed: _loadDropsFromAPI,
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _isMuted = !_isMuted),
                      icon: Icon(
                        _isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            _buildFilterRail(l10n),
          ]),
        ),
        if (_showHeartAnim)
          Positioned(
            left: _heartAnimPos.dx - 40,
            top: _heartAnimPos.dy - 40,
            child: const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFEF4444),
              size: 80,
            ),
          ),
      ]),
    );
  }
}

// Side action button widget
class _SideAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _SideAction({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 30,
              shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black45, blurRadius: 3)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
