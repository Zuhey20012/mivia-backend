import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

bool _fontsLoaded = false;

/// Loads the bundled fonts and Material icons, so goldens show the real Birch Market type instead
/// of the test font's boxes.
Future<void> loadMalvoyaFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<ByteData> bytes(String path) async => ByteData.view(Uint8List.fromList(await File(path).readAsBytes()).buffer);
  final hanken = FontLoader(MFonts.body);
  for (final w in [400, 500, 600, 700, 800]) {
    hanken.addFont(bytes('fonts/HankenGrotesk-$w.ttf'));
  }
  await hanken.load();
  final bricolage = FontLoader(MFonts.display);
  for (final w in [600, 700, 800]) {
    bricolage.addFont(bytes('fonts/BricolageGrotesque-$w.ttf'));
  }
  await bricolage.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load();
    }
  }
}

/// One way of looking at a component.
class Variant {
  const Variant(this.name, {this.brightness = Brightness.light, this.locale = const Locale('en'), this.textScale = 1.0});
  final String name;
  final Brightness brightness;
  final Locale locale;
  final double textScale;
}

/// Light, dark, Finnish and large text (1.3): every golden shows all four.
const variants = [
  Variant('Light · EN'),
  Variant('Dark · EN', brightness: Brightness.dark),
  Variant('Light · FI', locale: Locale('fi')),
  Variant('Light · EN · text 1.3', textScale: 1.3),
];

/// The app shell used by tests: Malvoya theme, both languages.
Widget testApp(Widget child, {Color brand = MPalette.malva, Brightness brightness = Brightness.light, Locale locale = const Locale('en'), double textScale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildMalvoyaTheme(brand: brand, brightness: brightness),
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('fi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: c!),
    home: Scaffold(body: child),
  );
}

/// Renders [build] in the four [variants] side by side (2 × 2) and compares with
/// `goldens/<name>.png`. [paneHeight] is the height of one pane.
Future<void> expectGolden(WidgetTester tester, String name, Widget Function(BuildContext context) build, {double paneWidth = 380, double paneHeight = 300, Color brand = MPalette.malva}) async {
  // Real file reads cannot finish inside the test's fake-async zone
  await tester.runAsync(loadMalvoyaFonts);
  const gap = 8.0;
  final width = paneWidth * 2 + gap * 3;
  final height = (paneHeight + 28) * 2 + gap * 3;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  Widget pane(Variant v) {
    final theme = buildMalvoyaTheme(brand: brand, brightness: v.brightness);
    return SizedBox(
      width: paneWidth,
      height: paneHeight + 28,
      child: Theme(
        data: theme,
        child: Localizations(
          locale: v.locale,
          delegates: GlobalMaterialLocalizations.delegates,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(v.textScale), disableAnimations: true),
              child: Material(
                color: theme.scaffoldBackgroundColor,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    height: 28,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Text(v.name, textScaler: TextScaler.noScaling, style: MType.caption.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: ScaffoldMessenger(
                      child: Scaffold(
                        backgroundColor: theme.scaffoldBackgroundColor,
                        body: Padding(padding: const EdgeInsets.all(MSpace.lg), child: Builder(builder: build)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    supportedLocales: const [Locale('en'), Locale('fi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: const Key('golden'),
        child: Container(
          color: const Color(0xFF8C8794),
          padding: const EdgeInsets.all(gap),
          child: Wrap(spacing: gap, runSpacing: gap, children: [for (final v in variants) pane(v)]),
        ),
      ),
    ),
  ));
  // Spinners never settle: pump a fixed time instead of pumpAndSettle
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byKey(const Key('golden')), matchesGoldenFile('goldens/$name.png'));
}
