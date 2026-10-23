import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// A pill chip: a filter that can be on or off, a choice, or an active filter with a remove button.
///
/// States: default, selected (soft brand fill, brand border, check mark), pressed, disabled
/// ([onSelected] null and no [onRemove]). The visible pill is 36 px high inside a 48 dp touch target.
class MChip extends StatelessWidget {
  /// Creates a chip.
  const MChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.icon,
    this.count,
    this.onRemove,
    this.showCheck = true,
  });

  /// The text.
  final String label;

  /// On (filter applied, option chosen).
  final bool selected;

  /// Tapped; receives the new value. Null makes the chip read-only.
  final ValueChanged<bool>? onSelected;

  /// Leading icon (hidden while the check mark shows).
  final IconData? icon;

  /// A small number after the label (results, active filters).
  final int? count;

  /// Shows a × that removes the chip (active filters).
  final VoidCallback? onRemove;

  /// Show a check mark when [selected].
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final enabled = onSelected != null || onRemove != null;
    final fg = !enabled ? c.onSurfaceVariant : (selected ? c.onPrimarySoft : c.onSurface);
    final leading = selected && showCheck ? Icons.check_rounded : icon;
    final text = count == null ? label : '$label  $count';

    Widget pill = AnimatedContainer(
      duration: MMotion.of(context, MMotion.fast),
      curve: MMotion.standard,
      constraints: const BoxConstraints(minHeight: 36),
      padding: EdgeInsets.only(left: leading == null ? 14 : 10, right: onRemove == null ? 14 : 4),
      decoration: ShapeDecoration(
        color: selected ? c.primarySoft : c.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.primary : c.outline, width: selected ? 1.5 : 1.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[Icon(leading, size: 18, color: fg), const SizedBox(width: 6)],
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: MType.label.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
        ),
        if (onRemove != null)
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              tooltip: tr(context, 'Remove $label', 'Poista $label'),
              onPressed: () {
                Haptics.selection();
                onRemove!();
              },
              icon: Icon(Icons.close_rounded, color: fg),
            ),
          ),
      ]),
    );

    if (onSelected != null) {
      pill = Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            Haptics.selection();
            onSelected!(!selected);
          },
          child: pill,
        ),
      );
    }

    return Semantics(
      button: onSelected != null,
      selected: selected,
      enabled: enabled,
      label: count == null ? label : '$label, $count',
      excludeSemantics: onRemove == null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTouchTarget),
        child: Align(widthFactor: 1, heightFactor: 1, child: pill),
      ),
    );
  }
}

/// One quick filter in an [MFilterBar].
@immutable
class MFilterOption {
  /// Creates an option.
  const MFilterOption({required this.id, required this.label, this.selected = false, this.icon});

  /// Stable id ("size_m", "open_now").
  final String id;

  /// Text.
  final String label;

  /// On.
  final bool selected;

  /// Optional icon.
  final IconData? icon;
}

/// The one filter pattern for every list (Zalando-style): a "Filters" button with the number of
/// active filters, an optional sort button, quick toggle chips, and the active filters as
/// removable chips with "Clear all".
///
/// Scrolls horizontally, so it never wraps or overflows at large text sizes.
class MFilterBar extends StatelessWidget {
  /// Creates the bar.
  const MFilterBar({
    super.key,
    this.quick = const [],
    this.onQuickChanged,
    this.active = const [],
    this.onRemove,
    this.onClearAll,
    this.onOpenFilters,
    this.sortLabel,
    this.onSort,
    this.padding = const EdgeInsets.symmetric(horizontal: MSpace.lg),
  });

  /// Toggle chips shown always (e.g. "Open now", "Pickup").
  final List<MFilterOption> quick;

  /// A quick chip was toggled: its id and new value.
  final void Function(String id, bool selected)? onQuickChanged;

  /// Filters chosen in the filter sheet, shown as removable chips.
  final List<MFilterOption> active;

  /// An active filter's × was tapped.
  final ValueChanged<String>? onRemove;

  /// "Clear all" (shown when two or more filters are active).
  final VoidCallback? onClearAll;

  /// Opens the full filter sheet.
  final VoidCallback? onOpenFilters;

  /// The current sort ("Nearest"); shows a sort button when set.
  final String? sortLabel;

  /// Opens the sort choice.
  final VoidCallback? onSort;

  /// Outer padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (onOpenFilters != null)
        MChip(
          label: tr(context, 'Filters', 'Suodattimet'),
          icon: Icons.tune_rounded,
          count: active.isEmpty ? null : active.length,
          selected: active.isNotEmpty,
          showCheck: false,
          onSelected: (_) => onOpenFilters!(),
        ),
      if (sortLabel != null)
        MChip(
          label: sortLabel!,
          icon: Icons.swap_vert_rounded,
          showCheck: false,
          onSelected: onSort == null ? null : (_) => onSort!(),
        ),
      for (final q in quick)
        MChip(
          label: q.label,
          icon: q.icon,
          selected: q.selected,
          onSelected: onQuickChanged == null ? null : (v) => onQuickChanged!(q.id, v),
        ),
      for (final a in active)
        MChip(
          label: a.label,
          selected: true,
          showCheck: false,
          onRemove: onRemove == null ? null : () => onRemove!(a.id),
        ),
      if (active.length >= 2 && onClearAll != null)
        TextButton(
          onPressed: () {
            Haptics.selection();
            onClearAll!();
          },
          child: Text(tr(context, 'Clear all', 'Tyhjennä')),
        ),
    ];
    return SizedBox(
      height: 52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: MSpace.sm),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}
