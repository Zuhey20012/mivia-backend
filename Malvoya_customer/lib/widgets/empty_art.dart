import 'package:flutter/material.dart';
import '../config/theme.dart';

/// What an empty or error state is about; each has its own small drawing.
enum EmptyArtKind { bag, orders, favourites, search, offline, store, drops, delivery }

/// Small hand-drawn scenes for empty and error states, in the Birch Market palette (a sunny dot,
/// a pastel hill, the object itself). Drawn with CustomPaint, so no image files or downloads.
class EmptyArt extends StatelessWidget {
  final EmptyArtKind kind;
  final double width;
  const EmptyArt(this.kind, {super.key, this.width = 168});

  /// The drawing that fits a Material icon used by an existing empty state, if there is one.
  static EmptyArtKind? forIcon(IconData icon) {
    if (icon == Icons.shopping_bag_outlined || icon == Icons.shopping_bag_rounded) return EmptyArtKind.bag;
    if (icon == Icons.receipt_long_outlined || icon == Icons.receipt_long_rounded) return EmptyArtKind.orders;
    if (icon == Icons.favorite_border_rounded || icon == Icons.favorite_rounded) return EmptyArtKind.favourites;
    if (icon == Icons.search_off_rounded || icon == Icons.search_rounded) return EmptyArtKind.search;
    if (icon == Icons.cloud_off_rounded || icon == Icons.wifi_off_rounded) return EmptyArtKind.offline;
    if (icon == Icons.storefront_outlined || icon == Icons.storefront_rounded) return EmptyArtKind.store;
    if (icon == Icons.play_circle_outline_rounded) return EmptyArtKind.drops;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 0.76,
        child: CustomPaint(painter: _ArtPainter(kind, dark)),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  final EmptyArtKind kind;
  final bool dark;
  _ArtPainter(this.kind, this.dark);

  // Drawn on a 160 × 122 canvas and scaled to fit
  static const _w = 160.0;

  Color get _paper => dark ? const Color(0xFF2E2636) : Colors.white;
  Color get _line => dark ? const Color(0xFF4A4054) : AppTheme.clay;
  Color get _brand => dark ? const Color(0xFFC9A3DD) : AppTheme.primary;

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _w;
    canvas.save();
    canvas.scale(s);

    // Scene: a pastel hill, the sun and a few confetti dots
    final hill = dark ? AppTheme.primary.withValues(alpha: 0.22) : AppTheme.lilac;
    canvas.drawOval(const Rect.fromLTWH(12, 86, 136, 30), _fill(hill));
    canvas.drawCircle(const Offset(128, 26), 15, _fill(AppTheme.sunshine.withValues(alpha: dark ? 0.75 : 1)));
    canvas.drawCircle(const Offset(30, 34), 4, _fill(AppTheme.sunshine.withValues(alpha: 0.8)));
    canvas.drawCircle(const Offset(140, 74), 3, _fill(_brand.withValues(alpha: 0.35)));
    canvas.drawCircle(const Offset(22, 80), 3, _fill(AppTheme.clayInk.withValues(alpha: 0.35)));
    canvas.drawCircle(const Offset(112, 8), 2.5, _fill(_brand.withValues(alpha: 0.3)));

    switch (kind) {
      case EmptyArtKind.bag:
        _bag(canvas);
      case EmptyArtKind.orders:
        _receipt(canvas);
      case EmptyArtKind.favourites:
        _heart(canvas);
      case EmptyArtKind.search:
        _magnifier(canvas);
      case EmptyArtKind.offline:
        _cloud(canvas);
      case EmptyArtKind.store:
        _shop(canvas);
      case EmptyArtKind.drops:
        _phone(canvas);
      case EmptyArtKind.delivery:
        _bike(canvas);
    }
    canvas.restore();
  }

