import 'package:flutter/material.dart';

/// The Birch Market base palette: raw values. Screens never use these directly; they read the
/// semantic roles in [MalvoyaColors] (which also work in dark mode).
abstract final class MPalette {
  /// White: light-mode surfaces, and text and icons on the brand colours.
  static const white = Color(0xFFFFFFFF);

  /// Modal scrim and dark overlays (54 % black).
  static const scrim = Color(0x8A000000);

  /// Light background.
  static const birch = Color(0xFFF6F3EE);

  /// Dark background (brand material, splash).
  static const night = Color(0xFF17131C);

  /// Body text on light surfaces.
  static const ink = Color(0xFF1C1820);

  /// Secondary text on light surfaces.
  static const inkSecondary = Color(0xFF6B6472);

  /// Hairlines and borders on light surfaces.
  static const line = Color(0xFFEDE6DA);

  /// Highlights, the active tab, badges.
  static const sunshine = Color(0xFFF2C14E);

  /// Soft sunshine fill.
  static const sunshineLight = Color(0xFFFDF1D8);

  /// Text and icons on [sunshineLight] (≥ 7:1).
  static const amberInk = Color(0xFF6A4500);

  /// Status green (AA on white).
  static const green = Color(0xFF248A52);

  /// Status red.
  static const red = Color(0xFFD93025);

  /// Status amber.
  static const amber = Color(0xFFE08A00);

  /// Customer app brand.
  static const malva = Color(0xFF6D2E8C);

  /// Store app brand.
  static const moss = Color(0xFF2E6B4F);

  /// Courier app brand; also sale prices.
  static const lingon = Color(0xFFC2412D);

  /// Dark mode: background.
  static const nightBackground = Color(0xFF121015);

  /// Dark mode: cards and sheets.
  static const nightSurface = Color(0xFF221C29);

  /// Dark mode: input fills, quiet tiles.
  static const nightSurfaceVariant = Color(0xFF2A2331);

  /// Dark mode: hairlines.
  static const nightLine = Color(0xFF332B3B);

  /// Dark mode: raised fills (snackbars, pressed tiles).
  static const nightRaised = Color(0xFF3A3242);

  /// Dark mode: body text.
  static const nightInk = birch;

  /// Dark mode: secondary text.
  static const nightInkSecondary = Color(0xFFB9AFC2);

  /// Strong status red for text on soft red (≥ 4.5:1).
  static const redInk = Color(0xFFB3261E);

  /// Soft red fill.
  static const redLight = Color(0xFFFDECEA);

  /// Dark green for white text on green (≈ 6.5:1).
  static const greenDark = Color(0xFF1B6B40);

  /// Borders that must be seen on light surfaces (high contrast).
  static const lineStrong = Color(0xFF7A7268);

  /// Borders that must be seen on dark surfaces.
  static const nightLineStrong = Color(0xFFA79EAF);

  /// Border of an error box on light surfaces.
  static const redLine = Color(0xFFFFCDD2);

  /// Scrim behind text over photos and video (70 % black), e.g. the bottom of a drop.
  static const mediaScrim = Color(0xB3000000);

  /// A lighter media scrim (40 % black), e.g. the top of a drop under the status bar.
  static const mediaScrimSoft = Color(0x66000000);

  /// A liked heart over photos and video.
  static const like = Color(0xFFFF4D6D);

  /// "You are here" on maps (the platform convention for your own position).
  static const locationBlue = Color(0xFF2563EB);

  /// Moss on dark surfaces.
  static const mossOnDark = Color(0xFF8FD5AE);

  /// Malva, pressed / deep.
  static const malvaStrong = Color(0xFF55226E);

  /// Malva on dark surfaces.
  static const malvaOnDark = Color(0xFFC9A3DD);

  /// Moss, pressed / deep.
  static const mossStrong = Color(0xFF245740);

  /// Soft Moss tint.
  static const mossSoft = Color(0xFFE4EFE9);

  /// Lingon, pressed / deep.
  static const lingonStrong = Color(0xFF9E3222);

  /// Pastel tile: lilac (also the soft Malva tint).
  static const lilac = Color(0xFFF1E7F6);

  /// Pastel tile: mint.
  static const mint = Color(0xFFE3F2E9);

  /// Pastel tile: peach.
  static const peach = Color(0xFFFBEAE6);

  /// Pastel tile and input fill: sand.
  static const sand = Color(0xFFF3EEE6);

  /// Pastel tile: clay.
  static const clay = Color(0xFFE9DFD2);

  /// Text and icons on clay and sand.
  static const clayInk = Color(0xFF8A6F55);
}

