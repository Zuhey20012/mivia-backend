import 'package:flutter/material.dart';

/// Malvoya brand theme — "Thread M" identity.
/// Quiet, premium, native: system fonts (SF Pro on iOS, Roboto on Android), one brand colour
/// (Malva), warm Birch/Night neutrals and platform-standard status colours.
/// Member names are kept from earlier versions so every screen keeps compiling.
class AppTheme {
  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6D2E8C);       // Malva
  static const Color primaryDark = Color(0xFF55226E);
  static const Color primaryLight = Color(0xFFF1E7F6);
  static const Color accent = Color(0xFF9B5DB8);        // Malva, lighter
  static const Color accentLight = Color(0xFFF3E8F7);
  static const Color emerald = Color(0xFF248A52);       // success (AA on white)
  static const Color emeraldLight = Color(0xFFE3F2E9);
  static const Color success = Color(0xFF248A52);
  static const Color warning = Color(0xFFE08A00);

  // Dark-surface constants (screens use these on dark backgrounds)
  static const Color background = Color(0xFF17131C);    // Night
  static const Color surface = Color(0xFF221C29);
  static const Color textPrimary = Color(0xFFF6F3EE);   // Birch
  static const Color textSecondary = Color(0xFFB9AFC2);
  static const Color divider = Color(0xFF3A3242);
  static const Color glassBorder = Color(0x1F6D2E8C);

  // Light neutrals
  static const Color birch = Color(0xFFF6F3EE);
  static const Color night = Color(0xFF17131C);
  static const Color ink = Color(0xFF1C1820);
  static const Color inkSecondary = Color(0xFF6B6472);

  // ── Tonal fills (kept as gradients for API compatibility, intentionally subtle) ──
  static const LinearGradient irisFuchsiaGradient = LinearGradient(
    colors: [Color(0xFF6D2E8C), Color(0xFF5E2779)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient cyberMintGradient = LinearGradient(
    colors: [Color(0xFF248A52), Color(0xFF1E7545)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient cosmicCoralGradient = LinearGradient(
    colors: [Color(0xFFC2412D), Color(0xFFA83725)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient crystalPearlGradient = LinearGradient(
    colors: [Color(0xFF221C29), Color(0xFF17131C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Clean card: solid surface, hairline border, soft shadow.
  static BoxDecoration glossyCardDecoration({
    Color glowColor = primary,
    double radius = 20.0,
    bool isDark = false,
  }) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF221C29) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: isDark ? const Color(0xFF332B3B) : const Color(0xFFE9E4EC), width: 0.8),
      boxShadow: isDark
          ? const []
          : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
    );
  }

  static const Color primaryColor = primary;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF7A3599), Color(0xFF6D2E8C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient violetGradient = primaryGradient;
  static const LinearGradient emeraldGradient = cyberMintGradient;
  static const LinearGradient darkCardGradient = crystalPearlGradient;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(color: primary.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4)),
      ];

  // ── Shared component styling ─────────────────────────────────────────────
  static const _radius = 14.0;
  static const _pageTransitions = PageTransitionsTheme(builders: {
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
  });

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surfaceColor,
    required Color fill,
    required Color border,
    required Color text,
    required Color subtext,
    Color brand = primary,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
      primary: brightness == Brightness.dark ? const Color(0xFFC9A3DD) : brand,
      onPrimary: brightness == Brightness.dark ? const Color(0xFF2A0F38) : Colors.white,
      secondary: accent,
      surface: surfaceColor,
      onSurface: text,
      onSurfaceVariant: subtext,
      outlineVariant: border,
      error: brightness == Brightness.dark ? const Color(0xFFFF6B5E) : const Color(0xFFD93025),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2);
    const buttonSize = Size.fromHeight(52);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: bg,
      pageTransitionsTheme: _pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: border, thickness: 0.6, space: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: scheme.primary,
        unselectedItemColor: subtext,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: border, width: 0.8)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: buttonSize,
          side: BorderSide(color: border, width: 1),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary, textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        labelStyle: TextStyle(color: subtext),
        hintStyle: TextStyle(color: subtext.withValues(alpha: 0.8)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark ? const Color(0xFF3A3242) : night,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(iconColor: subtext, textColor: text),
    );
  }

  static ThemeData get lightTheme => _base(
        brightness: Brightness.light,
        bg: birch,
        surfaceColor: Colors.white,
        fill: const Color(0xFFEFEBF1),
        border: const Color(0xFFE6E1EA),
        text: ink,
        subtext: inkSecondary,
      );

  static ThemeData get darkTheme => _base(
        brightness: Brightness.dark,
        bg: const Color(0xFF121015),
        surfaceColor: surface,
        fill: const Color(0xFF2A2331),
        border: const Color(0xFF332B3B),
        text: textPrimary,
        subtext: textSecondary,
      );

  /// Warm, low-blue-light variant of the dark theme.
  static ThemeData get eyeComfortTheme => _base(
        brightness: Brightness.dark,
        bg: const Color(0xFF14110E),
        surfaceColor: const Color(0xFF1E1813),
        fill: const Color(0xFF2A2119),
        border: const Color(0xFF382C22),
        text: const Color(0xFFFDE8CF),
        subtext: const Color(0xFFC7B299),
        brand: const Color(0xFFB9772A),
      );

  // ── Context helpers ──────────────────────────────────────────────────────
  static bool isDarkMode(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color scaffoldBackground(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  static Color cardBackground(BuildContext context) => isDarkMode(context) ? surface : Colors.white;
  static Color cardBorder(BuildContext context) => isDarkMode(context) ? const Color(0xFF332B3B) : const Color(0xFFE6E1EA);
  static Color primaryText(BuildContext context) => isDarkMode(context) ? textPrimary : ink;
  static Color secondaryText(BuildContext context) => isDarkMode(context) ? textSecondary : inkSecondary;
  static Color inputBackground(BuildContext context) => isDarkMode(context) ? const Color(0xFF2A2331) : const Color(0xFFEFEBF1);
  static Color subtleDivider(BuildContext context) => isDarkMode(context) ? const Color(0xFF2A2331) : const Color(0xFFEDE8F0);
}
