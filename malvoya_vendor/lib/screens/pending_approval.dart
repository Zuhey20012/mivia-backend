import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../widgets/account_sheet.dart';

/// Welcome for a store account without a store yet (right after registering). Explains the review
/// process; payout details are verified by Stripe, never stored in this app.
class PendingApprovalScreen extends StatelessWidget {
  /// "Set up my store": the home screen then shows the store setup.
  final VoidCallback onStart;
  const PendingApprovalScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final name = auth.currentUser?.name;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl, vertical: MSpace.x3l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: MSpace.md),
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(28)),
                child: const Icon(Icons.storefront_rounded, size: 40, color: AppTheme.primary),
              ),
              const SizedBox(height: 28),
              Text(
                name == null || name.isEmpty ? tr(context, 'Welcome', 'Tervetuloa') : tr(context, 'Welcome, $name', 'Tervetuloa, $name'),
                textAlign: TextAlign.center,
                style: AppTheme.display(size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                tr(context, 'Set up your store now. Shoppers can see it once our team has reviewed it.',
                    'Perusta kauppasi nyt. Asiakkaat näkevät sen, kun tiimimme on tarkistanut sen.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: MTextSize.bodyL, height: 1.4, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: MSpace.x3l),
              _step(Icons.edit_note_rounded, tr(context, 'Create your store', 'Perusta kauppasi'),
                  tr(context, 'Name, category, address and your first products.', 'Nimi, kategoria, osoite ja ensimmäiset tuotteesi.')),
              _step(Icons.verified_user_outlined, tr(context, 'Review', 'Tarkistus'),
                  tr(context, 'We check your store details (the Y-tunnus for businesses) and contact you if we need anything.',
                      'Tarkistamme kauppasi tiedot (yrityksiltä Y-tunnuksen) ja otamme yhteyttä, jos tarvitsemme jotain.')),
              _step(Icons.account_balance_outlined, tr(context, 'Payouts and fees', 'Tilitykset ja maksut'),
                  tr(context,
                      'Set up payouts in Store → Payouts; Stripe checks your identity and bank details on its own pages. Malvoya keeps a commission on each sale (10 % unless agreed otherwise) and pays the rest 15 days after delivery.',
                      'Ota tilitykset käyttöön kohdassa Kauppa → Tilitykset; Stripe tarkistaa henkilöllisyytesi ja pankkitietosi omilla sivuillaan. Malvoya pidättää jokaisesta myynnistä provision (10 %, ellei toisin sovita) ja tilittää loput 15 päivää toimituksen jälkeen.')),
              _step(Icons.info_outline_rounded, tr(context, 'Good to know', 'Hyvä tietää'),
                  tr(context,
                      'Malvoya is just starting in Finland. There are very few shoppers and couriers so far, so orders may be rare at first. We will not promise sales we cannot guarantee.',
                      'Malvoya on vasta aloittamassa Suomessa. Asiakkaita ja kuriireja on toistaiseksi hyvin vähän, joten tilauksia voi aluksi tulla harvoin. Emme lupaa myyntiä, jota emme voi taata.')),
              const SizedBox(height: MSpace.xxl),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: onStart,
                  child: Text(tr(context, 'Set up my store', 'Perusta kauppani')),
                ),
              ),
              const SizedBox(height: MSpace.md),
              TextButton(
                onPressed: () => showAccountSheet(context),
                child: Text(tr(context, 'Help, sign out or delete account', 'Apua, uloskirjautuminen tai tilin poisto'), style: const TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: MTextSize.bodyM, height: 1.35, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
