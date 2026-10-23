import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// A short "thank you" right after paying: a sunny check pops in with a ring of confetti dots,
/// then everything fades away by itself (about 1.8 s; a tap closes it sooner). With "reduce
/// motion" on it shows still and briefly.
class PaidMoment extends StatefulWidget {
  final VoidCallback onDone;
  const PaidMoment({super.key, required this.onDone});

  @override
  State<PaidMoment> createState() => _PaidMomentState();
}

class _PaidMomentState extends State<PaidMoment> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.value = 0.6;
      Future.delayed(const Duration(milliseconds: 1100), _close);
    } else {
      _c.forward().whenComplete(_close);
    }
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.scaffoldBackground(context);
    return Semantics(
      liveRegion: true,
      label: tr(context, 'Thanks for your order', 'Kiitos tilauksestasi'),
      child: GestureDetector(
        onTap: _close,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            // In 0–0.25, hold, out after 0.8
            final fade = t < 0.8 ? 1.0 : 1 - (t - 0.8) / 0.2;
            final pop = Curves.elasticOut.transform((t / 0.45).clamp(0.0, 1.0));
            final burst = Curves.easeOutCubic.transform(((t - 0.08) / 0.5).clamp(0.0, 1.0));
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Container(
                color: bg.withValues(alpha: 0.94),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(
                        painter: _ConfettiPainter(burst),
                        child: Center(
                          child: Transform.scale(
                            scale: 0.4 + 0.6 * pop,
                            child: Container(
                              width: 104,
                              height: 104,
                              decoration: const BoxDecoration(color: AppTheme.sunshine, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 62, color: AppTheme.ink),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: MSpace.sm),
                    Text(tr(context, 'Thanks for your order', 'Kiitos tilauksestasi'), style: AppTheme.display(context, size: 26)),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: MSpace.x3l),
                      child: Text(
                        tr(context, 'You can follow every step here.', 'Voit seurata jokaista vaihetta täällä.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.secondaryText(context), fontSize: MTextSize.bodyL),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  _ConfettiPainter(this.t);

  static const _colors = [AppTheme.primary, AppTheme.sunshine, AppTheme.lingon, AppTheme.success, AppTheme.primaryOnDark];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final center = size.center(Offset.zero);
    const count = 14;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + 0.3;
      final distance = 50 + 46 * t + (i.isEven ? 8 : 0);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final paint = Paint()..color = _colors[i % _colors.length].withValues(alpha: (1 - t * 0.6).clamp(0.0, 1.0));
      final r = (i % 3 == 0 ? 5.0 : 3.6) * (1 - t * 0.3);
      if (i % 2 == 0) {
        canvas.drawCircle(p, r, paint);
      } else {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(angle + t * 2);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: r * 2.6, height: r * 1.2), const Radius.circular(2)), paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
