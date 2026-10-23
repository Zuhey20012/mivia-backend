import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// How an app presents itself. The look is the same; a few defaults differ.
enum MalvoyaThemeStyle {
  /// The customer app: centred app bar titles, body text in full ink, outlined filter chips.
  shop,

  /// The store and courier apps (work tools): start-aligned titles, quieter body text so numbers
  /// and actions stand out, tinted chips with a sunshine selection.
  tool,
}

/// The full Birch Market [ThemeData] for one app.
///
/// Each app passes only its brand colour: Malva (customer), Moss (store) or Lingon (courier).
/// Buttons are pill-shaped with a theme minimum size of `Size(64, 54)`: they size to their content,
/// so a full-width button asks for it with a `SizedBox(width: double.infinity)` (never
/// `Size.fromHeight` in the theme, which breaks buttons inside rows). Bottom sheets show a drag
/// handle; transparent custom sheets switch it off ([showMSheet] does this for you).
///
/// [highContrast] is used for `MaterialApp.highContrastTheme`: stronger secondary text, lines and
/// field borders. [colors] replaces the colour roles (the customer app's warm "eye comfort" mode).
ThemeData buildMalvoyaTheme({
  required Color brand,
  required Brightness brightness,
  MalvoyaThemeStyle style = MalvoyaThemeStyle.shop,
  bool highContrast = false,
  MalvoyaColors? colors,
}) {
  final b = MalvoyaBrand.of(brand);
  final dark = brightness == Brightness.dark;
  final c = colors ?? (dark ? MalvoyaColors.dark(b) : MalvoyaColors.light(b));
  final tokens = MalvoyaTokens(brand: b, colors: c, pastels: dark ? MalvoyaPastels.dark : MalvoyaPastels.light);
  final tool = style == MalvoyaThemeStyle.tool;

  final secondaryText = highContrast ? c.onSurface : c.onSurfaceVariant;
  final line = highContrast ? c.outlineStrong : c.outline;

  final scheme = ColorScheme.fromSeed(seedColor: b.color, brightness: brightness).copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primarySoft,
    onPrimaryContainer: c.onPrimarySoft,
    secondary: c.sunshine,
    onSecondary: c.onSunshine,
    tertiary: b.color == MPalette.lingon ? MPalette.malva : MPalette.lingon,
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: secondaryText,
    outline: highContrast ? c.onSurface : c.outlineStrong,
    outlineVariant: line,
    error: c.danger,
    onError: c.onDanger,
    errorContainer: c.dangerSoft,
    onErrorContainer: c.onDangerSoft,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.onInverseSurface,
    surfaceTint: Colors.transparent,
  );

  const buttonText = TextStyle(fontFamily: MFonts.body, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1);
  const buttonSize = Size(64, 54);
  const buttonPadding = EdgeInsets.symmetric(horizontal: MSpace.xxl);
  const buttonShape = StadiumBorder();

  final bodyQuiet = tool ? secondaryText : c.onSurface;
  final textTheme = TextTheme(
    displayLarge: MType.displayL.copyWith(color: c.onSurface),
    displayMedium: MType.displayM.copyWith(color: c.onSurface),
    displaySmall: MType.displayS.copyWith(color: c.onSurface),
    headlineLarge: MType.displayM.copyWith(color: c.onSurface),
    headlineMedium: MType.displayS.copyWith(color: c.onSurface),
    headlineSmall: MType.displayS.copyWith(color: c.onSurface),
    titleLarge: MType.title.copyWith(color: c.onSurface),
    titleMedium: MType.bodyL.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: c.onSurface),
    titleSmall: MType.bodyM.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: c.onSurface),
    bodyLarge: MType.bodyL.copyWith(color: c.onSurface),
    bodyMedium: MType.bodyM.copyWith(color: bodyQuiet),
    bodySmall: MType.caption.copyWith(fontWeight: FontWeight.w400, color: tool ? secondaryText : c.onSurfaceVariant),
    labelLarge: MType.bodyM.copyWith(fontWeight: FontWeight.w700, color: c.onSurface),
    labelMedium: MType.label.copyWith(color: c.onSurface),
    labelSmall: MType.caption.copyWith(fontWeight: FontWeight.w600, color: c.onSurface),
  );

  OutlineInputBorder field([BorderSide side = BorderSide.none]) => OutlineInputBorder(borderRadius: MRadius.brMd, borderSide: side);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: MFonts.body,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryColor: c.primary,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    extensions: [tokens],
    // Flutter's defaults (the iOS slide on iOS/macOS) plus Android's predictive-back animation.
    // Spreading the defaults avoids naming CupertinoPageTransitionsBuilder, which moved packages.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      ...const PageTransitionsTheme().builders,
      TargetPlatform.android: const PredictiveBackPageTransitionsBuilder(),
    }),
    splashFactory: kIsWeb ? InkRipple.splashFactory : InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: DividerThemeData(color: line, thickness: highContrast ? 1.2 : 0.8, space: highContrast ? 1.2 : 0.8),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: tool ? null : true,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: c.onSurface),
      titleTextStyle: MType.title.copyWith(fontSize: 19, color: c.onSurface),
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.surface,
      selectedItemColor: c.primary,
      unselectedItemColor: secondaryText,
      showUnselectedLabels: true,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: MType.caption.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: MType.caption.copyWith(fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.sunshine,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.all(MType.caption.copyWith(fontWeight: FontWeight.w700)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.onSurface,
      unselectedLabelColor: secondaryText,
      indicatorColor: c.primary,
      dividerColor: Colors.transparent,
      labelStyle: MType.bodyM.copyWith(fontWeight: FontWeight.w800),
      unselectedLabelStyle: MType.bodyM.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: MRadius.brLg, side: BorderSide(color: line)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.onSurface,
        minimumSize: buttonSize,
        padding: buttonPadding,
        side: BorderSide(color: line, width: 1.5),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: MFonts.body, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.sunshine,
      foregroundColor: c.onSunshine,
      elevation: 0,
      shape: buttonShape,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceVariant,
      labelStyle: TextStyle(color: secondaryText),
      hintStyle: TextStyle(color: secondaryText.withValues(alpha: highContrast ? 1 : 0.85)),
      border: field(),
      enabledBorder: highContrast ? field(BorderSide(color: line, width: 1.4)) : field(),
      focusedBorder: field(BorderSide(color: c.primary, width: 1.6)),
      errorBorder: field(BorderSide(color: c.danger, width: 1.2)),
      focusedErrorBorder: field(BorderSide(color: c.danger, width: 1.6)),
      errorStyle: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: MSpace.lg),
    ),
    chipTheme: tool
        ? ChipThemeData(
            backgroundColor: c.primarySoft,
            selectedColor: c.sunshine,
            labelStyle: MType.label.copyWith(color: c.onPrimarySoft),
            secondaryLabelStyle: MType.label.copyWith(color: c.onSunshine),
            padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
            shape: const StadiumBorder(),
            side: BorderSide.none,
            checkmarkColor: c.onSunshine,
          )
        : ChipThemeData(
            shape: const StadiumBorder(),
            side: BorderSide(color: line, width: 1.2),
            backgroundColor: c.surface,
            selectedColor: c.primarySoft,
            checkmarkColor: c.primary,
            labelStyle: TextStyle(color: c.onSurface, fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: line, circularTrackColor: Colors.transparent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : null),
      checkColor: WidgetStateProperty.all(c.onPrimary),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverseSurface,
      contentTextStyle: MType.bodyM.copyWith(color: c.onInverseSurface, fontWeight: FontWeight.w600),
      actionTextColor: c.sunshine,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.brMd),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: line,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.sheetTop),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.brLg),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: secondaryText,
      textColor: c.onSurface,
      shape: const RoundedRectangleBorder(borderRadius: MRadius.brMd),
    ),
  );
}
