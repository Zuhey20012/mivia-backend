import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/strings.dart';

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
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(fontSize: 14, height: 1.35, color: secondary)),
                  ],
                ),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'You pay at checkout', 'Maksat kassalla'), style: AppTheme.display(context, size: 20)),
              const SizedBox(height: 4),
              Text(tr(context, 'Nothing is saved in the app.', 'Sovellukseen ei tallenneta mitään.'), style: TextStyle(fontSize: 15, color: secondary)),
              const SizedBox(height: 12),
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
