import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// "Huomenta" / "Good morning", "Päivää" / "Good afternoon" or "Iltaa" / "Good evening" for the
/// phone's time ([now] for tests). [formal] gives "Hyvää huomenta" and so on (the store app).
///
/// Morning is 5–11, afternoon 11–18, evening the rest.
String mGreeting(BuildContext context, {DateTime? now, bool formal = false}) {
  final h = (now ?? DateTime.now()).hour;
  final part = h >= 5 && h < 11
      ? 0
      : h >= 11 && h < 18
          ? 1
          : 2;
  return switch (part) {
    0 => tr(context, 'Good morning', formal ? 'Hyvää huomenta' : 'Huomenta'),
    1 => tr(context, 'Good afternoon', formal ? 'Hyvää päivää' : 'Päivää'),
    _ => tr(context, 'Good evening', formal ? 'Hyvää iltaa' : 'Iltaa'),
  };
}

/// The first name of a full name ("Aino Virtanen" → "Aino"), or null when there is none.
String? firstNameOf(String? name) {
  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? null : first;
}

/// Remembers which "once per session" animations have played (they reset when the app restarts).
abstract final class MOnce {
  static final _played = <String>{};

  /// True the first time [key] is asked for in this session, false afterwards.
  static bool take(String key) => _played.add(key);

  /// True when [key] has played.
  static bool played(String key) => _played.contains(key);

  /// Lets tests play everything again.
  @visibleForTesting
  static void debugReset() => _played.clear();
}

/// Fades its child in while it rises a few pixels: a soft entrance for a greeting or a header.
///
/// With [onceKey] it plays only the first time in a session (later it simply shows). Nothing moves
/// with "Remove animations".
class MRiseIn extends StatefulWidget {
  /// Rises [child] in after [delay].
  const MRiseIn({super.key, required this.child, this.onceKey, this.delay = Duration.zero, this.duration = MMotion.slow, this.offset = 12});

  /// The content.
  final Widget child;

  /// Play only once per session under this key.
  final String? onceKey;

  /// Wait before starting.
  final Duration delay;

  /// Length of the entrance.
  final Duration duration;

  /// How far it rises, in logical pixels.
  final double offset;

  @override
  State<MRiseIn> createState() => _MRiseInState();
}

class _MRiseInState extends State<MRiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration + widget.delay);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delay.inMicroseconds / (_c.duration!.inMicroseconds == 0 ? 1 : _c.duration!.inMicroseconds), 1, curve: MMotion.emphasised),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final key = widget.onceKey;
    final fresh = key == null || MOnce.take(key);
    if (!fresh || reduceMotion(context)) {
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
        ),
      );
}

/// Staggers the entrance of the [MStaggerItem]s below it with one animation: each item fades and
/// rises a little after the one before. With [onceKey] it plays once per session.
class MStaggerIn extends StatefulWidget {
  /// Staggers the items in [child].
  const MStaggerIn({super.key, required this.child, this.onceKey, this.step = const Duration(milliseconds: 45), this.itemDuration = MMotion.slow, this.count = 9});

  /// Contains the [MStaggerItem]s.
  final Widget child;

  /// Play only once per session under this key.
  final String? onceKey;

  /// Delay between two items.
  final Duration step;

  /// Length of each item's entrance.
  final Duration itemDuration;

  /// How many items take part (later indexes start with the last).
  final int count;

  @override
  State<MStaggerIn> createState() => _MStaggerInState();
}

class _MStaggerInState extends State<MStaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.itemDuration + widget.step * (widget.count - 1));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final key = widget.onceKey;
    if ((key != null && !MOnce.take(key)) || reduceMotion(context)) {
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
  Widget build(BuildContext context) => _StaggerScope(animation: _c, step: widget.step, count: widget.count, child: widget.child);
}

class _StaggerScope extends InheritedWidget {
  const _StaggerScope({required this.animation, required this.step, required this.count, required super.child});
  final AnimationController animation;
  final Duration step;
  final int count;

  @override
  bool updateShouldNotify(_StaggerScope old) => old.animation != animation || old.step != step || old.count != count;
}

/// One item of an [MStaggerIn] (shows as is without one).
class MStaggerItem extends StatelessWidget {
  /// Item number [index] (0 first).
  const MStaggerItem({super.key, required this.index, required this.child});

  /// Position in the stagger.
  final int index;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_StaggerScope>();
    if (scope == null) return child;
    final total = scope.animation.duration!.inMicroseconds;
    final start = (scope.step.inMicroseconds * index.clamp(0, scope.count - 1)) / total;
    final end = (start + (total - scope.step.inMicroseconds * (scope.count - 1)) / total).clamp(0.0, 1.0);
    final t = CurvedAnimation(parent: scope.animation, curve: Interval(start.clamp(0.0, 1.0), end, curve: MMotion.emphasised));
    return FadeTransition(
      opacity: t,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(t), child: child),
    );
  }
}

/// A status pill with a dot ("Open" / "Avoinna"). While [live] the dot breathes softly, a slow
/// halo that says "this is on right now"; otherwise it is still.
class MStatusPill extends StatefulWidget {
  /// A pill reading [label] in [color] (default: success).
  const MStatusPill({super.key, required this.label, this.live = false, this.color, this.background});

  /// The status text.
  final String label;

  /// Breathes while true.
  final bool live;

  /// Dot and text colour.
  final Color? color;

  /// Pill fill (default: a soft tint of [color]).
  final Color? background;

  @override
  State<MStatusPill> createState() => _MStatusPillState();
}

class _MStatusPillState extends State<MStatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  void _sync() {
    final breathe = widget.live && !reduceMotion(context);
    if (breathe && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!breathe && _breath.isAnimating) {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MStatusPill old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final fg = widget.color ?? c.onSuccessSoft;
    final bg = widget.background ?? (widget.color == null ? c.successSoft : fg.withValues(alpha: 0.12));
    return Semantics(
      label: widget.label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(MSpace.sm + 2, MSpace.xs + 1, MSpace.md, MSpace.xs + 1),
        decoration: BoxDecoration(color: bg, borderRadius: MRadius.pillRadius),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 16,
            height: 16,
            child: RepaintBoundary(child: CustomPaint(painter: _BreathPainter(_breath, fg, widget.live))),
          ),
          const SizedBox(width: MSpace.xs + 2),
          Text(widget.label, style: MType.label.copyWith(color: fg)),
        ]),
      ),
    );
  }
}

class _BreathPainter extends CustomPainter {
  _BreathPainter(this.t, this.color, this.live) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final v = Curves.easeInOut.transform(t.value);
    if (live) {
      canvas.drawCircle(center, 4.5 + 3.5 * v, Paint()..color = color.withValues(alpha: 0.28 * (1 - v) + 0.06));
    }
    canvas.drawCircle(center, 4, Paint()..color = live ? color : color.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_BreathPainter old) => old.color != color || old.live != live || old.t != t;
}
