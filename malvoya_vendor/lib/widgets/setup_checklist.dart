import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/haptics.dart';
import '../core/strings.dart';

/// The steps of the setup checklist. The dashboard opens the matching screen for each.
enum SetupStep { details, pin, hours, payouts, product, tax, approval }

/// "Get your store ready" worked out in the app from `GET /stores/my`: used only with servers that
/// have no `GET /stores/my/onboarding` (before API 2.11; see [OnboardingChecklist]). Nothing is ticked
/// by hand, and the card is gone once every step is done.
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
    return _ChecklistCard(
      title: tr(context, 'Get your store ready', 'Valmistele kauppasi'),
      done: done,
      total: steps.length,
      children: [
        for (final e in steps.entries) _row(context, e.key, e.value, highlighted: e.key == next),
      ],
    );
  }

  Widget _row(BuildContext context, SetupStep step, bool isDone, {required bool highlighted}) {
    final (title, subtitle, icon) = _text(context, step);
    return ChecklistRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      done: isDone,
      highlighted: highlighted,
      // Approval is Malvoya's step: nothing to open
      onTap: !isDone && step != SetupStep.approval ? () => onOpen(step) : null,
    );
  }
}

/// The checklist from the server (API 2.11, `GET /stores/my/onboarding`): each step says whether it
/// is done and what the app should open (`action`). The server also tells the Malvoya team once
/// everything but approval is done; approval itself is always a person's decision.
class OnboardingChecklist extends StatelessWidget {
  /// The onboarding answer: `{steps, percent, approved, readyForApproval}`.
  final Map<String, dynamic> onboarding;

  /// `GET /stores/my` (for the registered name of the business check).
  final Map<String, dynamic>? store;

  /// Opens the screen for a step's action (`edit_store`, `set_hours`, `accept_agreement`, …).
  final void Function(String action) onAction;
  const OnboardingChecklist({super.key, required this.onboarding, required this.store, required this.onAction});

  /// The steps to show: private sellers skip the business check.
  static List<Map> stepsOf(Map<String, dynamic> o) =>
      ((o['steps'] as List?) ?? const []).whereType<Map>().where((s) => s['skipped'] != true).toList();

  /// Every step done and the store approved: the card is not shown.
  static bool isComplete(Map<String, dynamic> o) => o['approved'] == true && stepsOf(o).every((s) => s['done'] == true);

  /// Actions that open something in the app (`wait` and `none` do not).
  static const actionable = {
    'edit_store', 'create_store', 'set_location', 'set_hours', 'connect_payouts', 'add_product', 'tax_info', 'accept_agreement', 'edit_business_id',
  };

  String _title(BuildContext context, Map step) {
    final t = step['title'];
    if (t is Map) {
      final v = t[isFinnish(context) ? 'fi' : 'en'] ?? t['en'];
      if (v is String && v.isNotEmpty) return v;
    }
    return '${step['key']}';
  }

  (String?, IconData) _about(BuildContext context, String key) => switch (key) {
        'details' => (tr(context, 'Name, address and contact details', 'Nimi, osoite ja yhteystiedot'), Icons.storefront_outlined),
        'map_pin' => (tr(context, 'Couriers and delivery fees use it', 'Lähetit ja toimitusmaksut käyttävät sitä'), Icons.location_on_outlined),
        'hours' => (tr(context, 'You are closed automatically outside them', 'Kauppa sulkeutuu niiden ulkopuolella automaattisesti'), Icons.schedule_rounded),
        'payouts' => (tr(context, 'Set up Stripe to receive your sales', 'Ota Stripe käyttöön saadaksesi myyntisi'), Icons.account_balance_outlined),
        'first_product' => (tr(context, 'Photos, price and sizes', 'Kuvat, hinta ja koot'), Icons.checkroom_rounded),
        'tax_info' => (tr(context, 'Required from every seller by EU law (DAC7)', 'EU-laki (DAC7) edellyttää jokaiselta myyjältä'), Icons.receipt_long_outlined),
        'agreement' => (tr(context, 'Read and accept them to take orders', 'Lue ja hyväksy ne, jotta voit ottaa vastaan tilauksia'), Icons.gavel_rounded),
        'business_check' => (null, Icons.fact_check_outlined),
        _ => (null, Icons.radio_button_unchecked_rounded),
      };

