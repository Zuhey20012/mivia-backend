import 'dart:ui' show PathMetric, lerpDouble;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import 'brand_mark.dart';

enum _Phase { idle, pulling, refreshing, hiding }

/// Pull to refresh with the Thread M: as the list is pulled, the M draws itself in the app colour;
/// once far enough, the sunshine dot appears; while refreshing, a stretch of thread keeps running
/// along the M. A drop-in replacement for [RefreshIndicator] (same gesture, same `onRefresh`).
///
/// With "Remove animations" the M is shown whole and still while refreshing.
class MRefreshIndicator extends StatefulWidget {
  /// Wraps the scrollable [child].
  const MRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.backgroundColor,
    this.displacement = 40,
    this.edgeOffset = 0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.semanticsLabel,
  });

  /// Called when the list was pulled far enough; the M runs until the future completes.
  final RefreshCallback onRefresh;

  /// The scrollable (a `ListView`, `CustomScrollView`, …; keep it always scrollable).
  final Widget child;

  /// The thread's colour (default: the app colour).
  final Color? color;

  /// The disc behind the M (default: the surface colour).
  final Color? backgroundColor;

  /// Where the disc settles while refreshing, below [edgeOffset].
  final double displacement;

  /// Space above the disc (e.g. a pinned header).
  final double edgeOffset;

  /// Which scroll notifications count (as in [RefreshIndicator]).
  final ScrollNotificationPredicate notificationPredicate;

  /// Whether the pull must start at the top edge (as in [RefreshIndicator]).
  final RefreshIndicatorTriggerMode triggerMode;

  /// Read by screen readers while refreshing (default: Material's "Refresh").
  final String? semanticsLabel;

  /// The disc's diameter.
  static const discSize = 40.0;

  @override
  State<MRefreshIndicator> createState() => _MRefreshIndicatorState();
}

class _MRefreshIndicatorState extends State<MRefreshIndicator> with SingleTickerProviderStateMixin {
  // One controller: the thread running along the M while refreshing. The pull itself follows the
  // finger (a notifier, no animation).
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  final _pull = ValueNotifier<double>(0);
  final _phase = ValueNotifier<_Phase>(_Phase.idle);
  bool _armed = false;
  double _drag = 0;

