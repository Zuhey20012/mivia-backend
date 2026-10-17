import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../core/strings.dart';
import 'empty_art.dart';
import '../core/haptics.dart';

/// Shimmering placeholder shapes shown while a screen loads, in the shape of what is coming
/// (instead of a bare spinner). Children are painted with plain white boxes; the shimmer tints them.
class Skeleton extends StatelessWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    return Semantics(
      label: tr(context, 'Loading', 'Ladataan'),
      excludeSemantics: true,
      child: Shimmer.fromColors(
        baseColor: dark ? const Color(0xFF2A2331) : AppTheme.sand,
        highlightColor: dark ? const Color(0xFF3A3242) : Colors.white,
        child: child,
      ),
    );
  }
}

/// One rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// One product tile placeholder (photo, name, price), for slivers and custom grids.
class SkeletonProductTile extends StatelessWidget {
  const SkeletonProductTile({super.key});

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SkeletonBox(height: double.infinity, radius: AppTheme.radiusMd)),
            SizedBox(height: 10),
            SkeletonBox(width: 120, height: 14),
            SizedBox(height: 6),
            SkeletonBox(width: 70, height: 14),
          ],
        ),
      );
}

/// Two-column product grid placeholder (same proportions as `ProductTile` grids).
class SkeletonProductGrid extends StatelessWidget {
  final int count;
  final EdgeInsets padding;
  const SkeletonProductGrid({super.key, this.count = 6, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 40)});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
          itemCount: count,
          itemBuilder: (_, __) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox(height: double.infinity, radius: AppTheme.radiusMd)),
              SizedBox(height: 10),
              SkeletonBox(width: 120, height: 14),
              SizedBox(height: 6),
              SkeletonBox(width: 70, height: 14),
            ],
          ),
        ),
      );
}

/// A list of card-shaped placeholders (orders, stores, returns).
class SkeletonCardList extends StatelessWidget {
  final int count;
  final double thumbHeight;
  final EdgeInsets padding;
  const SkeletonCardList({super.key, this.count = 5, this.thumbHeight = 68, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 40)});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: count,
          itemBuilder: (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
            ),
            child: Row(
              children: [
                SkeletonBox(width: 56, height: thumbHeight, radius: 12),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 150, height: 15),
                      SizedBox(height: 8),
                      SkeletonBox(width: 110, height: 12),
                      SizedBox(height: 10),
                      SkeletonBox(width: 80, height: 20, radius: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Placeholder for a detail page: a large block on top, then a few text lines and cards.
class SkeletonDetail extends StatelessWidget {
  final double heroHeight;
  const SkeletonDetail({super.key, this.heroHeight = 220});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            SkeletonBox(height: heroHeight, radius: AppTheme.radiusLg),
            const SizedBox(height: 18),
            const SkeletonBox(width: 220, height: 24),
            const SizedBox(height: 10),
            const SkeletonBox(width: 150, height: 14),
            const SizedBox(height: 22),
            const SkeletonBox(height: 120, radius: AppTheme.radiusLg),
            const SizedBox(height: 14),
            const SkeletonBox(height: 90, radius: AppTheme.radiusLg),
          ],
        ),
      );
}

/// A calm empty or error state: icon, one sentence and, when [onRetry] is set, a "Try again" pill.
/// Scrollable so it can sit inside a RefreshIndicator.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;
  final IconData? actionIcon;
  final double top;

  /// A short heading above [message] (optional).
  final String? title;

  const StateMessage({
    super.key,
    required this.icon,
    required this.message,
    this.onRetry,
    this.actionLabel,
    this.actionIcon,
    this.title,
    this.top = 110,
  });

  /// The standard error state with a retry button.
  const StateMessage.error({super.key, required this.message, required this.onRetry, this.top = 110})
      : icon = Icons.cloud_off_rounded,
        actionLabel = null,
        actionIcon = null,
        title = null;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryText(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(40, top, 40, 40),
          child: Column(
            children: [
              if (EmptyArt.forIcon(icon) case final art?)
                EmptyArt(art)
              else
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary), shape: BoxShape.circle),
                  child: Icon(icon, size: 38, color: AppTheme.isDarkMode(context) ? const Color(0xFFC9A3DD) : AppTheme.primary),
                ),
              const SizedBox(height: 16),
              if (title != null) ...[
                Text(title!, textAlign: TextAlign.center, style: AppTheme.display(context, size: 20)),
                const SizedBox(height: 6),
              ],
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 15, height: 1.4)),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Haptics.selection();
                    onRetry!();
                  },
                  // A plain retry shows the refresh arrow; a named next step shows its own icon (or none)
                  icon: Icon(actionIcon ?? (actionLabel == null ? Icons.refresh_rounded : Icons.arrow_forward_rounded), size: 20),
                  label: Text(actionLabel ?? tr(context, 'Try again', 'Yritä uudelleen')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
