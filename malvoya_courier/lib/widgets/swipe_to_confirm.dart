import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/haptics.dart';
import '../core/strings.dart';

/// A full-width "slide to confirm" bar for steps that cannot be undone (picked up, delivered).
/// A pocket tap or a glove brushing the screen does not trigger it; a deliberate slide past 80 %
/// does. With TalkBack/VoiceOver on, or "remove animations", it is a plain button with the same
/// label, because sliding is hard with a screen reader.
class SwipeToConfirm extends StatefulWidget {
  final String label;
  final IconData icon;
  final Future<void> Function() onConfirmed;
  final bool busy;
  final bool enabled;
  final Color color;
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.arrow_forward_rounded,
    this.busy = false,
    this.enabled = true,
    this.color = AppTheme.primary,
  });

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> with SingleTickerProviderStateMixin {
  static const _height = 64.0;
  static const _knob = 56.0;
  double _drag = 0; // 0..1
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _drag = _from * (1 - _back.value)));
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool get _active => widget.enabled && !widget.busy;

  void _reset() {
    _from = _drag;
    _armed = false;
    _back.forward(from: 0);
  }

  Future<void> _fire() async {
    Haptics.success();
    setState(() => _drag = 1);
    await widget.onConfirmed();
    if (mounted) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Screen readers and switch access: a normal button
    if (media.accessibleNavigation) {
      return SizedBox(
        width: double.infinity,
        height: _height,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: widget.color, minimumSize: const Size(64, _height)),
          onPressed: _active ? widget.onConfirmed : null,
          icon: widget.busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Icon(widget.icon),
          label: Text(widget.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );
    }
    final color = _active ? widget.color : AppTheme.textSecondary;
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.label,
      hint: tr(context, 'Slide to the right to confirm', 'Liu\'uta oikealle vahvistaaksesi'),
      onTap: _active ? widget.onConfirmed : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final track = c.maxWidth - _knob - 8;
        return GestureDetector(
          onHorizontalDragStart: _active
              ? (_) {
                  _back.stop();
                  Haptics.select();
                }
              : null,
          onHorizontalDragUpdate: _active
              ? (d) {
                  setState(() => _drag = (_drag + d.delta.dx / track).clamp(0.0, 1.0));
                  final armed = _drag > 0.8;
                  if (armed != _armed) {
                    _armed = armed;
                    if (armed) Haptics.tap();
                  }
                }
              : null,
          onHorizontalDragEnd: _active ? (_) => _drag > 0.8 ? _fire() : _reset() : null,
          child: Container(
            height: _height,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(_height / 2), border: Border.all(color: color, width: 2)),
            child: Stack(children: [
              // Fill behind the knob
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4 + _knob + track * _drag,
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_height / 2))),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: _knob + 8, right: 16),
                  child: Opacity(
                    opacity: (1 - _drag * 1.4).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800, height: 1.15),
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
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                  child: widget.busy
                      ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Icon(_drag > 0.8 ? Icons.check_rounded : widget.icon, color: Colors.white, size: 28),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
