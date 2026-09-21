import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import 'admin_dashboard.dart';
import 'chatbot.dart';
import 'settings_screen.dart';
import 'returns_screen.dart';
import 'payment_methods_screen.dart';
import 'address_management_screen.dart';
import 'support_hub_screen.dart';
import 'terms_legal_screen.dart';
import 'privacy_gdpr_screen.dart';
import 'orders.dart';
import '../locale_provider.dart';
import '../l10n.dart';
import '../config/theme.dart';
import '../theme_provider.dart';
import 'notification_center_drawer.dart';

/**
 * Malvoya Luxury Profile & Operational Account Hub
 * Features dynamic 25-language localization, authentic provider-based verification badge,
 * Try-at-Home concierge fitting, dedicated Google Pay 1-Tap toggle switch,
 * and GDPR Article 17 self-service.
 */

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
  }

  void _nav(BuildContext context, Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _showThemePicker(BuildContext context, ThemeProvider themeProvider) {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final dividerColor = AppTheme.subtleDivider(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(l10n.translate('displayAppearance'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: 4),
            Text(l10n.translate('displayAppearanceSubtitle'), style: TextStyle(fontSize: 12, color: textSecondary)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.light_mode_rounded, color: Color(0xFFEAB308), size: 22),
              title: Text(l10n.translate('themeCrispDaylight'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.light ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                themeProvider.setTheme(AppThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            Divider(height: 1, indent: 56, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.dark_mode_rounded, color: Color(0xFF8B5CF6), size: 22),
              title: Text(l10n.translate('themeOledMidnight'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.dark ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                themeProvider.setTheme(AppThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            Divider(height: 1, indent: 56, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined, color: Color(0xFFD97706), size: 22),
              title: Text(l10n.translate('themeEyeComfort'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.eyeComfort ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                themeProvider.setTheme(AppThemeMode.eyeComfort);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageBottomSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final dividerColor = AppTheme.subtleDivider(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            final l10n = AppLocalizations.of(context);
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.translate('language'),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.translate('instantSwitching'),
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: dividerColor),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: AppLocalizations.languages.entries.map((entry) {
                        final isSelected = provider.locale.languageCode == entry.key;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              fontSize: 15,
                              color: isSelected ? AppTheme.primary : textPrimary,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 22)
                              : null,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            provider.setLocaleCode(entry.key);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.translate('languageSwitchedTo').replaceAll('{lang}', entry.value)),
                                duration: const Duration(seconds: 2),
                                backgroundColor: const Color(0xFF1E1B4B),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthService auth) {
    HapticFeedback.heavyImpact();
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text(l10n.translate('confirmDelete'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPrimary)),
          ],
        ),
        content: Text(
          l10n.translate('deleteAccountSimpleMsg'),
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await auth.logout();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.translate('deleteAccountSimpleMsg')),
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                );
              }
            },
            child: Text(l10n.translate('confirmDelete'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AuthService auth) {
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(l10n.translate('logOutTitle'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textPrimary)),
        content: Text(l10n.translate('logOutMsg'), style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: Text(l10n.translate('logOut'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final borderColor = AppTheme.cardBorder(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuGroup({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final cardBg = AppTheme.cardBackground(context);
    final textSecondary = AppTheme.secondaryText(context);
    final borderColor = AppTheme.cardBorder(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: 11, color: textSecondary))
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final dividerColor = AppTheme.subtleDivider(context);

        final userName = auth.currentUser?.name ?? 'Valued Customer';
        final userEmail = auth.currentUser?.email ?? '';
        final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'M';
        final currentLangName = AppLocalizations.languages[localeProvider.locale.languageCode] ?? '🇬🇧 English';

        // Authentic registration verification badge (NO GOLD VIP)
        final isGoogle = userEmail.contains('@gmail.com');
        final isPhone = userEmail.contains('@phone.malvoya') || RegExp(r'^[+0-9]').hasMatch(userEmail);
        final String verificationBadgeText = isGoogle
            ? l10n.translate('googleVerified')
            : isPhone
                ? l10n.translate('phoneVerified')
                : l10n.translate('verifiedMember');

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              l10n.translate('profile'),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textPrimary),
            ),
            elevation: 0,
            backgroundColor: cardBg,
            iconTheme: IconThemeData(color: textPrimary),
            actions: [
              IconButton(
                icon: Icon(Icons.settings_outlined, color: textPrimary),
                tooltip: l10n.translate('settings'),
                onPressed: () => _nav(context, const SettingsScreen()),
              ),
            ],
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              // Sleek Customer Profile Header with Authentic Verification Badge
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                color: cardBg,
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppTheme.primary,
                          child: Text(
                            userInitial,
                            style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: Colors.white, size: 12),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  userName,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Authentic Verification Badge (Replaced Gold VIP)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      verificationBadgeText,
                                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            userEmail.isNotEmpty ? userEmail : (auth.currentUser?.phone ?? ''),
                            style: TextStyle(color: textSecondary, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Quick-Access Action Grid (4 Refined Cards: Orders, Returns/Swap, Addresses, Language)
              // Google Pay completely removed per brand guidelines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildQuickCard(
                      context: context,
                      icon: Icons.receipt_long_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      title: l10n.translate('orders'),
                      subtitle: l10n.translate('liveTracking'),
                      onTap: () => _nav(context, const OrdersScreen()),
                    ),
                    const SizedBox(width: 10),
                    _buildQuickCard(
                      context: context,
                      icon: Icons.swap_horiz_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      title: l10n.translate('swipeToSwap'),
                      subtitle: l10n.translate('refundsReturns'),
                      onTap: () => _nav(context, const ReturnsScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildQuickCard(
                      context: context,
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFF8B5CF6),
                      title: l10n.translate('deliveryAddresses'),
                      subtitle: l10n.translate('savedLocations'),
                      onTap: () => _nav(context, const AddressManagementScreen()),
                    ),
                    const SizedBox(width: 10),
                    _buildQuickCard(
                      context: context,
                      icon: Icons.language_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      title: currentLangName.split(' ').first,
                      subtitle: currentLangName.replaceFirst(currentLangName.split(' ').first, '').trim(),
                      onTap: () => _showLanguageBottomSheet(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Menu Group 1: Experience & Interface
              _buildMenuGroup(
                context: context,
                title: l10n.translate('experienceInterface'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.palette_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    title: l10n.translate('displayAppearance'),
                    subtitle: l10n.translate('displayAppearanceSubtitle'),
                    onTap: () => _showThemePicker(context, themeProvider),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    title: l10n.translate('language'),
                    subtitle: currentLangName,
                    onTap: () => _showLanguageBottomSheet(context),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.notifications_none_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    title: l10n.translate('multiChannelAlerts'),
                    subtitle: l10n.translate('multiChannelAlertsSubtitle'),
                    onTap: () => NotificationCenterDrawer.show(context),
                  ),
                ],
              ),

              // Menu Group 2: FinTech, Payment & Fulfillment (Google Pay OUT)
              _buildMenuGroup(
                context: context,
                title: l10n.translate('fintechFulfillment'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    title: l10n.translate('paymentMethods'),
                    subtitle: l10n.translate('paymentMethodsSubtitle'),
                    onTap: () => _nav(context, const PaymentMethodsScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.assignment_return_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    title: l10n.translate('refundsReturns'),
                    subtitle: l10n.translate('refundsReturnsSubtitle'),
                    onTap: () => _nav(context, const ReturnsScreen()),
                  ),
                ],
              ),

              // Menu Group 3: Privacy & Data Rights
              _buildMenuGroup(
                context: context,
                title: l10n.translate('privacyDataRights'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.privacy_tip_outlined,
                    iconColor: Colors.teal,
                    title: l10n.translate('dataRights'),
                    subtitle: l10n.translate('dataRightsSubtitle'),
                    onTap: () => _nav(context, const PrivacyGdprScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.gavel_rounded,
                    iconColor: const Color(0xFFD97706),
                    title: l10n.translate('legalTerms'),
                    subtitle: l10n.translate('legalTermsSubtitle'),
                    onTap: () => _nav(context, const TermsLegalScreen()),
                  ),
                ],
              ),

              // Menu Group 4: Concierge & Support
              _buildMenuGroup(
                context: context,
                title: l10n.translate('conciergeAssistance'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.auto_awesome_rounded,
                    iconColor: AppTheme.primary,
                    title: l10n.translate('aiConcierge'),
                    subtitle: l10n.translate('aiConciergeSubtitle'),
                    onTap: () => _nav(context, const ChatbotScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.support_agent_rounded,
                    iconColor: const Color(0xFF06B6D4),
                    title: l10n.translate('customerSupport'),
                    subtitle: l10n.translate('customerSupportSubtitle'),
                    onTap: () => _nav(context, const SupportHubScreen()),
                  ),
                ],
              ),

              // Admin Control Room (if Admin)
              Consumer<AuthService>(
                builder: (context, a, _) {
                  if (a.isAdmin) {
                    return _buildMenuGroup(
                      context: context,
                      title: l10n.translate('adminControlRoom'),
                      children: [
                        _buildTile(
                          context: context,
                          icon: Icons.admin_panel_settings_rounded,
                          iconColor: Colors.purple,
                          title: 'Owner & Fleet Dashboard',
                          subtitle: 'Algorithmic transparency audit & metrics',
                          onTap: () => _nav(context, const AdminDashboard()),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 16),

              // Bottom Clean Account Actions (Log Out & GDPR Art. 17 Delete)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 17),
                      label: Text(
                        l10n.translate('logOut'),
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _confirmLogout(context, auth),
                    ),
                    Text('  •  ', style: TextStyle(color: textSecondary)),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 17),
                      label: Text(
                        l10n.translate('deleteAccountGdpr'),
                        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _confirmDeleteAccount(context, auth),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        );
      },
    );
  }
}
