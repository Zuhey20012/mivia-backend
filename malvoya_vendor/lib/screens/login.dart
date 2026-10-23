import 'package:flutter/material.dart';
import '../widgets/language_sheet.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'forgot_password_sheet.dart';
import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  String? _error;
  /// The last sign-in was refused for a wrong email/phone or password: offer a reset next to the error.
  bool _wrongPassword = false;

  @override
  void initState() {
    super.initState();
    // Explicitly start with blank fields - no autofill or saved email at top
    _emailCtrl.clear();
    _passCtrl.clear();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = tr(context, 'Please enter your email or phone number and your password.', 'Anna sähköpostiosoitteesi tai puhelinnumerosi ja salasanasi.'));
      return;
    }
    setState(() { _loading = true; _error = null; _wrongPassword = false; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted && err != null) {
      setState(() { _error = err; _loading = false; _wrongPassword = auth.lastLoginRejected; });
    }
  }

  Future<void> _forgotPassword() async {
    final result = await showForgotPasswordSheet(context, email: _emailCtrl.text.trim());
    // Signed in with the new password: the app has already switched to the store
    if (!mounted || result == null) return;
    setState(() {
      if (result.email.isNotEmpty) _emailCtrl.text = result.email;
      _passCtrl.clear();
      _error = result.message;
      _wrongPassword = false;
    });
  }

  Future<void> _handleGoogle() async {
    setState(() { _loading = true; _error = null; _wrongPassword = false; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.loginWithGoogle();
    if (mounted && err != null) {
      setState(() { _error = err; _loading = false; });
    }
  }

  void _showPhoneDialog() {
    final phoneCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool codeSent = false;

    showMSheet(context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24, left: 24, right: 24,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: MSpace.xl),
              Text(tr(context, 'Sign in with your phone', 'Kirjaudu puhelimella'), style: const TextStyle(fontSize: MTextSize.displayS, fontWeight: FontWeight.bold)),
              const SizedBox(height: MSpace.sm),
              Text(tr(context, 'We send a sign-in code to your mobile number by text message.', 'Lähetämme kirjautumiskoodin tekstiviestillä matkapuhelinnumeroosi.'), style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: MSpace.xl),
              if (!codeSent) ...[
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Phone number', 'Puhelinnumero'),
                    hintText: '+358 40 1234567',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: MSpace.xl),
                SizedBox(
                  width: double.infinity,
                  child: MButton(label: tr(context, 'Send code', 'Lähetä koodi'), loading: _loading, onPressed: _loading ? null : () async {
                      final phone = phoneCtrl.text.trim();
                      if (phone.isEmpty) {
                        MSnack.show(context, tr(context, 'Please enter your phone number', 'Anna puhelinnumerosi'));
                        return;
                      }
                      setModalState(() => _loading = true);
                      final auth = Provider.of<AuthService>(context, listen: false);
                      await auth.verifyPhone(
                        phoneNumber: phone,
                        onCodeSent: (verId) {
                          setModalState(() {
                            codeSent = true;
                            _loading = false;
                          });
                        },
                        onError: (err) {
                          setModalState(() => _loading = false);
                          MSnack.show(context, err);
                        },
                        onAutoVerified: () {
                          Navigator.pop(ctx);
                        },
                      );
                    }),
                ),
              ] else ...[
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: tr(context, '6-digit code', '6-numeroinen koodi'),
                    hintText: '123456',
                    prefixIcon: const Icon(Icons.password_outlined),
                  ),
                ),
                const SizedBox(height: MSpace.xl),
                SizedBox(
                  width: double.infinity,
                  child: MButton(label: tr(context, 'Verify and sign in', 'Vahvista ja kirjaudu'), loading: _loading, onPressed: _loading ? null : () async {
                      final code = codeCtrl.text.trim();
                      if (code.isEmpty) return;
                      setModalState(() => _loading = true);
                      final auth = Provider.of<AuthService>(context, listen: false);
                      final err = await auth.signInWithSmsCode(code);
                      setModalState(() => _loading = false);
                      if (err != null) {
                        MSnack.show(context, err);
                      } else {
                        Navigator.pop(ctx);
                      }
                    }),
                ),
              ],
            ],
          ),
        ),
      ), transparent: true, isScrollControlled: true, useSafeArea: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLangKey = Provider.of<LocaleProvider>(context).locale.languageCode;
    final currentLangLabel = AppLocalizations.languages[currentLangKey] ?? 'English';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: MSpace.lg),

              // Language selector pill
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => showLanguageSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.md, vertical: 6),
                    decoration: BoxDecoration(
                      color: MPalette.sand,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language_rounded, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          currentLangLabel,
                          style: const TextStyle(fontSize: MTextSize.bodyM),
                        ),
                        const SizedBox(width: MSpace.xs),
                        const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: MSpace.xxl),

              // Logo + Branding
              Center(
                child: Column(
                  children: [
                    BrandTile(size: 76, background: AppTheme.primary),
                    const SizedBox(height: MSpace.lg),
                    const Text('Malvoya Store', style: TextStyle(fontSize: MTextSize.displayL, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, letterSpacing: -0.5)),
                    const SizedBox(height: MSpace.xs),
                    Text(tr(context, 'Sell locally', 'Myy paikallisesti'), style: const TextStyle(fontSize: MTextSize.bodyM, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(l10n.translate('welcomeBack'), style: const TextStyle(fontSize: MTextSize.displayM, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(l10n.translate('signIn'), style: const TextStyle(fontSize: MTextSize.bodyM, color: AppTheme.textSecondary)),
              const SizedBox(height: 28),

              // Email field
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.translate('email'),
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Password field
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  labelText: l10n.translate('password'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePass ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _loading ? null : _forgotPassword,
                  child: Text(tr(context, 'Forgot password?', 'Unohditko salasanan?')),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MPalette.redLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MPalette.redLine),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: MPalette.red, size: 18),
                          const SizedBox(width: MSpace.sm),
                          Expanded(child: Text(_error!, style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label))),
                        ],
                      ),
                      if (_wrongPassword)
                        TextButton.icon(
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: MPalette.red),
                          onPressed: _loading ? null : _forgotPassword,
                          icon: const Icon(Icons.lock_reset_rounded, size: 20),
                          label: Text(tr(context, 'Forgot password? Reset it', 'Unohditko salasanan? Vaihda se')),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: MSpace.xxl),

              // Login button
              MButton(label: l10n.translate('login'), expand: true, loading: _loading, onPressed: _handleLogin),

              const SizedBox(height: MSpace.xxl),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: AppTheme.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
                    child: Text(tr(context, 'or', 'tai'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.label, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(child: Divider(color: AppTheme.divider)),
                ],
              ),

              const SizedBox(height: MSpace.xl),

              // Google Sign-In button
              OutlinedButton(
                onPressed: _handleGoogle,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.sm)),
                  backgroundColor: AppTheme.surface,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.g_mobiledata_rounded, size: 24, color: AppTheme.textPrimary),
                    const SizedBox(width: MSpace.sm),
                    Text(tr(context, 'Continue with Google', 'Jatka Googlella'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: MTextSize.bodyL)),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.md),

              // Phone Sign-In button
              OutlinedButton(
                onPressed: _showPhoneDialog,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.sm)),
                  backgroundColor: AppTheme.surface,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone_iphone_rounded, size: 20, color: AppTheme.textPrimary),
                    const SizedBox(width: MSpace.sm),
                    Text(tr(context, 'Continue with phone number', 'Jatka puhelinnumerolla'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: MTextSize.bodyL)),
                  ],
                ),
              ),

              const SizedBox(height: MSpace.x3l),

              // Register link
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
                  },
                  child: Text.rich(
                    TextSpan(
                      text: tr(context, 'New seller? ', 'Uusi myyjä? '),
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: MTextSize.bodyM),
                      children: [
                        TextSpan(
                          text: tr(context, 'Create an account', 'Luo tili'),
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
