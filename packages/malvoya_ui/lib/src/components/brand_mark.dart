import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// The Malvoya "Thread M": one continuous thread that stitches an M and ends in a map pin.
/// Drawn in code so it stays sharp at every size and follows the theme colour.
class BrandMark extends StatelessWidget {
  /// The mark, [size] wide, in [color].
  const BrandMark({super.key, this.size = 40, required this.color});

  /// Width and height.
  final double size;

  /// Stroke colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Malvoya',
      image: true,
      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _ThreadMPainter(color))),
    );
  }
}

/// App-icon style tile: the mark on a rounded brand-coloured square.
class BrandTile extends StatelessWidget {
  /// The tile, [size] wide, on [background].
  const BrandTile({super.key, this.size = 76, required this.background, this.foreground = MPalette.birch});

  /// Width and height.
  final double size;

  /// Tile colour (the app's brand).
  final Color background;

  /// Mark colour.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.225),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: BrandMark(size: size * 0.62, color: foreground),
    );
  }
}

class _ThreadMPainter extends CustomPainter {
  final Color color;
  _ThreadMPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Same geometry as the published logo (100×100 view box).
    final path = Path()
      ..moveTo(20 * s, 82 * s)
      ..lineTo(20 * s, 36 * s)
      ..cubicTo(20 * s, 21 * s, 36 * s, 18 * s, 43 * s, 30 * s)
      ..lineTo(50 * s, 43 * s)
      ..lineTo(57 * s, 30 * s)
      ..cubicTo(64 * s, 18 * s, 80 * s, 21 * s, 80 * s, 36 * s)
      ..lineTo(80 * s, 66 * s);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(80 * s, 82 * s), 7 * s, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ThreadMPainter old) => old.color != color;
}
