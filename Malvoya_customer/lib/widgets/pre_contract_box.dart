import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// "Before you pay": who sells to you and what your rights are (Consumer Protection Act ch. 6 §9,
/// Directive 2011/83 Art. 6): the seller's name and trader status, a business seller's address and
/// contact details, the right of withdrawal (or that a private seller gives none), the cost of a
/// return, and links to the Terms and the withdrawal form.
///
/// [seller] is the store as the API describes it (`GET /stores/:id`, merged with any seller details
/// the quote carries). Missing fields are simply not shown; nothing is made up.
class PreContractBox extends StatelessWidget {
  final Map<String, dynamic>? seller;

  /// The cart's store name, used while the store is still loading.
  final String? fallbackName;

  /// Reserve & collect: the right of withdrawal counts from collection, not delivery.
  final bool pickup;

  const PreContractBox({super.key, required this.seller, this.fallbackName, this.pickup = false});

  static String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final s = seller ?? const <String, dynamic>{};
    final muted = AppTheme.secondaryText(context);
    final ink = AppTheme.primaryText(context);
    final type = _text(s['sellerType']);
    final isBusiness = type == 'BUSINESS';
    final isPrivate = type == 'PRIVATE';
    final name = _text(s['name']) ?? fallbackName;
    // A business's registered name when it differs from the shop's name
    final legalName = isBusiness ? _text(s['legalName']) : null;
    final businessId = isBusiness ? _text(s['businessId']) : null;
    // A business seller's address and contact; for a private seller only the town
    final address = isBusiness ? _text(s['address']) : null;
    final city = isPrivate ? _text(s['city']) : null;
    final phone = isBusiness ? _text(s['phone']) : null;
    final email = isBusiness ? _text(s['email']) : null;

    // Server wording wins when the API sends it ({en, fi} or a string)
    final withdrawal = localized(context, s['withdrawal']) ??
        (isBusiness
            ? (pickup
                ? tr(context, 'You have a 14-day right of withdrawal, counted from the day you collect the order. Start a return in the app (Profile → Returns) or use the withdrawal form.',
                    'Sinulla on 14 päivän peruuttamisoikeus, joka lasketaan tilauksen noutopäivästä. Aloita palautus sovelluksessa (Profiili → Palautukset) tai käytä peruuttamislomaketta.')
                : tr(context, 'You have a 14-day right of withdrawal, counted from the day you receive the order. Start a return in the app (Profile → Returns) or use the withdrawal form.',
                    'Sinulla on 14 päivän peruuttamisoikeus, joka lasketaan tilauksen vastaanottopäivästä. Aloita palautus sovelluksessa (Profiili → Palautukset) tai käytä peruuttamislomaketta.'))
            : isPrivate
                ? tr(context, 'Private seller: no statutory right of withdrawal. Consumer protection law does not apply to purchases between private people.',
                    'Yksityinen myyjä: lakisääteistä peruuttamisoikeutta ei ole. Kuluttajansuojalaki ei koske yksityishenkilöiden välisiä kauppoja.')
                : null);
    final returnCost = localized(context, s['returnCost']) ??
        (isBusiness
            ? tr(context, 'If you withdraw, you pay the cost of sending the item back unless the seller has agreed otherwise.',
                'Jos peruutat ostoksen, maksat tuotteen palautuskulut, ellei myyjän kanssa ole toisin sovittu.')
            : null);

    Widget line(IconData icon, String text, {bool strong = false, String? semantics}) => Padding(
          padding: const EdgeInsets.only(bottom: MSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  semanticsLabel: semantics,
                  style: TextStyle(
                    fontSize: strong ? MTextSize.bodyM : MTextSize.label,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                    color: strong ? ink : muted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'Before you pay', 'Ennen kuin maksat'), style: AppTheme.display(context, size: 18)),
          const SizedBox(height: MSpace.md),
          if (name != null) line(Icons.storefront_rounded, '${tr(context, 'Seller', 'Myyjä')}: $name', strong: true),
          if (legalName != null && legalName != name) line(Icons.badge_outlined, legalName),
          if (isBusiness)
            line(Icons.verified_outlined,
                [tr(context, 'Business seller', 'Yritysmyyjä'), if (businessId != null) 'Y-tunnus $businessId'].join(' · ')),
          if (isPrivate) line(Icons.person_outline_rounded, tr(context, 'Private seller (not a business)', 'Yksityinen myyjä (ei yritys)')),
          if (address != null) line(Icons.place_outlined, address),
          if (city != null) line(Icons.place_outlined, city),
          if (phone != null) line(Icons.call_outlined, phone, semantics: '${tr(context, 'Phone', 'Puhelin')} $phone'),
          if (email != null) line(Icons.mail_outline_rounded, email, semantics: '${tr(context, 'Email', 'Sähköposti')} $email'),
          if (withdrawal != null) ...[
            const SizedBox(height: MSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MSpace.md),
              decoration: BoxDecoration(
                color: isPrivate
                    ? AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine)
                    : AppTheme.pastel(context, AppTheme.mint, AppTheme.moss),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(withdrawal, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: ink, height: 1.4)),
            ),
            const SizedBox(height: MSpace.sm),
          ],
          if (returnCost != null) line(Icons.assignment_return_outlined, returnCost),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => openLegal('terms'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(tr(context, 'Terms of Service', 'Käyttöehdot')),
              ),
              if (!isPrivate)
                TextButton.icon(
                  onPressed: () => openLegal('withdrawal-form'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: Text(tr(context, 'Withdrawal form', 'Peruuttamislomake')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