/// One app's brand colour with its hand-tuned companions.
@immutable
class MalvoyaBrand {
  /// Creates a brand. Prefer [malva], [moss], [lingon] or [MalvoyaBrand.of].
  const MalvoyaBrand({
    required this.color,
    required this.strong,
    required this.soft,
    required this.onDark,
    required this.dark,
  });

  /// Customer app: Malva.
  static const malva = MalvoyaBrand(
    color: MPalette.malva,
    strong: MPalette.malvaStrong,
    soft: MPalette.lilac,
    dark: MPalette.malvaOnDark,
    onDark: Color(0xFF2A0F38),
  );

  /// Store app: Moss.
  static const moss = MalvoyaBrand(
    color: MPalette.moss,
    strong: MPalette.mossStrong,
    soft: MPalette.mossSoft,
    dark: MPalette.mossOnDark,
    onDark: Color(0xFF0B2A1D),
  );

  /// Courier app: Lingon.
  static const lingon = MalvoyaBrand(
    color: MPalette.lingon,
    strong: MPalette.lingonStrong,
    soft: MPalette.peach,
    dark: Color(0xFFF4A08F),
    onDark: Color(0xFF3A0D05),
  );

  /// The brand on light surfaces (buttons, links, focus).
  final Color color;

  /// A darker shade (pressed states, art).
  final Color strong;

  /// A soft tint for tiles and selected states on light surfaces.
  final Color soft;

  /// The brand as used on dark surfaces (lighter, so it keeps its contrast).
  final Color dark;

  /// Text on [dark].
  final Color onDark;

  /// The hand-tuned brand for [color] when it is one of the three, otherwise derived from it.
  static MalvoyaBrand of(Color color) {
    for (final b in const [malva, moss, lingon]) {
      if (b.color.toARGB32() == color.toARGB32()) return b;
    }
    final hsl = HSLColor.fromColor(color);
    return MalvoyaBrand(
      color: color,
      strong: hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor(),
      soft: hsl.withLightness(0.94).withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0)).toColor(),
      dark: hsl.withLightness(0.75).toColor(),
      onDark: hsl.withLightness(0.12).toColor(),
    );
  }

  @override
  bool operator ==(Object other) => other is MalvoyaBrand && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Semantic colour roles. Read them with `MalvoyaTokens.of(context).colors` (or `context.mColors`).
///
/// Every `on…` colour meets WCAG 2.1 AA (4.5:1) for text on its partner.
@immutable
class MalvoyaColors {
  /// Creates a full set of roles. Use [light] or [dark].
  const MalvoyaColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineStrong,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.primaryStrong,
    required this.sunshine,
    required this.onSunshine,
    required this.sunshineSoft,
    required this.onSunshineSoft,
    required this.success,
    required this.onSuccess,
    required this.successSoft,
    required this.onSuccessSoft,
    required this.warning,
    required this.onWarning,
    required this.warningSoft,
    required this.onWarningSoft,
    required this.danger,
    required this.onDanger,
    required this.dangerSoft,
    required this.onDangerSoft,
    required this.sale,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  /// Light roles for [brand].
  factory MalvoyaColors.light(MalvoyaBrand brand) => MalvoyaColors(
        brightness: Brightness.light,
        background: MPalette.birch,
        surface: Colors.white,
        surfaceVariant: MPalette.sand,
        onSurface: MPalette.ink,
        onSurfaceVariant: MPalette.inkSecondary,
        outline: MPalette.line,
        outlineStrong: MPalette.lineStrong,
        primary: brand.color,
        onPrimary: Colors.white,
        primarySoft: brand.soft,
        onPrimarySoft: brand.color,
        primaryStrong: brand.strong,
        sunshine: MPalette.sunshine,
        onSunshine: MPalette.ink,
        sunshineSoft: MPalette.sunshineLight,
        onSunshineSoft: MPalette.amberInk,
        success: MPalette.green,
        onSuccess: Colors.white,
        successSoft: MPalette.mint,
        onSuccessSoft: MPalette.greenDark,
        warning: MPalette.amber,
        onWarning: MPalette.ink,
        warningSoft: MPalette.sunshineLight,
        onWarningSoft: MPalette.amberInk,
        danger: MPalette.red,
        onDanger: Colors.white,
        dangerSoft: MPalette.redLight,
        onDangerSoft: MPalette.redInk,
        sale: MPalette.lingon,
        inverseSurface: MPalette.night,
        onInverseSurface: Colors.white,
        skeletonBase: MPalette.sand,
        skeletonHighlight: Colors.white,
      );

