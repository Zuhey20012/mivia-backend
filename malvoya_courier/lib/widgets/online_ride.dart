import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// The go-online moment: when [online] turns on, the courier's vehicle rides across the online bar
/// while the road lines under it rush past, then the bar settles. One animation, played only on
/// the switch to online (never while simply online), and not at all with "Remove animations".
class OnlineRide extends StatefulWidget {
  const OnlineRide({
    super.key,
    required this.online,
    required this.icon,
    required this.child,
    required this.road,
    required this.rider,
    required this.riderIcon,
  });

  /// The courier is online.
  final bool online;

  /// The courier's vehicle.
  final IconData icon;

  /// The bar's content (dimmed while the vehicle passes).
  final Widget child;

  /// Colour of the road lines.
  final Color road;

  /// The vehicle's disc.
  final Color rider;

  /// The vehicle icon's colour.
  final Color riderIcon;

  /// Length of the ride.
  static const duration = Duration(milliseconds: 1100);

  @override
  State<OnlineRide> createState() => _OnlineRideState();
}

class _OnlineRideState extends State<OnlineRide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: OnlineRide.duration);
  late final Animation<double> _dim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 0.2), weight: 20),
    TweenSequenceItem(tween: ConstantTween<double>(0.2), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 0.2, end: 1), weight: 25),
  ]).animate(_c);

  @override
  void didUpdateWidget(OnlineRide old) {
    super.didUpdateWidget(old);
    if (!old.online && widget.online && !reduceMotion(context)) _c.forward(from: 0);
    if (!widget.online && _c.isAnimating) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth.isFinite ? box.maxWidth : 0.0;
      return Stack(clipBehavior: Clip.none, children: [
        FadeTransition(opacity: _dim, child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  if (!_c.isAnimating) return const SizedBox.shrink();
                  final t = _c.value;
                  final x = Curves.easeInOutCubic.transform(t) * math.max(0, width - 40);
                  final opacity = (t < 0.1 ? t / 0.1 : t > 0.85 ? (1 - t) / 0.15 : 1.0).clamp(0.0, 1.0);
                  return Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: CustomPaint(painter: _RoadPainter(t, widget.road))),
                    Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: opacity,
                        child: Center(
                          child: Transform.translate(
                            // A small bounce, as if over the cobbles
                            offset: Offset(0, -math.sin(t * math.pi * 10).abs() * 2),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: widget.rider, shape: BoxShape.circle),
                              child: Icon(widget.icon, size: 22, color: widget.riderIcon),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

/// Dashed road lines that rush to the left while the vehicle rides right.
class _RoadPainter extends CustomPainter {
  _RoadPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = math.sin(t * math.pi);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45 * strength)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dash = 14.0, gap = 12.0;
    final shift = (t * 260) % (dash + gap);
    for (final (y, offset) in [(size.height * 0.5 - 12, 0.0), (size.height * 0.5 + 12, 11.0)]) {
      for (double x = -shift - offset; x < size.width; x += dash + gap) {
        if (x + dash <= 0) continue;
        canvas.drawLine(Offset(math.max(0, x), y), Offset(math.min(size.width, x + dash), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.t != t || old.color != color;
}
