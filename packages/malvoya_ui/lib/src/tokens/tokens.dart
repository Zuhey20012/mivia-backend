import 'package:flutter/material.dart';
import 'colors.dart';
import 'layout.dart';

/// All theme-dependent design tokens, carried by the theme as a [ThemeExtension].
///
/// ```dart
/// final t = MalvoyaTokens.of(context);
/// Container(color: t.colors.surfaceVariant, padding: const EdgeInsets.all(MSpace.lg));
/// Text('Hei', style: MType.bodyL.copyWith(color: t.colors.onSurfaceVariant));
/// ```
/// Spacing ([MSpace]), radii ([MRadius]), type ([MType]) and motion ([MMotion]) do not depend on
/// the theme and are plain constants.
@immutable
class MalvoyaTokens extends ThemeExtension<MalvoyaTokens> {
  /// Creates the tokens for [brand] and [colors].
  const MalvoyaTokens({required this.brand, required this.colors, required this.pastels});

  /// The tokens for [brand] in [brightness].
  factory MalvoyaTokens.forBrand(MalvoyaBrand brand, Brightness brightness) => MalvoyaTokens(
        brand: brand,
        colors: brightness == Brightness.dark ? MalvoyaColors.dark(brand) : MalvoyaColors.light(brand),
        pastels: brightness == Brightness.dark ? MalvoyaPastels.dark : MalvoyaPastels.light,
      );

  /// The app's brand (Malva, Moss or Lingon).
  final MalvoyaBrand brand;

  /// Semantic colour roles.
  final MalvoyaColors colors;

  /// Pastel tiles.
  final MalvoyaPastels pastels;

  /// True in dark mode.
  bool get isDark => colors.isDark;

  /// Shadows for [level] in the current brightness.
  List<BoxShadow> shadow(MElevation level) => level.shadows(brightness: colors.brightness);

  /// The tokens of the nearest theme. Without a Malvoya theme (e.g. a bare test), the light Malva
  /// tokens.
  static MalvoyaTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MalvoyaTokens>() ?? MalvoyaTokens.forBrand(MalvoyaBrand.malva, theme.brightness);
  }

  @override
  MalvoyaTokens copyWith({MalvoyaBrand? brand, MalvoyaColors? colors, MalvoyaPastels? pastels}) =>
      MalvoyaTokens(brand: brand ?? this.brand, colors: colors ?? this.colors, pastels: pastels ?? this.pastels);

  @override
  MalvoyaTokens lerp(covariant MalvoyaTokens? other, double t) {
    if (other == null) return this;
    return MalvoyaTokens(
      brand: t < 0.5 ? brand : other.brand,
      colors: colors.lerp(other.colors, t),
      pastels: pastels.lerp(other.pastels, t),
    );
  }
}

/// Short access from a widget: `context.mColors.danger`, `context.mTokens.shadow(MElevation.e2)`.
extension MalvoyaTokensContext on BuildContext {
  /// [MalvoyaTokens.of].
  MalvoyaTokens get mTokens => MalvoyaTokens.of(this);

  /// The semantic colours.
  MalvoyaColors get mColors => MalvoyaTokens.of(this).colors;

  /// The pastels.
  MalvoyaPastels get mPastels => MalvoyaTokens.of(this).pastels;
}
