import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../screens/map_tracker.dart';

/**
 * Master Apparel Runway & Concierge Try-at-Home Feed
 * High-performance 120Hz shoppable runway feed featuring Nordic luxury fashion
 * and boutique garments with multi-size try-at-home concierge delivery.
 * 100% Luxury Fashion — Zero restaurants.
 */

class ApparelGarmentModel {
  final String id;
  final String brand;
  final String title;
  final double price;
  final int etaMinutes;
  final String fabricComposition;
  final String modelMetrics;
  final List<String> availableSizes;
  final Color accentColor;
  final IconData garmentIcon;
  final double fittingFee;

  ApparelGarmentModel({
    required this.id,
    required this.brand,
    required this.title,
    required this.price,
    required this.etaMinutes,
    required this.fabricComposition,
    required this.modelMetrics,
    required this.availableSizes,
    required this.accentColor,
    required this.garmentIcon,
    this.fittingFee = 0.0,
  });
}

class ApparelRunwayFeedScreen extends StatefulWidget {
  final List<ApparelGarmentModel>? customGarments;
  const ApparelRunwayFeedScreen({super.key, this.customGarments});

  @override
  State<ApparelRunwayFeedScreen> createState() => _ApparelRunwayFeedScreenState();
}

class _ApparelRunwayFeedScreenState extends State<ApparelRunwayFeedScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _glintController;
  int _focusedIndex = 0;

  late final List<ApparelGarmentModel> _garments;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _glintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _garments = widget.customGarments ?? [
      ApparelGarmentModel(
        id: 'grm_samsoe_overshirt_01',
        brand: 'Samsøe Samsøe',
        title: 'Liam Recycled Wool Overshirt',
        price: 189.00,
        etaMinutes: 18,
        fabricComposition: '100% Recycled Italian Wool • Dry Clean Only',
        modelMetrics: 'Model is 186cm • Wearing Size L',
        availableSizes: ['S', 'M', 'L', 'XL'],
        accentColor: const Color(0xFF8E4FAE),
        garmentIcon: Icons.checkroom_rounded,
      ),
      ApparelGarmentModel(
        id: 'grm_marimekko_linen_02',
        brand: 'Marimekko Helsinki',
        title: 'Unikko Organic Linen Kimono Coat',
        price: 245.00,
        etaMinutes: 22,
        fabricComposition: '100% Certified Organic European Linen',
        modelMetrics: 'Model is 178cm • Wearing Size M',
        availableSizes: ['XS', 'S', 'M', 'L'],
        accentColor: const Color(0xFF9B5DB8),
        garmentIcon: Icons.dry_cleaning_rounded,
      ),
      ApparelGarmentModel(
        id: 'grm_makia_merino_03',
        brand: 'Makia Clothing',
        title: 'Harbour Heavy Knit Merino Wool Sweater',
        price: 165.00,
        etaMinutes: 15,
        fabricComposition: '100% Extra-Fine Merino Wool • Mulesing-Free',
        modelMetrics: 'Model is 182cm • Wearing Size M',
        availableSizes: ['S', 'M', 'L', 'XL', 'XXL'],
        accentColor: const Color(0xFF6D2E8C),
        garmentIcon: Icons.style_rounded,
      ),
      ApparelGarmentModel(
        id: 'grm_filippa_silk_04',
        brand: 'Filippa K',
        title: 'Minimalist Mulberry Silk Slip Dress',
        price: 290.00,
        etaMinutes: 25,
        fabricComposition: '100% Mulberry Silk Crepe • OEKO-TEX Standard',
        modelMetrics: 'Model is 176cm • Wearing Size S',
        availableSizes: ['XS', 'S', 'M'],
        accentColor: const Color(0xFF248A52),
        garmentIcon: Icons.woman_rounded,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _glintController.dispose();
    super.dispose();
  }

  void _onSwipe(int idx) {
    HapticFeedback.selectionClick();
    setState(() => _focusedIndex = idx);
  }

  void _handleInitiateFitting(ApparelGarmentModel garment, List<String> sizes) {
    HapticFeedback.heavyImpact();
    final isMulti = sizes.length > 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17131C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: garment.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(garment.garmentIcon, color: garment.accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        garment.brand.toUpperCase(),
                        style: TextStyle(color: garment.accentColor, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        garment.title,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Selected Sizes to Try:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        sizes.join(" & "),
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Garment Pre-Auth Escrow:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text("€${garment.price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Concierge Fitting Fee (Courier Wait):", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        garment.fittingFee > 0 ? "€${garment.fittingFee.toStringAsFixed(2)}" : "Free / Included",
                        style: const TextStyle(color: Color(0xFF248A52), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Statutory ALV (25.5% incl.):", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text("€${(garment.price * 0.255 / 1.255).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF248A52), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isMulti
                        ? "Escrow pre-authorizes 1 garment + fitting fee. Courier waits 15 mins while you try both sizes. Keep your favorite; rejected size restocks atomically."
                        : "Express courier dispatch. Direct delivery from local boutique to your doorstep in ~${garment.etaMinutes} mins.",
                    style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: garment.accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  Navigator.pop(ctx);
                  final cleanId = "TRY-" + DateTime.now().millisecondsSinceEpoch.toString().substring(7);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapTrackerScreen(
                        orderId: cleanId,
                        merchantName: garment.brand,
                        deliveryAddress: "Boutique Express Delivery Destination",
                      ),
                    ),
                  );
                },
                child: Text(
                  isMulti ? "Confirm Concierge Fitting (€${(garment.price + garment.fittingFee).toStringAsFixed(2)})" : "Confirm Express Order (€${garment.price.toStringAsFixed(2)})",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF8E4FAE).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8E4FAE).withValues(alpha: 0.4)),
              ),
              child: const Text("120Hz RUNWAY", style: TextStyle(color: Color(0xFF8E4FAE), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
            ),
            const SizedBox(width: 8),
            Text(l10n.translate('tryAtHome'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 14),
                const SizedBox(width: 4),
                Text("${_focusedIndex + 1}/${_garments.length}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _garments.length,
        onPageChanged: _onSwipe,
        itemBuilder: (context, index) {
          final garment = _garments[index];

          return Stack(
            fit: StackFit.expand,
            children: [
              // Dynamic Animated Fabric Canvas with Anisotropic Light Glint Simulation
              AnimatedBuilder(
                animation: _glintController,
                builder: (context, _) {
                  final t = _glintController.value;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(math.sin(t * 2 * math.pi) * 0.4, math.cos(t * 2 * math.pi) * 0.3),
                        radius: 1.2,
                        colors: [
                          garment.accentColor.withValues(alpha: 0.35),
                          const Color(0xFF17131C),
                          const Color(0xFF050811),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: garment.accentColor.withValues(alpha: 0.12),
                              border: Border.all(color: garment.accentColor.withValues(alpha: 0.3), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: garment.accentColor.withValues(alpha: 0.25),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(garment.garmentIcon, size: 72, color: garment.accentColor),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.motion_photos_on_rounded, color: Color(0xFF8E4FAE), size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  "Impeller GLSL Luxury Fabric Glint",
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Subtle bottom gradient vignette
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xF0050811)],
                    stops: [0.55, 1.0],
                  ),
                ),
              ),

              // Action card overlay at the bottom
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _ApparelFittingCard(
                  garment: garment,
                  onProceed: (sizes) => _handleInitiateFitting(garment, sizes),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ApparelFittingCard extends StatefulWidget {
  final ApparelGarmentModel garment;
  final Function(List<String> sizes) onProceed;

  const _ApparelFittingCard({
    required this.garment,
    required this.onProceed,
  });

  @override
  State<_ApparelFittingCard> createState() => _ApparelFittingCardState();
}

class _ApparelFittingCardState extends State<_ApparelFittingCard> {
  final Set<String> _selectedSizes = {};

  @override
  void initState() {
    super.initState();
    _selectedSizes.add(widget.garment.availableSizes.first);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17131C).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.garment.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.garment.brand.toUpperCase(),
                  style: TextStyle(color: widget.garment.accentColor, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF248A52).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "~${widget.garment.etaMinutes} min delivery",
                  style: const TextStyle(color: Color(0xFF248A52), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.garment.title,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            widget.garment.fabricComposition,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            widget.garment.modelMetrics,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Boutique Price: €${widget.garment.price.toStringAsFixed(2)}",
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Text(
                  "ALV 25.5% incl.",
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Colors.cyanAccent, size: 14),
              const SizedBox(width: 6),
              const Text(
                "Select up to 2 sizes to try at home:",
                style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: widget.garment.availableSizes.map((sz) {
              final isSelected = _selectedSizes.contains(sz);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      if (_selectedSizes.length > 1) _selectedSizes.remove(sz);
                    } else {
                      if (_selectedSizes.length < 2) _selectedSizes.add(sz);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? widget.garment.accentColor : Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? widget.garment.accentColor : Colors.white24,
                    ),
                  ),
                  child: Text(
                    sz,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.garment.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                widget.onProceed(_selectedSizes.toList());
              },
              child: Text(
                _selectedSizes.length > 1
                    ? "Try Sizes ${_selectedSizes.join(' & ')} at Home"
                    : "Express Purchase (€${widget.garment.price.toStringAsFixed(2)})",
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
