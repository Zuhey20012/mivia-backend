import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../theme_provider.dart';
import '../auth_service.dart';
import '../locale_provider.dart';
import '../l10n.dart';
import '../core/strings.dart';
import '../core/google_link_tile.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? tr(context, 'Name saved', 'Nimi tallennettu')),
      behavior: SnackBarBehavior.floating,
    ));
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
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
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: textPrimary),
            ),
            elevation: 0,
            backgroundColor: appbarBg,
            foregroundColor: textPrimary,
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    title: Text(userName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
                    subtitle: contact.isEmpty ? null : Text(contact, style: TextStyle(color: textSecondary, fontSize: 12)),
                    trailing: _savingName
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () => _editName(auth, l10n),
                            child: Text(l10n.translate('editAction'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  const GoogleLinkTile(leading: Icon(Icons.link_rounded, color: AppTheme.primary, size: 22)),
                ],
              ),

              // 2. LANGUAGE AND APPEARANCE
              _buildCard(
                context: context,
                title: l10n.translate('regionalLocalization'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.language_rounded, color: AppTheme.primary, size: 22),
                    title: Text(l10n.translate('activeLanguage'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                    subtitle: Text(AppLocalizations.languages[localeProvider.locale.languageCode] ?? 'English', style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) {
                          final mBg = AppTheme.cardBackground(context);
                          final mText = AppTheme.primaryText(context);

                          return Container(
                            color: mBg,
                            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.translate('selectLanguagePrompt'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: mText)),
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
                        },
                      );
                    },
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined, color: AppTheme.primary, size: 22),
                    title: Text(l10n.translate('displayAppearance'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                    subtitle: Text(
                      themeProvider.mode == AppThemeMode.light
                          ? l10n.translate('themeLight')
                          : (themeProvider.mode == AppThemeMode.dark ? l10n.translate('themeDark') : l10n.translate('themeAmber')),
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (ctx) {
                          final mBg = AppTheme.cardBackground(context);
                          final mText = AppTheme.primaryText(context);

                          return SafeArea(
                            child: Container(
                              color: mBg,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.light_mode_outlined, color: Color(0xFFEAB308)),
                                    title: Text(l10n.translate('themeLight'), style: TextStyle(color: mText, fontWeight: FontWeight.w600)),
                                    trailing: themeProvider.mode == AppThemeMode.light ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                    onTap: () {
                                      themeProvider.setTheme(AppThemeMode.light);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.dark_mode_outlined, color: Color(0xFF6D2E8C)),
                                    title: Text(l10n.translate('themeDark'), style: TextStyle(color: mText, fontWeight: FontWeight.w600)),
                                    trailing: themeProvider.mode == AppThemeMode.dark ? const Icon(Icons.check, color: AppTheme.primary) : null,
                                    onTap: () {
                                      themeProvider.setTheme(AppThemeMode.dark);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.wb_sunny_outlined, color: Color(0xFFB86E00)),
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
                        },
                      );
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
                    title: Text(l10n.translate('exportData'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                    subtitle: Text(l10n.translate('rightOfAccessArt15Sub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyGdprScreen())),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.gavel_rounded, color: Color(0xFFB86E00), size: 22),
                    title: Text(l10n.translate('termsOfServiceLaw'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                    subtitle: Text(l10n.translate('fourteenDayWithdrawal'), style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsLegalScreen())),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFB3261E), size: 22),
                    title: Text(l10n.translate('deleteAccount'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFB3261E))),
                    subtitle: Text(l10n.translate('eraseAccountArt17'), style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyGdprScreen())),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Center(
                child: Text(
                  l10n.translate('platformLegalFooter'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: textSecondary, height: 1.4),
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
