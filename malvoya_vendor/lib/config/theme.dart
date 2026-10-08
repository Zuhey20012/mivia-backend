import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Malvoya Store theme: "Birch Market" in Moss green.
/// Same family as the customer app: calm Birch neutrals, one brand colour, a sunny yellow for
/// highlights, pill-shaped buttons and the rounded Bricolage display face for headings.
class AppTheme {
  // ── Type ─────────────────────────────────────────────────────────────────
  static const String bodyFont = 'HankenGrotesk';
  static const String displayFont = 'BricolageGrotesque';

  // ── Brand: Moss (trust, commerce) ────────────────────────────────────────
  static const Color primary = Color(0xFF2E6B4F);
  static const Color primaryDark = Color(0xFF245740);
  static const Color primaryLight = Color(0xFFE4EFE9);
  static const Color accent = Color(0xFFC2412D);
  static const Color success = Color(0xFF248A52);
  static const Color warning = Color(0xFFE08A00);
  static const Color primaryColor = primary;

  // ── Market accents ───────────────────────────────────────────────────────
  static const Color sunshine = Color(0xFFF2C14E);
  static const Color sunshineLight = Color(0xFFFDF1D8);
  static const Color malva = Color(0xFF6D2E8C);
  static const Color lilac = Color(0xFFF1E7F6);
  static const Color peach = Color(0xFFFBEAE6);
  static const Color sand = Color(0xFFF3EEE6);

  // ── Neutrals ─────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF6F3EE);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1C1820);
  static const Color textSecondary = Color(0xFF6B6472);
  static const Color divider = Color(0xFFEDE6DA);

  static const double radiusMd = 18;
  static const double radiusLg = 24;

  /// Headline style in the display face.
  static TextStyle display({double size = 22, FontWeight weight = FontWeight.w800, Color color = textPrimary}) =>
      TextStyle(fontFamily: displayFont, fontSize: size, fontWeight: weight, height: 1.1, letterSpacing: -0.4, color: color);

  static ThemeData get lightTheme {
    const buttonText = TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700);
    const buttonSize = Size(64, 54);
    TextStyle disp(double size) => TextStyle(
        fontFamily: displayFont, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.12, color: textPrimary);

    return ThemeData(
      useMaterial3: true,
      fontFamily: bodyFont,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
      splashFactory: InkSparkle.splashFactory,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(seedColor: primary).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: sunshine,
        onSecondary: textPrimary,
        tertiary: accent,
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outlineVariant: divider,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: textPrimary),
        titleTextStyle: disp(20).copyWith(fontWeight: FontWeight.w700),
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: buttonSize,
          shape: const StadiumBorder(),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: buttonSize,
          side: const BorderSide(color: divider, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: sunshine,
        foregroundColor: textPrimary,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sand,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: const BorderSide(color: primary, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 15),
        hintStyle: const TextStyle(color: textSecondary, fontSize: 15),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg - 2), side: const BorderSide(color: divider)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: primaryLight,
        selectedColor: sunshine,
        labelStyle: TextStyle(fontFamily: bodyFont, color: primary, fontWeight: FontWeight.w700, fontSize: 13),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: StadiumBorder(),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: sunshine,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: bodyFont, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w800, fontSize: 14.5),
        unselectedLabelStyle: TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 0.8, space: 0.8),
      listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd))),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: divider,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : null),
      ),
      textTheme: TextTheme(
        displayLarge: disp(34),
        displayMedium: disp(26),
        displaySmall: disp(21),
        headlineMedium: disp(24),
        headlineSmall: disp(21),
        titleLarge: disp(19),
        bodyLarge: const TextStyle(color: textPrimary, fontSize: 16, height: 1.5),
        bodyMedium: const TextStyle(color: textSecondary, fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(color: textSecondary, fontSize: 12),
        titleMedium: const TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        labelLarge: const TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        actionTextColor: sunshine,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
    );
  }
}
