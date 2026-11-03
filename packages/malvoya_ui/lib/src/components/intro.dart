import 'dart:async';
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/type.dart';
import 'brand_mark.dart';

/// The animated welcome that follows the native splash on a cold start.
///
/// On the splash's own colour (the app's brand, so nothing flashes) the Thread M draws itself as
/// one stroke, the sunshine pin dot drops in with a soft bounce, and the app name and a short
/// tagline fade in: [duration] in all, then a [handOff] fade to the app (≤ 1.4 s together).
///
/// It never delays real work: start the app's set-up before `runApp` and pass it as [ready]. The
/// app ([builder]) is built as soon as both the intro and [ready] are done. A tap skips the rest of
/// the animation; with "Remove animations" the final frame shows at once and the hand-off is
/// instant. It plays once per process (a cold start), never on resume.
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   final ready = initServices(); // runs while the intro plays
///   runApp(MalvoyaIntro(
///     brand: MalvoyaBrand.malva,
///     appName: 'Malvoya',
///     tagline: (context) => tr(context, 'Local fashion and beauty', 'Lähikauppojen muoti ja kauneus'),
///     ready: ready,
///     builder: (_) => const MalvoyaApp(),
///   ));
/// }
/// ```
class MalvoyaIntro extends StatefulWidget {
  /// The intro for [brand], then [builder].
  const MalvoyaIntro({
    super.key,
    required this.brand,
    required this.appName,
    required this.tagline,
    required this.builder,
    this.ready,
    this.followSystemLanguage = true,
    this.onFinished,
    this.playOnce = true,
  });

  /// The app's brand; its colour is the background (the native splash colour).
  final MalvoyaBrand brand;

  /// "Malvoya", "Malvoya Store", …
  final String appName;

  /// The short tagline, written with `tr(context, en, fi)`.
  final String Function(BuildContext context) tagline;

  /// The app's start-up work; the app is shown once it has finished (errors do not hold it up).
  final Future<void>? ready;

  /// The app, built once the intro and [ready] are both done.
  final WidgetBuilder builder;

  /// Use the phone's language for the tagline when no language was saved yet (the customer app
  /// does; the store and courier apps start in Finnish).
  final bool followSystemLanguage;

  /// Called once the intro has faded out.
  final VoidCallback? onFinished;

  /// Play only on the first intro of the process (a cold start); later ones show the last frame at
  /// once. The gallery turns this off to replay it.
  final bool playOnce;

  /// The animation itself (stroke, dot, words).
  static const duration = Duration(milliseconds: 1200);

  /// The fade from the intro to the app.
  static const handOff = Duration(milliseconds: 150);

  /// The mark's size on screen.
  static const markSize = 112.0;

  static bool _played = false;

  /// True once an intro has played in this process (a later one shows its last frame at once).
  static bool get played => _played;

  /// Lets a test play the intro again.
  @visibleForTesting
  static void debugReset() => _played = false;

  @override
  State<MalvoyaIntro> createState() => _MalvoyaIntroState();
}

