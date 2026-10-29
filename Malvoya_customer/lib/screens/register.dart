import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/age_gate.dart';
import '../l10n.dart';
import '../realtime_notification_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  bool _agreeToTerms = false;
  bool _adult = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl.clear();
    _emailCtrl.clear();
    _passCtrl.clear();
    _agreeToTerms = false;
    _adult = false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final l10n = AppLocalizations.of(context);
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = l10n.translate('fillAllFields'));
      return;
    }
    if (_passCtrl.text.length < 10) {
      setState(() => _error = l10n.translate('passTooShort'));
      return;
    }
    if (!_adult) {
      setState(() => _error = tr(context, 'Confirm that you are 18 or older.', 'Vahvista, että olet täyttänyt 18 vuotta.'));
      return;
    }
    if (!_agreeToTerms) {
      setState(() => _error = l10n.translate('acceptTermsPrompt'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.register(
      _nameCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passCtrl.text,
      ageConfirmed: _adult,
    );
    if (!mounted) return;
    if (err != null) {
      // Server messages (e.g. a password found in known data breaches) are shown as they are
      setState(() { _error = localizeServerMessage(context, err); _loading = false; });
    } else {
      RealtimeNotificationService.notifyCustomerJoined(
        context,
        email: _emailCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
      );
      Navigator.pop(context);
    }
  }

  void _showLanguageSelector(BuildContext context) {
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
      ),
      builder: (ctx) {
        return Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            final l10n = AppLocalizations.of(context);
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(MSpace.xl, MSpace.lg, MSpace.xl, MSpace.xxl),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MSheetHandle(),
                  const SizedBox(height: MSpace.lg),
                  Text(l10n.translate('selectLanguagePrompt'), style: TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: MSpace.xs),
                  Text(l10n.translate('languagesSubtitle'), style: TextStyle(fontSize: MTextSize.label, color: textSecondary)),
                  const SizedBox(height: MSpace.md),
                  Divider(height: 1, color: cardBorder),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: AppLocalizations.languages.entries.map((entry) {
                        final isSelected = provider.locale.languageCode == entry.key;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 2),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: MTextSize.bodyL,
                              color: isSelected ? AppTheme.primary : textPrimary,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary) : null,
                          onTap: () {
                            provider.setLocale(Locale(entry.key));
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLangKey = Provider.of<LocaleProvider>(context).locale.languageCode;
    final currentLangLabel = AppLocalizations.languages[currentLangKey] ?? 'English';
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MSpace.lg),
            child: GestureDetector(
              onTap: () => _showLanguageSelector(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language_rounded, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      currentLangLabel.split(' ').first,
                      style: const TextStyle(fontSize: MTextSize.bodyM),
                    ),
                    const SizedBox(width: MSpace.xs),
                    Icon(Icons.arrow_drop_down, size: 18, color: textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: MSpace.md),
              // Brand Icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(MRadius.md),
                ),
                child: const Icon(Icons.shopping_bag_outlined, color: AppTheme.onBrand, size: 28),
              ),
              const SizedBox(height: MSpace.xxl),
              Text(
                l10n.translate('createYourAccount'),
                style: TextStyle(
                  fontSize: MTextSize.displayM,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.translate('signUpSubtitle'),
                style: TextStyle(fontSize: MTextSize.bodyL, color: textSecondary),
              ),
              const SizedBox(height: MSpace.x3l),

              // Full Name
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: l10n.translate('fullName'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Email
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: l10n.translate('email'),
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Password
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleRegister(),
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  labelText: l10n.translate('passwordMin6'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePass ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              // Error Display
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MPalette.redLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: MPalette.red, size: 18),
                      const SizedBox(width: MSpace.sm),
                      Expanded(child: Text(_error!, style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: MSpace.xl),

              // Accounts are for adults (the server refuses a new account without this)
              AgeCheckbox(
                value: _adult,
                onChanged: (v) => setState(() {
                  _adult = v;
                  if (v && _error == tr(context, 'Confirm that you are 18 or older.', 'Vahvista, että olet täyttänyt 18 vuotta.')) _error = null;
                }),
              ),
              const SizedBox(height: MSpace.sm),

              // Legal Terms & Privacy Policy Checkbox (Ultra-High Contrast OLED & Light Compliant)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? (_agreeToTerms ? MPalette.nightRaised : MPalette.nightSurfaceVariant)
                      : (_agreeToTerms ? MPalette.lilac : MPalette.sand),
                  borderRadius: BorderRadius.circular(MRadius.md),
                  border: Border.all(
                    color: _agreeToTerms ? AppTheme.primary : (isDark ? MPalette.malva : MPalette.lilac),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreeToTerms,
                        activeColor: AppTheme.primary,
                        checkColor: AppTheme.onBrand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        side: BorderSide(
                          color: isDark ? MPalette.malvaOnDark : MPalette.malva,
                          width: 1.8,
                        ),
                        onChanged: (v) {
                          setState(() {
                            _agreeToTerms = v ?? false;
                            if (_agreeToTerms && _error == AppLocalizations.of(context).translate('acceptTermsPrompt')) {
                              _error = null;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _agreeToTerms = !_agreeToTerms;
                            if (_agreeToTerms && _error == AppLocalizations.of(context).translate('acceptTermsPrompt')) {
                              _error = null;
                            }
                          });
                        },
                        child: Text(
                          l10n.translate('agreeTermsText'),
                          style: TextStyle(
                            fontSize: MTextSize.label,
                            color: isDark ? MPalette.birch : MPalette.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // The documents being accepted, readable before accepting
              Wrap(
                spacing: 4,
                children: [
                  TextButton(onPressed: () => openLegal('terms'), child: Text(tr(context, 'Terms of Service', 'Käyttöehdot'))),
                  TextButton(onPressed: () => openLegal('privacy'), child: Text(tr(context, 'Privacy Policy', 'Tietosuojaseloste'))),
                ],
              ),

              const SizedBox(height: MSpace.lg),

              // Sign Up Button
              // Soft until the terms are ticked; tapping then explains what is missing
              MButton(
                label: l10n.translate('createAccount'),
                expand: true,
                loading: _loading,
                variant: _agreeToTerms && _adult ? MButtonVariant.primary : MButtonVariant.secondary,
                onPressed: _handleRegister,
              ),

              const SizedBox(height: MSpace.xxl),

              // Already have an account? Sign in
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text.rich(
                    TextSpan(
                      text: '${l10n.translate('alreadyHaveAccount')} ',
                      style: TextStyle(color: textSecondary, fontSize: MTextSize.bodyM),
                      children: [
                        TextSpan(
                          text: l10n.translate('signIn'),
                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: MSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