  /// Dark roles for [brand].
  factory MalvoyaColors.dark(MalvoyaBrand brand) => MalvoyaColors(
        brightness: Brightness.dark,
        background: MPalette.nightBackground,
        surface: MPalette.nightSurface,
        surfaceVariant: MPalette.nightSurfaceVariant,
        onSurface: MPalette.nightInk,
        onSurfaceVariant: MPalette.nightInkSecondary,
        outline: MPalette.nightLine,
        outlineStrong: MPalette.nightLineStrong,
        primary: brand.dark,
        onPrimary: brand.onDark,
        primarySoft: brand.color.withValues(alpha: 0.25),
        onPrimarySoft: brand.dark,
        primaryStrong: brand.color,
        sunshine: MPalette.sunshine,
        onSunshine: MPalette.ink,
        sunshineSoft: const Color(0xFF3A3020),
        onSunshineSoft: const Color(0xFFF7D98A),
        success: const Color(0xFF5BC48A),
        onSuccess: const Color(0xFF0B2A1A),
        successSoft: const Color(0xFF1E3A2A),
        onSuccessSoft: const Color(0xFF8FD5AE),
        warning: const Color(0xFFF0A63A),
        onWarning: MPalette.ink,
        warningSoft: const Color(0xFF3A3020),
        onWarningSoft: const Color(0xFFF7D98A),
        danger: const Color(0xFFFF6B5E),
        onDanger: const Color(0xFF2A0905),
        dangerSoft: const Color(0xFF3A1F22),
        onDangerSoft: const Color(0xFFFFB4AB),
        sale: const Color(0xFFFF8A73),
        inverseSurface: MPalette.nightRaised,
        onInverseSurface: Colors.white,
        skeletonBase: MPalette.nightSurfaceVariant,
        skeletonHighlight: MPalette.nightRaised,
      );

  /// Warm, low-blue-light dark roles ("eye comfort"), with an amber accent instead of the brand.
  factory MalvoyaColors.warmDark() {
    const amberBrand = MalvoyaBrand(
      color: Color(0xFFB9772A),
      strong: Color(0xFF8E5A1F),
      soft: Color(0xFF3A2C1E),
      dark: Color(0xFFE0A55C),
      onDark: Color(0xFF2A1A08),
    );
    final base = MalvoyaColors.dark(amberBrand);
    return MalvoyaColors(
      brightness: Brightness.dark,
      background: const Color(0xFF14110E),
      surface: const Color(0xFF1E1813),
      surfaceVariant: const Color(0xFF2A2119),
      onSurface: const Color(0xFFFDE8CF),
      onSurfaceVariant: const Color(0xFFC7B299),
      outline: const Color(0xFF382C22),
      outlineStrong: const Color(0xFFC7B299),
      primary: amberBrand.dark,
      onPrimary: amberBrand.onDark,
      primarySoft: amberBrand.color.withValues(alpha: 0.25),
      onPrimarySoft: amberBrand.dark,
      primaryStrong: amberBrand.color,
      sunshine: base.sunshine,
      onSunshine: base.onSunshine,
      sunshineSoft: base.sunshineSoft,
      onSunshineSoft: base.onSunshineSoft,
      success: base.success,
      onSuccess: base.onSuccess,
      successSoft: base.successSoft,
      onSuccessSoft: base.onSuccessSoft,
      warning: base.warning,
      onWarning: base.onWarning,
      warningSoft: base.warningSoft,
      onWarningSoft: base.onWarningSoft,
      danger: base.danger,
      onDanger: base.onDanger,
      dangerSoft: base.dangerSoft,
      onDangerSoft: base.onDangerSoft,
      sale: base.sale,
      inverseSurface: const Color(0xFF382C22),
      onInverseSurface: const Color(0xFFFDE8CF),
      skeletonBase: const Color(0xFF2A2119),
      skeletonHighlight: const Color(0xFF382C22),
    );
  }

  /// Light or dark.
  final Brightness brightness;

  /// Screen background (Birch / Night).
  final Color background;

  /// Cards, sheets, dialogs.
  final Color surface;

  /// Input fills, quiet tiles (sand).
  final Color surfaceVariant;

  /// Body text and icons on [surface] and [background].
  final Color onSurface;

  /// Secondary text, hints, inactive icons.
  final Color onSurfaceVariant;

  /// Hairlines, card borders, dividers.
  final Color outline;

  /// Borders that must be seen (high contrast, focused chips).
  final Color outlineStrong;

  /// The app's brand accent (Malva, Moss or Lingon).
  final Color primary;

  /// Text and icons on [primary].
  final Color onPrimary;

  /// Soft brand tint (selected chips, icon circles).
  final Color primarySoft;

  /// Text and icons on [primarySoft].
  final Color onPrimarySoft;

  /// Darker brand (pressed fills, illustrations).
  final Color primaryStrong;

  /// The playful accent: highlights, the active tab, counters.
  final Color sunshine;

  /// Text on [sunshine].
  final Color onSunshine;

