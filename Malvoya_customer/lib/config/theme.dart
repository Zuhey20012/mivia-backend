import 'package:flutter/material.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// The customer app's theme: Birch Market in Malva, built by `packages/malvoya_ui`.
///
/// This class is a thin adapter so existing screens keep compiling: every colour comes from the
/// design-system palette ([MPalette], [MalvoyaBrand.malva]) and the context helpers read the
/// semantic tokens ([MalvoyaTokens]). New code reads `context.mColors`, [MSpace], [MRadius],
/// [MType] and [MMotion] directly.
class AppTheme {
  AppTheme._();

  // ── Type ─────────────────────────────────────────────────────────────────
  static const String bodyFont = MFonts.body;
  static const String displayFont = MFonts.display;

  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color primary = MPalette.malva;
  static const Color primaryDark = MPalette.malvaStrong;
  static const Color primaryLight = MPalette.lilac;
  /// Malva as drawn on dark surfaces.
  static const Color primaryOnDark = MPalette.malvaOnDark;
  static const Color emerald = MPalette.green;
  static const Color emeraldLight = MPalette.mint;
  static const Color success = MPalette.green;
  static const Color warning = MPalette.amber;
  static const Color danger = MPalette.red;
  static const Color dangerLight = MPalette.redLight;
  static const Color dangerInk = MPalette.redInk;
  static const Color lingon = MPalette.lingon;
  static const Color moss = MPalette.moss;

  // ── Market accents (the playful side) ────────────────────────────────────
  static const Color sunshine = MPalette.sunshine;
  static const Color sunshineLight = MPalette.sunshineLight;
  /// Text and icons on [sunshineLight].
  static const Color amberInk = MPalette.amberInk;
  static const Color lilac = MPalette.lilac;
  static const Color mint = MPalette.mint;
  static const Color peach = MPalette.peach;
  static const Color sand = MPalette.sand;
  static const Color clay = MPalette.clay;
  static const Color clayInk = MPalette.clayInk;

  // Dark-surface constants (screens use these on dark backgrounds)
  static const Color background = MPalette.night;
  static const Color surface = MPalette.nightSurface;
  static const Color textPrimary = MPalette.nightInk;
  static const Color textSecondary = MPalette.nightInkSecondary;
  static const Color divider = MPalette.nightRaised;

  // Light neutrals
  static const Color birch = MPalette.birch;
  static const Color night = MPalette.night;
  static const Color ink = MPalette.ink;
  static const Color inkSecondary = MPalette.inkSecondary;

  // ── Shape (the design-system radius scale) ───────────────────────────────
  static const double radiusSm = MRadius.sm;
  static const double radiusMd = MRadius.md;
  static const double radiusLg = MRadius.lg;

  /// Clean card: solid surface, hairline border, soft shadow (elevation e2).
  static BoxDecoration glossyCardDecoration({double radius = radiusLg, bool isDark = false}) => BoxDecoration(
        color: isDark ? MPalette.nightSurface : MPalette.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: isDark ? MPalette.nightLine : MPalette.line, width: 1),
        boxShadow: isDark ? const [] : softShadow,
      );

  static const Color primaryColor = primary;

  /// Text and icons on the Malva fill (and other strong fills), in light and dark mode.
  static const Color onBrand = MPalette.white;

  /// Text and icons over photos and video (always white).
  static const Color onMedia = MPalette.white;

  /// Dark overlays.
  static const Color scrim = MPalette.scrim;

  static List<BoxShadow> get softShadow => MElevation.e2.shadows();
  static List<BoxShadow> get cardShadow => softShadow;

  /// Headline style in the display face. Use for screen titles and section headings.
  static TextStyle display(BuildContext context, {double size = MTextSize.displayS, FontWeight weight = FontWeight.w800, Color? color}) =>
      TextStyle(
        fontFamily: displayFont,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        letterSpacing: -0.4,
        color: color ?? primaryText(context),
      );

  static ThemeData get lightTheme => buildMalvoyaTheme(brand: primary, brightness: Brightness.light);

  static ThemeData get darkTheme => buildMalvoyaTheme(brand: primary, brightness: Brightness.dark);

  /// Used when the phone asks for more contrast.
  static ThemeData get highContrastTheme => buildMalvoyaTheme(brand: primary, brightness: Brightness.light, highContrast: true);

  /// Warm, low-blue-light variant of the dark theme.
  static ThemeData get eyeComfortTheme => buildMalvoyaTheme(brand: primary, brightness: Brightness.dark, colors: MalvoyaColors.warmDark());

  // ── Context helpers (read the semantic tokens) ───────────────────────────
  static bool isDarkMode(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color scaffoldBackground(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  static Color cardBackground(BuildContext context) => context.mColors.surface;
  static Color cardBorder(BuildContext context) => context.mColors.outline;
  static Color primaryText(BuildContext context) => context.mColors.onSurface;
  static Color secondaryText(BuildContext context) => context.mColors.onSurfaceVariant;
  static Color inputBackground(BuildContext context) => context.mColors.surfaceVariant;
  static Color subtleDivider(BuildContext context) => isDarkMode(context) ? MPalette.nightSurfaceVariant : MPalette.line;
  /// The brand as it reads on the current background (Malva, or its light tint in dark mode).
  static Color brand(BuildContext context) => context.mColors.primary;

  /// A soft pastel tile colour that also works in dark mode (where it becomes a gentle tint of [hue]).
  static Color pastel(BuildContext context, Color light, Color hue) =>
      isDarkMode(context) ? hue.withValues(alpha: 0.22) : light;
}
