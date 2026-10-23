import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:shimmer/shimmer.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';

/// Shimmering placeholders in the shape of what is loading (instead of a bare spinner).
///
/// Paint the shapes with [MSkeletonBox] inside an [MSkeleton]; the shimmer tints them. The
/// shimmer stands still when the phone reduces motion, and screen readers hear one "Loading".
class MSkeleton extends StatelessWidget {
  /// Wraps placeholder shapes.
  const MSkeleton({super.key, required this.child});

  /// The placeholder shapes.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Semantics(
      label: tr(context, 'Loading', 'Ladataan'),
      liveRegion: true,
      excludeSemantics: true,
      child: Shimmer.fromColors(
        baseColor: c.skeletonBase,
        highlightColor: c.skeletonHighlight,
        enabled: !reduceMotion(context),
        child: child,
      ),
    );
  }
}

/// One rounded placeholder block (use inside [MSkeleton]).
class MSkeletonBox extends StatelessWidget {
  /// Creates a block. A null [width] fills the row.
  const MSkeletonBox({super.key, this.width, this.height = 14, this.radius = MRadius.xs});

  /// Width (null = as wide as allowed).
  final double? width;

  /// Height.
  final double height;

  /// Corner radius.
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// A card-shaped placeholder: optional thumbnail and a few text lines (orders, stores, returns).
class MSkeletonCard extends StatelessWidget {
  /// Creates a card placeholder.
  const MSkeletonCard({super.key, this.thumbnail = false, this.thumbHeight = 72, this.lines = 3, this.button = false});

  /// A thumbnail on the left.
  final bool thumbnail;

  /// Height of the thumbnail (it is 64 wide).
  final double thumbHeight;

  /// Text lines (the first is a heading).
  final int lines;

  /// A pill button at the bottom.
  final bool button;

  @override
  Widget build(BuildContext context) {
    const widths = [0.55, 0.85, 0.4, 0.7, 0.6];
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: EdgeInsets.all(thumbnail ? MSpace.md : MSpace.lg),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 1.5),
        borderRadius: MRadius.brLg,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (thumbnail) ...[
          MSkeletonBox(width: 64, height: thumbHeight, radius: MRadius.sm),
          const SizedBox(width: MSpace.md),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < lines; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                MSkeletonBox(width: box.maxWidth * widths[i % widths.length], height: i == 0 ? 16 : 12),
              ],
              if (button) ...[
                const SizedBox(height: 14),
                const MSkeletonBox(height: 44, radius: MRadius.pill),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A scrollable list of [MSkeletonCard]s. It can be pulled to refresh like the real list.
class MSkeletonList extends StatelessWidget {
  /// Creates the list.
  const MSkeletonList({
    super.key,
    this.count = 4,
    this.thumbnail = false,
    this.thumbHeight = 72,
    this.lines = 3,
    this.button = false,
    this.padding = const EdgeInsets.all(MSpace.lg),
    this.header = const [],
  });

  /// Number of cards.
  final int count;

  /// Cards with thumbnails.
  final bool thumbnail;

  /// Height of the thumbnails.
  final double thumbHeight;

  /// Lines per card.
  final int lines;

  /// The first card has a button.
  final bool button;

  /// Padding of the list.
  final EdgeInsets padding;

  /// Real widgets above the placeholders (a header that is already known).
  final List<Widget> header;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          ...header,
          MSkeleton(
            child: Column(children: [
              for (var i = 0; i < count; i++) MSkeletonCard(thumbnail: thumbnail, thumbHeight: thumbHeight, lines: lines, button: button && i == 0),
            ]),
          ),
        ],
      );
}

/// One product tile placeholder (photo, name, price), for grids and slivers.
class MSkeletonProductTile extends StatelessWidget {
  /// Creates the tile placeholder.
  const MSkeletonProductTile({super.key});

  @override
  Widget build(BuildContext context) => const MSkeleton(child: _ProductShape());
}

class _ProductShape extends StatelessWidget {
  const _ProductShape();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: MSkeletonBox(height: double.infinity, radius: MRadius.md)),
          SizedBox(height: 10),
          MSkeletonBox(width: 120, height: 14),
          SizedBox(height: 6),
          MSkeletonBox(width: 70, height: 14),
        ],
      );
}

/// Two-column product grid placeholder (same proportions as the product grids).
class MSkeletonProductGrid extends StatelessWidget {
  /// Creates the grid.
  const MSkeletonProductGrid({super.key, this.count = 6, this.padding = const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l)});

  /// Number of tiles.
  final int count;

  /// Padding of the grid.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => MSkeleton(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: 0.56),
          itemCount: count,
          itemBuilder: (_, __) => const _ProductShape(),
        ),
      );
}

/// Placeholder for a detail page: a large block on top, then text lines and cards.
class MSkeletonDetail extends StatelessWidget {
  /// Creates the placeholder.
  const MSkeletonDetail({super.key, this.heroHeight = 220});

  /// Height of the top block.
  final double heroHeight;

  @override
  Widget build(BuildContext context) => MSkeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(MSpace.lg),
          children: [
            MSkeletonBox(height: heroHeight, radius: MRadius.lg),
            const SizedBox(height: 18),
            const MSkeletonBox(width: 220, height: 24),
            const SizedBox(height: 10),
            const MSkeletonBox(width: 150, height: 14),
            const SizedBox(height: 22),
            const MSkeletonBox(height: 120, radius: MRadius.lg),
            const SizedBox(height: 14),
            const MSkeletonBox(height: 90, radius: MRadius.lg),
          ],
        ),
      );
}
