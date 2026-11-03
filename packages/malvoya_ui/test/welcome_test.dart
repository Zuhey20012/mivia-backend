// The welcome experience: the animated intro, the Thread M refresh indicator, greetings and the
// small signature animations.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'helpers.dart';

/// The intro over a tiny "app"; [finished] flips when the intro has faded out.
Widget _intro({Future<void>? ready, required VoidCallback onFinished, bool still = false}) {
  final intro = MalvoyaIntro(
    brand: MalvoyaBrand.malva,
    appName: 'Malvoya',
    tagline: (context) => tr(context, 'Local fashion and beauty', 'Lähikauppojen muoti ja kauneus'),
    ready: ready,
    onFinished: onFinished,
    builder: (_) => const Directionality(textDirection: TextDirection.ltr, child: Center(child: Text('APP'))),
  );
  if (!still) return intro;
  return Builder(
    builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: intro),
  );
}

Finder get _introMark => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is IntroMarkPainter);

/// Pumps 16 ms frames until [done] (at most [max]); returns how long that took.
Future<Duration> _pumpUntil(WidgetTester tester, bool Function() done, {Duration max = const Duration(seconds: 3)}) async {
  var elapsed = Duration.zero;
  const frame = Duration(milliseconds: 16);
  while (!done() && elapsed < max) {
    await tester.pump(frame);
    elapsed += frame;
  }
  return elapsed;
}

