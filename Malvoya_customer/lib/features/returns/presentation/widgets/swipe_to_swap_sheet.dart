import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../l10n.dart';

/**
 * Malvoya "Swipe to Swap" Variant & Exchange Sheet
 * Blank state matching Drop aesthetic until boutique variant telemetry is onboarded.
 * Zero hardcoded mock swatch colors, zero mock fabrics, zero mock badges.
 */

class SwipeToSwapSheet extends StatelessWidget {
  final String orderId;
  final String itemName;
  final String currentSize;
  final String currentColor;
  final double price;
  final String storeName;

  const SwipeToSwapSheet({
    super.key,
    required this.orderId,
    required this.itemName,
    this.currentSize = 'S',
    this.currentColor = '',
    required this.price,
    this.storeName = 'Local Boutique',
  });

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String itemName,
    String currentSize = 'S',
    String currentColor = '',
    required double price,
    String storeName = 'Local Boutique',
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SwipeToSwapSheet(
        orderId: orderId,
        itemName: itemName,
        currentSize: currentSize,
        currentColor: currentColor,
        price: price,
        storeName: storeName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF6D2E8C).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 32),

          // Glowing Violet/Purple Emblem (Identical to Drop aesthetic)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6D2E8C), Color(0xFF55226E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6D2E8C).withValues(alpha: 0.5),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            l10n.translate('swapVariantsComingSoon'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),

          // Subtitle
          Text(
            l10n.translate('swapVariantsComingSoonSub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),

          // Item Reference Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6D2E8C).withValues(alpha: 0.35), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.checkroom_rounded, size: 16, color: Color(0xFF6D2E8C)),
                const SizedBox(width: 8),
                Text(
                  itemName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Close Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                l10n.translate('close'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
