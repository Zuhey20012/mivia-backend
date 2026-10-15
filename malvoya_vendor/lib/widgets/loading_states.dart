import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../core/strings.dart';

/// Shared loading, empty and error states for the store app, so every list looks the same while
/// it loads, when it is empty and when it fails.

/// Soft shimmer over grey placeholder shapes. Turns still when the system asks for less motion.
class Shimmering extends StatelessWidget {
  final Widget child;
  const Shimmering({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: AppTheme.divider,
        highlightColor: const Color(0xFFFAF8F4),
        enabled: !MediaQuery.of(context).disableAnimations,
        child: child,
      );
}

/// One grey placeholder shape (use inside [Shimmering]).
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// A card-shaped placeholder: optional thumbnail on the left and a few text lines.
class SkeletonCard extends StatelessWidget {
  final bool thumbnail;
  final int lines;
  final bool button;
  const SkeletonCard({super.key, this.thumbnail = false, this.lines = 3, this.button = false});

  @override
  Widget build(BuildContext context) {
    const widths = [0.55, 0.85, 0.4, 0.7, 0.6];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(thumbnail ? 10 : 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 8), border: Border.all(color: AppTheme.divider)),
      child: Shimmering(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (thumbnail) ...[
            const SkeletonBox(width: 64, height: 78, radius: 10),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < lines; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  SkeletonBox(width: c.maxWidth * widths[i % widths.length], height: i == 0 ? 16 : 12),
                ],
                if (button) ...[
                  const SizedBox(height: 14),
                  const SkeletonBox(height: 44, radius: 22),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A scrollable list of [SkeletonCard]s, used in place of a full-screen spinner. It can be pulled
/// to refresh like the real list.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool thumbnail;
  final int lines;
  final bool button;
  final EdgeInsets padding;
  final List<Widget> header;
  const SkeletonList({
    super.key,
    this.count = 4,
    this.thumbnail = false,
    this.lines = 3,
    this.button = false,
    this.padding = const EdgeInsets.all(16),
    this.header = const [],
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: tr(context, 'Loading', 'Ladataan'),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            ...header,
            for (var i = 0; i < count; i++) SkeletonCard(thumbnail: thumbnail, lines: lines, button: button && i == 0),
          ],
        ),
      );
}

/// A friendly empty state: sunny circle with an icon, a short explanation and optional actions.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final double top;
  const EmptyState({super.key, required this.icon, required this.message, this.actions = const [], this.top = 56});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppTheme.sunshineLight, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: const Color(0xFF8A5A00)),
          ),
          const SizedBox(height: 18),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: 15)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...actions,
          ],
        ]),
      );
}

/// Loading failed: what went wrong and a "Try again" button.
class ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final double top;
  const ErrorState({super.key, this.message, required this.onRetry, this.top = 56});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppTheme.peach, shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, size: 40, color: AppTheme.accent),
          ),
          const SizedBox(height: 18),
          Text(
            message ?? tr(context, 'Could not load this. Check your connection and try again.', 'Lataus epäonnistui. Tarkista yhteys ja yritä uudelleen.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: 15),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
        ]),
      );
}

/// A slim error strip above content that is still shown (e.g. older data after a failed refresh).
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(color: AppTheme.peach, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: AppTheme.accent, fontWeight: FontWeight.w600))),
          TextButton(onPressed: onRetry, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
        ]),
      );
}
