import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Second step of signing in when two-step sign-in is on (API 2.13, for stores since 2.16): the code
/// from the authenticator app, or one of the recovery codes. The app's home shows it while
/// [AuthService.twoStepPending]; any sign-in path (password, Google, phone, new password) leads here.
class TwoStepSignInScreen extends StatefulWidget {
  const TwoStepSignInScreen({super.key});

  @override
  State<TwoStepSignInScreen> createState() => _TwoStepSignInScreenState();
}

class _TwoStepSignInScreenState extends State<TwoStepSignInScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _recovery = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (code.length < 6 || _busy) {
      setState(() => _error = _recovery
          ? tr(context, 'Enter one of your recovery codes.', 'Anna yksi palautuskoodeistasi.')
          : tr(context, 'Enter the 6-digit code from your authenticator app.', 'Anna todennussovelluksen 6-numeroinen koodi.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Provider.of<AuthService>(context, listen: false);
    final err = await auth.completeTwoStep(code);
    // On success (or an expired challenge) the app's home switches screens by itself
    if (!mounted || err == null) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = err;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          tooltip: tr(context, 'Back to sign-in', 'Takaisin kirjautumiseen'),
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: auth.cancelTwoStep,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: MSpace.lg),
            const Align(
              alignment: Alignment.centerLeft,
              child: CircleAvatar(radius: 32, backgroundColor: AppTheme.primaryLight, child: Icon(Icons.shield_outlined, size: 32, color: AppTheme.primary)),
            ),
            const SizedBox(height: MSpace.xl),
            Text(tr(context, 'Two-step sign-in', 'Kaksivaiheinen kirjautuminen'), style: AppTheme.display(size: 28)),
            const SizedBox(height: MSpace.sm),
            Text(
              _recovery
                  ? tr(context, 'Enter one of the recovery codes you saved when you turned two-step sign-in on. Each code works once.',
                      'Anna yksi palautuskoodeista, jotka tallensit ottaessasi kaksivaiheisen kirjautumisen käyttöön. Kukin koodi toimii kerran.')
                  : tr(context, 'Open your authenticator app and enter the 6-digit code it shows for Malvoya.',
                      'Avaa todennussovellus ja anna sen Malvoyalle näyttämä 6-numeroinen koodi.'),
              style: const TextStyle(fontSize: MTextSize.bodyL, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: MSpace.xxl),
            MTextField(
              controller: _code,
              autofocus: true,
              label: _recovery ? tr(context, 'Recovery code', 'Palautuskoodi') : tr(context, '6-digit code', '6-numeroinen koodi'),
              prefixIcon: Icons.password_rounded,
              keyboardType: _recovery ? TextInputType.visiblePassword : TextInputType.number,
              autofillHints: _recovery ? null : const [AutofillHints.oneTimeCode],
              maxLength: _recovery ? 20 : 6,
              inputFormatters: _recovery ? null : [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              errorText: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: MSpace.lg),
            MButton(label: tr(context, 'Sign in', 'Kirjaudu'), expand: true, loading: _busy, onPressed: _busy ? null : _submit),
            const SizedBox(height: MSpace.sm),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _recovery = !_recovery;
                        _error = null;
                        _code.clear();
                      }),
              child: Text(_recovery
                  ? tr(context, 'Use the authenticator app instead', 'Käytä todennussovellusta')
                  : tr(context, 'I cannot use my authenticator app', 'En voi käyttää todennussovellusta')),
            ),
            if (_recovery)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.xs, bottom: MSpace.xl),
                child: Text(
                  tr(context, 'No recovery codes either? Write to the Malvoya team from the contact page; we check that the store is yours before turning it off.',
                      'Eikö palautuskoodejakaan ole? Kirjoita Malvoyan tiimille yhteydenottosivulta; tarkistamme, että kauppa on sinun, ennen kuin poistamme sen käytöstä.'),
                  style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// "I am 18 or older" for a new account made with Google or a phone number (API 2.16). The app's
/// home shows it while [AuthService.ageConfirmationNeeded]; confirming repeats the sign-in.
class AgeConfirmScreen extends StatefulWidget {
  const AgeConfirmScreen({super.key});

  @override
  State<AgeConfirmScreen> createState() => _AgeConfirmScreenState();
}

class _AgeConfirmScreenState extends State<AgeConfirmScreen> {
  bool _checked = false;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    if (!_checked || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await Provider.of<AuthService>(context, listen: false).confirmAgeAndContinue();
    if (!mounted || err == null) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          tooltip: tr(context, 'Back to sign-in', 'Takaisin kirjautumiseen'),
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: auth.cancelAgeConfirmation,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.xxl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: MSpace.lg),
            Text(tr(context, 'Create your store account', 'Luo kauppatilisi'), style: AppTheme.display(size: 28)),
            const SizedBox(height: MSpace.sm),
            Text(
              tr(context, 'There is no Malvoya account for this sign-in yet. Selling on Malvoya is for adults: confirm your age to create the account.',
                  'Tällä kirjautumisella ei ole vielä Malvoya-tiliä. Malvoyassa myyminen on aikuisille: vahvista ikäsi luodaksesi tilin.'),
              style: const TextStyle(fontSize: MTextSize.bodyL, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: MSpace.xxl),
            AgeCheckbox(value: _checked, onChanged: _busy ? null : (v) => setState(() => _checked = v)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: MSpace.md),
                child: Text(_error!, style: const TextStyle(color: MPalette.red, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: MSpace.xl),
            MButton(
              label: tr(context, 'Create account', 'Luo tili'),
              expand: true,
              loading: _busy,
              onPressed: _checked && !_busy ? _continue : null,
            ),
            const SizedBox(height: MSpace.md),
            Text(
              tr(context, 'You accept the Seller Terms in the app before your store takes orders.',
                  'Hyväksyt myyjän ehdot sovelluksessa ennen kuin kauppasi ottaa vastaan tilauksia.'),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The "I am 18 or older" box, shared by registration and [AgeConfirmScreen].
class AgeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AgeCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
            Expanded(
              child: Text(tr(context, 'I am 18 or older', 'Olen vähintään 18-vuotias'),
                  style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ),
            const SizedBox(width: MSpace.md),
          ]),
        ),
      ),
    );
  }
}
