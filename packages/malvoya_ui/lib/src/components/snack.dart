import 'package:flutter/material.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// The tone of an [MSnack].
enum MSnackKind {
  /// Something worked ("Saved", "Order accepted").
  success,

  /// Neutral information ("Copied", "Added to your bag").
  info,

  /// Something failed. Shown longer.
  error,
}

/// Short feedback at the bottom of the screen: a floating dark pill with a coloured icon, an
/// optional action and a calm default duration (4 s, errors 6 s).
///
/// Screen readers announce it (SnackBar is a live region). Never use a snack for something the
/// user must act on; use a sheet or a dialog instead.
abstract final class MSnack {
  /// Shows [message], replacing a snack that is already visible.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context,
    String message, {
    MSnackKind kind = MSnackKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return null;
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(build(context, message, kind: kind, actionLabel: actionLabel, onAction: onAction, duration: duration));
  }

  /// [show] with [MSnackKind.success].
  static void success(BuildContext context, String message) => show(context, message, kind: MSnackKind.success);

  /// [show] with [MSnackKind.error].
  static void error(BuildContext context, String message) => show(context, message, kind: MSnackKind.error);

  /// The SnackBar itself (for a `ScaffoldMessengerState` kept outside the widget tree).
  static SnackBar build(
    BuildContext context,
    String message, {
    MSnackKind kind = MSnackKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final c = context.mColors;
    final (IconData icon, Color tint) = switch (kind) {
      MSnackKind.success => (Icons.check_circle_rounded, c.isDark ? c.success : const Color(0xFF7FD3A2)),
      MSnackKind.info => (Icons.info_outline_rounded, c.sunshine),
      MSnackKind.error => (Icons.error_outline_rounded, c.isDark ? c.danger : const Color(0xFFFF8A80)),
    };
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverseSurface,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.brMd),
      duration: duration ?? (kind == MSnackKind.error ? const Duration(seconds: 6) : const Duration(seconds: 4)),
      content: Row(children: [
        Icon(icon, color: tint, size: 22),
        const SizedBox(width: MSpace.md),
        Expanded(child: Text(message, style: MType.bodyM.copyWith(color: c.onInverseSurface, fontWeight: FontWeight.w600))),
      ]),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, textColor: c.sunshine, onPressed: onAction ?? () {}),
    );
  }
}
