import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../theme_provider.dart';
import '../auth_service.dart';
import '../l10n.dart';
import 'notification_settings_screen.dart';
import 'signed_in_devices_screen.dart';
import 'terms_legal_screen.dart';
import 'privacy_gdpr_screen.dart';

/// Settings: the account (name, linked Google), language and appearance, and privacy / legal.
/// Every control here changes the real account or a real app preference.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _savingName = false;

  Future<void> _editName(AuthService auth, AppLocalizations l10n) async {
    final ctrl = TextEditingController(text: auth.currentUser?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('editProfile')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.translate('fullName')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr(ctx, 'Save', 'Tallenna'))),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == auth.currentUser?.name || !mounted) return;
    setState(() => _savingName = true);
    final error = await auth.updateName(name);
    if (!mounted) return;
    setState(() => _savingName = false);
    MSnack.show(context, error ?? tr(context, 'Name saved', 'Nimi tallennettu'));
  }

  Widget _buildCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBackground(context);
    final borderColor = AppTheme.cardBorder(context);
    final textSecondary = AppTheme.secondaryText(context);

    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: MPalette.night.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MSpace.lg, 14, MSpace.lg, MSpace.sm),
            child: Text(
              title,
              style: TextStyle(
                fontSize: MTextSize.caption,
                fontWeight: FontWeight.w800,
                color: textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final auth = Provider.of<AuthService>(context);
        final themeProvider = Provider.of<ThemeProvider>(context);
        final user = auth.currentUser;
        final userName = user?.name ?? '';
        // Phone-only accounts carry a placeholder email that is never shown
        final email = (user?.email ?? '').endsWith('@phone.malvoya.app') ? '' : (user?.email ?? '');
        final contact = [email, user?.phone ?? ''].where((v) => v.isNotEmpty).join('\n');

        final scaffoldBg = AppTheme.scaffoldBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final dividerColor = AppTheme.subtleDivider(context);
        final appbarBg = AppTheme.cardBackground(context);

        return Scaffold(
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            title: Text(
              l10n.translate('settings'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.title, color: textPrimary),
            ),
            elevation: 0,
            backgroundColor: appbarBg,
            foregroundColor: textPrimary,
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(MSpace.lg),
            children: [
              // 1. ACCOUNT
              _buildCard(
                context: context,
                title: l10n.translate('accountAndProfile'),
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      radius: 24,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'M',
                        style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.bold, fontSize: MTextSize.title),
                      ),
                    ),
                    title: Text(userName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL, color: textPrimary)),
                    subtitle: contact.isEmpty ? null : Text(contact, style: TextStyle(color: textSecondary, fontSize: MTextSize.caption)),
                    trailing: _savingName
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () => _editName(auth, l10n),
                            child: Text(l10n.translate('editAction'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                  ),
                  // On iOS only when the build is set up for Google sign-in
                  if (SignInSetup.google) ...[
                    Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                    GoogleLinkTile(account: Provider.of<AuthService>(context, listen: false), leading: const Icon(Icons.link_rounded, color: AppTheme.primary, size: 22)),
                  ],
                  if (auth.isAuthenticated) ...[
                    Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                    ListTile(
                      leading: const Icon(Icons.notifications_none_rounded, color: AppTheme.primary, size: 22),
                      title: Text(tr(context, 'Notifications', 'Ilmoitukset'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                      subtitle: Text(tr(context, 'Drops, lives and other optional messages', 'Dropit, livet ja muut valinnaiset viestit'),
                          style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                      trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen())),
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                    ListTile(
                      leading: const Icon(Icons.devices_rounded, color: AppTheme.primary, size: 22),
                      title: Text(tr(context, 'Signed-in devices', 'Kirjautuneet laitteet'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                      subtitle: Text(tr(context, 'See where you are signed in and sign out other devices', 'Katso, missä olet kirjautuneena, ja kirjaa muut laitteet ulos'),
                          style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                      trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignedInDevicesScreen())),
                    ),
                  ],
                ],
              ),

              // 2. LANGUAGE AND APPEARANCE
              _buildCard(
                context: context,
                title: l10n.translate('regionalLocalization'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.language_rounded, color: AppTheme.primary, size: 22),
                    title: Text(l10n.translate('activeLanguage'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                    subtitle: Text(AppLocalizations.languages[localeProvider.locale.languageCode] ?? 'English', style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    onTap: () {
                      showMSheet(context, builder: (ctx) {
                          final mBg = AppTheme.cardBackground(context);
                          final mText = AppTheme.primaryText(context);

                          return Container(
                            color: mBg,
                            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                            padding: const EdgeInsets.all(MSpace.xl),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.translate('selectLanguagePrompt'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.bold, color: mText)),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: ListView(
                                    children: AppLocalizations.languages.entries.map((e) {
                                      final isSel = localeProvider.locale.languageCode == e.key;
                                      return ListTile(
                                        title: Text(e.value, style: TextStyle(color: mText)),
                                        trailing: isSel ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                        onTap: () {
                                          localeProvider.setLocale(Locale(e.key));
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }, isScrollControlled: true, useSafeArea: false);
                    },
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined, color: AppTheme.primary, size: 22),
                    title: Text(l10n.translate('displayAppearance'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                    subtitle: Text(
                      themeProvider.mode == AppThemeMode.light
                          ? l10n.translate('themeLight')
                          : (themeProvider.mode == AppThemeMode.dark ? l10n.translate('themeDark') : l10n.translate('themeAmber')),
                      style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    onTap: () {
                      showMSheet(context, builder: (ctx) {
                          final mBg = AppTheme.cardBackground(context);
                          final mText = AppTheme.primaryText(context);

                          return SafeArea(
                            child: Container(
                              color: mBg,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.light_mode_outlined, color: MPalette.amber),
                                    title: Text(l10n.translate('themeLight'), style: TextStyle(color: mText, fontWeight: FontWeight.w600)),
                                    trailing: themeProvider.mode == AppThemeMode.light ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                    onTap: () {
                                      themeProvider.setTheme(AppThemeMode.light);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.dark_mode_outlined, color: MPalette.malva),
                                    title: Text(l10n.translate('themeDark'), style: TextStyle(color: mText, fontWeight: FontWeight.w600)),
                                    trailing: themeProvider.mode == AppThemeMode.dark ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                    onTap: () {
                                      themeProvider.setTheme(AppThemeMode.dark);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.wb_sunny_outlined, color: MPalette.amberInk),
                                    title: Text(l10n.translate('themeAmber'), style: TextStyle(color: mText, fontWeight: FontWeight.w600)),
                                    trailing: themeProvider.mode == AppThemeMode.eyeComfort ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                    onTap: () {
                                      themeProvider.setTheme(AppThemeMode.eyeComfort);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }, isScrollControlled: false, useSafeArea: false);
                    },
                  ),
                ],
              ),

              // 3. PRIVACY AND LEGAL
              _buildCard(
                context: context,
                title: l10n.translate('statutoryLegalCompliance'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_rounded, color: AppTheme.primary, size: 22),
                    title: Text(l10n.translate('exportData'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                    subtitle: Text(l10n.translate('rightOfAccessArt15Sub'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyGdprScreen())),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.gavel_rounded, color: MPalette.amberInk, size: 22),
                    title: Text(l10n.translate('termsOfServiceLaw'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: MTextSize.bodyM, color: textPrimary)),
                    subtitle: Text(l10n.translate('fourteenDayWithdrawal'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsLegalScreen())),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: MPalette.redInk, size: 22),
                    title: Text(l10n.translate('deleteAccount'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: MPalette.redInk)),
                    subtitle: Text(l10n.translate('eraseAccountArt17'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(context)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyGdprScreen())),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Center(
                child: Text(
                  l10n.translate('platformLegalFooter'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: MTextSize.caption, color: textSecondary, height: 1.4),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }
}
