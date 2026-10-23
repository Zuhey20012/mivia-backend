import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'helpers.dart';

void main() {
  group('MButton', () {
    testWidgets('loading disables the button and keeps its size', (tester) async {
      var taps = 0;
      Widget build(bool loading) => testApp(Center(child: MButton(label: 'Pay', loading: loading, onPressed: () => taps++)));

      await tester.pumpWidget(build(false));
      final idle = tester.getSize(find.byType(MButton));
      await tester.tap(find.byType(MButton));
      expect(taps, 1);

      await tester.pumpWidget(build(true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(MButton)), idle);
      await tester.tap(find.byType(MButton), warnIfMissed: false);
      expect(taps, 1, reason: 'a loading button ignores taps');
      final node = tester.getSemantics(find.byType(MButton));
      expect(node, containsSemantics(isEnabled: false, isButton: true));
      expect(node.value, 'Working');
    });

    testWidgets('null onPressed is disabled; touch target is at least 48 dp', (tester) async {
      await tester.pumpWidget(testApp(const Center(child: MButton(label: 'Go', onPressed: null, size: MButtonSize.sm))));
      final size = tester.getSize(find.byType(TextButton));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(find.byType(MButton)), containsSemantics(isEnabled: false));
    });

    testWidgets('long Finnish labels wrap at large text instead of overflowing', (tester) async {
      await tester.pumpWidget(testApp(
        const SizedBox(width: 220, child: MButton(label: 'Hyväksy ja jatka maksamaan tilaus', expand: true, onPressed: null)),
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('MSwipeConfirm', () {
    Future<int> slide(WidgetTester tester, double fraction) async {
      var confirmed = 0;
      await tester.pumpWidget(testApp(Center(
        child: SizedBox(width: 360, child: MSwipeConfirm(label: 'Picked up', onConfirmed: () async => confirmed++)),
      )));
      // The knob travels the bar width minus the knob (56) and the border (8)
      const track = 360 - 56 - 8;
      final start = tester.getTopLeft(find.byType(MSwipeConfirm)) + const Offset(30, 32);
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveBy(Offset(track * fraction / 10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return confirmed;
    }

    testWidgets('a short slide snaps back', (tester) async {
      expect(await slide(tester, 0.5), 0);
    });

    testWidgets('a slide past the threshold confirms once', (tester) async {
      expect(MSwipeConfirm.threshold, 0.8);
      expect(await slide(tester, 0.95), 1);
    });

    testWidgets('with a screen reader it is a plain button', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: MSwipeConfirm(label: 'Delivered', onConfirmed: () async => confirmed++),
        ),
      )));
      await tester.tap(find.text('Delivered'));
      expect(confirmed, 1);
    });
  });

  group('MSwatchPicker', () {
    const options = [
      MSwatchOption(id: '1', name: 'Rose 02', color: Color(0xFFC96F7A)),
      MSwatchOption(id: '2', name: 'Berry 03', color: Color(0xFF7A1F3D), soldOut: true),
      MSwatchOption(id: '3', name: 'Nude 04', color: Color(0xFFD9A48C)),
    ];

    testWidgets('tapping a shade selects it and shows its name', (tester) async {
      String? selected;
      await tester.pumpWidget(testApp(StatefulBuilder(
        builder: (context, set) => MSwatchPicker(options: options, selectedId: selected, onChanged: (id) => set(() => selected = id)),
      )));
      expect(find.textContaining('choose one'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Nude 04'));
      await tester.pump();
      expect(selected, '3');
      expect(find.textContaining('Nude 04'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Nude 04')), containsSemantics(isSelected: true));
    });

    testWidgets('a sold-out shade is announced and cannot be chosen', (tester) async {
      String? selected;
      await tester.pumpWidget(testApp(MSwatchPicker(options: options, selectedId: null, onChanged: (id) => selected = id)));
      final soldOut = find.bySemanticsLabel('Berry 03, sold out');
      expect(soldOut, findsOneWidget);
      await tester.tap(soldOut, warnIfMissed: false);
      expect(selected, isNull);
    });

    test('options come from API variants with a shade hex', () {
      final o = MSwatchOption.fromVariant({'id': 7, 'shadeName': 'Coral', 'shadeHex': '#FF7F50', 'inStock': false})!;
      expect(o.id, '7');
      expect(o.color, const Color(0xFFFF7F50));
      expect(o.soldOut, isTrue);
      expect(MSwatchOption.fromVariant({'id': 8, 'size': 'M'}), isNull);
    });
  });

  group('MSizeSelector', () {
    testWidgets('selects available sizes, ignores sold-out ones, opens the size guide', (tester) async {
      String? selected;
      var guide = 0;
      await tester.pumpWidget(testApp(MSizeSelector(
        options: const [MSizeOption(id: 's', label: 'S', soldOut: true), MSizeOption(id: 'm', label: 'M')],
        selectedId: null,
        onChanged: (id) => selected = id,
        onSizeGuide: () => guide++,
      )));
      await tester.tap(find.text('S'), warnIfMissed: false);
      expect(selected, isNull);
      await tester.tap(find.text('M'));
      expect(selected, 'm');
      await tester.tap(find.text('Size guide'));
      expect(guide, 1);
      expect(tester.getSize(find.ancestor(of: find.text('M'), matching: find.byType(InkWell))).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('S, sold out'), findsOneWidget);
    });
  });

  group('showMSheet', () {
    Future<void> open(WidgetTester tester, {required bool transparent}) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showMSheet<void>(
            context,
            transparent: transparent,
            builder: (_) => MSheet(handle: transparent, title: 'Sheet', child: const Text('Body')),
          ),
          child: const Text('Open'),
        ),
      )));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a solid sheet shows the theme drag handle once', (tester) async {
      await open(tester, transparent: false);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.showDragHandle, isTrue);
      expect(find.byType(MSheetHandle), findsNothing);
    });

    testWidgets('a transparent sheet turns the theme handle off and draws its own', (tester) async {
      await open(tester, transparent: true);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.showDragHandle, isFalse);
      expect(sheet.backgroundColor, Colors.transparent);
      expect(find.byType(MSheetHandle), findsOneWidget);
    });
  });

  group('MChip / MFilterBar', () {
    testWidgets('chips toggle and active filters can be removed', (tester) async {
      bool? toggled;
      String? removed;
      var cleared = 0;
      await tester.pumpWidget(testApp(MFilterBar(
        quick: const [MFilterOption(id: 'open', label: 'Open now')],
        onQuickChanged: (id, v) => toggled = v,
        active: const [MFilterOption(id: 'm', label: 'M'), MFilterOption(id: 'black', label: 'Black')],
        onRemove: (id) => removed = id,
        onClearAll: () => cleared++,
        onOpenFilters: () {},
      )));
      await tester.tap(find.text('Open now'));
      expect(toggled, isTrue);
      await tester.tap(find.byTooltip('Remove Black'));
      expect(removed, 'black');
      await tester.tap(find.text('Clear all'));
      expect(cleared, 1);
      expect(find.text('Filters  2'), findsOneWidget);
    });
  });

  group('theme', () {
    test('buttons keep the content-sized minimum, never Size.fromHeight', () {
      for (final brand in [MPalette.malva, MPalette.moss, MPalette.lingon]) {
        final t = buildMalvoyaTheme(brand: brand, brightness: Brightness.light);
        expect(t.filledButtonTheme.style!.minimumSize!.resolve({}), const Size(64, 54));
        expect(t.elevatedButtonTheme.style!.minimumSize!.resolve({}), const Size(64, 54));
        expect(t.outlinedButtonTheme.style!.minimumSize!.resolve({}), const Size(64, 54));
        expect(t.filledButtonTheme.style!.shape!.resolve({}), isA<StadiumBorder>());
        expect(t.colorScheme.primary, brand);
        expect(t.extension<MalvoyaTokens>()!.colors.primary, brand);
        expect(t.pageTransitionsTheme.builders[TargetPlatform.android], isA<PredictiveBackPageTransitionsBuilder>());
        expect(t.bottomSheetTheme.showDragHandle, isTrue);
      }
    });

    test('dark mode lightens the brand and the tool style quiets body text', () {
      final dark = buildMalvoyaTheme(brand: MPalette.malva, brightness: Brightness.dark);
      expect(dark.colorScheme.primary, MalvoyaBrand.malva.dark);
      final tool = buildMalvoyaTheme(brand: MPalette.moss, brightness: Brightness.light, style: MalvoyaThemeStyle.tool);
      expect(tool.textTheme.bodyMedium!.color, MPalette.inkSecondary);
      final shop = buildMalvoyaTheme(brand: MPalette.malva, brightness: Brightness.light);
      expect(shop.textTheme.bodyMedium!.color, MPalette.ink);
      expect(shop.textTheme.bodyMedium!.fontFamily, MFonts.body);
    });

    testWidgets('reduce motion: MMotion.of returns zero', (tester) async {
      late Duration d;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) {
          d = MMotion.of(context, MMotion.base);
          return const SizedBox();
        }),
      ));
      expect(d, Duration.zero);
    });
  });
}
