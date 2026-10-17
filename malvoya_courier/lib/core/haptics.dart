import 'package:flutter/services.dart';

/// One place for the app's haptics, so the same kind of moment always feels the same.
/// The phone's own vibration setting still applies.
class Haptics {
  Haptics._();

  /// Choosing something: a tab, a toggle, opening a sheet.
  static void select() => HapticFeedback.selectionClick();

  /// A normal confirmed action.
  static void tap() => HapticFeedback.mediumImpact();

  /// A step that cannot be undone went through (picked up, delivered).
  static void success() => HapticFeedback.heavyImpact();

  /// Refused or needs attention.
  static void warning() => HapticFeedback.heavyImpact();

  /// A new job offer: long–short–long, distinct from every other buzz in the app and easy to feel
  /// in a pocket or a phone holder.
  static Future<void> offer() async {
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await HapticFeedback.vibrate();
  }
}
