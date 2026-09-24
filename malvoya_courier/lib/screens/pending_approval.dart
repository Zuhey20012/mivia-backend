import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Shown until an admin approves the courier on the server.
/// Identity and right-to-work documents are checked by the Malvoya team, never collected in this app.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final approved = await Provider.of<AuthService>(context, listen: false).refreshApprovalStatus();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still under review. We will let you know as soon as you are approved.')),
      );
    }
  }

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
                child: const Icon(Icons.hourglass_top_rounded, size: 40, color: AppTheme.primary),
              ),
              const SizedBox(height: 28),
              Text(
                'Hi $name',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your courier account is being reviewed.\nTilisi on tarkistettavana.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              _step(Icons.badge_outlined, 'Identity & right to work',
                  'Our team will contact you to verify your ID and your right to work in Finland.'),
              _step(Icons.description_outlined, 'Courier agreement',
                  'You will receive the courier agreement to review and sign before your first delivery.'),
              _step(Icons.check_circle_outline, 'Start delivering',
                  'Once approved, go online and accept the deliveries you want.'),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _checking ? null : _checkStatus,
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Check status'),
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
