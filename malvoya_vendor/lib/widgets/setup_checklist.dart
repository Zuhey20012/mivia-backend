import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/haptics.dart';
import '../core/strings.dart';

/// The steps of the setup checklist. The dashboard opens the matching screen for each.
enum SetupStep { details, pin, hours, payouts, product, tax, approval }

/// "Get your store ready": what is still missing before the store can sell, ticked off from the
/// store data the server sends (`GET /stores/my`). Nothing is ticked by hand, and the card is gone
/// once every step is done.
class SetupChecklist extends StatelessWidget {
  final Map<String, dynamic> store;

  /// How many products the store has (null = not known yet, the step stays open).
  final int? productCount;
  final void Function(SetupStep step) onOpen;
  const SetupChecklist({super.key, required this.store, required this.productCount, required this.onOpen});

  static bool _filled(dynamic v) => v != null && '$v'.trim().isNotEmpty;

  /// Each step and whether it is done. Steps the server cannot tell us about (older servers do not
  /// send `taxInfoComplete`) are left out rather than guessed.
  static Map<SetupStep, bool> stepsFor(Map<String, dynamic> store, int? productCount) => {
        SetupStep.details: _filled(store['name']) && _filled(store['description']) && _filled(store['address']) && _filled(store['logoUrl']),
        SetupStep.pin: store['latitude'] is num && store['longitude'] is num,
        SetupStep.hours: store['openingHours'] is Map && (store['openingHours'] as Map).isNotEmpty,
        if (store.containsKey('payoutsEnabled')) SetupStep.payouts: store['payoutsEnabled'] == true,
        SetupStep.product: (productCount ?? 0) > 0,
        if (store.containsKey('taxInfoComplete')) SetupStep.tax: store['taxInfoComplete'] == true,
        SetupStep.approval: store['isVerified'] == true,
      };

  static bool isComplete(Map<String, dynamic> store, int? productCount) => stepsFor(store, productCount).values.every((d) => d);

  (String, String, IconData) _text(BuildContext context, SetupStep s) => switch (s) {
        SetupStep.details => (
            tr(context, 'Store details', 'Kaupan tiedot'),
            tr(context, 'Name, description, address and logo', 'Nimi, kuvaus, osoite ja logo'),
            Icons.storefront_outlined
          ),
        SetupStep.pin => (
            tr(context, 'Map pin', 'Karttamerkki'),
            tr(context, 'Couriers and delivery fees use it', 'Lähetit ja toimitusmaksut käyttävät sitä'),
            Icons.location_on_outlined
          ),
        SetupStep.hours => (
            tr(context, 'Opening hours', 'Aukioloajat'),
            tr(context, 'You are closed automatically outside them', 'Kauppa sulkeutuu niiden ulkopuolella automaattisesti'),
            Icons.schedule_rounded
          ),
        SetupStep.payouts => (
            tr(context, 'Payouts', 'Tilitykset'),
            tr(context, 'Set up Stripe to receive your sales', 'Ota Stripe käyttöön saadaksesi myyntisi'),
            Icons.account_balance_outlined
          ),
        SetupStep.product => (
            tr(context, 'First product', 'Ensimmäinen tuote'),
            tr(context, 'Photos, price and sizes', 'Kuvat, hinta ja koot'),
            Icons.checkroom_rounded
          ),
        SetupStep.tax => (
            tr(context, 'Tax information', 'Verotiedot'),
            tr(context, 'Required from every seller by EU law (DAC7)', 'EU-laki (DAC7) edellyttää jokaiselta myyjältä'),
            Icons.receipt_long_outlined
          ),
        SetupStep.approval => (
            tr(context, 'Approval by Malvoya', 'Malvoyan hyväksyntä'),
            tr(context, 'A person checks your store, then shoppers can see it', 'Ihminen tarkistaa kauppasi, sitten asiakkaat näkevät sen'),
            Icons.verified_outlined
          ),
      };

  @override
  Widget build(BuildContext context) {
    final steps = stepsFor(store, productCount);
    final done = steps.values.where((d) => d).length;
    if (done == steps.length) return const SizedBox.shrink();
    // The first open step the store can do itself is highlighted
    final next = steps.entries.firstWhere((e) => !e.value && e.key != SetupStep.approval, orElse: () => steps.entries.firstWhere((e) => !e.value)).key;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2), border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            Expanded(child: Text(tr(context, 'Get your store ready', 'Valmistele kauppasi'), style: AppTheme.display(size: 18))),
            Text(tr(context, '$done of ${steps.length} done', '$done/${steps.length} valmis'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            label: tr(context, '$done of ${steps.length} setup steps done', '$done/${steps.length} vaihetta valmiina'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: done / steps.length, minHeight: 8, backgroundColor: AppTheme.sand, color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final e in steps.entries) _row(context, e.key, e.value, highlighted: e.key == next),
      ]),
    );
  }

  Widget _row(BuildContext context, SetupStep step, bool isDone, {required bool highlighted}) {
    final (title, subtitle, icon) = _text(context, step);
    // Approval is Malvoya's step: nothing to open
    final tappable = !isDone && step != SetupStep.approval;
    return Semantics(
      button: tappable,
      label: isDone ? tr(context, '$title, done', '$title, valmis') : title,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tappable
            ? () {
                Haptics.select();
                onOpen(step);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? AppTheme.success : (highlighted ? AppTheme.sunshine : AppTheme.sand),
                ),
                child: Icon(isDone ? Icons.check_rounded : icon, size: 19, color: isDone ? Colors.white : AppTheme.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDone ? AppTheme.textSecondary : AppTheme.textPrimary,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      )),
                  if (!isDone) Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.3)),
                ]),
              ),
              if (tappable) const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary) else const SizedBox(width: 24),
            ]),
          ),
        ),
      ),
    );
  }
}
