import 'package:flutter/material.dart';
import '../core/strings.dart';

/// True when the phone asks for less motion (Android "Remove animations"). Decorative animation
/// is skipped then; state changes still happen instantly.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Shrinks its child slightly while a finger is on it, like a physical button. The tap itself is
/// handled by the child (or [onTap]); this only adds the feel.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    // The tap recogniser presses after a brief moment, so a scroll that starts on the tile never
    // shrinks it; a child with its own tap handler wins the tap and this just releases.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && !still ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A euro amount that counts smoothly to its new value when it changes (bag total, order total).
class AnimatedEuro extends StatelessWidget {
  final int cents;
  final TextStyle? style;
  final String prefix;
  const AnimatedEuro(this.cents, {super.key, this.style, this.prefix = ''});

  @override
  Widget build(BuildContext context) {
    final text = '$prefix${euro(context, cents)}';
    if (reduceMotion(context)) return Text(text, style: style);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: cents.toDouble()),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Text('$prefix${euro(context, value.round())}', style: style),
      ),
    );
  }
}

/// Gives its child a short, springy pop whenever [trigger] changes (e.g. the bag count).
class Bump extends StatefulWidget {
  final Object? trigger;
  final Widget child;
  const Bump({super.key, required this.trigger, required this.child});

  @override
  State<Bump> createState() => _BumpState();
}

class _BumpState extends State<Bump> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.22).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween<double>(begin: 1.22, end: 1).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant Bump old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}
