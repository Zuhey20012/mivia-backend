import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// The colour of a "#RRGGBB" string (the API's `shadeHex`), or null.
Color? colorFromHex(String? hex) {
  final h = hex?.trim().replaceFirst('#', '');
  if (h == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return Color(int.parse('FF$h', radix: 16));
}

/// One beauty shade or colour: a circle of the real colour.
///
/// States: default, selected (a brand ring with a gap, so even a shade close to the brand stays
/// visible), sold out (a diagonal line; still focusable and announced, not selectable), pressed.
/// Light shades get a hairline so they never vanish on white. 48 dp touch target.
class MSwatch extends StatelessWidget {
  /// Creates a swatch.
  const MSwatch({super.key, required this.color, required this.name, this.selected = false, this.soldOut = false, this.onTap, this.size = 40});

  /// The shade.
  final Color color;

  /// "Rose 02": read by screen readers and shown by the picker.
  final String name;

  /// Chosen.
  final bool selected;

  /// No stock: crossed out, not selectable.
  final bool soldOut;

  /// Tapped (ignored when sold out).
  final VoidCallback? onTap;

  /// Circle diameter (the touch target is at least 48).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final light = color.computeLuminance() > 0.8;
    final ring = selected ? c.primary : Colors.transparent;
    final outer = size + 10;
    final circle = AnimatedContainer(
      duration: MMotion.of(context, MMotion.fast),
      width: outer,
      height: outer,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: light || c.isDark ? c.outlineStrong.withValues(alpha: 0.5) : Colors.transparent, width: 1),
        ),
        child: soldOut
            ? CustomPaint(painter: _SoldOutLine(color.computeLuminance() > 0.45 ? c.onSurface.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.9)))
            : (selected ? Icon(Icons.check_rounded, size: size * 0.45, color: color.computeLuminance() > 0.45 ? Colors.black87 : Colors.white) : null),
      ),
    );
    final label = soldOut ? '$name, ${tr(context, 'sold out', 'loppu')}' : name;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !soldOut && onTap != null,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: soldOut || onTap == null
              ? null
              : () {
                  Haptics.selection();
                  onTap!();
                },
          radius: outer / 2 + 4,
          child: SizedBox(
            width: outer < kMinTouchTarget ? kMinTouchTarget : outer,
            height: outer < kMinTouchTarget ? kMinTouchTarget : outer,
            child: Center(child: Opacity(opacity: soldOut ? 0.55 : 1, child: circle)),
          ),
        ),
      ),
    );
  }
}

class _SoldOutLine extends CustomPainter {
  final Color color;
  _SoldOutLine(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * 0.18, size.height * 0.82), Offset(size.width * 0.82, size.height * 0.18), p);
  }

  @override
  bool shouldRepaint(_SoldOutLine old) => old.color != color;
}

/// One option of an [MSwatchPicker].
@immutable
class MSwatchOption {
  /// Creates an option.
  const MSwatchOption({required this.id, required this.name, required this.color, this.soldOut = false});

  /// From an API variant (`id`, `shadeName` or `color`, `shadeHex`, `inStock`). Null without a usable hex.
  static MSwatchOption? fromVariant(Map variant) {
    final color = colorFromHex(variant['shadeHex'] as String?);
    final id = asInt(variant['id']);
    if (color == null || id == null) return null;
    final name = '${variant['shadeName'] ?? variant['color'] ?? ''}'.trim();
    return MSwatchOption(id: '$id', name: name.isEmpty ? '#${(variant['shadeHex'] as String).replaceFirst('#', '')}' : name, color: color, soldOut: variant['inStock'] == false);
  }

  /// Stable id (the variant id).
  final String id;

  /// Shade name.
  final String name;

  /// Shade colour.
  final Color color;

  /// No stock.
  final bool soldOut;
}

/// Choose a shade (Sephora / Lyko pattern): a heading with the chosen shade's name, then the
/// swatches in rows. The name updates as the selection changes, so the colour is never the only
/// cue.
class MSwatchPicker extends StatelessWidget {
  /// Creates the picker.
  const MSwatchPicker({super.key, required this.options, required this.selectedId, required this.onChanged, this.label, this.swatchSize = 40});

  /// The shades in display order.
  final List<MSwatchOption> options;

  /// The chosen shade, or null.
  final String? selectedId;

  /// A shade was chosen.
  final ValueChanged<String> onChanged;

  /// Heading (default "Shade" / "Sävy").
  final String? label;

  /// Circle size.
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final selected = options.where((o) => o.id == selectedId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${label ?? tr(context, 'Shade', 'Sävy')}: ', style: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
          TextSpan(
            text: selected == null ? tr(context, 'choose one', 'valitse') : (selected.soldOut ? '${selected.name} (${tr(context, 'sold out', 'loppu')})' : selected.name),
            style: MType.bodyM.copyWith(color: selected == null ? c.onSurfaceVariant : c.onSurface),
          ),
        ]),
      ),
      const SizedBox(height: MSpace.xs),
      Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final o in options)
            MSwatch(
              color: o.color,
              name: o.name,
              selected: o.id == selectedId,
              soldOut: o.soldOut,
              size: swatchSize,
              onTap: () => onChanged(o.id),
            ),
        ],
      ),
    ]);
  }
}
