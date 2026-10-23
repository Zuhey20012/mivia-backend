import 'package:flutter/painting.dart';

/// The bundled font families (declared in this package's pubspec, so they are referenced with the
/// `packages/malvoya_ui/` prefix). Fonts are never loaded from the network.
abstract final class MFonts {
  /// Hanken Grotesk: body text, labels, buttons.
  static const body = 'packages/malvoya_ui/HankenGrotesk';

  /// Bricolage Grotesque: display and headings.
  static const display = 'packages/malvoya_ui/BricolageGrotesque';
}

/// The type scale: eight sizes. [MTextSize] holds the numbers, [MType] the full styles. Styles carry no colour, so text takes the colour of its context
/// (`DefaultTextStyle`) unless a screen sets one. All sizes scale with the phone's text size.
///
/// | token     | size | face       | use                                   |
/// |-----------|------|------------|---------------------------------------|
/// | displayL  | 32   | Bricolage  | hero numbers, onboarding              |
/// | displayM  | 26   | Bricolage  | screen headlines                      |
/// | displayS  | 22   | Bricolage  | sheet and section headlines           |
/// | title     | 18   | Bricolage  | card titles, app bar                  |
/// | bodyL     | 16   | Hanken     | body copy, buttons                    |
/// | bodyM     | 14   | Hanken     | secondary copy, list subtitles        |
/// | label     | 13   | Hanken 700 | chips, badges, small buttons, meta    |
/// | caption   | 12   | Hanken     | fine print, hints, timestamps         |
/// Use `fontSize: MTextSize.label` to put an existing style on the scale.
abstract final class MTextSize {
  /// 32.
  static const double displayL = 32;

  /// 26.
  static const double displayM = 26;

  /// 22.
  static const double displayS = 22;

  /// 18.
  static const double title = 18;

  /// 16.
  static const double bodyL = 16;

  /// 14.
  static const double bodyM = 14;

  /// 13.
  static const double label = 13;

  /// 12.
  static const double caption = 12;
}

/// The eight sizes as full styles (face, weight, line height). Prefer these for new text; use
/// [MTextSize] only to put an existing style on the scale.
abstract final class MType {
  /// 32, Bricolage 800.
  static const displayL = TextStyle(fontFamily: MFonts.display, fontSize: 32, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.6);

  /// 26, Bricolage 800.
  static const displayM = TextStyle(fontFamily: MFonts.display, fontSize: 26, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.5);

  /// 22, Bricolage 800.
  static const displayS = TextStyle(fontFamily: MFonts.display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.4);

  /// 18, Bricolage 700.
  static const title = TextStyle(fontFamily: MFonts.display, fontSize: 18, fontWeight: FontWeight.w700, height: 1.12, letterSpacing: -0.3);

  /// 16, Hanken 400, line height 1.45.
  static const bodyL = TextStyle(fontFamily: MFonts.body, fontSize: 16, fontWeight: FontWeight.w400, height: 1.45);

  /// 14, Hanken 400, line height 1.4.
  static const bodyM = TextStyle(fontFamily: MFonts.body, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);

  /// 13, Hanken 700.
  static const label = TextStyle(fontFamily: MFonts.body, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3);

  /// 12, Hanken 500.
  static const caption = TextStyle(fontFamily: MFonts.body, fontSize: 12, fontWeight: FontWeight.w500, height: 1.35);

  /// All eight, largest first (for the gallery and docs).
  static Map<String, TextStyle> get all => {
        'displayL': displayL,
        'displayM': displayM,
        'displayS': displayS,
        'title': title,
        'bodyL': bodyL,
        'bodyM': bodyM,
        'label': label,
        'caption': caption,
      };

  /// A display-face style at a size outside the scale (large money amounts, the onboarding hero).
  /// Prefer the scale; use this only for one-off hero numbers.
  static TextStyle displayAt(double size, {FontWeight weight = FontWeight.w800}) =>
      TextStyle(fontFamily: MFonts.display, fontSize: size, fontWeight: weight, height: 1.1, letterSpacing: -0.4);
}
