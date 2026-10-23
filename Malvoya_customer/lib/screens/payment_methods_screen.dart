import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';

/// Malvoya never sees, types in or stores card numbers or bank details.
/// Payment details are entered only in Stripe's secure payment sheet at checkout
/// (PCI-DSS is handled by Stripe; 3-D Secure / PSD2 strong authentication is applied by the bank).
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Paying', 'Maksaminen'))),
      body: const PaymentInfoView(),
    );
  }
}

class PaymentInfoView extends StatelessWidget {
  const PaymentInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    final cardColor = AppTheme.cardBackground(context);
    final secondary = AppTheme.secondaryText(context);

    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(fontSize: MTextSize.bodyM, height: 1.35, color: secondary)),
                  ],
                ),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(MSpace.xl),
      children: [
        Container(
          padding: const EdgeInsets.all(MSpace.xl),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'You pay at checkout', 'Maksat kassalla'), style: AppTheme.display(context, size: 20)),
              const SizedBox(height: MSpace.xs),
              Text(tr(context, 'Nothing is saved in the app.', 'Sovellukseen ei tallenneta mitään.'), style: TextStyle(fontSize: MTextSize.bodyL, color: secondary)),
              const SizedBox(height: MSpace.md),
              row(Icons.credit_card_rounded, tr(context, 'Card or Google Pay', 'Kortti tai Google Pay'),
                  tr(context, 'You choose how to pay in Stripe\'s payment sheet when you place an order.',
                      'Valitset maksutavan Stripen maksuikkunassa, kun teet tilauksen.')),
              row(Icons.lock_outline_rounded, tr(context, 'Malvoya never sees your card', 'Malvoya ei näe korttiasi'),
                  tr(context, 'Card details go straight to Stripe, our payment provider. Malvoya never sees or stores them.',
                      'Korttitiedot menevät suoraan maksunvälittäjällemme Stripelle. Malvoya ei näe eikä tallenna niitä.')),
              row(Icons.verified_user_outlined, tr(context, 'Strong customer authentication', 'Vahva tunnistautuminen'),
                  tr(context, 'Your bank may ask you to confirm the payment (3-D Secure), as EU rules (PSD2) require.',
                      'Pankkisi voi pyytää vahvistamaan maksun (3-D Secure), kuten EU:n säännöt (PSD2) edellyttävät.')),
              row(Icons.undo_rounded, tr(context, 'Refunds', 'Hyvitykset'),
                  tr(context, 'Refunds go back to the payment method you used.', 'Hyvitykset palautetaan käyttämällesi maksutavalle.')),
            ],
          ),
        ),
      ],
    );
  }
}