  @override
  void dispose() {
    _spin.dispose();
    _pull.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    switch (status) {
      case RefreshIndicatorStatus.drag:
        _drag = 0;
        _armed = false;
        _pull.value = 0;
        _phase.value = _Phase.pulling;
      case RefreshIndicatorStatus.armed:
        _armed = true;
        _pull.value = 1;
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        _pull.value = 1;
        _phase.value = _Phase.refreshing;
        if (!reduceMotion(context)) _spin.repeat();
      case RefreshIndicatorStatus.done:
      case RefreshIndicatorStatus.canceled:
        _spin.stop();
        // "Remove animations": gone at once, no fade
        _phase.value = reduceMotion(context) ? _Phase.idle : _Phase.hiding;
      case null:
        _spin.stop();
        _phase.value = _Phase.idle;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (!widget.notificationPredicate(n) || _phase.value != _Phase.pulling || _armed) return false;
    final down = n.metrics.axisDirection == AxisDirection.down;
    if (n is ScrollUpdateNotification && n.scrollDelta != null) {
      _drag += down ? -n.scrollDelta! : n.scrollDelta!;
    } else if (n is OverscrollNotification) {
      _drag += down ? -n.overscroll : n.overscroll;
    } else {
      return false;
    }
    // The same distance the Material indicator arms at: a quarter of the viewport
    _pull.value = (_drag / (n.metrics.viewportDimension * 0.25)).clamp(0.0, 1.0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final color = widget.color ?? c.primary;
    final disc = widget.backgroundColor ?? c.surface;
    final still = reduceMotion(context);
    return Stack(fit: StackFit.passthrough, children: [
      RefreshIndicator.noSpinner(
        onRefresh: widget.onRefresh,
        onStatusChange: _onStatus,
        notificationPredicate: widget.notificationPredicate,
        triggerMode: widget.triggerMode,
        child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: widget.edgeOffset,
        child: IgnorePointer(
          child: ValueListenableBuilder<_Phase>(
            valueListenable: _phase,
            builder: (context, phase, _) {
              if (phase == _Phase.idle) return const SizedBox.shrink();
              final hiding = phase == _Phase.hiding;
              return AnimatedOpacity(
                opacity: hiding ? 0 : 1,
                duration: MMotion.of(context, MMotion.fast),
                onEnd: () {
                  // After the frame: onEnd can come while this builder is building
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _phase.value == _Phase.hiding) _phase.value = _Phase.idle;
                  });
                },
                child: AnimatedScale(
                  scale: hiding ? 0.6 : 1,
                  duration: MMotion.of(context, MMotion.fast),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _pull,
                    builder: (context, pull, child) {
                      // Comes down with the finger, then rests at the displacement
                      final top = lerpDouble(-MRefreshIndicator.discSize, widget.displacement, phase == _Phase.pulling ? Curves.easeOut.transform(pull) : 1)!;
                      return Padding(padding: EdgeInsets.only(top: top.clamp(0, double.infinity)), child: Opacity(opacity: pull.clamp(0.0, 1.0), child: child));
                    },
                    child: Center(
                      child: Semantics(
                        liveRegion: phase == _Phase.refreshing,
                        label: phase == _Phase.refreshing ? (widget.semanticsLabel ?? MaterialLocalizations.of(context).refreshIndicatorSemanticLabel) : null,
                        child: Container(
                          width: MRefreshIndicator.discSize,
                          height: MRefreshIndicator.discSize,
                          decoration: BoxDecoration(
                            color: disc,
                            shape: BoxShape.circle,
                            border: c.isDark ? Border.all(color: c.outline) : null,
                            boxShadow: context.mTokens.shadow(MElevation.e2),
                          ),
                          alignment: Alignment.center,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: const Size.square(24),
                              painter: RefreshMarkPainter(
                                pull: _pull,
                                spin: _spin,
                                refreshing: phase != _Phase.pulling,
                                still: still,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

/// The refresh indicator's M: drawn up to [pull] while pulling, then a running stretch of thread
/// driven by [spin] (or the whole M when [still]).
class RefreshMarkPainter extends CustomPainter {
  /// Repaints with [pull] and [spin].
  RefreshMarkPainter({required this.pull, required this.spin, required this.refreshing, required this.still, required this.color})
      : super(repaint: Listenable.merge([pull, spin]));

  /// How far the list has been pulled (0–1; 1 = it refreshes on release).
  final ValueListenable<double> pull;

  /// The running thread (0–1, repeating).
  final Animation<double> spin;

  /// True from the release until the indicator is gone.
  final bool refreshing;

  /// "Remove animations": no running thread.
  final bool still;

  /// The thread's colour.
  final Color color;

  PathMetric? _metric;
  double _size = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    if (_metric == null || _size != w) {
      _metric = threadMPath(w).computeMetrics().first;
      _size = w;
    }
    final m = _metric!;
    final len = m.length;
    final stroke = threadMStroke(w, color)..strokeWidth = threadMStrokeWidth(w) * 1.25;
    // The whole M, faint, as a track
    canvas.drawPath(m.extractPath(0, len), threadMStroke(w, color.withValues(alpha: 0.16))..strokeWidth = stroke.strokeWidth);
    final p = pull.value;
    if (!refreshing || still) {
      final upTo = refreshing ? 1.0 : p;
      if (upTo > 0) canvas.drawPath(m.extractPath(0, len * upTo), stroke);
    } else {
      // A third of the thread runs through the M, start to end, again and again
      final seg = len * 0.34;
      final head = spin.value * (len + seg);
      canvas.drawPath(m.extractPath((head - seg).clamp(0, len), head.clamp(0, len)), stroke);
    }
    if (p >= 1 || refreshing) {
      canvas.drawCircle(threadMDotCenter(w), threadMDotRadius(w) * 1.25, Paint()..color = MPalette.sunshine);
    }
  }

  @override
  bool shouldRepaint(RefreshMarkPainter old) =>
      old.refreshing != refreshing || old.still != still || old.color != color || old.pull != pull || old.spin != spin;
}
