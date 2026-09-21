import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Shown to VENDOR and COURIER users who registered but aren't yet approved.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final isVendor = auth.currentUser?.role == 'VENDOR';
    final name = auth.currentUser?.name?.split(' ').first ?? 'there';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated waiting illustration
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF8E7), Color(0xFFFFEBB0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(Icons.hourglass_empty_rounded, size: 60, color: Color(0xFFFFB800)),
              ),
              const SizedBox(height: 32),
              Text(
                'Hi $name! 👋',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                isVendor
                    ? 'Your vendor account is under review'
                    : 'Your courier application is under review',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                isVendor
                    ? 'Our team reviews all vendor applications within 24–48 hours to ensure quality on our platform. We\'ll send you an email once your store is approved and ready to go!'
                    : 'Our team reviews courier applications within 24–48 hours. Once approved, you\'ll be able to start accepting deliveries and earning money right away!',
                style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Status steps
              _buildStatusStep(
                icon: Icons.check_circle_rounded,
                color: AppTheme.success,
                title: 'Application submitted',
                subtitle: 'Your details have been received',
                done: true,
              ),
              _buildStatusStep(
                icon: Icons.manage_search_rounded,
                color: const Color(0xFFFFB800),
                title: 'Under review',
                subtitle: 'Our team is reviewing your account',
                done: false,
                isActive: true,
              ),
              _buildStatusStep(
                icon: Icons.rocket_launch_outlined,
                color: Colors.grey.shade300,
                title: isVendor ? 'Store goes live' : 'Start delivering',
                subtitle: isVendor ? 'Your store will be published' : 'You\'ll receive your first orders',
                done: false,
              ),

              const SizedBox(height: 48),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.mail_outline_rounded, color: AppTheme.primary, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Check your email at\n${auth.currentUser?.email ?? ''}',
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStep({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool done,
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: done ? color.withValues(alpha: 0.15) : (isActive ? color.withValues(alpha: 0.12) : Colors.grey.shade100),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: done || isActive ? color : Colors.grey.shade400),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: done || isActive ? AppTheme.textPrimary : Colors.grey.shade400)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: done || isActive ? AppTheme.textSecondary : Colors.grey.shade400)),
              ],
            ),
          ),
          if (isActive)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFFFB800)))),
        ],
      ),
    );
  }
}
