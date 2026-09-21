import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
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
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (mounted && err != null) {
      setState(() { _error = err; _loading = false; });
    }
  }

  Future<void> _handleGoogle() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.loginWithGoogle();
    if (mounted && err != null) {
      setState(() { _error = err; _loading = false; });
    }
  }

  void _showPhoneDialog() {
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24, left: 24, right: 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Phone Sign-In / Kirjaudu puhelimella', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Sign in or register directly using your mobile number", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+358 40 1234567',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password (or set one)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final phone = phoneCtrl.text.trim();
                    if (phone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your phone number')));
                      return;
                    }
                    Navigator.pop(ctx);
                    setState(() { _loading = true; _error = null; });
                    final auth = Provider.of<AuthService>(context, listen: false);
                    final err = await auth.loginWithPhone(phone);
                    if (mounted && err != null) {
                      setState(() { _error = err; _loading = false; });
                    }
                  },
                  child: const Text('Sign In with Phone'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Language / Valitse kieli', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('European Union & Universal Languages (25 languages)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: AppLocalizations.languages.entries.map((entry) {
                        final isSelected = provider.locale.languageCode == entry.key;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 16,
                              color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
                            ),
                          ),
                          trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).primaryColor) : null,
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
    final currentLangLabel = AppLocalizations.languages[currentLangKey] ?? '🇬🇧 English';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Language selector pill
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => _showLanguageSelector(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language_rounded, size: 16, color: Color(0xFFE65100)),
                        const SizedBox(width: 6),
                        Text(
                          currentLangLabel.split(' ').first,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Logo + Branding (Orange courier gradient)
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8C42), Color(0xFFE65100)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE65100).withOpacity(0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 42),
                    ),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context).translate('malvoyaCourier'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('Delivery Partner Portal', style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              Text(l10n.translate('welcomeBack'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(l10n.translate('signIn'), style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 28),

              // Email field
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '${l10n.translate('email')} / Phone',
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
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFE53E3E), fontSize: 13))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Login button
              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65100)),
                        onPressed: _handleLogin,
                        child: Text(l10n.translate('login')),
                      ),
              ),

              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 20),

              // Google Sign-In button
              OutlinedButton(
                onPressed: _handleGoogle,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.white,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.g_mobiledata_rounded, size: 24, color: Colors.black87),
                    SizedBox(width: 8),
                    Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 15)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Phone Sign-In button
              OutlinedButton(
                onPressed: _showPhoneDialog,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.white,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone_iphone_rounded, size: 20, color: Colors.black87),
                    SizedBox(width: 8),
                    Text('Continue with Phone Number', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 15)),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Register link
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
                  },
                  child: RichText(
                    text: TextSpan(
                      text: "New courier? ",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      children: const [
                        TextSpan(
                          text: 'Register here',
                          style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
