import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../core/strings.dart';

/// Placeholders shaped like the content that is loading, instead of a full-screen spinner.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

class _Shimmer extends StatelessWidget {
  final List<Widget> children;
  const _Shimmer({required this.children});

  @override
  Widget build(BuildContext context) => Semantics(
        label: tr(context, 'Loading', 'Ladataan'),
        child: ExcludeSemantics(
          child: Shimmer.fromColors(
            baseColor: AppTheme.divider,
            highlightColor: AppTheme.background,
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          ),
        ),
      );
}

Widget _card(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );

/// Two job cards: pay, pickup line, distance tiles and the accept button.
class JobsSkeleton extends StatelessWidget {
  const JobsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => _Shimmer(children: [
        for (var i = 0; i < 2; i++)
          _card(const [
            SkeletonBox(width: 120, height: 32),
            SizedBox(height: 10),
            SkeletonBox(width: 180, height: 14),
            SizedBox(height: 16),
            SkeletonBox(height: 16),
            SizedBox(height: 8),
            SkeletonBox(width: 200, height: 14),
            SizedBox(height: 14),
            Row(children: [
              Expanded(child: SkeletonBox(height: 56, radius: 14)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 56, radius: 14)),
            ]),
            SizedBox(height: 14),
            SkeletonBox(height: 56, radius: 28),
          ]),
      ]);
}

/// Step indicator and the current step's card.
class DeliverySkeleton extends StatelessWidget {
  const DeliverySkeleton({super.key});

  @override
  Widget build(BuildContext context) => _Shimmer(children: [
        const SkeletonBox(width: 220, height: 16),
        const SizedBox(height: 14),
        _card(const [SkeletonBox(height: 44)]),
        _card(const [
          SkeletonBox(width: 200, height: 22),
          SizedBox(height: 12),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 160, height: 14),
          SizedBox(height: 16),
          SkeletonBox(height: 56, radius: 28),
          SizedBox(height: 10),
          SkeletonBox(height: 56, radius: 28),
        ]),
      ]);
}

/// Stat tiles and a few delivery rows.
class EarningsSkeleton extends StatelessWidget {
  const EarningsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tiles() => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: SkeletonBox(height: 86, radius: 20)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 86, radius: 20)),
          ]),
        );
    return _Shimmer(children: [
      tiles(),
      tiles(),
      tiles(),
      const SizedBox(height: 6),
      const SkeletonBox(height: 120, radius: 18),
      const SizedBox(height: 16),
      for (var i = 0; i < 3; i++) ...[
        const SkeletonBox(height: 18),
        const SizedBox(height: 6),
        const SkeletonBox(width: 140, height: 12),
        const SizedBox(height: 16),
      ],
    ]);
  }
}

/// One look for empty and error states. Always scrollable, so pull-to-refresh works on it too.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String text;
  final VoidCallback? onRetry;
  final Widget? action;
  final bool error;

  const StateMessage({super.key, required this.icon, this.title, required this.text, this.onRetry, this.action, this.error = false});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(color: error ? AppTheme.sunshineLight : AppTheme.primaryLight, shape: BoxShape.circle),
                      child: Icon(icon, size: 40, color: error ? const Color(0xFF8A5A00) : AppTheme.primary),
                    ),
                    const SizedBox(height: 16),
                    if (title != null) ...[
                      Text(title!, textAlign: TextAlign.center, style: AppTheme.display(size: 20)),
                      const SizedBox(height: 6),
                    ],
                    Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4)),
                    if (onRetry != null) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr(context, 'Try again', 'Yritä uudelleen')),
                      ),
                    ],
                    if (action != null) ...[const SizedBox(height: 18), action!],
                  ]),
                ),
              ),
            ),
          ],
        ),
      );
}