  void _bag(Canvas c) {
    final handle = Path()
      ..moveTo(66, 50)
      ..lineTo(66, 42)
      ..arcToPoint(const Offset(94, 42), radius: const Radius.circular(14))
      ..lineTo(94, 50);
    c.drawPath(handle, _stroke(dark ? const Color(0xFF8E6AA3) : AppTheme.primaryDark, 5));
    c.drawRRect(RRect.fromLTRBR(52, 48, 108, 104, const Radius.circular(12)), _fill(AppTheme.primary));
    c.drawRect(const Rect.fromLTRB(52, 64, 108, 72), _fill(AppTheme.sunshine));
    c.drawCircle(const Offset(66, 56), 2.6, _fill(Colors.white.withValues(alpha: 0.85)));
    c.drawCircle(const Offset(94, 56), 2.6, _fill(Colors.white.withValues(alpha: 0.85)));
  }

  void _receipt(Canvas c) {
    final paper = Path()..moveTo(54, 26)..lineTo(104, 26)..lineTo(104, 98);
    // Torn, zigzag bottom edge
    var x = 104.0;
    var up = true;
    while (x > 54) {
      x -= 6.25;
      paper.lineTo(x, up ? 94 : 98);
      up = !up;
    }
    paper
      ..lineTo(54, 98)
      ..close();
    c.drawPath(paper, _fill(_paper));
    c.drawPath(paper, _stroke(_line, 2));
    for (final (y, len) in const [(40.0, 34.0), (52.0, 26.0), (64.0, 30.0), (76.0, 18.0)]) {
      c.drawLine(Offset(64, y), Offset(64 + len, y), _stroke(_line, 4));
    }
    c.drawCircle(const Offset(104, 92), 13, _fill(AppTheme.success));
    final tick = Path()..moveTo(98, 92)..lineTo(102.5, 96.5)..lineTo(110, 88);
    c.drawPath(tick, _stroke(Colors.white, 3.2));
  }

  void _heart(Canvas c) {
    const cx = 80.0, cy = 66.0, w = 64.0, h = 60.0;
    final heart = Path()
      ..moveTo(cx, cy + h * 0.38)
      ..cubicTo(cx - w * 0.62, cy - h * 0.05, cx - w * 0.38, cy - h * 0.66, cx, cy - h * 0.3)
      ..cubicTo(cx + w * 0.38, cy - h * 0.66, cx + w * 0.62, cy - h * 0.05, cx, cy + h * 0.38)
      ..close();
    c.drawPath(heart, _fill(AppTheme.lingon));
    c.drawOval(const Rect.fromLTWH(60, 44, 12, 8), _fill(Colors.white.withValues(alpha: 0.5)));
    // Little sparkles around it
    for (final o in const [Offset(46, 40), Offset(116, 50), Offset(112, 90)]) {
      c.drawLine(o.translate(-4, 0), o.translate(4, 0), _stroke(AppTheme.sunshine, 2.4));
      c.drawLine(o.translate(0, -4), o.translate(0, 4), _stroke(AppTheme.sunshine, 2.4));
    }
  }

  void _magnifier(Canvas c) {
    c.drawLine(const Offset(90, 76), const Offset(108, 96), _stroke(dark ? const Color(0xFF8E6AA3) : AppTheme.primaryDark, 10));
    c.drawCircle(const Offset(74, 58), 24, _fill(_paper));
    c.drawCircle(const Offset(74, 58), 24, _stroke(_brand, 7));
    // A gentle glint and a few scattered dots: nothing here yet
    final glint = Path()
      ..moveTo(62, 52)
      ..arcToPoint(const Offset(70, 44), radius: const Radius.circular(12));
    c.drawPath(glint, _stroke(_line, 3.2));
    c.drawCircle(const Offset(68, 64), 2.6, _fill(_line));
    c.drawCircle(const Offset(76, 64), 2.6, _fill(_line));
    c.drawCircle(const Offset(84, 64), 2.6, _fill(_line));
  }

