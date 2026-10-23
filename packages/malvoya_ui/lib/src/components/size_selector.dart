import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// One size of an [MSizeSelector].
@immutable
class MSizeOption {
  /// Creates an option.
  const MSizeOption({required this.id, required this.label, this.soldOut = false});

  /// Stable id (the variant id).
  final String id;

  /// "M", "38", "S · Black".
  final String label;

  /// No stock.
  final bool soldOut;
}

/// Choose a size: a "Size" heading with a "Size guide" link, then size tiles.
///
/// The tile style is the customer app's add-to-bag tile: at least 60 × 48, soft brand fill and a
/// 2 px brand border when chosen, sold-out sizes crossed out and not selectable (still announced
/// as "M, sold out"). Wraps to more rows instead of scrolling, so every size is visible.
class MSizeSelector extends StatelessWidget {
  /// Creates the selector.
  const MSizeSelector({super.key, required this.options, required this.selectedId, required this.onChanged, this.label, this.onSizeGuide});

  /// The sizes in display order.
  final List<MSizeOption> options;

  /// The chosen size, or null.
  final String? selectedId;

  /// A size was chosen.
  final ValueChanged<String> onChanged;

  /// Heading (default "Size" / "Koko"). Empty string hides the heading row.
  final String? label;

  /// Shows a "Size guide" link that calls this.
  final VoidCallback? onSizeGuide;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final heading = label ?? tr(context, 'Size', 'Koko');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (heading.isNotEmpty || onSizeGuide != null)
        Row(children: [
          Expanded(child: Text(heading, style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface))),
          if (onSizeGuide != null)
            TextButton.icon(
              onPressed: onSizeGuide,
              icon: const Icon(Icons.straighten_rounded, size: 18),
              label: Text(tr(context, 'Size guide', 'Kokotaulukko')),
            ),
        ]),
      const SizedBox(height: MSpace.sm),
      Wrap(
        spacing: MSpace.sm,
        runSpacing: MSpace.sm,
        children: [for (final o in options) _SizeTile(option: o, selected: o.id == selectedId, onTap: () => onChanged(o.id))],
      ),
    ]);
  }
}

class _SizeTile extends StatelessWidget {
  final MSizeOption option;
  final bool selected;
  final VoidCallback onTap;
  const _SizeTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final available = !option.soldOut;
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      label: available ? option.label : '${option.label}, ${tr(context, 'sold out', 'loppu')}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: MRadius.brMd,
          onTap: available
              ? () {
                  Haptics.selection();
                  onTap();
                }
              : null,
          child: AnimatedContainer(
            duration: MMotion.of(context, MMotion.fast),
            curve: MMotion.standard,
            constraints: const BoxConstraints(minWidth: 60, minHeight: kMinTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? c.primarySoft : (available ? c.surface : c.surfaceVariant),
              borderRadius: MRadius.brMd,
              border: Border.all(color: selected ? c.primary : c.outline, width: selected ? 2 : 1.5),
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                option.label,
                style: MType.bodyL.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: selected ? c.primary : (available ? c.onSurface : c.onSurfaceVariant),
                  decoration: available ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
