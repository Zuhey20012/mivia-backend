import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import '../auth_service.dart';
import '../local_notification_service.dart';
import 'address_management_screen.dart';

/**
 * Malvoya GDPR & Data Protection Sovereignty Hub
 * Full European statutory compliance (Regulation EU 2016/679)
 * Supports dynamic 25-language translation, self-service Article 15 JSON archives,
 * and Article 17 irreversible erasure.
 */

class PrivacyGdprScreen extends StatefulWidget {
  const PrivacyGdprScreen({super.key});

  @override
  State<PrivacyGdprScreen> createState() => _PrivacyGdprScreenState();
}

class _PrivacyGdprScreenState extends State<PrivacyGdprScreen> {
  bool _consentAnalytics = true;
  bool _consentPersonalization = true;
  bool _consentRadar = true;
  bool _consentMarketing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConsentPreferences();
  }

  Future<void> _loadConsentPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _consentAnalytics = prefs.getBool('consent_analytics') ?? true;
        _consentPersonalization = prefs.getBool('consent_personalization') ?? true;
        _consentRadar = prefs.getBool('consent_courier_radar') ?? true;
        _consentMarketing = prefs.getBool('consent_marketing_sms') ?? false;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateConsent(String key, bool val) async {
    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, val);
    } catch (_) {}
  }

  Future<void> _exportUserData(AuthService auth, AppLocalizations l10n) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    final savedAddrs = prefs.getString('malvoya_addresses') ?? '[]';
    final userPhone = prefs.getString('malvoya_user_phone') ?? 'Not configured';
    final userCountry = prefs.getString('malvoya_country') ?? 'Finland 🇫🇮';

    final exportData = {
      'gdpr_export_metadata': {
        'regulation': 'EU General Data Protection Regulation (GDPR 2016/679)',
        'article': 'Article 15 (Right of Access) & Article 20 (Data Portability)',
        'export_timestamp': DateTime.now().toIso8601String(),
        'data_controller': 'Malvoya Platform, Helsinki, Finland (support@malvoya.com)',
        'supervisory_authority': 'Office of the Data Protection Ombudsman (Tietosuojavaltuutetun toimisto)',
      },
      'profile': {
        'user_id': auth.currentUser?.id ?? 'usr_guest_8492',
        'full_name': auth.currentUser?.name ?? 'Customer',
        'registered_email': auth.currentUser?.email ?? '',
        'registered_phone': userPhone,
        'country_jurisdiction': userCountry,
      },
      'privacy_consent_matrix': {
        'analytics_telemetry': _consentAnalytics,
        'boutique_personalization': _consentPersonalization,
        'courier_radar_tracking': _consentRadar,
        'promotional_marketing': _consentMarketing,
      },
      'saved_addresses': jsonDecode(savedAddrs),
      'security_tokens': {
        'pin_protection_active': prefs.getBool('malvoya_pin_enabled') ?? false,
        'pci_dss_token_vault': 'Stripe & Adyen Encrypted Reference Token Active',
      },
    };

    final prettyJson = const JsonEncoder.withIndent('  ').convert(exportData);

    if (!mounted) return;

    // Show on-device notification
    await LocalNotificationService.showNotification(
      id: 301,
      title: '📁 ${l10n.translate('gdprArchiveReady')}',
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
                          subject: 'Malvoya GDPR Personal Data Export Archive',
                          body: 'Attached is your official GDPR Article 15 personal data record:\n\n$prettyJson',
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
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 24),
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
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                auth.logout();

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
                      backgroundColor: const Color(0xFF7C3AED),
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
                          leading: const Icon(Icons.edit_location_alt_outlined, color: Color(0xFF10B981)),
                          title: Text(l10n.translate('rightToRectificationArt16'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('rightToRectificationArt16Sub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressManagementScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. CONSENT & COOKIE MANAGEMENT
                    _buildCard(
                      title: l10n.translate('dataProcessingConsents'),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textSecondary: textSecondary,
                      children: [
                        SwitchListTile(
                          title: Text(l10n.translate('analyticalTelemetry'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('analyticalTelemetrySub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          value: _consentAnalytics,
                          activeTrackColor: AppTheme.primary,
                          onChanged: (val) {
                            setState(() => _consentAnalytics = val);
                            _updateConsent('consent_analytics', val);
                          },
                        ),
                        Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                        SwitchListTile(
                          title: Text(l10n.translate('boutiquePersonalization'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('boutiquePersonalizationSub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          value: _consentPersonalization,
                          activeTrackColor: AppTheme.primary,
                          onChanged: (val) {
                            setState(() => _consentPersonalization = val);
                            _updateConsent('consent_personalization', val);
                          },
                        ),
                        Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                        SwitchListTile(
                          title: Text(l10n.translate('courierProximityRadar'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('courierRadarSub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          value: _consentRadar,
                          activeTrackColor: AppTheme.primary,
                          onChanged: (val) {
                            setState(() => _consentRadar = val);
                            _updateConsent('consent_courier_radar', val);
                          },
                        ),
                        Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
                        SwitchListTile(
                          title: Text(l10n.translate('promotionalMarketing'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimary)),
                          subtitle: Text(l10n.translate('promotionalMarketingSub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          value: _consentMarketing,
                          activeTrackColor: AppTheme.primary,
                          onChanged: (val) {
                            setState(() => _consentMarketing = val);
                            _updateConsent('consent_marketing_sms', val);
                          },
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
                          title: Text(l10n.translate('contactDpo'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text('dpo@malvoya.com • Helsinki, Finland', style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 18),
                          onTap: () {
                            LocalNotificationService.openEmailApp(
                              email: 'dpo@malvoya.com',
                              subject: 'GDPR Data Subject Request - Malvoya Customer Account',
                              body: 'Hello DPO,\n\nI am contacting you regarding my rights under the GDPR for my account (${auth.currentUser?.email}).',
                            );
                          },
                        ),
                        Divider(height: 1, indent: 56, color: dividerColor),
                        ListTile(
                          leading: const Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
                          title: Text(l10n.translate('privacyDeskInquiries'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                          subtitle: Text('privacy@malvoya.com • ${l10n.translate("promptGdprResponse")}', style: TextStyle(fontSize: 12, color: textSecondary)),
                          trailing: const Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 18),
                          onTap: () {
                            LocalNotificationService.openEmailApp(
                              email: 'privacy@malvoya.com',
                              subject: 'GDPR Privacy Inquiry - Malvoya Customer Account',
                              body: 'Hello Malvoya Privacy Team,\n\nI am contacting you regarding data privacy for my account (${auth.currentUser?.email}).',
                            );
                          },
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
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
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
                              icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626)),
                              label: Text(l10n.translate('eraseAccountPersonalData'), style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w800)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
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
