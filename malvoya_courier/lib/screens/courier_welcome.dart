import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'login.dart';
import 'register.dart';

class CourierWelcomeScreen extends StatelessWidget {
  const CourierWelcomeScreen({super.key});

  void _showLanguagePicker(BuildContext context) {
    showMSheet(context, builder: (ctx) {
        final currentCode = Localizations.localeOf(context).languageCode;
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: MSpace.md, bottom: MSpace.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.xl, vertical: MSpace.md),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      AppLocalizations.of(context).translate('selectLanguage'),
                      style: const TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800),
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
      }, transparent: true, isScrollControlled: true, useSafeArea: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentCode = Localizations.localeOf(context).languageCode;
    final currentLangName = AppLocalizations.languages[currentCode] ?? 'English';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
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
              child: const Icon(Icons.delivery_dining_rounded, color: AppTheme.onPrimary, size: 18),
            ),
            const SizedBox(width: MSpace.sm),
            Text(
              AppLocalizations.of(context).translate('malvoyaCourier'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: MTextSize.title,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MSpace.lg),
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
                      style: const TextStyle(fontSize: MTextSize.bodyM),
                    ),
                    const SizedBox(width: MSpace.xs),
                    Text(
                      currentCode.toUpperCase(),
                      style: const TextStyle(
                        fontSize: MTextSize.caption,
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
                padding: const EdgeInsets.symmetric(horizontal: MSpace.xl, vertical: MSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Malvoya Express Hero Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(MRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MSpace.xs),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.translate('courierBadge'),
                                  style: const TextStyle(
                                    color: AppTheme.onPrimary,
                                    fontSize: MTextSize.caption,
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
                              color: AppTheme.onPrimary,
                              fontSize: MTextSize.displayM,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: MSpace.sm),
                          Text(
                            l10n.translate('courierWelcomeSubtitle'),
                            style: TextStyle(
                              color: AppTheme.onPrimary.withValues(alpha: 0.92),
                              fontSize: MTextSize.bodyM,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: MSpace.lg),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.sm),
                            decoration: BoxDecoration(
                              color: MPalette.night.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(MRadius.sm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.payments_rounded, color: AppTheme.sunshine, size: 18),
                                const SizedBox(width: MSpace.sm),
                                Text(
                                  l10n.translate('courierRate'),
                                  style: const TextStyle(
                                    color: AppTheme.onPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: MTextSize.label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: MSpace.lg),

                    // Honest note: there are few stores and customers yet
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(MRadius.md)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, color: MPalette.amberInk, size: 22),
                        const SizedBox(width: MSpace.md),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(l10n.translate('earlyTitle'), style: const TextStyle(fontSize: MTextSize.bodyM, fontWeight: FontWeight.w800, color: MPalette.amberInk)),
                            const SizedBox(height: 3),
                            Text(l10n.translate('earlyDesc'), style: const TextStyle(fontSize: MTextSize.caption, color: MPalette.amberInk, height: 1.35)),
                          ]),
                        ),
                      ]),
                    ),

                    const SizedBox(height: MSpace.xxl),

                    // How delivering with Malvoya works
                    Text(
                      l10n.translate('whyDeliver'),
                      style: const TextStyle(
                        fontSize: MTextSize.title,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildPillarCard(
                      icon: Icons.access_time_filled_rounded,
                      iconColor: MPalette.malva,
                      title: l10n.translate('perkFlexible'),
                      description: l10n.translate('perkFlexibleDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: MPalette.green,
                      title: l10n.translate('perkEarnings'),
                      description: l10n.translate('perkEarningsDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.storefront_rounded,
                      iconColor: MPalette.amber,
                      title: l10n.translate('perkRetail'),
                      description: l10n.translate('perkRetailDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.pedal_bike_rounded,
                      iconColor: MPalette.moss,
                      title: l10n.translate('perkVehicle'),
                      description: l10n.translate('perkVehicleDesc'),
                    ),
                    const SizedBox(height: 10),
                    _buildPillarCard(
                      icon: Icons.badge_outlined,
                      iconColor: AppTheme.primary,
                      title: l10n.translate('perkEntrepreneur'),
                      description: l10n.translate('perkEntrepreneurDesc'),
                    ),

                    const SizedBox(height: MSpace.xl),
                  ],
                ),
              ),
            ),

            // Pinned Bottom Actions
            Container(
              padding: const EdgeInsets.fromLTRB(MSpace.xl, 14, MSpace.xl, MSpace.xl),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: MPalette.night.withValues(alpha: 0.06),
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
                        foregroundColor: AppTheme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(MRadius.md),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rocket_launch_rounded, size: 20),
                          const SizedBox(width: MSpace.sm),
                          Text(
                            l10n.translate('applyToDeliver'),
                            style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w800),
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
                        side: BorderSide(color: AppTheme.divider, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(MRadius.md),
                        ),
                      ),
                      child: Text(
                        l10n.translate('alreadyPartnerSignIn'),
                        style: const TextStyle(fontSize: MTextSize.bodyM, fontWeight: FontWeight.w700),
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
        color: MPalette.birch,
        borderRadius: BorderRadius.circular(MRadius.md),
        border: Border.all(color: MPalette.night.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MRadius.sm),
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
                    fontSize: MTextSize.bodyM,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: MTextSize.caption,
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
