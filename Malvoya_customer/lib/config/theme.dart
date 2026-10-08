import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Malvoya brand theme: "Birch Market".
/// Calm Birch neutrals and one brand colour (Malva) carry the app; a sunny yellow, soft pastel
/// tiles, pill-shaped buttons and the rounded Bricolage display face add a friendly, playful
/// side. Body text is Hanken Grotesk. Both fonts ship inside the app (no network font loading).
/// Member names from earlier versions are kept so every screen keeps compiling.
class AppTheme {
  // ── Type ─────────────────────────────────────────────────────────────────
  static const String bodyFont = 'HankenGrotesk';
  static const String displayFont = 'BricolageGrotesque';

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
  static const Color lingon = Color(0xFFC2412D);        // sale prices, couriers
  static const Color moss = Color(0xFF2E6B4F);

  // ── Market accents (the playful side) ────────────────────────────────────
  static const Color sunshine = Color(0xFFF2C14E);      // highlights, active tab, badges
  static const Color sunshineLight = Color(0xFFFDF1D8);
  static const Color lilac = Color(0xFFF1E7F6);
  static const Color mint = Color(0xFFE3F2E9);
  static const Color peach = Color(0xFFFBEAE6);
  static const Color sand = Color(0xFFF3EEE6);
  static const Color clay = Color(0xFFE9DFD2);
  static const Color clayInk = Color(0xFF8A6F55);

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

  // ── Shape ────────────────────────────────────────────────────────────────
  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;

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
    double radius = radiusLg,
    bool isDark = false,
  }) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF221C29) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: isDark ? const Color(0xFF332B3B) : const Color(0xFFEDE6DA), width: 1),
      boxShadow: isDark ? const [] : softShadow,
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

  static List<BoxShadow> get softShadow => [
        BoxShadow(color: const Color(0xFF3A2A1A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6)),
      ];
  static List<BoxShadow> get cardShadow => softShadow;

  static List<BoxShadow> get glowShadow => [
        BoxShadow(color: primary.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4)),
      ];

  /// Headline style in the display face. Use for screen titles and section headings.
  static TextStyle display(BuildContext context, {double size = 22, FontWeight weight = FontWeight.w800, Color? color}) =>
      TextStyle(
        fontFamily: displayFont,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        letterSpacing: -0.4,
        color: color ?? primaryText(context),
      );

  // ── Shared component styling ─────────────────────────────────────────────
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
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFFC9A3DD) : brand,
      onPrimary: dark ? const Color(0xFF2A0F38) : Colors.white,
      secondary: sunshine,
      onSecondary: ink,
      tertiary: lingon,
      surface: surfaceColor,
      onSurface: text,
      onSurfaceVariant: subtext,
      outlineVariant: border,
      error: dark ? const Color(0xFFFF6B5E) : const Color(0xFFD93025),
    );
    const buttonShape = StadiumBorder();
    const buttonText = TextStyle(fontFamily: bodyFont, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1);
    const buttonSize = Size(64, 54);

    final baseText = ThemeData(brightness: brightness, fontFamily: bodyFont).textTheme;
    TextStyle disp(TextStyle? s, double size) =>
        (s ?? const TextStyle()).copyWith(fontFamily: displayFont, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.12);
    final textTheme = baseText
        .copyWith(
          displayLarge: disp(baseText.displayLarge, 40),
          displayMedium: disp(baseText.displayMedium, 32),
          displaySmall: disp(baseText.displaySmall, 28),
          headlineLarge: disp(baseText.headlineLarge, 26),
          headlineMedium: disp(baseText.headlineMedium, 24),
          headlineSmall: disp(baseText.headlineSmall, 21),
          titleLarge: disp(baseText.titleLarge, 19),
        )
        .apply(bodyColor: text, displayColor: text);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: bodyFont,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: bg,
      pageTransitionsTheme: _pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: border, thickness: 0.8, space: 0.8),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(fontFamily: displayFont, color: text, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: scheme.primary,
        unselectedItemColor: subtext,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: sunshine,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg - 2), side: BorderSide(color: border, width: 1)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? text : ink,
          minimumSize: buttonSize,
          side: BorderSide(color: border, width: 1.5),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: bodyFont, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: sunshine,
        foregroundColor: ink,
        elevation: 0,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        labelStyle: TextStyle(color: subtext),
        hintStyle: TextStyle(color: subtext.withValues(alpha: 0.85)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: border, width: 1.2),
        backgroundColor: surfaceColor,
        selectedColor: dark ? scheme.primary.withValues(alpha: 0.25) : lilac,
        checkmarkColor: scheme.primary,
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: border),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF3A3242) : night,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        actionTextColor: sunshine,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: subtext,
        textColor: text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
    );
  }

  static ThemeData get lightTheme => _base(
        brightness: Brightness.light,
        bg: birch,
        surfaceColor: Colors.white,
        fill: sand,
        border: const Color(0xFFEDE6DA),
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
  static Color cardBorder(BuildContext context) => isDarkMode(context) ? const Color(0xFF332B3B) : const Color(0xFFEDE6DA);
  static Color primaryText(BuildContext context) => isDarkMode(context) ? textPrimary : ink;
  static Color secondaryText(BuildContext context) => isDarkMode(context) ? textSecondary : inkSecondary;
  static Color inputBackground(BuildContext context) => isDarkMode(context) ? const Color(0xFF2A2331) : sand;
  static Color subtleDivider(BuildContext context) => isDarkMode(context) ? const Color(0xFF2A2331) : const Color(0xFFEDE6DA);

  /// A soft pastel tile colour that also works in dark mode (where it becomes a gentle tint of [hue]).
  static Color pastel(BuildContext context, Color light, Color hue) =>
      isDarkMode(context) ? hue.withValues(alpha: 0.22) : light;
}
