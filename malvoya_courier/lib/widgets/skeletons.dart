import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// Placeholders shaped like the courier screens that are loading, built from malvoya_ui skeletons.
class _Shimmer extends StatelessWidget {
  final List<Widget> children;
  const _Shimmer({required this.children});

  @override
  Widget build(BuildContext context) => MSkeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(MSpace.lg),
          children: children,
        ),
      );
}

Widget _card(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(border: Border.all(color: MPalette.white, width: 1.5), borderRadius: MRadius.brLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );

/// Two job cards: pay, pickup line, distance tiles and the accept button.
class JobsSkeleton extends StatelessWidget {
  const JobsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => _Shimmer(children: [
        for (var i = 0; i < 2; i++)
          _card(const [
            MSkeletonBox(width: 120, height: 32),
            SizedBox(height: 10),
            MSkeletonBox(width: 180, height: 14),
            SizedBox(height: MSpace.lg),
            MSkeletonBox(height: 16),
            SizedBox(height: MSpace.sm),
            MSkeletonBox(width: 200, height: 14),
            SizedBox(height: 14),
            Row(children: [
              Expanded(child: MSkeletonBox(height: 56, radius: 14)),
              SizedBox(width: MSpace.sm),
              Expanded(child: MSkeletonBox(height: 56, radius: 14)),
            ]),
            SizedBox(height: 14),
            MSkeletonBox(height: 56, radius: 28),
          ]),
      ]);
}

/// Step indicator and the current step's card.
class DeliverySkeleton extends StatelessWidget {
  const DeliverySkeleton({super.key});

  @override
  Widget build(BuildContext context) => _Shimmer(children: [
        const MSkeletonBox(width: 220, height: 16),
        const SizedBox(height: 14),
        _card(const [MSkeletonBox(height: 44)]),
        _card(const [
          MSkeletonBox(width: 200, height: 22),
          SizedBox(height: MSpace.md),
          MSkeletonBox(height: 14),
          SizedBox(height: MSpace.sm),
          MSkeletonBox(width: 160, height: 14),
          SizedBox(height: MSpace.lg),
          MSkeletonBox(height: 56, radius: 28),
          SizedBox(height: 10),
          MSkeletonBox(height: 56, radius: 28),
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
            Expanded(child: MSkeletonBox(height: 86, radius: 20)),
            SizedBox(width: 10),
            Expanded(child: MSkeletonBox(height: 86, radius: 20)),
          ]),
        );
    return _Shimmer(children: [
      tiles(),
      tiles(),
      tiles(),
      const SizedBox(height: 6),
      const MSkeletonBox(height: 120, radius: 18),
      const SizedBox(height: MSpace.lg),
      for (var i = 0; i < 3; i++) ...[
        const MSkeletonBox(height: 18),
        const SizedBox(height: 6),
        const MSkeletonBox(width: 140, height: 12),
        const SizedBox(height: MSpace.lg),
      ],
    ]);
  }
}