class _MalvoyaIntroState extends State<MalvoyaIntro> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: MalvoyaIntro.duration);
  late final AnimationController _out = AnimationController(vsync: this, duration: MalvoyaIntro.handOff);
  late final Animation<double> _words = CurvedAnimation(parent: _intro, curve: const Interval(0.72, 1, curve: MMotion.emphasised));
  late final Animation<Offset> _wordsRise = Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(_words);
  late final Animation<double> _fadeOut = ReverseAnimation(_out);

  String _code = AppLanguage.code;
  bool _ready = false;
  bool _introDone = false;
  bool _gone = false;
  bool _still = false;
  bool _started = false;
  bool _inSetup = false;

  /// setState, except while the first build is being set up (that build follows anyway).
  void _update(VoidCallback fn) => _inSetup || !mounted ? fn() : setState(fn);

  @override
  void initState() {
    super.initState();
    _resolveLanguage();
    final ready = widget.ready;
    if (ready == null) {
      _ready = true;
    } else {
      ready.then((_) {}, onError: (Object e, StackTrace s) {
        // Each service reports its own failures; the app still opens
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'malvoya_ui', context: ErrorDescription('during app start-up')));
      }).whenComplete(() {
        if (!mounted) return;
        _ready = true;
        _maybeLeave();
      });
    }
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _introDone = true;
        _maybeLeave();
      }
    });
    _out.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _update(() => _gone = true);
        widget.onFinished?.call();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = reduceMotion(context);
    _inSetup = true;
    if (_still || (widget.playOnce && MalvoyaIntro._played)) {
      _intro.value = 1; // the status listener sees "completed"
    } else {
      _intro.forward();
    }
    _inSetup = false;
    MalvoyaIntro._played = true;
  }

  /// The saved language (or the phone's), read while the mark is drawing, well before the tagline.
  Future<void> _resolveLanguage() async {
    var code = await LocaleProvider.savedCode();
    if (code == null && widget.followSystemLanguage) {
      final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      if (AppLanguage.supportedCodes.contains(system)) code = system;
    }
    code ??= 'fi';
    if (mounted && code != _code) setState(() => _code = code!);
  }

  void _skip() {
    if (_intro.isAnimating) _intro.value = 1;
  }

  void _maybeLeave() {
    if (!_ready || !_introDone || _out.isAnimating || _out.isCompleted || !mounted) return;
    _update(() {}); // builds the app under the intro
    if (_still) {
      _out.value = 1;
    } else {
      // Fade on the frame after the app's first one, so its first build never eats the fade
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _out.forward();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _out.dispose();
    super.dispose();
  }

  Widget _layer(BuildContext context) {
    final onBrand = MPalette.birch;
    return Localizations(
      locale: Locale(_code),
      delegates: const [DefaultWidgetsLocalizations.delegate],
      child: Builder(builder: (context) {
        final tagline = widget.tagline(context);
        return Semantics(
          label: '${widget.appName}. $tagline',
          onTap: _introDone ? null : _skip,
          onTapHint: _introDone ? null : tr(context, 'Skip the intro', 'Ohita esittely'),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: ColoredBox(
              color: widget.brand.color,
              child: Stack(fit: StackFit.expand, children: [
                // The mark sits exactly in the middle, where the native splash had it
                Center(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: const Size.square(MalvoyaIntro.markSize),
                      painter: IntroMarkPainter(progress: _intro, color: onBrand, dot: MPalette.sunshine),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(top: MalvoyaIntro.markSize + MSpace.x4l + MSpace.x4l),
                    child: FadeTransition(
                      opacity: _words,
                      child: SlideTransition(
                        position: _wordsRise,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: MSpace.x3l),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(widget.appName, textAlign: TextAlign.center, style: MType.displayM.copyWith(color: onBrand)),
                            const SizedBox(height: MSpace.xs),
                            Text(tagline, textAlign: TextAlign.center, style: MType.bodyL.copyWith(color: onBrand.withValues(alpha: 0.88))),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showApp = _ready && _introDone;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(fit: StackFit.expand, children: [
        if (showApp) KeyedSubtree(key: const ValueKey('malvoya-app'), child: Builder(builder: widget.builder)),
        if (!_gone)
          KeyedSubtree(
            key: const ValueKey('malvoya-intro'),
            child: IgnorePointer(
              ignoring: showApp,
              child: FadeTransition(opacity: _fadeOut, child: _layer(context)),
            ),
          ),
      ]),
    );
  }
}

/// Paints the intro's Thread M at [progress] (0–1 over [MalvoyaIntro.duration]): the thread is
/// drawn over the first 64 % (≈ 0.8 s), the pin dot drops in from 54 % to 84 %.
class IntroMarkPainter extends CustomPainter {
  /// Repaints with [progress] (no rebuilds while it runs).
  IntroMarkPainter({required this.progress, required this.color, required this.dot}) : super(repaint: progress);

  /// The intro's timeline.
  final Animation<double> progress;

  /// The thread's colour.
  final Color color;

  /// The pin dot's colour (sunshine).
  final Color dot;

  static const _stroke = Interval(0, 0.64, curve: Curves.easeInOutCubic);
  static const _drop = Interval(0.54, 0.84, curve: Curves.easeOutBack);

  PathMetric? _metric;
  double _metricSize = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final t = progress.value;
    if (_metric == null || _metricSize != w) {
      _metric = threadMPath(w).computeMetrics().first;
      _metricSize = w;
    }
    final metric = _metric!;
    final drawn = _stroke.transform(t.clamp(0, 1));
    if (drawn > 0) {
      canvas.drawPath(metric.extractPath(0, metric.length * drawn), threadMStroke(w, color));
    }
    if (t > _drop.begin) {
      final d = _drop.transform(t.clamp(0, 1));
      final target = threadMDotCenter(w);
      // Falls from above the M's right leg and settles with a little overshoot
      final y = target.dy - (1 - d) * w * 0.55;
      final opacity = ((t - _drop.begin) / 0.08).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(target.dx, y), threadMDotRadius(w), Paint()..color = dot.withValues(alpha: dot.a * opacity));
    }
  }

  @override
  bool shouldRepaint(IntroMarkPainter old) => old.progress != progress || old.color != color || old.dot != dot;
}
