import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'sign_in_steps.dart';

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
  bool _acceptTerms = false;
  bool _adult = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = tr(context, 'Please fill in all fields.', 'Täytä kaikki kentät.'));
      return;
    }
    // API 2.16: new passwords need 10 characters; the server also refuses passwords known from data
    // breaches, and its message is shown as it is
    if (_passCtrl.text.length < 10) {
      setState(() => _error = tr(context, 'The password needs at least 10 characters.', 'Salasanassa on oltava vähintään 10 merkkiä.'));
      return;
    }
    if (!_adult) {
      setState(() => _error = tr(context, 'Confirm that you are 18 or older.', 'Vahvista, että olet vähintään 18-vuotias.'));
      return;
    }
    if (!_acceptTerms) {
      setState(() => _error = tr(context, 'Accept the Seller Terms to create a store account.', 'Hyväksy myyjän ehdot luodaksesi kauppatilin.'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.register(
      _nameCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passCtrl.text,
      acceptTerms: _acceptTerms,
      ageConfirmed: _adult,
    );

    // On success the app's home switches to the welcome screen by itself and closes this one
    if (mounted && err != null) {
      setState(() { _error = err; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          tooltip: tr(context, 'Back', 'Takaisin'),
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: MSpace.xl),
              Text(tr(context, 'Sell on Malvoya', 'Myy Malvoyassa'), style: AppTheme.display(size: 28)),
              const SizedBox(height: 6),
              Text(
                tr(context,
                    'Create an account, then set up your store. Our team reviews every store before shoppers can see it. Malvoya is just starting in Finland, so we cannot promise a number of shoppers or orders yet.',
                    'Luo tili ja perusta sitten kauppasi. Tiimimme tarkistaa jokaisen kaupan ennen kuin asiakkaat näkevät sen. Malvoya on vasta aloittamassa Suomessa, joten emme voi vielä luvata tiettyä määrää asiakkaita tai tilauksia.'),
                style: const TextStyle(fontSize: MTextSize.bodyL, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 36),

              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr(context, 'Full name', 'Koko nimi'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr(context, 'Email address', 'Sähköpostiosoite'),
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleRegister(),
                decoration: InputDecoration(
                  labelText: tr(context, 'Password', 'Salasana'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePass ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              const SizedBox(height: MSpace.xs),
              Text(tr(context, 'At least 10 characters. Passwords known from data breaches are refused.', 'Vähintään 10 merkkiä. Tietovuodoista tunnettuja salasanoja ei hyväksytä.'),
                  style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              // Required for new accounts (API 2.16): the server records the confirmation
              AgeCheckbox(value: _adult, onChanged: (v) => setState(() {
                    _adult = v;
                    _error = null;
                  })),
              const SizedBox(height: MSpace.sm),
              // Required: the server records when the Seller Terms were accepted, and which version
              Container(
                decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    onTap: () => setState(() {
                      _acceptTerms = !_acceptTerms;
                      _error = null;
                    }),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(children: [
                        Checkbox(
                          value: _acceptTerms,
                          onChanged: (v) => setState(() {
                            _acceptTerms = v ?? false;
                            _error = null;
                          }),
                        ),
                        Expanded(
                          child: Text(tr(context, 'I accept the Seller Terms', 'Hyväksyn myyjän ehdot'),
                              style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        ),
                        const SizedBox(width: MSpace.md),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: MSpace.xs, bottom: MSpace.xs),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => openLegal('sellers'),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(tr(context, 'Read the Seller Terms', 'Lue myyjän ehdot')),
                    ),
                  ),
                ]),
              ),

              if (_error != null) ...[
                const SizedBox(height: MSpace.md),
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

              const SizedBox(height: MSpace.x3l),
              MButton(label: tr(context, 'Create account', 'Luo tili'), expand: true, loading: _loading, onPressed: _handleRegister),
              const SizedBox(height: MSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
