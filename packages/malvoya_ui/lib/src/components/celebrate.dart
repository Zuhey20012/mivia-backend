import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';
import 'brand_mark.dart';

/// A check that draws itself: the circle fills with a soft pop, then the tick is stroked and a
/// ring of sunshine dots bursts out. For "Order accepted" and "Delivered".
///
/// One animation of [duration]; with "Remove animations" the finished check shows at once.
class MSuccessCheck extends StatefulWidget {
  /// A check [size] wide.
  const MSuccessCheck({super.key, this.size = 72, this.color, this.duration = const Duration(milliseconds: 750), this.burst = true});

  /// Diameter of the circle (the burst reaches a little beyond it).
  final double size;

  /// Circle colour (default: success).
  final Color? color;

  /// Length of the animation.
  final Duration duration;

  /// Sunshine dots bursting out as the tick lands.
  final bool burst;

  @override
  State<MSuccessCheck> createState() => _MSuccessCheckState();
}

class _MSuccessCheckState extends State<MSuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final extent = widget.size * (widget.burst ? 1.6 : 1);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: extent,
        child: RepaintBoundary(
          child: CustomPaint(painter: SuccessCheckPainter(_c, circle: widget.color ?? c.success, tick: c.onSuccess, burst: widget.burst ? MPalette.sunshine : null)),
        ),
      ),
    );
  }
}

/// Paints [MSuccessCheck] at [t] (0–1).
class SuccessCheckPainter extends CustomPainter {
  /// Repaints with [t].
  SuccessCheckPainter(this.t, {required this.circle, required this.tick, this.burst}) : super(repaint: t);

  /// The animation.
  final Animation<double> t;

  /// Circle fill.
  final Color circle;

  /// Tick colour.
  final Color tick;

  /// Burst dot colour, or null for none.
  final Color? burst;

  static const _pop = Interval(0, 0.45, curve: Curves.easeOutBack);
  static const _draw = Interval(0.35, 0.8, curve: Curves.easeOutCubic);
  static const _burst = Interval(0.6, 1, curve: Curves.easeOut);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / (burst == null ? 2 : 3.2);
    final pop = _pop.transform(v);
    canvas.drawCircle(center, r * pop, Paint()..color = circle);

    final d = _draw.transform(v);
    if (d > 0) {
      final path = Path()
        ..moveTo(center.dx - r * 0.42, center.dy + r * 0.02)
        ..lineTo(center.dx - r * 0.12, center.dy + r * 0.32)
        ..lineTo(center.dx + r * 0.46, center.dy - r * 0.30);
      final PathMetric m = path.computeMetrics().first;
      canvas.drawPath(
        m.extractPath(0, m.length * d),
        Paint()
          ..color = tick
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final b = burst;
    if (b != null && v > _burst.begin && v < 1) {
      final p = _burst.transform(v);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + math.pi / 8;
        final dist = r * (1.1 + 0.45 * p);
        canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * dist, r * 0.09 * (1 - p), Paint()..color = (i.isEven ? b : circle).withValues(alpha: 1 - p));
      }
    }
  }

  @override
  bool shouldRepaint(SuccessCheckPainter old) => old.t != t || old.circle != circle || old.tick != tick || old.burst != burst;
}

/// Shows a check with [label] over the screen for a moment ("Order accepted" / "Tilaus hyväksytty"),
/// then fades it away. Taps go through to the screen. The label is also announced to screen readers.
void showMSuccessCheck(BuildContext context, String label, {Duration hold = const Duration(milliseconds: 1300)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  Haptics.success();
  SemanticsService.announce(label, Directionality.of(context));
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _SuccessToast(label: label, hold: hold, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _SuccessToast extends StatefulWidget {
  const _SuccessToast({required this.label, required this.hold, required this.onDone});
  final String label;
  final Duration hold;
  final VoidCallback onDone;

  @override
  State<_SuccessToast> createState() => _SuccessToastState();
}

class _SuccessToastState extends State<_SuccessToast> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _timer = Timer(widget.hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: MMotion.of(context, MMotion.base),
          onEnd: () {
            if (!_visible) widget.onDone();
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.lg, MSpace.xxl, MSpace.xl),
              decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brLg, boxShadow: context.mTokens.shadow(MElevation.e3)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const MSuccessCheck(size: 64),
                Text(widget.label, textAlign: TextAlign.center, style: MType.title.copyWith(color: c.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A once-in-a-lifetime moment (the store's first sale): a dialog with confetti in the pastel
/// palette and sunshine, the Thread M, [title] and [message]. Confetti only falls once; with
/// "Remove animations" it is left out.
Future<void> showMCelebration(BuildContext context, {required String title, required String message, String? action}) {
  Haptics.success();
  return showDialog<void>(
    context: context,
    builder: (ctx) => _Celebration(title: title, message: message, action: action ?? tr(ctx, 'Thanks!', 'Kiitos!')),
  );
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.title, required this.message, required this.action});
  final String title, message, action;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mTokens;
    final c = t.colors;
    final p = t.pastels;
    return Dialog(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.brLg),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: ConfettiPainter(_c, colors: [MPalette.sunshine, c.primary, p.lilac, p.mint, p.peach, MPalette.sunshine])),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.x3l, MSpace.xxl, MSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BrandTile(size: 72, background: c.primary, foreground: c.onPrimary),
            const SizedBox(height: MSpace.xl),
            Semantics(header: true, child: Text(widget.title, textAlign: TextAlign.center, style: MType.displayS.copyWith(color: c.onSurface))),
            const SizedBox(height: MSpace.sm),
            Text(widget.message, textAlign: TextAlign.center, style: MType.bodyL.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: MSpace.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(widget.action)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Confetti for [showMCelebration]: soft rounded bits and dots that fall and sway once over [t].
class ConfettiPainter extends CustomPainter {
  /// Repaints with [t].
  ConfettiPainter(this.t, {required this.colors}) : super(repaint: t);

  /// The fall (0–1, once).
  final Animation<double> t;

  /// Colours the bits rotate through.
  final List<Color> colors;

  static const _count = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1) return;
    // A fixed seed: the same pleasant arrangement every time, no randomness per frame
    final rnd = math.Random(7);
    for (var i = 0; i < _count; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final delay = rnd.nextDouble() * 0.35;
      final speed = 0.7 + rnd.nextDouble() * 0.6;
      final sway = 6 + rnd.nextDouble() * 14;
      final spin = rnd.nextDouble() * math.pi * 2;
      final local = ((v - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -12 + local * speed * (size.height + 24);
      final x = x0 + math.sin(local * math.pi * 3 + spin) * sway;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      final color = colors[i % colors.length];
      final paint = Paint()..color = color.withValues(alpha: color.a * fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin + local * math.pi * 2);
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3.5, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -2.5, 10, 5), const Radius.circular(2.5)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t || old.colors != colors;
}
