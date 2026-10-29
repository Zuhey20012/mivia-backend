import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/account_security.dart';

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
  bool _agreed = false;
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
      setState(() => _error = tr(context, 'Please fill out all fields.', 'Täytä kaikki kentät.'));
      return;
    }
    if (_passCtrl.text.length < kMinPasswordLength) {
      setState(() => _error = tr(context, 'Use a password of at least $kMinPasswordLength characters.', 'Käytä vähintään $kMinPasswordLength merkin salasanaa.'));
      return;
    }
    if (!_adult) {
      setState(() => _error = tr(context, 'Couriers must be 18 or older. Confirm your age to send your application.', 'Lähettien on oltava vähintään 18-vuotiaita. Vahvista ikäsi lähettääksesi hakemuksen.'));
      return;
    }
    if (!_agreed) {
      setState(() => _error = tr(context, 'Accept the courier agreement to send your application.', 'Hyväksy lähettisopimus lähettääksesi hakemuksen.'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.register(
      _nameCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passCtrl.text,
      acceptTerms: _agreed,
      ageConfirmed: _adult,
    );
    // On success the app closes this screen itself and its home shows the pending-approval screen
    if (mounted && err != null) setState(() { _error = err; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
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
              Text(tr(context, 'Apply to deliver', 'Hae lähetiksi'), style: AppTheme.display(size: 28)),
              const SizedBox(height: 6),
              Text(
                tr(context,
                    'Deliver local orders when it suits you, as an independent entrepreneur. You need to be 18 or older, have the right to work in Finland and a Y-tunnus (or a light-entrepreneur service). A person at Malvoya reviews every application.',
                    'Toimita paikallisia tilauksia silloin kun sinulle sopii, itsenäisenä yrittäjänä. Sinun pitää olla vähintään 18-vuotias ja sinulla pitää olla oikeus tehdä työtä Suomessa sekä Y-tunnus (tai laskutuspalvelu). Jokaisen hakemuksen käsittelee ihminen.'),
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
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _handleRegister(),
                decoration: InputDecoration(
                  labelText: tr(context, 'Password', 'Salasana'),
                  helperText: tr(context, 'At least $kMinPasswordLength characters', 'Vähintään $kMinPasswordLength merkkiä'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
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

              const SizedBox(height: MSpace.xl),
              // Required for every new account (API 2.16); never pre-ticked
              AgeCheckbox(value: _adult, onChanged: _loading ? null : (v) => setState(() { _adult = v; if (v) _error = null; })),
              // Required: the application records that the courier accepted the agreement
              CheckboxListTile(
                value: _agreed,
                onChanged: _loading ? null : (v) => setState(() { _agreed = v ?? false; if (_agreed) _error = null; }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
                title: Text(
                  tr(context, 'I have read and accept the Courier Agreement', 'Olen lukenut ja hyväksyn lähettisopimuksen'),
                  style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openLegal('couriers'),
                  icon: const Icon(Icons.gavel_rounded, size: 20),
                  label: Text(tr(context, 'Read the courier agreement', 'Lue lähettisopimus')),
                ),
              ),
              const SizedBox(height: MSpace.xl),
              MButton(label: tr(context, 'Send application', 'Lähetä hakemus'), expand: true, loading: _loading, onPressed: _agreed && _adult ? _handleRegister : null),
              const SizedBox(height: MSpace.x3l),
            ],
          ),
        ),
      ),
    );
  }
}
