import 'package:flutter/material.dart';

class AppTheme {
  // ── Malvoya Option B: Neo-Vibrant Glassmorphism Signature Palette ──────────
  static const Color primary = Color(0xFF8B5CF6);       // Electric Violet / Iris
  static const Color primaryDark = Color(0xFF7C3AED);   // Deep Violet
  static const Color primaryLight = Color(0xFFEDE9FE);  // Soft Violet tint
  static const Color accent = Color(0xFFEC4899);        // Hot Fuchsia / Pink
  static const Color accentLight = Color(0xFFFCE7F3);   // Soft Pink tint
  static const Color emerald = Color(0xFF10B981);       // Sub-second Dispatch Emerald
  static const Color emeraldLight = Color(0xFFD1FAE5);  // Soft Emerald tint
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);       // Radiant Amber
  static const Color background = Color(0xFF0F081D);    // Deep Velvet Violet Canvas
  static const Color surface = Color(0xFF1B1033);       // Velvet Amethyst Surface
  static const Color textPrimary = Color(0xFFFAF5FF);   // Luminous Velvet White
  static const Color textSecondary = Color(0xFFC4B5FD); // Soft Lavender Violet
  static const Color divider = Color(0xFF2E1B50);
  static const Color glassBorder = Color(0x3D8B5CF6);   // Frosted Violet stroke

  // ── Glossy Vibrant Style Flavors & Specular Glass Decorators ─────────────
  // 1. Electric Iris & Fuchsia Glow (Signature)
  static const LinearGradient irisFuchsiaGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 2. Cyber Mint & Emerald Aurora (Fintech Luxury)
  static const LinearGradient cyberMintGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF0D9488), Color(0xFF06B6D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 3. Cosmic Coral & Sunset Prism (High Energy)
  static const LinearGradient cosmicCoralGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFF43F5E), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 4. Crystal Pearl & Liquid Ice (VisionOS Specular Glass)
  static const LinearGradient crystalPearlGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF312E81), Color(0xFF1E1B4B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Builds a liquid frosted glass decoration with 1.5px top specular highlight
  /// and dual-layer ambient chromatic glow.
  static BoxDecoration glossyCardDecoration({
    Color glowColor = const Color(0xFF8B5CF6),
    double radius = 24.0,
    bool isDark = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF1E1438).withValues(alpha: 0.88),
                const Color(0xFF120B24).withValues(alpha: 0.70),
              ]
            : [
                Colors.white.withValues(alpha: 0.92),
                const Color(0xFFF8F7FF).withValues(alpha: 0.75),
              ],
      ),
      border: Border(
        top: BorderSide(
          color: Colors.white.withValues(alpha: isDark ? 0.35 : 0.95),
          width: 1.5,
        ),
        left: BorderSide(
          color: Colors.white.withValues(alpha: isDark ? 0.20 : 0.65),
          width: 1.0,
        ),
        right: BorderSide(
          color: glowColor.withValues(alpha: 0.18),
          width: 1.0,
        ),
        bottom: BorderSide(
          color: glowColor.withValues(alpha: 0.22),
          width: 1.0,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: glowColor.withValues(alpha: isDark ? 0.25 : 0.18),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // Keep legacy alias so existing code doesn't break
  static const Color primaryColor = primary;

  // Option B Signature Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF18102C), Color(0xFF100A20)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Option B Ambient Glass Shadows
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  // 1. Neo-Vibrant Luxury Light Theme (Wolt-Superior Crisp White)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: Colors.white,
        error: Color(0xFFEF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Color(0x1A8B5CF6),
        iconTheme: IconThemeData(color: Color(0xFF0F0B1E)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F0B1E),
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF6B7280),
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x1A8B5CF6), width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F1FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0x1F8B5CF6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0x1F8B5CF6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  // 2. Midnight OLED Dark Theme (#0A0518) - Malvoya Signature
  static ThemeData get darkTheme {
    const darkBg = Color(0xFF0A0518);
    const darkSurface = Color(0xFF140D28);
    const darkElevated = Color(0xFF1E133C);
    const darkTextPrimary = Color(0xFFFAF7FF);
    const darkTextSecondary = Color(0xFFA8A2B8);
    const darkBorder = Color(0xFF2E1F52);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: darkSurface,
        error: Color(0xFFEF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primary,
        unselectedItemColor: darkTextSecondary,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x338B5CF6), width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: darkBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: darkBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: primary, width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  // 3. Eye-Protection Amber Theme (3400K Warm Filter for Blue Light Reduction)
  static ThemeData get eyeComfortTheme {
    const amberBg = Color(0xFF14110E);
    const amberSurface = Color(0xFF1E1813);
    const amberElevated = Color(0xFF2A2119);
    const amberTextPrimary = Color(0xFFFDE8CF);
    const amberTextSecondary = Color(0xFFC7B299);
    const amberBorder = Color(0xFF382C22);
    const amberPrimary = Color(0xFFE08A28);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: amberPrimary,
      scaffoldBackgroundColor: amberBg,
      colorScheme: const ColorScheme.dark(
        primary: amberPrimary,
        secondary: Color(0xFFE06040),
        surface: amberSurface,
        error: Color(0xFFEF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: amberSurface,
        elevation: 0,
        iconTheme: IconThemeData(color: amberTextPrimary),
        titleTextStyle: TextStyle(
          color: amberTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: amberSurface,
        selectedItemColor: amberPrimary,
        unselectedItemColor: amberTextSecondary,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: amberSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: amberBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amberPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: amberElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: amberBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: amberBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: amberPrimary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  // ── Dynamic Semantic Theme Helpers (Wolt-Superior 2-Mode System) ─────────────
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color scaffoldBackground(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  static Color cardBackground(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFF140D28);
    return Colors.white;
  }

  static Color cardBorder(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFF2E1F52);
    return const Color(0x1F8B5CF6);
  }

  static Color primaryText(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFFFAF7FF);
    return const Color(0xFF0F0B1E); // Crisp deep velvet obsidian in Light mode
  }

  static Color secondaryText(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFFA8A2B8);
    return const Color(0xFF4B5563); // Rich neutral slate in Light mode
  }

  static Color inputBackground(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFF1E133C);
    return const Color(0xFFF6F4FB);
  }

  static Color subtleDivider(BuildContext context) {
    if (isDarkMode(context)) return const Color(0xFF20163A);
    return const Color(0xFFEDE8F5);
  }
}
