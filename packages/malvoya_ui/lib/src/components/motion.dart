import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';

/// Shrinks its child slightly while a finger is on it, like a physical button. The tap itself is
/// handled by the child (or [onTap]); this only adds the feel.
class Pressable extends StatefulWidget {
  /// Wraps [child].
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  /// The pressable content.
  final Widget child;

  /// Optional tap handler (otherwise the child handles the tap).
  final VoidCallback? onTap;

  /// Scale while pressed.
  final double scale;

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
        duration: _down ? const Duration(milliseconds: 90) : MMotion.fast,
        curve: MMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// A euro amount that counts smoothly to its new value when it changes (bag total, order total).
class AnimatedEuro extends StatelessWidget {
  /// Shows [cents] as euros, counting to new values.
  const AnimatedEuro(this.cents, {super.key, this.style, this.prefix = ''});

  /// The amount.
  final int cents;

  /// Text style.
  final TextStyle? style;

  /// Text before the amount.
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final text = '$prefix${euro(context, cents)}';
    if (reduceMotion(context)) return Text(text, style: style);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: cents.toDouble()),
        duration: MMotion.slow,
        curve: MMotion.standard,
        builder: (context, value, _) => Text('$prefix${euro(context, value.round())}', style: style),
      ),
    );
  }
}

/// Gives its child a short, springy pop whenever [trigger] changes (e.g. the bag count).
class Bump extends StatefulWidget {
  /// Pops [child] when [trigger] changes.
  const Bump({super.key, required this.trigger, required this.child});

  /// Any value; a change starts the pop.
  final Object? trigger;

  /// The content.
  final Widget child;

  @override
  State<Bump> createState() => _BumpState();
}

class _BumpState extends State<Bump> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: MMotion.slow);
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
