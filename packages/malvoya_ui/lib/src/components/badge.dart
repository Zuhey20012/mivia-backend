import 'package:flutter/material.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// The colour of an [MBadge].
enum MBadgeTone {
  /// Soft brand tint (default).
  brand,

  /// Sunshine: new, highlights, counters.
  sunshine,

  /// Done, paid, open now.
  success,

  /// Needs attention.
  warning,

  /// Failed, cancelled, sold out.
  danger,

  /// Quiet information (sand).
  neutral,
}

/// A small status pill ("New", "Paid", "Video", "Sold out"), or a count dot.
///
/// Not tappable: it describes something. Text keeps its contrast in every tone (soft fills with
/// their `on…` colours) and the badge grows with the text size.
class MBadge extends StatelessWidget {
  /// A pill with [label].
  const MBadge(this.label, {super.key, this.tone = MBadgeTone.brand, this.icon, this.strong = false, this.semanticLabel});

  /// A round counter (e.g. on the bag icon). 99+ above 99.
  MBadge.count(int count, {super.key, this.tone = MBadgeTone.sunshine, this.semanticLabel})
      : label = count > 99 ? '99+' : '$count',
        icon = null,
        strong = true;

  /// The text.
  final String label;

  /// Colour.
  final MBadgeTone tone;

  /// Optional leading icon.
  final IconData? icon;

  /// Full-strength fill instead of the soft one.
  final bool strong;

  /// Read instead of [label] (e.g. "3 items in your bag").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final (Color bg, Color fg) = switch ((tone, strong)) {
      (MBadgeTone.brand, false) => (c.primarySoft, c.onPrimarySoft),
      (MBadgeTone.brand, true) => (c.primary, c.onPrimary),
      (MBadgeTone.sunshine, false) => (c.sunshineSoft, c.onSunshineSoft),
      (MBadgeTone.sunshine, true) => (c.sunshine, c.onSunshine),
      (MBadgeTone.success, false) => (c.successSoft, c.onSuccessSoft),
      (MBadgeTone.success, true) => (c.success, c.onSuccess),
      (MBadgeTone.warning, false) => (c.warningSoft, c.onWarningSoft),
      (MBadgeTone.warning, true) => (c.warning, c.onWarning),
      (MBadgeTone.danger, false) => (c.dangerSoft, c.onDangerSoft),
      (MBadgeTone.danger, true) => (c.danger, c.onDanger),
      (MBadgeTone.neutral, _) => (c.surfaceVariant, c.onSurfaceVariant),
    };
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: MRadius.pillRadius),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: MSpace.xs)],
          Text(label, textAlign: TextAlign.center, style: MType.caption.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1.2)),
        ]),
      ),
    );
  }
}
