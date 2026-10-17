import 'package:flutter/services.dart';

/// One vocabulary for touch feedback, so the app feels the same everywhere:
/// - [selection]: chips, tabs, toggles, opening things
/// - [light]: adding to the bag, liking, following, favourites
/// - [medium]: confirmations (paying, placing, sending)
/// - [warning]: something went wrong (payment declined, order failed)
class Haptics {
  const Haptics._();

  static void selection() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void warning() => HapticFeedback.heavyImpact();
}
