import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// Malvoya Courier theme: Birch Market in Lingon, built by `packages/malvoya_ui`.
///
/// A thin adapter so existing screens keep compiling: every value comes from the design system
/// ([MPalette], [MRadius], [MType]); the ThemeData is [buildMalvoyaTheme] in the "tool" style
/// (start-aligned titles, quieter body text, tinted chips). New code reads `context.mColors`,
/// [MSpace], [MRadius], [MType] and [MMotion] directly.
class AppTheme {
  AppTheme._();

  // ── Type ─────────────────────────────────────────────────────────────────
  static const String bodyFont = MFonts.body;
  static const String displayFont = MFonts.display;

  // ── Brand: Lingon ────────────────────────────────────────────────
  static const Color primary = MPalette.lingon;
  static const Color primaryDark = MPalette.lingonStrong;
  static const Color primaryLight = MPalette.peach;
  static const Color accent = MPalette.malva;
  static const Color success = MPalette.green;
  /// Darker green for white text on green (≈6.5:1 contrast), e.g. the online bar.
  static const Color successDark = MPalette.greenDark;
  static const Color warning = MPalette.amber;
  /// Status red, for problems and destructive actions.
  static const Color danger = MPalette.red;
  static const Color dangerLight = MPalette.redLight;
  /// Red text on [dangerLight].
  static const Color dangerInk = MPalette.redInk;
  static const Color primaryColor = primary;

  // ── Market accents ───────────────────────────────────────────────────────
  static const Color sunshine = MPalette.sunshine;
  static const Color sunshineLight = MPalette.sunshineLight;
  /// Text and icons on [sunshineLight].
  static const Color amberInk = MPalette.amberInk;
  static const Color malva = MPalette.malva;
  static const Color lingon = MPalette.lingon;
  static const Color lilac = MPalette.lilac;
  static const Color peach = MPalette.peach;
  static const Color mint = MPalette.mint;
  static const Color sand = MPalette.sand;

  // ── Neutrals ─────────────────────────────────────────────────────────────
  static const Color background = MPalette.birch;
  static const Color surface = MPalette.white;
  /// Text and icons on [primary] (and the other strong fills).
  static const Color onPrimary = MPalette.white;
  /// Dark overlays.
  static const Color scrim = MPalette.scrim;
  static const Color textPrimary = MPalette.ink;
  static const Color textSecondary = MPalette.inkSecondary;
  static const Color divider = MPalette.line;

  // ── Shape (the design-system radius scale) ───────────────────────────────
  static const double radiusMd = MRadius.md;
  static const double radiusLg = MRadius.lg;

  /// Headline style in the display face.
  static TextStyle display({double size = MTextSize.displayS, FontWeight weight = FontWeight.w800, Color color = textPrimary}) =>
      TextStyle(fontFamily: displayFont, fontSize: size, fontWeight: weight, height: 1.1, letterSpacing: -0.4, color: color);

  static ThemeData get lightTheme => buildMalvoyaTheme(brand: primary, brightness: Brightness.light, style: MalvoyaThemeStyle.tool);

  /// Used when the phone asks for more contrast (Android "high contrast text", iOS "Increase
  /// contrast"): darker secondary text and lines, and visible field borders.
  static ThemeData get highContrastTheme =>
      buildMalvoyaTheme(brand: primary, brightness: Brightness.light, style: MalvoyaThemeStyle.tool, highContrast: true);
}
