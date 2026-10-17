import 'package:flutter/services.dart';

/// One place for the app's haptics, so the same kind of moment always feels the same.
///
/// The phone's own "touch feedback" setting still applies: Android and iOS ignore these when the
/// user has switched vibration off.
class Haptics {
  Haptics._();

  /// Choosing something: a chip, a tab, a toggle, opening a sheet.
  static void select() => HapticFeedback.selectionClick();

  /// A normal confirmed action: saved, accepted, marked ready.
  static void tap() => HapticFeedback.mediumImpact();

  /// Something finished well (an order accepted, a product saved).
  static void success() => HapticFeedback.mediumImpact();

  /// Something needs attention or was refused.
  static void warning() => HapticFeedback.heavyImpact();

  /// A new order came in: three strong pulses, felt even with the phone on the counter.
  static Future<void> newOrder() async {
    for (var i = 0; i < 3; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.heavyImpact();
    }
  }
}
