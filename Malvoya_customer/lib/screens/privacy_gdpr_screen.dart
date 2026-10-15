import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/legal_links.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import '../auth_service.dart';
import '../local_notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'address_management_screen.dart';
import 'support_hub_screen.dart';

/// Privacy: download your data (GDPR art. 15), correct it, ask about it, and delete the account
/// (art. 17; the server anonymises the user and keeps order records for the Accounting Act).

class PrivacyGdprScreen extends StatefulWidget {
  const PrivacyGdprScreen({super.key});

  @override
  State<PrivacyGdprScreen> createState() => _PrivacyGdprScreenState();
}

class _PrivacyGdprScreenState extends State<PrivacyGdprScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConsentPreferences();
  }

  Future<void> _loadConsentPreferences() async {
    setState(() => _loading = false);
  }



  Future<void> _exportUserData(AuthService auth, AppLocalizations l10n) async {
    HapticFeedback.mediumImpact();
    if (auth.accessToken == null) return;
    
    String prettyJson = '{}';
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.apiBase}/auth/me/data'),
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        prettyJson = const JsonEncoder.withIndent('  ').convert(data);
      } else {
        prettyJson = '{"error": "Failed to fetch data from server."}';
      }
    } catch (e) {
      prettyJson = '{"error": "Could not connect to server."}';
    }

    if (!mounted) return;

    // Show on-device notification
    await LocalNotificationService.showNotification(
      id: 301,
      title: l10n.translate('gdprArchiveReady'),
      body: l10n.translate('gdprArchiveSub'),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        final cardBg = AppTheme.cardBackground(ctx);
        final textPrimary = AppTheme.primaryText(ctx);
        final textSecondary = AppTheme.secondaryText(ctx);
        final inputBg = AppTheme.inputBackground(ctx);

        return Container(
          color: cardBg,
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.file_download_rounded, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.translate('gdprArt15ArchiveTitle'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text(l10n.translate('portableJsonFormat'), style: TextStyle(fontSize: 12, color: textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder(ctx)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      prettyJson,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4, color: textPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l10n.translate('copyJson')),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: prettyJson));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('gdprCopied')), behavior: SnackBarBehavior.floating),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: Text(l10n.translate('emailArchive')),
                      onPressed: () {
                        final email = auth.currentUser?.email ?? '';
                        LocalNotificationService.openEmailApp(
                          email: email,
                          subject: tr(context, 'My Malvoya data', 'Malvoya-tietoni'),
                          body: prettyJson,
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteAccount(AuthService auth, AppLocalizations l10n) {
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final cardBg = AppTheme.cardBackground(dialogCtx);
        final textPrimary = AppTheme.primaryText(dialogCtx);
        final textSecondary = AppTheme.secondaryText(dialogCtx);

        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD93025).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFB3261E), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.translate('confirmDelete'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: textPrimary),
                ),
              ),
            ],
          ),
          content: Text(
            l10n.translate('deleteAccountSimpleMsg'),
            style: TextStyle(fontSize: 14, height: 1.4, color: textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.translate('cancel'), style: TextStyle(fontWeight: FontWeight.w700, color: textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);

                if (auth.accessToken != null) {
                  // Deleting takes a moment: show that it is happening and block other taps
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => PopScope(
                      canPop: false,
                      child: AlertDialog(
                        content: Row(children: [
                          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          const SizedBox(width: 16),
                          Expanded(child: Text(tr(context, 'Deleting your account…', 'Poistetaan tiliäsi…'))),
                        ]),
                      ),
                    ),
                  );
                  final res = await ApiClient(auth).delete('/auth/me');
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pop();
                  if (!res.ok) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(tr(context, 'Your account was not deleted', 'Tiliäsi ei poistettu')),
                        content: Text(res.errorText(context) ??
                            tr(context, 'Could not delete your account. Please try again.', 'Tiliä ei voitu poistaa. Yritä uudelleen.')),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'OK', 'OK')))],
                      ),
                    );
                    return;
                  }
                }

                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                await auth.logout();

                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await LocalNotificationService.showNotification(
                    id: 302,
                    title: l10n.translate('accountErasedNotif'),
                    body: l10n.translate('accountErasedNotifBody'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.translate('accountErasedNotifBody')),
                      backgroundColor: const Color(0xFF55226E),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              child: Text(l10n.translate('confirmDelete'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final auth = Provider.of<AuthService>(context);
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final borderColor = AppTheme.cardBorder(context);
        final dividerColor = AppTheme.subtleDivider(context);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              l10n.translate('privacyPolicy'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textPrimary),
            ),
            backgroundColor: cardBg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    // GDPR Summary Header Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.privacy_tip_rounded, color: Colors.teal, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.translate('euGdprSovereignty'),
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.translate('euGdprSubtitle'),
                                  style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. DATA ACCESS & EXPORT SECTION
                    _buildCard(
                      title: l10n.translate('statutoryDataRights'),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textSecondary: textSecondary,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.download_for_offline_outlined, color: AppTheme.primary),
                          title: Text(l10n.translate('rightOfAccessArt15'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('rightOfAccessArt15Sub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: () => _exportUserData(auth, l10n),
                        ),
                        Divider(height: 1, indent: 56, color: dividerColor),
                        ListTile(
                          leading: const Icon(Icons.edit_location_alt_outlined, color: Color(0xFF248A52)),
                          title: Text(l10n.translate('rightToRectificationArt16'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('rightToRectificationArt16Sub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressManagementScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. No tracking to consent to
                    _buildCard(
                      title: tr(context, 'Tracking and consent', 'Seuranta ja suostumus'),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textSecondary: textSecondary,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.verified_user_outlined, color: AppTheme.primary),
                          title: Text(
                            tr(context, 'No ads, no analytics trackers', 'Ei mainoksia, ei analytiikkaseurantaa'),
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
                          ),
                          subtitle: Text(
                            tr(context,
                                'Malvoya uses your data only to run your orders and account, so there is nothing extra to consent to. The Drops feed is ranked without a personal profile.',
                                'Malvoya käyttää tietojasi vain tilaustesi ja tilisi hoitamiseen, joten erillistä suostumusta ei tarvita. Drops-syöte järjestetään ilman henkilökohtaista profiilia.'),
                            style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
                          ),
                        ),
                        Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                        ListTile(
                          leading: const Icon(Icons.description_outlined, color: AppTheme.primary),
                          title: Text(tr(context, 'Read the full privacy policy', 'Lue koko tietosuojaseloste'),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                          onTap: () => openLegal('privacy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. DPO & REGULATORY CONTACT
                    _buildCard(
                      title: l10n.translate('dpoSupervisoryContact'),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textSecondary: textSecondary,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.contact_mail_outlined, color: Color(0xFF3B82F6)),
                          title: Text(tr(context, 'Ask Malvoya about your data', 'Kysy Malvoyalta tiedoistasi'),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text(tr(context, 'Send a message under "Account and privacy". We reply by email.',
                                  'Lähetä viesti aiheella "Tili ja tietosuoja". Vastaamme sähköpostitse.'),
                              style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 18),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportHubScreen())),
                        ),
                        Divider(height: 1, indent: 56, color: dividerColor),
                        ListTile(
                          leading: const Icon(Icons.shield_outlined, color: Color(0xFF248A52)),
                          title: Text(tr(context, 'Data Protection Ombudsman', 'Tietosuojavaltuutettu'),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text(tr(context, 'You can also complain to the Finnish supervisory authority (tietosuoja.fi).',
                                  'Voit myös tehdä valituksen valvovalle viranomaiselle (tietosuoja.fi).'),
                              style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.open_in_new_rounded, color: Colors.grey, size: 18),
                          onTap: () => launchUrl(Uri.parse('https://tietosuoja.fi'), mode: LaunchMode.externalApplication),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. PERMANENT ACCOUNT ERASURE (GDPR ARTICLE 17)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFD93025).withValues(alpha: 0.4), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E), size: 22),
                              const SizedBox(width: 8),
                              Text(
                                l10n.translate('rightToErasureArt17'),
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.translate('rightToErasureArt17Sub'),
                            style: TextStyle(fontSize: 12, height: 1.4, color: textSecondary),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFB3261E)),
                              label: Text(l10n.translate('eraseAccountPersonalData'), style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w800)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFB3261E), width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () => _confirmDeleteAccount(auth, l10n),
                            ),
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

  Widget _buildCard({
    required String title,
    required Color cardBg,
    required Color borderColor,
    required Color textSecondary,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.6),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
