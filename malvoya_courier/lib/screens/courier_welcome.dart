import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'login.dart';
import 'register.dart';

class CourierWelcomeScreen extends StatelessWidget {
  const CourierWelcomeScreen({super.key});

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentCode = Localizations.localeOf(context).languageCode;
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      AppLocalizations.of(context).translate('selectLanguage'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: AppLocalizations.languages.length,
                  itemBuilder: (ctx, i) {
                    final code = AppLocalizations.languages.keys.elementAt(i);
                    final name = AppLocalizations.languages[code]!;
                    final isSelected = code == currentCode;
                    return ListTile(
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary)
                          : null,
                      onTap: () {
                        Provider.of<LocaleProvider>(context, listen: false).setLocale(Locale(code));
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentCode = Localizations.localeOf(context).languageCode;
    final currentLangName = AppLocalizations.languages[currentCode] ?? 'English';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).translate('malvoyaCourier'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () => _showLanguagePicker(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Text(
                      currentLangName.split(' ').first,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      currentCode.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppTheme.primaryDark),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Malvoya Express Hero Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B35), Color(0xFFFF8E53), Color(0xFFE0521C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('⚡️', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.translate('courierBadge'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.translate('courierWelcomeTitle'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('courierWelcomeSubtitle'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.payments_rounded, color: Colors.amberAccent, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.translate('courierRate'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Malvoya Value Pillars
                    Text(
                      l10n.translate('whyDeliver'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildPillarCard(
                      icon: Icons.access_time_filled_rounded,
                      iconColor: const Color(0xFF6C54EC),
                      title: l10n.translate('perkFlexible'),
                      description: l10n.translate('perkFlexibleDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFF2DC653),
                      title: l10n.translate('perkEarnings'),
                      description: l10n.translate('perkEarningsDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.bolt_rounded,
                      iconColor: const Color(0xFFFF9F1C),
                      title: l10n.translate('perkRetail'),
                      description: l10n.translate('perkRetailDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.pedal_bike_rounded,
                      iconColor: const Color(0xFF0077B6),
                      title: l10n.translate('perkVehicle'),
                      description: l10n.translate('perkVehicleDesc'),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Pinned Bottom Actions
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Primary: Apply to Deliver
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rocket_launch_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            l10n.translate('applyToDeliver'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Secondary: Sign In
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        l10n.translate('alreadyPartnerSignIn'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillarCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F7F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
