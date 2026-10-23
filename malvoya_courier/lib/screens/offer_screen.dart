import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../widgets/mini_route.dart';

/// What the full-screen offer shows, worked out by the dashboard from the server's offer and job
/// list. Pay and its explanation are exactly the server's; nothing here is estimated.
class OfferView {
  final int orderId;
  final String pay;
  final int tipCents;
  final String? explanation;
  final String? window;
  final String? age;
  final String storeName;
  final String? storeAddress;
  final int? items;
  final ({double lat, double lng})? me;
  final ({double lat, double lng})? store;
  final ({double lat, double lng})? dropOff;
  final String? toStore;
  final String? drop;
  const OfferView({
    required this.orderId,
    required this.pay,
    required this.tipCents,
    required this.storeName,
    this.explanation,
    this.window,
    this.age,
    this.storeAddress,
    this.items,
    this.me,
    this.store,
    this.dropOff,
    this.toStore,
    this.drop,
  });
}

/// A new job, full screen: pay with its explanation, a sketch of the route, distances and one big
/// Accept button within thumb reach. "Not now" just closes it — ignoring a job never counts against
/// the courier. Returns true when the courier tapped Accept.
///
/// The server gives offers no expiry (the first courier to accept gets the job), so there is no
/// countdown; the screen closes by itself when the job is taken or withdrawn ([openOffers]).
Future<bool> showOfferScreen(BuildContext context, {required OfferView offer, required ValueNotifier<Set<int>> openOffers}) async {
  final accepted = await Navigator.of(context).push<bool>(PageRouteBuilder<bool>(
    fullscreenDialog: true,
    transitionDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => _OfferScreen(offer: offer, openOffers: openOffers),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
  return accepted == true;
}

class _OfferScreen extends StatefulWidget {
  final OfferView offer;
  final ValueNotifier<Set<int>> openOffers;
  const _OfferScreen({required this.offer, required this.openOffers});

  @override
  State<_OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<_OfferScreen> {
  OfferView get o => widget.offer;

  @override
  void initState() {
    super.initState();
    widget.openOffers.addListener(_onOffersChanged);
  }

  @override
  void dispose() {
    widget.openOffers.removeListener(_onOffersChanged);
    super.dispose();
  }

  void _onOffersChanged() {
    if (mounted && !widget.openOffers.value.contains(o.orderId)) Navigator.of(context).maybePop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.xs, MSpace.xs, MSpace.lg, 0),
            child: Row(children: [
              IconButton(
                tooltip: tr(context, 'Not now', 'Ei nyt'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(14)),
                child: Text(tr(context, 'New job', 'Uusi keikka'), style: const TextStyle(color: AppTheme.onPrimary, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.sm, MSpace.xl, MSpace.lg), children: [
              Text(tr(context, 'Your pay for this job', 'Palkkiosi tästä keikasta'), style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
                Text(o.pay, style: AppTheme.display(size: 48)),
                if (o.tipCents > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(MRadius.sm)),
                    child: Text('${tr(context, 'incl. tip', 'sis. tipin')} ${euro(context, o.tipCents)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.label)),
                  ),
              ]),
              if (o.explanation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(o.explanation!, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: MTextSize.label)),
                ),
              if (o.window != null) ...[
                const SizedBox(height: MSpace.md),
                Container(
                  padding: const EdgeInsets.fromLTRB(MSpace.md, 10, MSpace.md, 10),
                  decoration: BoxDecoration(color: AppTheme.lilac, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, size: 18, color: AppTheme.malva),
                    const SizedBox(width: MSpace.sm),
                    Expanded(child: Text('${tr(context, 'Scheduled', 'Ajastettu')} · ${o.window}', style: const TextStyle(color: AppTheme.malva, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ],
              const SizedBox(height: MSpace.lg),
              if (o.store != null) ...[
                MiniRoute(me: o.me, store: o.store!, dropOff: o.dropOff, toStoreText: o.toStore, dropText: o.drop, height: 150),
                MiniRouteLegend(showMe: o.me != null),
                const SizedBox(height: MSpace.md),
              ],
              Row(children: [
                _tile(Icons.storefront_outlined, tr(context, 'You → shop', 'Sinä → kauppa'), o.toStore ?? '–'),
                const SizedBox(width: MSpace.sm),
                _tile(Icons.location_on_outlined, tr(context, 'Shop → drop-off area', 'Kauppa → toimitusalue'), o.drop == null ? '–' : '~${o.drop}'),
              ]),
              const SizedBox(height: 14),
              Text('${tr(context, 'Pick up', 'Nouto')}: ${o.storeName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title)),
              if (o.storeAddress != null) Text(o.storeAddress!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.bodyL)),
              if (o.items != null)
                Padding(
                  padding: const EdgeInsets.only(top: MSpace.xs),
                  child: Text(o.items == 1 ? tr(context, '1 item', '1 tuote') : tr(context, '${o.items} items', '${o.items} tuotetta'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 10),
              Text(
                [
                  if (o.age != null) o.age!,
                  tr(context, 'Straight-line distances. The first courier to accept gets the job; the exact address is shown after you accept.',
                      'Linnuntie-etäisyydet. Keikan saa ensimmäinen hyväksyvä lähetti; tarkka osoite näytetään hyväksynnän jälkeen.'),
                ].join(' · '),
                style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.35),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, MSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 66), textStyle: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800)),
                onPressed: () {
                  Haptics.medium();
                  Navigator.of(context).pop(true);
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(tr(context, 'Accept job', 'Ota keikka')),
              ),
              const SizedBox(height: 6),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(64, 48), foregroundColor: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr(context, 'Not now — it stays in Jobs', 'Ei nyt — se jää Keikat-listaan')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(MSpace.md, 10, MSpace.md, 10),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: MSpace.xs),
              Expanded(child: Text(label, maxLines: 2, style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppTheme.display(size: 22))),
          ]),
        ),
      );
}
