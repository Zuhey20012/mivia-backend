import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// The three onboarding scenes.
enum OnboardingScene {
  /// A shop with a striped awning, with clothes and shades floating gently above it.
  shops,

  /// Stacked video cards with a play button, in parallax as the pages are swiped.
  drops,

  /// A bike riding a dashed loop around a home pin.
  delivery,
}

/// A small motion illustration for an onboarding page, drawn with CustomPaint in the pastel
/// palette (no image files). [loop] is the shared ambient loop (0–1, repeating); [pages] gives the
/// swipe position for the parallax. Both only repaint this drawing, never the page.
class OnboardingArt extends StatelessWidget {
  /// The scene for page [index].
  const OnboardingArt({super.key, required this.scene, required this.index, required this.loop, required this.pages});

  /// Which drawing.
  final OnboardingScene scene;

  /// This page's index (for the parallax).
  final int index;

  /// The ambient loop.
  final Animation<double> loop;

  /// The page view's controller.
  final PageController pages;

  @override
  Widget build(BuildContext context) {
    final t = context.mTokens;
    final palette = _ArtPalette(
      paper: t.colors.surface,
      line: t.colors.outline,
      ink: t.colors.onSurface,
      brand: t.colors.primary,
      brandSoft: t.colors.primarySoft,
      brandStrong: t.colors.primaryStrong,
      onBrand: t.colors.onPrimary,
      pastels: t.pastels,
      dark: t.isDark,
    );
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: _OnboardingPainter.w / _OnboardingPainter.h,
        child: RepaintBoundary(
          child: CustomPaint(painter: _OnboardingPainter(scene, index, loop, pages, palette)),
        ),
      ),
    );
  }
}

@immutable
class _ArtPalette {
  const _ArtPalette({
    required this.paper,
    required this.line,
    required this.ink,
    required this.brand,
    required this.brandSoft,
    required this.brandStrong,
    required this.onBrand,
    required this.pastels,
    required this.dark,
  });
  final Color paper, line, ink, brand, brandSoft, brandStrong, onBrand;
  final MalvoyaPastels pastels;
  final bool dark;

  @override
  bool operator ==(Object other) =>
      other is _ArtPalette && other.paper == paper && other.brand == brand && other.ink == ink && other.dark == dark && other.line == line;

  @override
  int get hashCode => Object.hash(paper, brand, ink, dark, line);
}

class _OnboardingPainter extends CustomPainter {
  _OnboardingPainter(this.scene, this.index, this.loop, this.pages, this.p) : super(repaint: Listenable.merge([loop, pages]));

  final OnboardingScene scene;
  final int index;
  final Animation<double> loop;
  final PageController pages;
  final _ArtPalette p;

  // Drawn on a 300 × 210 canvas and scaled to fit
  static const w = 300.0;
  static const h = 210.0;
  static const _tau = math.pi * 2;

