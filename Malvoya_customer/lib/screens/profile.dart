import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import 'chatbot.dart';
import 'settings_screen.dart';
import 'returns_screen.dart';
import 'payment_methods_screen.dart';
import 'address_management_screen.dart';
import 'support_hub_screen.dart';
import 'terms_legal_screen.dart';
import 'privacy_gdpr_screen.dart';
import 'orders.dart';
import 'favorites_screen.dart';
import 'invite_screen.dart';
import 'blocked_users_screen.dart';
import 'agreements_screen.dart';
import '../core/agreements.dart';
import '../widgets/agreement_sheet.dart';
import '../widgets/forgot_password_sheet.dart';
import '../core/sign_in.dart';
import '../l10n.dart';
import '../config/theme.dart';
import '../theme_provider.dart';
import 'notification_center_drawer.dart';

/// Profile: orders, favourites, addresses, language, appearance, privacy and help.

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// The invite programme, when the server offers it (null hides "Invite a friend").
  Map<String, dynamic>? _referral;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReferral();
      // Fresh agreement state for the "Terms update" banner
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.isAuthenticated) Agreements.instance.load(auth);
    });
  }

  /// A soft notice about an announced, not yet effective version: never blocks anything.
  Widget _agreementBanner(BuildContext context) {
    return ListenableBuilder(
      listenable: Agreements.instance,
      builder: (context, _) {
        final item = Agreements.instance.pendingNotice;
        if (item == null) return const SizedBox.shrink();
        final date = agreementDate(context, item['pendingEffectiveAt']);
        final privacy = item['doc'] == 'privacy';
        final text = privacy
            ? tr(context, 'Privacy Policy update on $date: review', 'Tietosuojaseloste päivittyy $date: tutustu')
            : tr(context, 'Terms update on $date: review', 'Käyttöehdot päivittyvät $date: tutustu');
        return Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, 14),
          child: Material(
            color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: () {
                Haptics.light();
                showAgreementSheet(context, Agreements.instance.promptFor(item, pending: true));
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.md),
                  child: Row(
                    children: [
                      Icon(Icons.event_note_rounded, color: AppTheme.isDarkMode(context) ? AppTheme.sunshine : MPalette.amberInk),
                      const SizedBox(width: MSpace.md),
                      Expanded(
                        child: Text(text,
                            style: TextStyle(fontSize: MTextSize.bodyM, fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadReferral() async {
    final data = await loadReferral(Provider.of<AuthService>(context, listen: false));
    if (mounted) setState(() => _referral = data);
  }

  /// Change password = the reset flow with the account's email: a code proves it is them, and
  /// they are signed in again with the new password (the server ends every session).
  Future<void> _changePassword(AuthService auth, String email) async {
    Haptics.light();
    final outcome = await showForgotPasswordSheet(context, email: email, changing: true);
    if (outcome == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (outcome.signedIn) {
      messenger.showSnackBar(SnackBar(content: Text(tr(context, 'Password changed.', 'Salasana vaihdettu.'))));
    } else {
      // The old session was ended by the server, so sign out instead of pretending
      messenger.showSnackBar(SnackBar(content: Text(tr(context, 'Password changed. Sign in with your new password.', 'Salasana vaihdettu. Kirjaudu sisään uudella salasanalla.'))));
      await auth.logout();
    }
  }

  void _nav(BuildContext context, Widget screen) {
    Haptics.light();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _showThemePicker(BuildContext context, ThemeProvider themeProvider) {
    Haptics.light();
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
        padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox.shrink(),
            const SizedBox(height: 18),
            Text(l10n.translate('displayAppearance'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
            const SizedBox(height: MSpace.xs),
            Text(l10n.translate('displayAppearanceSubtitle'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
            const SizedBox(height: MSpace.lg),
            ListTile(
              leading: const Icon(Icons.light_mode_rounded, color: MPalette.amber, size: 22),
              title: Text(l10n.translate('themeCrispDaylight'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.light ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                Haptics.selection();
                themeProvider.setTheme(AppThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            Divider(height: 1, indent: 56, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.dark_mode_rounded, color: MPalette.malva, size: 22),
              title: Text(l10n.translate('themeOledMidnight'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.dark ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                Haptics.selection();
                themeProvider.setTheme(AppThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            Divider(height: 1, indent: 56, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined, color: MPalette.amberInk, size: 22),
              title: Text(l10n.translate('themeEyeComfort'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: textPrimary)),
              trailing: themeProvider.mode == AppThemeMode.eyeComfort ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
              onTap: () {
                Haptics.selection();
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
    Haptics.light();
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
              padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox.shrink(),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.translate('language'),
                            style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.translate('instantSwitching'),
                            style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 3),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              fontSize: MTextSize.bodyL,
                              color: isSelected ? AppTheme.primary : textPrimary,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 22)
                              : null,
                          onTap: () {
                            Haptics.selection();
                            provider.setLocaleCode(entry.key);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.translate('languageSwitchedTo').replaceAll('{lang}', entry.value)),
                                duration: const Duration(seconds: 2),
                                backgroundColor: MPalette.night,
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

  /// Account deletion happens on the Privacy screen, which really deletes the account on the
  /// server (signing out alone must never look like a deletion).
  void _openAccountDeletion(BuildContext context) {
    Haptics.selection();
    _nav(context, const PrivacyGdprScreen());
  }

  void _confirmLogout(BuildContext context, AuthService auth) {
    Haptics.medium();
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.lg)),
        title: Text(l10n.translate('logOutTitle'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: MTextSize.title, color: textPrimary)),
        content: Text(l10n.translate('logOutMsg'), style: const TextStyle(fontSize: MTextSize.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MPalette.red,
              foregroundColor: AppTheme.onBrand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.sm)),
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
                color: MPalette.night.withValues(alpha: 0.03),
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.label, color: textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: MSpace.xs, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: MTextSize.caption,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(MRadius.xs),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: textPrimary),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: MTextSize.caption, color: textSecondary))
          : null,
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context), size: 20),
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

        final userName = auth.currentUser?.name ?? (auth.isAuthenticated ? '' : tr(context, 'Guest', 'Vieras'));
        final rawEmail = auth.currentUser?.email ?? '';
        // Phone-only accounts carry a placeholder email that is never shown
        final userEmail = rawEmail.endsWith('@phone.malvoya.app') ? '' : rawEmail;
        final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'M';
        final currentLangName = AppLocalizations.languages[localeProvider.locale.languageCode] ?? 'English';

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              l10n.translate('profile'),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: MTextSize.title, color: textPrimary),
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
                padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.xl),
                color: cardBg,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppTheme.primary,
                      child: Text(
                        userInitial,
                        style: const TextStyle(fontSize: MTextSize.displayM, color: AppTheme.onBrand, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w900, color: textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            userEmail.isNotEmpty ? userEmail : (auth.currentUser?.phone ?? ''),
                            style: TextStyle(color: textSecondary, fontSize: MTextSize.caption),
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

              // Guests: an account is needed to pay, follow orders and save favourites
              if (!auth.isAuthenticated)
                Padding(
                  padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, 14),
                  child: SignInCard(
                    title: tr(context, 'Sign in or create an account', 'Kirjaudu tai luo tili'),
                    message: tr(context, 'You need an account to pay, follow your orders and save favourites. Your bag stays as it is.',
                        'Tarvitset tilin maksamiseen, tilausten seuraamiseen ja suosikkien tallentamiseen. Ostoskassisi säilyy ennallaan.'),
                  ),
                ),

              if (auth.isAuthenticated) _agreementBanner(context),

              // Quick-Access Action Grid (4 Refined Cards: Orders, Returns/Swap, Addresses, Language)
              // Google Pay completely removed per brand guidelines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                child: Row(
                  children: [
                    _buildQuickCard(
                      context: context,
                      icon: Icons.receipt_long_rounded,
                      iconColor: MPalette.malva,
                      title: l10n.translate('orders'),
                      subtitle: l10n.translate('liveTracking'),
                      onTap: () => _nav(context, const OrdersScreen()),
                    ),
                    const SizedBox(width: 10),
                    _buildQuickCard(
                      context: context,
                      icon: Icons.favorite_rounded,
                      iconColor: MPalette.lingon,
                      title: tr(context, 'Favourites', 'Suosikit'),
                      subtitle: tr(context, 'Saved items', 'Tallennetut tuotteet'),
                      onTap: () => _nav(context, const FavoritesScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                child: Row(
                  children: [
                    _buildQuickCard(
                      context: context,
                      icon: Icons.location_on_rounded,
                      iconColor: MPalette.malva,
                      title: l10n.translate('deliveryAddresses'),
                      subtitle: l10n.translate('savedLocations'),
                      onTap: () => _nav(context, const AddressManagementScreen()),
                    ),
                    const SizedBox(width: 10),
                    _buildQuickCard(
                      context: context,
                      icon: Icons.language_rounded,
                      iconColor: MPalette.malvaStrong,
                      title: l10n.translate('language'),
                      subtitle: currentLangName,
                      onTap: () => _showLanguageBottomSheet(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.lg),

              if (_referral != null && auth.isAuthenticated)
                _buildMenuGroup(
                  context: context,
                  title: tr(context, 'Invite', 'Kutsu'),
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.card_giftcard_rounded,
                      iconColor: MPalette.amberInk,
                      title: tr(context, 'Invite a friend', 'Kutsu ystävä'),
                      subtitle: tr(context, 'Share your code: ${_referral!['code']}', 'Jaa koodisi: ${_referral!['code']}'),
                      onTap: () async {
                        Haptics.light();
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => InviteScreen(initial: _referral)));
                        _loadReferral();
                      },
                    ),
                  ],
                ),

              // Account: password (only for accounts that have one and a real email address)
              if (auth.isAuthenticated && (auth.currentUser?.hasPassword ?? false) && userEmail.contains('@'))
                _buildMenuGroup(
                  context: context,
                  title: tr(context, 'Account', 'Tili'),
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.key_rounded,
                      iconColor: AppTheme.primary,
                      title: tr(context, 'Change password', 'Vaihda salasana'),
                      subtitle: tr(context, 'We email you a code to confirm it is you', 'Lähetämme koodin sähköpostiisi varmistukseksi'),
                      onTap: () => _changePassword(auth, userEmail),
                    ),
                  ],
                ),

              // Menu Group 1: Experience & Interface
              _buildMenuGroup(
                context: context,
                title: l10n.translate('experienceInterface'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.palette_outlined,
                    iconColor: MPalette.malva,
                    title: l10n.translate('displayAppearance'),
                    subtitle: l10n.translate('displayAppearanceSubtitle'),
                    onTap: () => _showThemePicker(context, themeProvider),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.language_rounded,
                    iconColor: MPalette.malvaStrong,
                    title: l10n.translate('language'),
                    subtitle: currentLangName,
                    onTap: () => _showLanguageBottomSheet(context),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.notifications_none_rounded,
                    iconColor: MPalette.malva,
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
                    iconColor: MPalette.malva,
                    title: l10n.translate('paymentMethods'),
                    subtitle: l10n.translate('paymentMethodsSubtitle'),
                    onTap: () => _nav(context, const PaymentMethodsScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.assignment_return_outlined,
                    iconColor: MPalette.malvaStrong,
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
                    iconColor: MPalette.green,
                    title: l10n.translate('dataRights'),
                    subtitle: l10n.translate('dataRightsSubtitle'),
                    onTap: () => _nav(context, const PrivacyGdprScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.gavel_rounded,
                    iconColor: MPalette.amberInk,
                    title: l10n.translate('legalTerms'),
                    subtitle: l10n.translate('legalTermsSubtitle'),
                    onTap: () => _nav(context, const TermsLegalScreen()),
                  ),
                  if (auth.isAuthenticated) ...[
                    Divider(height: 1, indent: 56, color: dividerColor),
                    _buildTile(
                      context: context,
                      icon: Icons.handshake_outlined,
                      iconColor: AppTheme.primary,
                      title: tr(context, 'Agreements', 'Sopimukset'),
                      subtitle: tr(context, 'What you have accepted, and copies', 'Mitä olet hyväksynyt, ja kopiot'),
                      onTap: () => _nav(context, const AgreementsScreen()),
                    ),
                    Divider(height: 1, indent: 56, color: dividerColor),
                    _buildTile(
                      context: context,
                      icon: Icons.block_rounded,
                      iconColor: MPalette.red,
                      title: tr(context, 'Blocked users', 'Estetyt käyttäjät'),
                      subtitle: tr(context, 'People whose comments and reviews you have hidden', 'Henkilöt, joiden kommentit ja arviot olet piilottanut'),
                      onTap: () => _nav(context, const BlockedUsersScreen()),
                    ),
                  ],
                ],
              ),

              // Menu Group 4: Concierge & Support
              _buildMenuGroup(
                context: context,
                title: tr(context, 'Help', 'Apua'),
                children: [
                  _buildTile(
                    context: context,
                    icon: Icons.help_outline_rounded,
                    iconColor: AppTheme.primary,
                    title: tr(context, 'Help assistant', 'Apuri'),
                    subtitle: tr(context, 'Automatic answers about orders, returns and sizes', 'Automaattiset vastaukset tilauksista, palautuksista ja koosta'),
                    onTap: () => _nav(context, const ChatbotScreen()),
                  ),
                  Divider(height: 1, indent: 56, color: dividerColor),
                  _buildTile(
                    context: context,
                    icon: Icons.support_agent_rounded,
                    iconColor: MPalette.malva,
                    title: l10n.translate('customerSupport'),
                    subtitle: l10n.translate('customerSupportSubtitle'),
                    onTap: () => _nav(context, const SupportHubScreen()),
                  ),
                ],
              ),

              const SizedBox(height: MSpace.lg),

              // Bottom Clean Account Actions (Log Out & GDPR Art. 17 Delete)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.xl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.logout_rounded, color: MPalette.red, size: 17),
                      label: Text(
                        l10n.translate('logOut'),
                        style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _confirmLogout(context, auth),
                    ),
                    Text('  •  ', style: TextStyle(color: textSecondary)),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, color: MPalette.redInk, size: 17),
                      label: Text(
                        l10n.translate('deleteAccountGdpr'),
                        style: const TextStyle(color: MPalette.redInk, fontSize: MTextSize.caption, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _openAccountDeletion(context),
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
