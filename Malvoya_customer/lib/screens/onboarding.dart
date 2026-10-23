import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

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
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
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
    _pages.nextPage(duration: Duration(milliseconds: reduceMotion(context) ? 1 : 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      (
        MArtKind.store,
        AppTheme.lilac,
        AppTheme.primary,
        tr(context, 'Fashion from shops near you', 'Muotia läheisistä kaupoista'),
        tr(context, 'Clothes, shoes and finds from local boutiques and second-hand sellers in your town.',
            'Vaatteita, kenkiä ja löytöjä kotikaupunkisi putiikeista ja kirpputorimyyjiltä.'),
      ),
      (
        MArtKind.drops,
        AppTheme.sunshineLight,
        AppTheme.sunshine,
        tr(context, 'See it move in Drops', 'Katso liikkeessä Dropeissa'),
        tr(context, 'Short videos from the shops themselves. Like something? Add it to your bag right from the video.',
            'Lyhyitä videoita suoraan kaupoilta. Pidätkö näkemästäsi? Lisää tuote kassiin suoraan videolta.'),
      ),
      (
        MArtKind.delivery,
        AppTheme.mint,
        AppTheme.moss,
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
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
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
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (art, tile, hue, title, body) = slides[i];
                  return LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              decoration: BoxDecoration(
                                color: AppTheme.pastel(context, tile, hue),
                                borderRadius: BorderRadius.circular(AppTheme.radiusLg + 8),
                              ),
                              child: Center(child: MEmptyArt(art, width: 220)),
                            ),
                            const SizedBox(height: MSpace.x3l),
                            Text(title, textAlign: TextAlign.center, style: AppTheme.display(context, size: 28)),
                            const SizedBox(height: MSpace.md),
                            Text(
                              body,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: MTextSize.bodyL, height: 1.45, color: AppTheme.secondaryText(context)),
                            ),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        slides.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: MSpace.xs),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page ? AppTheme.sunshine : AppTheme.cardBorder(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: MSpace.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: () => _next(slides.length),
                      child: Text(last ? tr(context, 'Get started', 'Aloitetaan') : tr(context, 'Next', 'Seuraava')),
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
