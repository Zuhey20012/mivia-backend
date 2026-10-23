import 'package:flutter/services.dart';

/// One kind of buzz, for [Haptics.sequence].
enum HapticKind {
  /// A tick, as when choosing something.
  selection,

  /// A light tap.
  light,

  /// A normal tap.
  medium,

  /// A strong thump.
  heavy,

  /// The phone's default vibration (longer than an impact).
  vibrate,
}

/// One vocabulary for touch feedback, so the same kind of moment feels the same in every app.
///
/// The phone's own "touch feedback" setting still applies: Android and iOS ignore these when the
/// user switched vibration off.
class Haptics {
  Haptics._();

  /// Choosing something: a chip, a tab, a toggle, opening a sheet.
  static void selection() => HapticFeedback.selectionClick();

  /// Small positive moments: adding to the bag, liking, following.
  static void light() => HapticFeedback.lightImpact();

  /// A normal confirmed action: paying, placing, sending, saving, accepting.
  static void medium() => HapticFeedback.mediumImpact();

  /// Something finished well (an order accepted, a product saved).
  static void success() => HapticFeedback.mediumImpact();

  /// A step that cannot be undone went through (picked up, delivered).
  static void strong() => HapticFeedback.heavyImpact();

  /// Something was refused or needs attention.
  static void warning() => HapticFeedback.heavyImpact();

  /// Several buzzes with a pause before each one after the first, e.g. an alarm that is easy to
  /// feel in a pocket: `sequence([(HapticKind.heavy, Duration.zero), (HapticKind.heavy, ms180)])`.
  static Future<void> sequence(List<(HapticKind, Duration)> steps) async {
    for (final (kind, pause) in steps) {
      if (pause > Duration.zero) await Future<void>.delayed(pause);
      await switch (kind) {
        HapticKind.selection => HapticFeedback.selectionClick(),
        HapticKind.light => HapticFeedback.lightImpact(),
        HapticKind.medium => HapticFeedback.mediumImpact(),
        HapticKind.heavy => HapticFeedback.heavyImpact(),
        HapticKind.vibrate => HapticFeedback.vibrate(),
      };
    }
  }
}
