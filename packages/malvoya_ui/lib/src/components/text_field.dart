import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// A filled text field in the Birch Market style (sand fill, 16 px corners, brand focus ring).
///
/// States: default, focused, filled, disabled ([enabled] false), error ([errorText]: a red border
/// and the message under the field, announced by screen readers). [obscure] fields get a 48 dp
/// show/hide button. The label floats above the text, so it stays readable at large text sizes.
class MTextField extends StatefulWidget {
  /// Creates a field.
  const MTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
  });

  /// The text controller.
  final TextEditingController? controller;

  /// Floating label ("Email").
  final String? label;

  /// Placeholder shown while empty.
  final String? hint;

  /// A short help line under the field.
  final String? helper;

  /// Shows the error state with this message.
  final String? errorText;

  /// Leading icon.
  final IconData? prefixIcon;

  /// Trailing widget (ignored for [obscure] fields, which show the eye button).
  final Widget? suffix;

  /// A password field with a show/hide button.
  final bool obscure;

  /// False shows the disabled state.
  final bool enabled;

  /// Selectable but not editable (pickers).
  final bool readOnly;

  /// Focus when shown.
  final bool autofocus;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Capitalisation.
  final TextCapitalization textCapitalization;

  /// Autofill hints (email, password, …).
  final Iterable<String>? autofillHints;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Lines (1 for a single-line field).
  final int? maxLines;

  /// Minimum lines for multi-line fields.
  final int? minLines;

  /// Maximum length, with a counter.
  final int? maxLength;

  /// Text changed.
  final ValueChanged<String>? onChanged;

  /// Keyboard action pressed.
  final ValueChanged<String>? onSubmitted;

  /// Tapped (for read-only pickers).
  final VoidCallback? onTap;

  /// Focus node.
  final FocusNode? focusNode;

  @override
  State<MTextField> createState() => _MTextFieldState();
}

class _MTextFieldState extends State<MTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final error = widget.errorText;
    Widget? suffix = widget.suffix;
    if (widget.obscure) {
      suffix = IconButton(
        tooltip: _hidden ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
        constraints: const BoxConstraints(minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: c.onSurfaceVariant),
        onPressed: () => setState(() => _hidden = !_hidden),
      );
    }
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      obscureText: widget.obscure && _hidden,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: MType.bodyL.copyWith(color: widget.enabled ? c.onSurface : c.onSurfaceVariant, height: 1.3),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 3,
        errorText: error,
        errorMaxLines: 3,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, color: error != null ? c.danger : c.onSurfaceVariant),
        suffixIcon: suffix,
        fillColor: widget.enabled ? null : c.surfaceVariant.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: MSpace.lg),
      ),
    );
  }
}