  /// -1 … 1: how far this page is from the centre of the screen while swiping.
  double get _swipe {
    if (!pages.hasClients || !pages.position.hasContentDimensions) return 0;
    return ((pages.page ?? index.toDouble()) - index).clamp(-1.0, 1.0);
  }

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double width) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// A gentle float: [amp] px, with its own [phase] so items do not move in step.
  double _bob(double amp, double phase) => math.sin(loop.value * _tau * 3 + phase) * amp;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / w);
    // The whole scene drifts a little against the swipe (the text moves at full speed)
    canvas.translate(-_swipe * 26, 0);
    // Ground and sun, as in the empty-state drawings
    canvas.drawOval(const Rect.fromLTWH(30, 176, 240, 26), _fill(p.dark ? p.brand.withValues(alpha: 0.18) : p.brandSoft));
    canvas.drawCircle(Offset(36, 30 + _bob(2, 1.2)), 13, _fill(MPalette.sunshine.withValues(alpha: p.dark ? 0.8 : 1)));
    canvas.drawCircle(const Offset(272, 150), 3, _fill(p.brand.withValues(alpha: 0.3)));
    canvas.drawCircle(const Offset(20, 120), 2.5, _fill(MPalette.clayInk.withValues(alpha: 0.35)));
    switch (scene) {
      case OnboardingScene.shops:
        _shops(canvas);
      case OnboardingScene.drops:
        _drops(canvas);
      case OnboardingScene.delivery:
        _delivery(canvas);
    }
    canvas.restore();
  }

  // ── 1. Local shops: an awning and floating finds ─────────────────────────
  void _shops(Canvas canvas) {
    // Shop front
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(74, 96, 152, 86), const Radius.circular(10));
    canvas.drawRRect(body, _fill(p.paper));
    canvas.drawRRect(body, _stroke(p.line, 2));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(86, 114, 38, 30), const Radius.circular(6)), _fill(p.pastels.mint));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(176, 114, 38, 30), const Radius.circular(6)), _fill(p.pastels.peach));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(132, 124, 36, 58), const Radius.circular(6)), _fill(p.brandSoft));
    canvas.drawCircle(const Offset(160, 154), 2.5, _fill(p.brand));

    // Striped, scalloped awning
    const left = 64.0, right = 236.0, top = 72.0, bottom = 100.0;
    const stripes = 6;
    const sw = (right - left) / stripes;
    for (var i = 0; i < stripes; i++) {
      final x = left + i * sw;
      final color = i.isEven ? p.brand : p.paper;
      final stripe = Path()
        ..moveTo(x, top)
        ..lineTo(x + sw, top)
        ..lineTo(x + sw, bottom)
        ..arcToPoint(Offset(x, bottom), radius: const Radius.circular(sw / 2))
        ..close();
      canvas.drawPath(stripe, _fill(color));
    }
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(left - 6, top - 10, right - left + 12, 12), const Radius.circular(6)), _fill(p.brandStrong));

    // Finds floating above it
    _dress(canvas, Offset(98, 38 + _bob(4, 0)));
    _swatches(canvas, Offset(150, 34 + _bob(3.5, 1.6)));
    _lipstick(canvas, Offset(204, 36 + _bob(4, 3.1)));
    _bag(canvas, Offset(262, 84 + _bob(3, 4.4)));
  }

  void _dress(Canvas canvas, Offset c) {
    final dress = Path()
      ..moveTo(c.dx - 7, c.dy - 16)
      ..lineTo(c.dx + 7, c.dy - 16)
      ..lineTo(c.dx + 9, c.dy - 4)
      ..lineTo(c.dx + 17, c.dy + 16)
      ..quadraticBezierTo(c.dx, c.dy + 21, c.dx - 17, c.dy + 16)
      ..lineTo(c.dx - 9, c.dy - 4)
      ..close();
    canvas.drawPath(dress, _fill(MPalette.lingon.withValues(alpha: 0.85)));
    canvas.drawLine(Offset(c.dx - 9, c.dy - 4), Offset(c.dx + 9, c.dy - 4), _stroke(p.paper.withValues(alpha: 0.8), 2));
  }

  /// Three shade circles like the shade picker, the middle one chosen (a ring with a gap).
  void _swatches(Canvas canvas, Offset c) {
    final shades = [MPalette.peach, MPalette.clayInk, MPalette.malvaOnDark];
    for (var i = 0; i < 3; i++) {
      final o = Offset(c.dx + (i - 1) * 22, c.dy);
      canvas.drawCircle(o, 8, _fill(shades[i]));
      canvas.drawCircle(o, 8, _stroke(p.line, 1));
      if (i == 1) canvas.drawCircle(o, 11.5, _stroke(p.brand, 2));
    }
  }

  void _lipstick(Canvas canvas, Offset c) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.35);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-7, 0, 14, 18), const Radius.circular(3)), _fill(p.ink.withValues(alpha: 0.8)));
    canvas.drawRect(const Rect.fromLTWH(-5, -6, 10, 7), _fill(MPalette.sunshine));
    final bullet = Path()
      ..moveTo(-4.5, -6)
      ..lineTo(-4.5, -16)
      ..lineTo(4.5, -21)
      ..lineTo(4.5, -6)
      ..close();
    canvas.drawPath(bullet, _fill(MPalette.lingon));
    canvas.restore();
  }

  void _bag(Canvas canvas, Offset c) {
    canvas.drawArc(Rect.fromCenter(center: c.translate(0, -10), width: 16, height: 16), math.pi, math.pi, false, _stroke(p.brandStrong, 2.5));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, 2), width: 26, height: 22), const Radius.circular(5)), _fill(MPalette.sunshine));
  }

  // ── 2. Drops: stacked video cards in parallax ────────────────────────────
  void _drops(Canvas canvas) {
    final s = _swipe;
    const center = Offset(150, 100);
    // Cards further back move more against the swipe: depth
    _card(canvas, center.translate(-50 + s * 34, 10), -0.17, p.pastels.lilac, front: false);
    _card(canvas, center.translate(50 - s * 22, 10), 0.17, p.pastels.peach, front: false);
    _card(canvas, center.translate(-s * 10, _bob(2.5, 0)), 0, p.brand, front: true);
    // Little likes rising from the front card
    for (var i = 0; i < 3; i++) {
      final t = (loop.value * 3 + i / 3) % 1;
      final o = Offset(196 + math.sin((t + i) * _tau) * 5 - s * 10, 150 - t * 70);
      canvas.drawCircle(o, 4 * (1 - t * 0.4), _fill((i.isEven ? MPalette.sunshine : MPalette.like).withValues(alpha: 1 - t)));
    }
  }

  void _card(Canvas canvas, Offset c, double angle, Color fill, {required bool front}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 86, height: 136), const Radius.circular(16));
    canvas.drawRRect(rect.shift(const Offset(0, 4)), _fill(p.ink.withValues(alpha: 0.06)));
    canvas.drawRRect(rect, _fill(fill));
    if (!front) canvas.drawRRect(rect, _stroke(p.dark ? p.line : MPalette.clay, 1.5));
    if (front) {
      // A "photo": a sunny dot and a hill, then the play button and the progress line
      canvas.save();
      canvas.clipRRect(rect);
      canvas.drawCircle(const Offset(22, -40), 12, _fill(MPalette.sunshine.withValues(alpha: 0.9)));
      canvas.drawOval(const Rect.fromLTWH(-70, 24, 140, 80), _fill(p.onBrand.withValues(alpha: 0.14)));
      canvas.restore();
      canvas.drawCircle(Offset.zero, 18, _fill(p.onBrand.withValues(alpha: 0.95)));
      final play = Path()
        ..moveTo(-5, -8)
        ..lineTo(9, 0)
        ..lineTo(-5, 8)
        ..close();
      canvas.drawPath(play, _fill(p.brand));
      canvas.drawLine(const Offset(-30, 54), const Offset(30, 54), _stroke(p.onBrand.withValues(alpha: 0.35), 3));
      canvas.drawLine(const Offset(-30, 54), Offset(-30 + 60 * ((loop.value * 2) % 1), 54), _stroke(p.onBrand, 3));
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-30, 40, 44, 6), const Radius.circular(3)), _fill(p.paper.withValues(alpha: 0.7)));
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-30, 50, 30, 6), const Radius.circular(3)), _fill(p.paper.withValues(alpha: 0.5)));
    }
    canvas.restore();
  }

  // ── 3. Delivery or pickup: a bike circling a home pin ────────────────────
  static const _loopCenter = Offset(150, 118);
  static const _rx = 112.0, _ry = 52.0;
  PathMetric? _dashMetric;

  void _delivery(Canvas canvas) {
    // The dashed route
    _dashMetric ??= (Path()..addOval(Rect.fromCenter(center: _loopCenter, width: _rx * 2, height: _ry * 2))).computeMetrics().first;
    final m = _dashMetric!;
    final dash = _stroke(p.dark ? p.line : MPalette.clayInk.withValues(alpha: 0.4), 3);
    for (double d = 0; d < m.length; d += 15) {
      canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), dash);
    }
    final a = loop.value * _tau;
    final bike = _loopCenter + Offset(math.cos(a) * _rx, math.sin(a) * _ry);
    final behind = math.sin(a) < 0; // the far side of the loop
    final facingLeft = math.sin(a) > 0; // moving right on the far side, left on the near side
    if (behind) _bike(canvas, bike, 0.82, facingLeft);
    _pin(canvas);
    if (!behind) _bike(canvas, bike, 1, facingLeft);
  }

  void _pin(Canvas canvas) {
    const top = Offset(150, 74);
    canvas.drawOval(Rect.fromCenter(center: const Offset(150, 136), width: 34, height: 8), _fill(p.ink.withValues(alpha: 0.10)));
    final pin = Path()
      ..moveTo(150, 134)
      ..cubicTo(132, 112, 122, 98, 122, 82)
      ..arcToPoint(const Offset(178, 82), radius: const Radius.circular(28))
      ..cubicTo(178, 98, 168, 112, 150, 134)
      ..close();
    canvas.drawPath(pin, _fill(p.brand));
    // A little house inside
    final house = Path()
      ..moveTo(top.dx - 12, top.dy + 6)
      ..lineTo(top.dx, top.dy - 6)
      ..lineTo(top.dx + 12, top.dy + 6)
      ..lineTo(top.dx + 12, top.dy + 18)
      ..lineTo(top.dx - 12, top.dy + 18)
      ..close();
    canvas.drawPath(house, _fill(p.onBrand));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(top.dx - 3.5, top.dy + 8, 7, 10), const Radius.circular(2)), _fill(MPalette.sunshine));
  }

  void _bike(Canvas canvas, Offset at, double scale, bool facingLeft) {
    canvas.save();
    canvas.translate(at.dx, at.dy - 12 * scale);
    canvas.scale(facingLeft ? -scale : scale, scale);
    final frame = _stroke(p.ink.withValues(alpha: 0.85), 2.2);
    final spin = loop.value * _tau * 8;
    for (final x in const [-11.0, 11.0]) {
      canvas.drawCircle(Offset(x, 6), 7.5, _stroke(p.ink.withValues(alpha: 0.85), 2.2));
      canvas.drawLine(Offset(x, 6), Offset(x + math.cos(spin) * 7, 6 + math.sin(spin) * 7), _stroke(p.ink.withValues(alpha: 0.4), 1.2));
    }
    final path = Path()
      ..moveTo(-11, 6)
      ..lineTo(-3, -4)
      ..lineTo(8, -4)
      ..lineTo(11, 6)
      ..moveTo(-3, -4)
      ..lineTo(1, 6)
      ..lineTo(8, -4)
      ..moveTo(8, -4)
      ..lineTo(6, -10)
      ..lineTo(10, -10);
    canvas.drawPath(path, frame);
    // Rider and the parcel on the rack
    canvas.drawLine(const Offset(-2, -6), const Offset(2, -16), _stroke(MPalette.lingon, 3.2));
    canvas.drawCircle(const Offset(3, -20), 3.6, _fill(MPalette.sunshine));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-17, -12, 11, 9), const Radius.circular(2)), _fill(MPalette.clayInk));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OnboardingPainter old) => old.scene != scene || old.index != index || old.p != p || old.loop != loop || old.pages != pages;
}
