import 'package:flutter/material.dart';

/// Spacing on a 4-point grid. Use for padding, gaps and margins.
///
/// `xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · x3l 32 · x4l 40`
abstract final class MSpace {
  /// 4: icon-to-text, tight stacks.
  static const double xs = 4;

  /// 8: between related items.
  static const double sm = 8;

  /// 12: inside compact cards, list rows.
  static const double md = 12;

  /// 16: screen side padding, card padding.
  static const double lg = 16;

  /// 20: roomy side padding, sheet padding.
  static const double xl = 20;

  /// 24: between groups, sheet sides.
  static const double xxl = 24;

  /// 32: between sections, empty states.
  static const double x3l = 32;

  /// 40: hero spacing.
  static const double x4l = 40;

  /// The scale, smallest first.
  static const all = [xs, sm, md, lg, xl, xxl, x3l, x4l];
}

/// Corner radii: `xs 8 · sm 12 · md 16 · lg 24 · pill`.
abstract final class MRadius {
  /// 8: badges, small thumbnails, skeleton text.
  static const double xs = 8;

  /// 12: thumbnails, small tiles.
  static const double sm = 12;

  /// 16: inputs, list tiles, snackbars, info boxes.
  static const double md = 16;

  /// 24: cards, sheets, dialogs, hero images.
  static const double lg = 24;

  /// Fully rounded ends (buttons, chips): use with `StadiumBorder` or [pillRadius].
  static const double pill = 999;

  /// `BorderRadius.circular` of [xs].
  static const brXs = BorderRadius.all(Radius.circular(xs));

  /// `BorderRadius.circular` of [sm].
  static const brSm = BorderRadius.all(Radius.circular(sm));

  /// `BorderRadius.circular` of [md].
  static const brMd = BorderRadius.all(Radius.circular(md));

  /// `BorderRadius.circular` of [lg].
  static const brLg = BorderRadius.all(Radius.circular(lg));

  /// Pill-shaped ends.
  static const pillRadius = BorderRadius.all(Radius.circular(pill));

  /// Top corners of a bottom sheet.
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(lg));
}

/// Three elevation levels. Birch Market is flat: shadows are warm and soft, and dark mode uses
/// borders instead (only [e3] keeps a faint shadow there).
enum MElevation {
  /// Resting cards on the background (subtle lift).
  e1,

  /// Raised cards, product tiles, the selected item.
  e2,

  /// Floating: the tab bar, sticky bottom bars, snackbars.
  e3;

  /// The shadows for this level.
  List<BoxShadow> shadows({Brightness brightness = Brightness.light}) {
    final dark = brightness == Brightness.dark;
    const warm = Color(0xFF3A2A1A);
    return switch (this) {
      MElevation.e1 => dark ? const [] : [BoxShadow(color: warm.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      MElevation.e2 => dark ? const [] : [BoxShadow(color: warm.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6))],
      MElevation.e3 => [
          BoxShadow(color: (dark ? Colors.black : warm).withValues(alpha: dark ? 0.35 : 0.12), blurRadius: 28, offset: const Offset(0, 12)),
        ],
    };
  }
}

/// Motion: three durations and two curves. Animate state changes only, never for decoration
/// alone, and respect the phone's "remove animations" setting with [of] / [reduceMotion].
abstract final class MMotion {
  /// 150 ms: presses, toggles, small fades.
  static const fast = Duration(milliseconds: 150);

  /// 240 ms: most transitions (chips, expanding, snapping back).
  static const base = Duration(milliseconds: 240);

  /// 400 ms: larger moves (sheets, counting money, celebration).
  static const slow = Duration(milliseconds: 400);

  /// Standard easing (Material 3 "standard"): things that move within the screen.
  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Emphasised easing (Material 3 "emphasised decelerate"): things entering the screen.
  static const emphasised = Cubic(0.05, 0.7, 0.1, 1.0);

  /// [duration], or zero when the phone asks for less motion.
  static Duration of(BuildContext context, Duration duration) => reduceMotion(context) ? Duration.zero : duration;
}

/// True when the phone asks for less motion (Android "Remove animations", iOS "Reduce motion").
/// Decorative animation is skipped then; state changes still happen, instantly.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Minimum touch target (Material 3 / WCAG 2.5.8): every tappable thing is at least this big.
const double kMinTouchTarget = 48;
