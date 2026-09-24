import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'vendor_dashboard.dart';

/// Shown right after a vendor registers. Explains the review process; business and payout
/// details are verified by the Malvoya team and a payment provider, never stored in this app.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final name = auth.currentUser?.name ?? 'there';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(28)),
                child: const Icon(Icons.storefront_rounded, size: 40, color: AppTheme.primary),
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome, $name',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 10),
              const Text(
                'Set up your store now. It becomes visible to customers once our team has reviewed it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              _step(Icons.edit_note_rounded, 'Create your store', 'Name, category, address and your first products.'),
              _step(Icons.verified_user_outlined, 'Review',
                  'We check your business details (Y-tunnus or identity for private sellers) and contact you if we need anything.'),
              _step(Icons.account_balance_outlined, 'Payouts',
                  'Payout details are collected securely by our payment provider during review — never typed into this app.'),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const VendorDashboard()),
                  ),
                  child: const Text('Set up my store'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => auth.logout(),
                child: const Text('Sign out', style: TextStyle(color: AppTheme.textSecondary)),
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
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 14, height: 1.35, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
