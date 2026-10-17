import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

/// One bar: its label under the axis and the amount in cents.
typedef EarningsBar = ({String label, int cents});

/// A plain bar chart of earnings (pay per hour today, or per day this week). Bars with nothing are
/// drawn as a thin baseline, so a quiet day reads as quiet and not as missing data. The highest bar
/// is labelled with its amount; [summary] is read out by screen readers instead of the drawing.
class EarningsChart extends StatelessWidget {
  final List<EarningsBar> bars;
  final String Function(int cents) money;
  final String summary;
  final int? highlight;
  const EarningsChart({super.key, required this.bars, required this.money, required this.summary, this.highlight});

  @override
  Widget build(BuildContext context) {
    final contrast = MediaQuery.of(context).highContrast;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: SizedBox(
        height: 150 + 14 * (scale - 1) * 2,
        child: CustomPaint(
          painter: _BarsPainter(bars: bars, money: money, highlight: highlight, contrast: contrast, textScale: scale),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<EarningsBar> bars;
  final String Function(int cents) money;
  final int? highlight;
  final bool contrast;
  final double textScale;
  _BarsPainter({required this.bars, required this.money, this.highlight, required this.contrast, required this.textScale});

  TextPainter _text(String s, {double size = 11, FontWeight weight = FontWeight.w600, Color color = AppTheme.textSecondary}) =>
      TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: size * textScale, fontWeight: weight, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final labelH = 16.0 * textScale;
    final topPad = 18.0 * textScale;
    final chartH = size.height - labelH - topPad;
    final maxCents = bars.map((b) => b.cents).fold<int>(0, math.max);
    final slot = size.width / bars.length;
    final barW = math.min(slot * 0.62, 34.0);
    final base = topPad + chartH;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()
      ..color = contrast ? AppTheme.textPrimary : AppTheme.divider
      ..strokeWidth = 1);
    // Every label when they fit, otherwise every other one (hours of a day)
    final probe = _text(bars.map((b) => b.label).reduce((a, b) => a.length >= b.length ? a : b));
    final every = probe.width + 4 > slot ? (probe.width / slot).ceil() + 1 : 1;
    var peakIndex = -1;
    for (var i = 0; i < bars.length; i++) {
      if (maxCents > 0 && bars[i].cents == maxCents && peakIndex < 0) peakIndex = i;
    }
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final x = slot * i + (slot - barW) / 2;
      final h = maxCents == 0 ? 0.0 : chartH * b.cents / maxCents;
      final on = i == highlight;
      final color = b.cents == 0 ? (contrast ? AppTheme.textSecondary : AppTheme.divider) : (on ? AppTheme.primary : AppTheme.primary.withValues(alpha: contrast ? 1 : 0.55));
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, base - math.max(h, 2), barW, math.max(h, 2)),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      if (i % every == 0 || on) {
        final t = _text(b.label, weight: on ? FontWeight.w800 : FontWeight.w600, color: on ? AppTheme.textPrimary : AppTheme.textSecondary);
        t.paint(canvas, Offset(slot * i + (slot - t.width) / 2, base + 3));
      }
      if (i == peakIndex) {
        final t = _text(money(b.cents), size: 11, weight: FontWeight.w800, color: AppTheme.textPrimary);
        final tx = (slot * i + (slot - t.width) / 2).clamp(0.0, size.width - t.width);
        t.paint(canvas, Offset(tx, base - h - t.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.bars != bars || old.highlight != highlight || old.contrast != contrast || old.textScale != textScale;
}