  void _cloud(Canvas c) {
    final cloud = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 72), radius: 16))
      ..addOval(Rect.fromCircle(center: const Offset(80, 60), radius: 21))
      ..addOval(Rect.fromCircle(center: const Offset(101, 72), radius: 15))
      ..addRRect(RRect.fromLTRBR(60, 68, 101, 88, const Radius.circular(4)));
    c.drawPath(cloud, _fill(_paper));
    c.drawLine(const Offset(56, 42), const Offset(106, 98), _stroke(dark ? const Color(0xFF121015) : AppTheme.birch, 9));
    c.drawLine(const Offset(56, 42), const Offset(106, 98), _stroke(AppTheme.lingon, 5));
  }

  void _shop(Canvas c) {
    c.drawRect(const Rect.fromLTRB(52, 58, 108, 102), _fill(_paper));
    c.drawRect(const Rect.fromLTRB(52, 58, 108, 102), _stroke(_line, 2));
    c.drawRRect(RRect.fromLTRBAndCorners(72, 74, 88, 102, topLeft: const Radius.circular(8), topRight: const Radius.circular(8)), _fill(AppTheme.primary));
    // Striped awning with a scalloped edge
    for (var i = 0; i < 4; i++) {
      final left = 46.0 + i * 17;
      final color = i.isEven ? AppTheme.sunshine : _paper;
      c.drawRect(Rect.fromLTRB(left, 42, left + 17, 56), _fill(color));
      c.drawCircle(Offset(left + 8.5, 56), 8.5, _fill(color));
    }
    c.drawRRect(RRect.fromLTRBR(44, 38, 116, 44, const Radius.circular(3)), _fill(dark ? const Color(0xFF8E6AA3) : AppTheme.primaryDark));
  }

  void _phone(Canvas c) {
    c.drawRRect(RRect.fromLTRBR(58, 22, 102, 104, const Radius.circular(12)), _fill(AppTheme.night));
    c.drawRRect(RRect.fromLTRBR(62, 28, 98, 98, const Radius.circular(8)), _fill(dark ? const Color(0xFF3A3242) : AppTheme.lilac));
    final play = Path()..moveTo(74, 52)..lineTo(90, 63)..lineTo(74, 74)..close();
    c.drawPath(play, _fill(AppTheme.primary));
    c.drawLine(const Offset(66, 92), const Offset(94, 92), _stroke(AppTheme.sunshine, 3));
  }

  void _bike(Canvas c) {
    final ink = dark ? AppTheme.textPrimary : AppTheme.ink;
    // Wheels
    c.drawCircle(const Offset(52, 88), 14, _stroke(ink, 4));
    c.drawCircle(const Offset(110, 88), 14, _stroke(ink, 4));
    // Frame, seat and handlebar
    final frame = Path()
      ..moveTo(52, 88)
      ..lineTo(72, 64)
      ..lineTo(98, 64)
      ..lineTo(110, 88)
      ..moveTo(72, 64)
      ..lineTo(84, 88)
      ..lineTo(98, 64)
      ..moveTo(98, 64)
      ..lineTo(102, 50)
      ..lineTo(110, 50);
    c.drawPath(frame, _stroke(AppTheme.lingon, 4.5));
    c.drawLine(const Offset(64, 60), const Offset(76, 60), _stroke(ink, 4.5));
    // Parcel on the rack, in Malvoya colours
    c.drawRRect(RRect.fromLTRBR(40, 40, 70, 60, const Radius.circular(4)), _fill(AppTheme.sunshine));
    c.drawLine(const Offset(55, 40), const Offset(55, 60), _stroke(AppTheme.primary, 3));
    // Speed lines
    for (final y in const [70.0, 78.0]) {
      c.drawLine(Offset(14, y), Offset(30, y), _stroke(_brand.withValues(alpha: 0.4), 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => old.kind != kind || old.dark != dark;
}
