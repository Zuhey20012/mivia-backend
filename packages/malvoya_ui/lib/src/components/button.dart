import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// What a button does, from most to least prominent.
enum MButtonVariant {
  /// The one main action of a screen or sheet (brand fill).
  primary,

  /// A supporting action next to a primary one (soft brand fill).
  secondary,

  /// A neutral alternative (outlined).
  outline,

  /// Destructive: delete, cancel an order, decline (red fill).
  danger,

  /// The quietest action, e.g. "Skip" or a link inside a card.
  text,
}

/// Button heights: 40 (always inside a 48 dp touch target), 54 (the theme default) and 60.
enum MButtonSize {
  /// 40 visible, 48 touch target.
  sm,

  /// 54: the standard button.
  md,

  /// 60: the main call to action at the bottom of a screen.
  lg,
}

/// The Birch Market button: pill-shaped, sized to its content unless [expand] is set.
///
/// States: default, pressed (a gentle 0.97 press scale, still when the phone reduces motion),
/// disabled ([onPressed] null), loading ([loading]: a spinner replaces the label, the button keeps
/// its size and colour and cannot be pressed again) and focused (keyboard). Labels wrap to two
/// lines at large text sizes rather than being cut.
class MButton extends StatefulWidget {
  /// Creates a button.
  const MButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = MButtonVariant.primary,
    this.size = MButtonSize.md,
    this.icon,
    this.trailingIcon = false,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  });

  /// The text on the button (a verb: "Pay", "Accept order").
  final String label;

  /// Called on tap. Null disables the button.
  final VoidCallback? onPressed;

  /// Prominence.
  final MButtonVariant variant;

  /// Height.
  final MButtonSize size;

  /// Optional icon before the label (after it with [trailingIcon]).
  final IconData? icon;

  /// Put [icon] after the label (for "Next →").
  final bool trailingIcon;

  /// Shows a spinner and ignores taps while an action runs.
  final bool loading;

  /// Fill the available width (full-width bottom buttons).
  final bool expand;

  /// Read by screen readers instead of [label].
  final String? semanticLabel;

  @override
  State<MButton> createState() => _MButtonState();
}

class _MButtonState extends State<MButton> {
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(() {
      final pressed = _states.value.contains(WidgetState.pressed);
      if (pressed != _pressed && mounted) setState(() => _pressed = pressed);
    });
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  double get _height => switch (widget.size) {
        MButtonSize.sm => 40,
        MButtonSize.md => 54,
        MButtonSize.lg => 60,
      };

  TextStyle get _text => switch (widget.size) {
        MButtonSize.sm => MType.bodyM.copyWith(fontWeight: FontWeight.w700, height: 1.2),
        MButtonSize.md => MType.bodyL.copyWith(fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.1),
        MButtonSize.lg => MType.bodyL.copyWith(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.1),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final enabled = widget.onPressed != null && !widget.loading;
    final (Color bg, Color fg) = switch (widget.variant) {
      MButtonVariant.primary => (c.primary, c.onPrimary),
      MButtonVariant.secondary => (c.primarySoft, c.onPrimarySoft),
      MButtonVariant.outline => (Colors.transparent, c.onSurface),
      MButtonVariant.danger => (c.danger, c.onDanger),
      MButtonVariant.text => (Colors.transparent, c.primary),
    };
    final spinnerSize = widget.size == MButtonSize.sm ? 18.0 : 22.0;
    final iconSize = widget.size == MButtonSize.sm ? 18.0 : 20.0;

    final labelText = Text(
      widget.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    Widget content = widget.icon == null
        ? labelText
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.trailingIcon) ...[Icon(widget.icon, size: iconSize), const SizedBox(width: MSpace.sm)],
              Flexible(child: labelText),
              if (widget.trailingIcon) ...[const SizedBox(width: MSpace.sm), Icon(widget.icon, size: iconSize)],
            ],
          );
    if (widget.loading) {
      // The label stays (invisible) so the button keeps its width
      content = Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0, child: content),
        SizedBox(width: spinnerSize, height: spinnerSize, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg)),
      ]);
    }

    final disabledBg = widget.loading ? bg : (bg == Colors.transparent ? bg : c.onSurface.withValues(alpha: 0.12));
    final disabledFg = widget.loading ? fg : c.onSurface.withValues(alpha: 0.38);
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(widget.variant == MButtonVariant.text ? kMinTouchTarget : 64, _height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: widget.size == MButtonSize.sm ? MSpace.lg : MSpace.xxl, vertical: MSpace.sm)),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: WidgetStatePropertyAll(_text),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? disabledBg : bg),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? disabledFg : fg),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return fg.withValues(alpha: 0.12);
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return fg.withValues(alpha: 0.08);
        return null;
      }),
      side: widget.variant == MButtonVariant.outline
          ? WidgetStateProperty.resolveWith((s) => BorderSide(color: s.contains(WidgetState.disabled) && !widget.loading ? c.outline : c.outlineStrong.withValues(alpha: 0.6), width: 1.5))
          : null,
    );

    final button = TextButton(
      onPressed: enabled ? widget.onPressed : null,
      statesController: _states,
      style: style,
      child: content,
    );

    // One clean node for screen readers: "Pay, button" / "Pay, working, button, disabled"
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? widget.label,
      value: widget.loading ? tr(context, 'Working', 'Käsitellään') : null,
      enabled: enabled,
      button: true,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed && !reduceMotion(context) ? 0.97 : 1,
        duration: MMotion.fast,
        curve: MMotion.standard,
        child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
      ),
    );
  }
}
