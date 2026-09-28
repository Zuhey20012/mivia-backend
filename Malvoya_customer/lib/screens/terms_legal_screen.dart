import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';

/// Terms, privacy policy and the rules for sellers and couriers — always the current version
/// from Malvoya's server.
class TermsLegalScreen extends StatelessWidget {
  const TermsLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final docs = [
      ('terms', Icons.gavel_rounded, tr(context, 'Terms of Service', 'Käyttöehdot'), tr(context, 'Buying, delivery, returns and complaints', 'Ostaminen, toimitus, palautukset ja valitukset')),
      ('privacy', Icons.privacy_tip_outlined, tr(context, 'Privacy Policy', 'Tietosuojaseloste'), tr(context, 'What data we use and your rights', 'Mitä tietoja käytämme ja oikeutesi')),
      ('sellers', Icons.storefront_outlined, tr(context, 'Seller Terms', 'Myyjän ehdot'), tr(context, 'Rules for stores on Malvoya', 'Säännöt Malvoyan kaupoille')),
      ('couriers', Icons.pedal_bike_rounded, tr(context, 'Courier Agreement', 'Lähettisopimus'), tr(context, 'Terms for independent couriers', 'Ehdot itsenäisille lähettäjille')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Legal', 'Juridiset tiedot'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final d in docs)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(d.$2, color: AppTheme.primary),
                title: Text(d.$3, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(d.$4),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => openLegal(d.$1),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            tr(context,
                'Consumer disputes: you can contact the Consumer Advisory Service (kkv.fi) and take the matter to the Consumer Disputes Board (kuluttajariita.fi).',
                'Kuluttajariidat: voit ottaa yhteyttä kuluttajaneuvontaan (kkv.fi) ja viedä asian kuluttajariitalautakuntaan (kuluttajariita.fi).'),
            style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