  @override
  Widget build(BuildContext context) {
    if (isComplete(onboarding)) return const SizedBox.shrink();
    final steps = stepsOf(onboarding);
    final approved = onboarding['approved'] == true;
    final total = steps.length + 1; // + Malvoya's approval
    final done = steps.where((s) => s['done'] == true).length + (approved ? 1 : 0);
    final next = steps.where((s) => s['done'] != true && actionable.contains(s['action'])).firstOrNull;
    final ready = onboarding['readyForApproval'] == true && !approved;
    return _ChecklistCard(
      title: approved ? tr(context, 'Still to do', 'Vielä tehtävää') : tr(context, 'Get your store ready', 'Valmistele kauppasi'),
      done: done,
      total: total,
      children: [
        for (final s in steps) s['key'] == 'business_check' ? _businessRow(context, s) : _row(context, s, highlighted: identical(s, next)),
        ChecklistRow(
          title: tr(context, 'Approval by Malvoya', 'Malvoyan hyväksyntä'),
          subtitle: tr(context, 'A person checks your store, then shoppers can see it', 'Ihminen tarkistaa kauppasi, sitten asiakkaat näkevät sen'),
          icon: Icons.verified_outlined,
          done: approved,
          highlighted: ready,
        ),
        if (ready)
          Container(
            margin: const EdgeInsets.fromLTRB(0, 4, 8, 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.hourglass_top_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(context,
                      'Everything is done on your side. The Malvoya team reviews your store next, and you will get a notification and an email when it is approved.',
                      'Kaikki on valmista sinun osaltasi. Seuraavaksi Malvoyan tiimi tarkistaa kauppasi, ja saat ilmoituksen ja sähköpostin, kun se on hyväksytty.'),
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, Map s, {required bool highlighted}) {
    final key = '${s['key']}';
    final action = '${s['action'] ?? ''}';
    final done = s['done'] == true;
    final (subtitle, icon) = _about(context, key);
    return ChecklistRow(
      title: _title(context, s),
      subtitle: subtitle,
      icon: icon,
      done: done,
      highlighted: highlighted,
      onTap: !done && actionable.contains(action) ? () => onAction(action) : null,
    );
  }

  /// The Y-tunnus lookup in the Finnish Trade Register (PRH): verified, a different registered name
  /// (Malvoya's team looks at it), not found or not active (the store corrects it), or still checking.
  Widget _businessRow(BuildContext context, Map s) {
    final title = _title(context, s);
    final status = s['status'] as String?;
    final check = store?['businessCheck'] is Map ? store!['businessCheck'] as Map : const {};
    final registeredName = '${check['registeredName'] ?? ''}'.trim();
    switch (status) {
      case 'matched':
        return ChecklistRow(
          title: title,
          subtitle: tr(context, 'Business ID verified in the Finnish Trade Register', 'Y-tunnus tarkistettu kaupparekisteristä'),
          icon: Icons.fact_check_outlined,
          done: true,
          showSubtitleWhenDone: true,
        );
      case 'name_mismatch':
        return ChecklistRow(
          title: title,
          subtitle: registeredName.isNotEmpty
              ? tr(context, 'The Trade Register has this Y-tunnus as “$registeredName”. The Malvoya team will check that it matches your store.',
                  'Kaupparekisterissä tällä Y-tunnuksella on nimi ”$registeredName”. Malvoyan tiimi tarkistaa, että se vastaa kauppaasi.')
              : tr(context, 'The name in the Trade Register differs from your store name. The Malvoya team will check it.',
                  'Kaupparekisterin nimi poikkeaa kauppasi nimestä. Malvoyan tiimi tarkistaa asian.'),
          icon: Icons.info_outline_rounded,
          done: s['done'] == true,
          attention: true,
          trailing: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () {
                Haptics.select();
                onAction('edit_business_id');
              },
              child: Text(tr(context, 'Edit', 'Muokkaa')),
            ),
          ),
        );
      case 'not_found':
      case 'inactive':
        return ChecklistRow(
          title: title,
          subtitle: status == 'not_found'
              ? tr(context, 'This Y-tunnus was not found in the Finnish Trade Register. Check it and correct it if needed.',
                  'Tätä Y-tunnusta ei löytynyt kaupparekisteristä. Tarkista se ja korjaa tarvittaessa.')
              : tr(context, 'The Trade Register shows this company as no longer active. Check your Y-tunnus.',
                  'Kaupparekisterin mukaan yritys ei ole enää toiminnassa. Tarkista Y-tunnuksesi.'),
          icon: Icons.error_outline_rounded,
          done: false,
          highlighted: true,
          onTap: () => onAction('edit_business_id'),
        );
      default:
        // `unavailable` (the register did not answer) or not checked yet
        return ChecklistRow(
          title: title,
          subtitle: tr(context, 'Checking…', 'Tarkistetaan…'),
          icon: Icons.fact_check_outlined,
          done: false,
          trailing: const Padding(
            padding: EdgeInsets.only(left: 8, right: 4),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
    }
  }
}

/// The card around a checklist: title, "3 of 8 done" and a progress bar.
class _ChecklistCard extends StatelessWidget {
  final String title;
  final int done;
  final int total;
  final List<Widget> children;
  const _ChecklistCard({required this.title, required this.done, required this.total, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2), border: Border.all(color: AppTheme.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Expanded(child: Text(title, style: AppTheme.display(size: 18))),
              Text(tr(context, '$done of $total done', '$done/$total valmis'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              label: tr(context, '$done of $total setup steps done', '$done/$total vaihetta valmiina'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8, backgroundColor: AppTheme.sand, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ]),
      );
}

/// One step: a round icon (a tick when done), the title, an explanation while open, and a chevron
/// when it opens something. [trailing] replaces the chevron (e.g. a spinner or an Edit button).
class ChecklistRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool done;
  final bool highlighted;
  final VoidCallback? onTap;

  /// Keeps the subtitle visible and the title un-struck once done (e.g. "verified in the register").
  final bool showSubtitleWhenDone;

  /// Needs a look without being undone: a sunny icon instead of the tick.
  final bool attention;
  final Widget? trailing;

  const ChecklistRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.done,
    this.highlighted = false,
    this.onTap,
    this.showSubtitleWhenDone = false,
    this.attention = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final ticked = done && !attention;
    final struck = ticked && !showSubtitleWhenDone;
    final showSubtitle = subtitle != null && !struck;
    final circle = attention ? AppTheme.sunshine : (ticked ? AppTheme.success : (highlighted ? AppTheme.sunshine : AppTheme.sand));
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: circle),
            child: Icon(ticked ? Icons.check_rounded : icon, size: 19, color: ticked ? Colors.white : AppTheme.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: [ticked ? tr(context, '$title, done', '$title, valmis') : title, if (showSubtitle) subtitle!].join('. '),
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: struck ? AppTheme.textSecondary : AppTheme.textPrimary,
                      decoration: struck ? TextDecoration.lineThrough : null,
                    )),
                if (showSubtitle) Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.3)),
              ]),
            ),
          ),
          trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary) : const SizedBox(width: 24)),
        ]),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Haptics.select();
          onTap!();
        },
        child: content,
      ),
    );
  }
}