  /// Soft sunshine fill (notices, tips).
  final Color sunshineSoft;

  /// Text and icons on [sunshineSoft].
  final Color onSunshineSoft;

  /// Done, paid, delivered.
  final Color success;

  /// Text on [success].
  final Color onSuccess;

  /// Soft success fill.
  final Color successSoft;

  /// Text and icons on [successSoft].
  final Color onSuccessSoft;

  /// Needs attention soon.
  final Color warning;

  /// Text on [warning].
  final Color onWarning;

  /// Soft warning fill.
  final Color warningSoft;

  /// Text and icons on [warningSoft].
  final Color onWarningSoft;

  /// Errors and destructive actions.
  final Color danger;

  /// Text on [danger].
  final Color onDanger;

  /// Soft danger fill (error boxes).
  final Color dangerSoft;

  /// Text and icons on [dangerSoft].
  final Color onDangerSoft;

  /// Reduced prices (only with a real Omnibus reference price).
  final Color sale;

  /// Snackbars and the floating tab bar.
  final Color inverseSurface;

  /// Text on [inverseSurface].
  final Color onInverseSurface;

  /// Skeleton shapes.
  final Color skeletonBase;

  /// The shimmer passing over skeleton shapes.
  final Color skeletonHighlight;

  /// True for the dark set.
  bool get isDark => brightness == Brightness.dark;

  /// Interpolates between two sets (theme animations).
  MalvoyaColors lerp(MalvoyaColors other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MalvoyaColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceVariant: l(surfaceVariant, other.surfaceVariant),
      onSurface: l(onSurface, other.onSurface),
      onSurfaceVariant: l(onSurfaceVariant, other.onSurfaceVariant),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      onPrimarySoft: l(onPrimarySoft, other.onPrimarySoft),
      primaryStrong: l(primaryStrong, other.primaryStrong),
      sunshine: l(sunshine, other.sunshine),
      onSunshine: l(onSunshine, other.onSunshine),
      sunshineSoft: l(sunshineSoft, other.sunshineSoft),
      onSunshineSoft: l(onSunshineSoft, other.onSunshineSoft),
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successSoft: l(successSoft, other.successSoft),
      onSuccessSoft: l(onSuccessSoft, other.onSuccessSoft),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningSoft: l(warningSoft, other.warningSoft),
      onWarningSoft: l(onWarningSoft, other.onWarningSoft),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      onDangerSoft: l(onDangerSoft, other.onDangerSoft),
      sale: l(sale, other.sale),
      inverseSurface: l(inverseSurface, other.inverseSurface),
      onInverseSurface: l(onInverseSurface, other.onInverseSurface),
      skeletonBase: l(skeletonBase, other.skeletonBase),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
    );
  }
}

/// Pastel tiles (the playful side). In dark mode each becomes a gentle tint of its hue.
@immutable
class MalvoyaPastels {
  /// Creates the set.
  const MalvoyaPastels({required this.lilac, required this.mint, required this.peach, required this.sand, required this.clay, required this.clayInk});

  /// Light pastels.
  static const light = MalvoyaPastels(
    lilac: MPalette.lilac,
    mint: MPalette.mint,
    peach: MPalette.peach,
    sand: MPalette.sand,
    clay: MPalette.clay,
    clayInk: MPalette.clayInk,
  );

  /// Dark tints.
  static final dark = MalvoyaPastels(
    lilac: MPalette.malva.withValues(alpha: 0.22),
    mint: MPalette.green.withValues(alpha: 0.22),
    peach: MPalette.lingon.withValues(alpha: 0.22),
    sand: MPalette.clayInk.withValues(alpha: 0.22),
    clay: MPalette.clayInk.withValues(alpha: 0.30),
    clayInk: const Color(0xFFD9C4AE),
  );

  /// Lilac tile.
  final Color lilac;

  /// Mint tile.
  final Color mint;

  /// Peach tile.
  final Color peach;

  /// Sand tile.
  final Color sand;

  /// Clay tile.
  final Color clay;

  /// Text and icons on clay and sand.
  final Color clayInk;

  /// The pastels in order, for rotating tiles.
  List<Color> get all => [lilac, mint, peach, sand, clay];

  /// Interpolates between two sets.
  MalvoyaPastels lerp(MalvoyaPastels other, double t) => MalvoyaPastels(
        lilac: Color.lerp(lilac, other.lilac, t)!,
        mint: Color.lerp(mint, other.mint, t)!,
        peach: Color.lerp(peach, other.peach, t)!,
        sand: Color.lerp(sand, other.sand, t)!,
        clay: Color.lerp(clay, other.clay, t)!,
        clayInk: Color.lerp(clayInk, other.clayInk, t)!,
      );
}
