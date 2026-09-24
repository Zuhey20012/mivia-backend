import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Malvoya never sees, types in or stores card numbers or bank details.
/// Payment details are entered only in Stripe's secure payment sheet at checkout
/// (PCI-DSS is handled by Stripe; 3-D Secure / PSD2 strong authentication is applied by the bank).
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maksutavat / Payment methods')),
      body: const PaymentInfoView(),
    );
  }
}

class PaymentInfoView extends StatelessWidget {
  const PaymentInfoView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final secondary = isDark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);

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
              const Text('Maksat turvallisesti kassalla', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text('You pay securely at checkout', style: TextStyle(fontSize: 15, color: secondary)),
              const SizedBox(height: 12),
              row(Icons.credit_card_rounded, 'Cards, Apple Pay & Google Pay',
                  'Choose how to pay in the secure Stripe payment sheet when you place an order.'),
              row(Icons.lock_outline_rounded, 'We never store your card',
                  'Card and bank details go straight to Stripe (PCI-DSS Level 1). Malvoya never sees them.'),
              row(Icons.verified_user_outlined, 'Strong customer authentication',
                  'Your bank may ask you to confirm the payment (3-D Secure), as required by PSD2.'),
              row(Icons.undo_rounded, 'Refunds',
                  'Refunds always go back to the payment method you used.'),
            ],
          ),
        ),
      ],
    );
  }
}
