import 'package:flutter/material.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// A settings / navigation row: an icon in a soft circle, a title, an optional subtitle and a
/// trailing widget or chevron.
///
/// At least 56 px high (48 dp touch target), grows with the text size, never truncates the title
/// to one line. [destructive] rows (delete account, sign out) use the danger colour.
class MListTile extends StatelessWidget {
  /// Creates a row.
  const MListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron,
    this.destructive = false,
    this.enabled = true,
    this.iconBackground,
  });

  /// Main text.
  final String title;

  /// Secondary text.
  final String? subtitle;

  /// Icon shown in a soft circle.
  final IconData? icon;

  /// Any leading widget instead of [icon].
  final Widget? leading;

  /// Trailing widget (a switch, a value, a badge).
  final Widget? trailing;

  /// Tapped. Null makes the row informational.
  final VoidCallback? onTap;

  /// Show a chevron (defaults to true when tappable and there is no [trailing]).
  final bool? chevron;

  /// Danger colouring.
  final bool destructive;

  /// False dims the row and ignores taps.
  final bool enabled;

  /// The circle colour behind [icon] (default: soft brand, soft danger when destructive).
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final fg = destructive ? c.danger : c.onSurface;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final lead = leading ??
        (icon == null
            ? null
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: iconBackground ?? (destructive ? c.dangerSoft : c.primarySoft), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: destructive ? c.onDangerSoft : c.onPrimarySoft),
              ));
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.sm),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: MSpace.md)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: MType.bodyL.copyWith(fontWeight: FontWeight.w600, height: 1.3, color: fg)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: MType.bodyM.copyWith(color: c.onSurfaceVariant, height: 1.35)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: MSpace.sm), trailing!],
          if (showChevron) ...[const SizedBox(width: MSpace.xs), Icon(Icons.chevron_right_rounded, color: c.onSurfaceVariant)],
        ]),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: MRadius.brMd,
          child: Semantics(button: onTap != null, enabled: enabled, child: row),
        ),
      ),
    );
  }
}

/// A section heading with an optional action on the right ("See all").
class MSectionHeader extends StatelessWidget {
  /// Creates a heading.
  const MSectionHeader(this.title, {super.key, this.subtitle, this.actionLabel, this.onAction, this.padding = const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xxl, MSpace.sm, MSpace.sm)});

  /// The heading (display face, a header for screen readers).
  final String title;

  /// One quiet line under it.
  final String? subtitle;

  /// Action text.
  final String? actionLabel;

  /// Action.
  final VoidCallback? onAction;

  /// Outer padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: MType.title.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: c.onSurface))),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
            ],
          ]),
        ),
        if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ]),
    );
  }
}
