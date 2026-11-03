import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../widgets/onboarding_art.dart';

/// Whether this phone has seen the short intro. Loaded once at start-up (a local flag).
class Onboarding {
  const Onboarding._();
  static const _key = 'onboarding_seen_v1';
  static final seen = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      seen.value = prefs.getBool(_key) ?? false;
    } catch (_) {
      seen.value = true; // never block the app on a storage problem
    }
  }

  static Future<void> markSeen() async {
    seen.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }
}

/// Three short screens on first launch: local shops, Drops, delivery or collect. Skippable.
/// It asks for nothing: no permissions, no account (location and notifications are asked later,
/// when they are needed).
///
/// Each page has a small motion illustration ([OnboardingArt]) driven by one ambient loop and the
/// swipe position (parallax). With "Remove animations" the drawings stay still.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  // The one ambient loop behind all three drawings (the bike's lap; floats run three times faster)
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _loop.stop();
      _loop.value = 0.3; // a still pose, the bike in front of the pin
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _finish() {
    Haptics.medium();
    Onboarding.markSeen();
  }

  void _next(int count) {
    if (_page >= count - 1) return _finish();
    Haptics.selection();
    if (reduceMotion(context)) {
      _pages.jumpToPage(_page + 1);
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 320), curve: MMotion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final p = context.mPastels;
    final slides = [
      (
        OnboardingScene.shops,
        p.lilac,
        tr(context, 'Fashion and beauty from shops near you', 'Muotia ja kauneutta läheltä'),
        tr(context, 'Clothes, cosmetics and finds from local boutiques and second-hand sellers in your town.',
            'Vaatteita, kosmetiikkaa ja löytöjä kotikaupunkisi putiikeista ja kirpputorimyyjiltä.'),
      ),
      (
        OnboardingScene.drops,
        c.sunshineSoft,
        tr(context, 'See it move in Drops', 'Katso liikkeessä Dropeissa'),
        tr(context, 'Short videos from the shops themselves. Like something? Add it to your bag right from the video.',
            'Lyhyitä videoita suoraan kaupoilta. Pidätkö näkemästäsi? Lisää tuote kassiin suoraan videolta.'),
      ),
      (
        OnboardingScene.delivery,
        p.mint,
        tr(context, 'Delivered today, or collect it', 'Kotiin tänään tai nouda itse'),
        tr(context, 'A local courier brings your order, and you can follow it live. Or reserve it and pick it up at the shop.',
            'Paikallinen kuriiri tuo tilauksesi, ja voit seurata sitä reaaliajassa. Tai varaa tuote ja nouda se kaupasta.'),
      ),
    ];
    final last = _page == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MSpace.sm, MSpace.xs, MSpace.sm, 0),
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: MMotion.of(context, MMotion.base),
                  child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(64, kMinTouchTarget)),
                    onPressed: last ? null : _finish,
                    child: Text(tr(context, 'Skip', 'Ohita')),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: slides.length,
                onPageChanged: (i) {
                  Haptics.selection();
                  setState(() => _page = i);
                },
                itemBuilder: (context, i) {
                  final (scene, tile, title, body) = slides[i];
                  return LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: MSpace.x3l - 4),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: MSpace.xl),
                              decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(MRadius.lg + 8)),
                              clipBehavior: Clip.antiAlias,
                              child: OnboardingArt(scene: scene, index: i, loop: _loop, pages: _pages),
                            ),
                            const SizedBox(height: MSpace.x3l),
                            Semantics(
                              header: true,
                              child: Text(title, textAlign: TextAlign.center, style: AppTheme.display(context, size: MTextSize.displayM + 2)),
                            ),
                            const SizedBox(height: MSpace.md),
                            Text(body, textAlign: TextAlign.center, style: MType.bodyL.copyWith(color: c.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.md, MSpace.xxl, MSpace.xl),
              child: Column(
                children: [
                  Semantics(
                    label: tr(context, 'Page ${_page + 1} of ${slides.length}', 'Sivu ${_page + 1}/${slides.length}'),
                    excludeSemantics: true,
                    child: _StretchDots(pages: _pages, count: slides.length),
                  ),
                  const SizedBox(height: MSpace.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: () => _next(slides.length),
                      child: AnimatedSwitcher(
                        duration: MMotion.of(context, MMotion.fast),
                        child: Text(
                          last ? tr(context, 'Start shopping', 'Aloita ostokset') : tr(context, 'Next', 'Seuraava'),
                          key: ValueKey(last),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page dots that stretch as you swipe: the dot of the current page grows into a sunshine pill,
/// following the finger rather than jumping.
class _StretchDots extends StatelessWidget {
  final PageController pages;
  final int count;
  const _StretchDots({required this.pages, required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return AnimatedBuilder(
      animation: pages,
      builder: (context, _) {
        final page = pages.hasClients && pages.position.hasContentDimensions ? (pages.page ?? 0) : 0.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: MSpace.xs),
                width: 8 + 18 * (1 - (page - i).abs()).clamp(0.0, 1.0),
                height: 8,
                decoration: BoxDecoration(
                  color: Color.lerp(c.outlineStrong.withValues(alpha: 0.35), c.sunshine, (1 - (page - i).abs()).clamp(0.0, 1.0)),
                  borderRadius: MRadius.pillRadius,
                ),
              ),
          ],
        );
      },
    );
  }
}
