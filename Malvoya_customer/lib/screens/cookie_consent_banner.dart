import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../l10n.dart';

class CookieConsentBanner extends StatefulWidget {
  final VoidCallback onDismiss;

  const CookieConsentBanner({super.key, required this.onDismiss});

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('cookie_consent_given') ?? false);
  }

  @override
  State<CookieConsentBanner> createState() => _CookieConsentBannerState();
}

class _CookieConsentBannerState extends State<CookieConsentBanner> {
  bool _showCustomization = false;
  bool _analyticsConsent = true;
  bool _personalizationConsent = true;
  bool _marketingConsent = false;

  Future<void> _saveConsent({
    required bool allAccepted,
    required bool essentialOnly,
  }) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cookie_consent_given', true);

    if (allAccepted) {
      await prefs.setBool('consent_analytics', true);
      await prefs.setBool('consent_personalization', true);
      await prefs.setBool('consent_marketing_sms', true);
      await prefs.setString('cookie_consent_choice', 'all_accepted');
    } else if (essentialOnly) {
      await prefs.setBool('consent_analytics', false);
      await prefs.setBool('consent_personalization', false);
      await prefs.setBool('consent_marketing_sms', false);
      await prefs.setString('cookie_consent_choice', 'essential_only');
    } else {
      await prefs.setBool('consent_analytics', _analyticsConsent);
      await prefs.setBool('consent_personalization', _personalizationConsent);
      await prefs.setBool('consent_marketing_sms', _marketingConsent);
      await prefs.setString('cookie_consent_choice', 'custom');
    }

    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final borderColor = AppTheme.cardBorder(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('cookieTitle'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'EU ePrivacy Directive & GDPR (2016/679)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('cookieDesc'),
                style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.45),
              ),
              if (_showCustomization) ...[
                const SizedBox(height: 14),
                _buildToggleRow(
                  title: 'Strictly Necessary Storage',
                  subtitle: 'Required for cart, secure PIN authorization & session tokens.',
                  value: true,
                  enabled: false,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onChanged: null,
                ),
                _buildToggleRow(
                  title: 'Performance & Dispatch Telemetry',
                  subtitle: 'Calculates real courier road distance and prevents app crashes.',
                  value: _analyticsConsent,
                  enabled: true,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onChanged: (val) => setState(() => _analyticsConsent = val),
                ),
                _buildToggleRow(
                  title: 'District Style Personalization',
                  subtitle: 'Highlights local boutique drops in your chosen Helsinki district.',
                  value: _personalizationConsent,
                  enabled: true,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onChanged: (val) => setState(() => _personalizationConsent = val),
                ),
                _buildToggleRow(
                  title: 'Promotional Drop Notifications',
                  subtitle: 'SMS/Email alerts when independent studios open new drops (opt-in only).',
                  value: _marketingConsent,
                  enabled: true,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onChanged: (val) => setState(() => _marketingConsent = val),
                ),
              ],
              const SizedBox(height: 18),
              if (!_showCustomization) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: borderColor, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _saveConsent(allAccepted: false, essentialOnly: true),
                        child: Text(
                          l10n.translate('rejectOptionalCookies'),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _saveConsent(allAccepted: true, essentialOnly: false),
                        child: Text(
                          l10n.translate('acceptAllCookies'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showCustomization = true),
                    child: Text(
                      'Customize Preferences',
                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _saveConsent(allAccepted: false, essentialOnly: false),
                    child: const Text(
                      'Save My Preferences',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required Color textPrimary,
    required Color textSecondary,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppTheme.primary,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