void main() {
  group('MalvoyaIntro', () {
    setUp(MalvoyaIntro.debugReset);

    testWidgets('plays and hands over to the app within 1.4 s', (tester) async {
      var finished = false;
      await tester.pumpWidget(_intro(onFinished: () => finished = true));
      expect(_introMark, findsOneWidget);
      expect(find.text('APP'), findsNothing);
      final took = await _pumpUntil(tester, () => finished);
      expect(finished, isTrue);
      expect(took, lessThanOrEqualTo(const Duration(milliseconds: 1400)));
      expect(MalvoyaIntro.duration + MalvoyaIntro.handOff, lessThanOrEqualTo(const Duration(milliseconds: 1400)));
      expect(find.text('APP'), findsOneWidget);
      expect(_introMark, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the name and tagline fade in with the mark', (tester) async {
      await tester.pumpWidget(_intro(onFinished: () {}));
      await tester.pump(const Duration(milliseconds: 1150));
      expect(find.text('Malvoya'), findsOneWidget);
      // Finnish until the saved language is read (tests have no saved language)
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'Local fashion and beauty' || w.data == 'Lähikauppojen muoti ja kauneus')), findsOneWidget);
      await _pumpUntil(tester, () => !tester.hasRunningAnimations);
    });

    testWidgets('a tap skips the rest of the animation', (tester) async {
      var finished = false;
      await tester.pumpWidget(_intro(onFinished: () => finished = true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_introMark, warnIfMissed: false);
      final took = await _pumpUntil(tester, () => finished);
      expect(finished, isTrue);
      expect(took, lessThan(const Duration(milliseconds: 500)), reason: 'well before the 1.2 s the animation would take');
      expect(find.text('APP'), findsOneWidget);
    });

    testWidgets('with "Remove animations" the app shows at once, nothing animates', (tester) async {
      var finished = false;
      await tester.pumpWidget(_intro(still: true, onFinished: () => finished = true));
      expect(finished, isTrue);
      expect(find.text('APP'), findsOneWidget);
      expect(_introMark, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('waits for the start-up work, then opens the app', (tester) async {
      final work = Completer<void>();
      var finished = false;
      await tester.pumpWidget(_intro(ready: work.future, onFinished: () => finished = true));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('APP'), findsNothing, reason: 'the services are still starting');
      expect(_introMark, findsOneWidget);
      work.complete();
      final took = await _pumpUntil(tester, () => finished);
      expect(finished, isTrue);
      expect(took, lessThan(const Duration(milliseconds: 500)));
      expect(find.text('APP'), findsOneWidget);
    });

    testWidgets('a failed start-up step still opens the app', (tester) async {
      final work = Completer<void>();
      var finished = false;
      await tester.pumpWidget(_intro(ready: work.future, onFinished: () => finished = true));
      work.completeError(StateError('offline'));
      await _pumpUntil(tester, () => finished);
      expect(tester.takeException(), isA<StateError>());
      expect(finished, isTrue);
    });

    testWidgets('plays once per process: a second intro skips straight to its last frame', (tester) async {
      await tester.pumpWidget(_intro(onFinished: () {}));
      await _pumpUntil(tester, () => !tester.hasRunningAnimations);
      expect(MalvoyaIntro.played, isTrue);
      var finished = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_intro(onFinished: () => finished = true));
      final took = await _pumpUntil(tester, () => finished);
      expect(finished, isTrue);
      expect(took, lessThan(const Duration(milliseconds: 500)));
    });
  });
  group('MRefreshIndicator', () {
    Finder mark() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is RefreshMarkPainter);

    Future<void> pullAndRefresh(WidgetTester tester, {bool still = false}) async {
      final done = Completer<void>();
      var calls = 0;
      Widget list = MRefreshIndicator(
        onRefresh: () {
          calls++;
          return done.future;
        },
        child: ListView(children: [for (var i = 0; i < 30; i++) SizedBox(height: 48, child: Text('Row $i'))]),
      );
      if (still) {
        final inner = list;
        list = Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: inner));
      }
      await tester.pumpWidget(testApp(list));
      expect(mark(), findsNothing);
      await tester.fling(find.text('Row 0'), const Offset(0, 400), 1200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, 1);
      expect(mark(), findsOneWidget, reason: 'the Thread M runs while refreshing');
      if (still) {
        final painter = tester.widget<CustomPaint>(mark()).painter! as RefreshMarkPainter;
        expect(painter.still, isTrue);
        expect(painter.spin.isAnimating, isFalse);
      } else {
        final painter = tester.widget<CustomPaint>(mark()).painter! as RefreshMarkPainter;
        expect(painter.spin.isAnimating, isTrue);
      }
      done.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(mark(), findsNothing, reason: 'gone once the refresh is done');
    }

    testWidgets('a pull refreshes and shows the running M', (tester) => pullAndRefresh(tester));

    testWidgets('with "Remove animations" the M stays still', (tester) => pullAndRefresh(tester, still: true));

    testWidgets('the painter draws partly while pulling', (tester) async {
      final pull = ValueNotifier<double>(0.5);
      final painter = RefreshMarkPainter(pull: pull, spin: const AlwaysStoppedAnimation(0), refreshing: false, still: false, color: MPalette.malva);
      await tester.pumpWidget(Center(child: CustomPaint(size: const Size.square(24), painter: painter)));
      expect(tester.takeException(), isNull);
      pull.value = 1;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('greetings', () {
    testWidgets('time of day, in both languages', (tester) async {
      late BuildContext en, fi;
      await tester.pumpWidget(testApp(Builder(builder: (c) {
        en = c;
        return const SizedBox();
      })));
      final enCtx = en;
      expect(mGreeting(enCtx, now: DateTime(2026, 1, 1, 7)), 'Good morning');
      expect(mGreeting(enCtx, now: DateTime(2026, 1, 1, 13)), 'Good afternoon');
      expect(mGreeting(enCtx, now: DateTime(2026, 1, 1, 21)), 'Good evening');
      expect(mGreeting(enCtx, now: DateTime(2026, 1, 1, 2)), 'Good evening');
      await tester.pumpWidget(testApp(Builder(builder: (c) {
        fi = c;
        return const SizedBox();
      }), locale: const Locale('fi')));
      final fiCtx = fi;
      expect(mGreeting(fiCtx, now: DateTime(2026, 1, 1, 7)), 'Huomenta');
      expect(mGreeting(fiCtx, now: DateTime(2026, 1, 1, 13)), 'Päivää');
      expect(mGreeting(fiCtx, now: DateTime(2026, 1, 1, 21)), 'Iltaa');
      expect(mGreeting(fiCtx, now: DateTime(2026, 1, 1, 7), formal: true), 'Hyvää huomenta');
    });

    test('first names', () {
      expect(firstNameOf('Aino  Virtanen'), 'Aino');
      expect(firstNameOf('  '), isNull);
      expect(firstNameOf(null), isNull);
    });
  });

  group('entrances', () {
    setUp(MOnce.debugReset);

    testWidgets('MRiseIn and MStaggerIn play once per session', (tester) async {
      Widget page() => testApp(Column(children: [
            const MRiseIn(onceKey: 'hello', child: Text('Hei')),
            MStaggerIn(onceKey: 'tiles', count: 3, child: Row(children: [for (var i = 0; i < 3; i++) MStaggerItem(index: i, child: Text('Tile $i'))])),
          ]));
      await tester.pumpWidget(page());
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Tile 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      expect(tester.hasRunningAnimations, isFalse, reason: 'already played in this session');
    });

    testWidgets('nothing moves with "Remove animations"', (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const Column(children: [
            MRiseIn(child: Text('Hei')),
            MStatusPill(label: 'Avoinna', live: true),
            MSuccessCheck(),
          ]),
        ),
      )));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the status pill breathes only while live', (tester) async {
      await tester.pumpWidget(testApp(const MStatusPill(label: 'Tauolla')));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(testApp(const MStatusPill(label: 'Avoinna', live: true)));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.bySemanticsLabel('Avoinna'), findsOneWidget);
    });

    testWidgets('the success check finishes and the toast goes away', (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(onPressed: () => showMSuccessCheck(context, 'Tilaus hyväksytty'), child: const Text('go')),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tilaus hyväksytty'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Tilaus hyväksytty'), findsNothing);
    });

    testWidgets('the celebration opens once and closes', (tester) async {
      await tester.pumpWidget(testApp(Builder(
        builder: (context) => TextButton(
          onPressed: () => showMCelebration(context, title: 'Ensimmäinen myyntisi!', message: 'Tästä se alkaa!', action: 'Mennään!'),
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Ensimmäinen myyntisi!'), findsOneWidget);
      await tester.tap(find.text('Mennään!'));
      await tester.pumpAndSettle();
      expect(find.text('Ensimmäinen myyntisi!'), findsNothing);
    });
  });
}
