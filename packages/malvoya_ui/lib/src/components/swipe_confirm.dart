import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// A full-width "slide to confirm" bar for steps that cannot be undone (picked up, delivered).
///
/// A pocket tap or a glove brushing the screen does not trigger it; a deliberate slide past
/// [threshold] does. With TalkBack/VoiceOver or switch access it becomes a plain button with the
/// same label, because sliding is hard with a screen reader. While [busy] the knob shows a spinner.
class MSwipeConfirm extends StatefulWidget {
  /// Creates the bar.
  const MSwipeConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.arrow_forward_rounded,
    this.busy = false,
    this.enabled = true,
    this.color,
  });

  /// How far (0–1 of the track) the knob must travel.
  static const threshold = 0.8;

  /// What happens ("Slide to confirm pickup").
  final String label;

  /// Runs after a full slide (or a tap on the accessible button).
  final Future<void> Function() onConfirmed;

  /// The knob's icon.
  final IconData icon;

  /// Shows a spinner and ignores slides.
  final bool busy;

  /// False dims the bar and ignores slides.
  final bool enabled;

  /// Bar colour (default: the brand).
  final Color? color;

  @override
  State<MSwipeConfirm> createState() => _MSwipeConfirmState();
}

class _MSwipeConfirmState extends State<MSwipeConfirm> with SingleTickerProviderStateMixin {
  static const _height = 64.0;
  static const _knob = 56.0;
  double _drag = 0; // 0..1
  bool _armed = false;
  double _from = 0;
  late final AnimationController _back;

  @override
  void initState() {
    super.initState();
    // Created here, not lazily: a lazy controller would first be created in dispose()
    _back = AnimationController(vsync: this, duration: MMotion.base)..addListener(() => setState(() => _drag = _from * (1 - _back.value)));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool get _active => widget.enabled && !widget.busy;

  void _reset() {
    _from = _drag;
    _armed = false;
    if (reduceMotion(context)) {
      setState(() => _drag = 0);
    } else {
      _back.forward(from: 0);
    }
  }

  Future<void> _fire() async {
    Haptics.strong();
    setState(() => _drag = 1);
    await widget.onConfirmed();
    if (mounted) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final brand = widget.color ?? c.primary;
    final onBrand = widget.color == null ? c.onPrimary : Colors.white;
    final media = MediaQuery.of(context);
    if (media.accessibleNavigation) {
      return SizedBox(
        width: double.infinity,
        height: _height,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: brand, foregroundColor: onBrand, minimumSize: const Size(64, _height)),
          onPressed: _active ? widget.onConfirmed : null,
          icon: widget.busy
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: onBrand))
              : Icon(widget.icon),
          label: Text(widget.label, style: MType.bodyL.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );
    }
    final color = _active ? brand : c.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.label,
      hint: tr(context, 'Slide to the right to confirm', 'Liu\'uta oikealle vahvistaaksesi'),
      onTap: _active ? widget.onConfirmed : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final track = box.maxWidth - _knob - 8;
        return GestureDetector(
          onHorizontalDragStart: _active
              ? (_) {
                  _back.stop();
                  Haptics.selection();
                }
              : null,
          onHorizontalDragUpdate: _active
              ? (d) {
                  setState(() => _drag = (_drag + d.delta.dx / track).clamp(0.0, 1.0));
                  final armed = _drag > MSwipeConfirm.threshold;
                  if (armed != _armed) {
                    _armed = armed;
                    if (armed) Haptics.medium();
                  }
                }
              : null,
          onHorizontalDragEnd: _active ? (_) => _drag > MSwipeConfirm.threshold ? _fire() : _reset() : null,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(_height / 2),
              border: Border.all(color: color, width: 2),
            ),
            child: Stack(children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4 + _knob + track * _drag,
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_height / 2))),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: _knob + MSpace.sm, right: MSpace.lg),
                  child: Opacity(
                    opacity: (1 - _drag * 1.4).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: MType.bodyL.copyWith(color: color, fontSize: 17, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 2 + track * _drag,
                top: (_height - _knob) / 2 - 2,
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: c.surface, width: 3)),
                  child: widget.busy
                      ? Padding(padding: const EdgeInsets.all(MSpace.lg), child: CircularProgressIndicator(strokeWidth: 2.5, color: onBrand))
                      : Icon(_drag > MSwipeConfirm.threshold ? Icons.check_rounded : widget.icon, color: onBrand, size: 28),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
