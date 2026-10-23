import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../screens/support_hub_screen.dart';

/// What happened in the sheet: the address used, and whether the customer is now signed in with
/// the new password.
class PasswordResetOutcome {
  final String email;
  final bool signedIn;
  const PasswordResetOutcome(this.email, this.signedIn);
}

/// "Forgot password?" / "Change password": email → 6-digit code → new password, in one sheet.
/// On success it signs in with the new password (the server ends every other session), so the
/// customer carries on where they were. Returns null when the sheet was closed early.
Future<PasswordResetOutcome?> showForgotPasswordSheet(BuildContext context, {String? email, bool changing = false}) {
  return showMSheet<PasswordResetOutcome>(context, builder: (_) => _ForgotPasswordSheet(initialEmail: email ?? '', changing: changing), isScrollControlled: true, useSafeArea: true);
}

// Same rules as registration (backend auth.schema.ts: 8–72 characters)
const _minLength = 8;
const _maxLength = 72;
const _resendSeconds = 60;

enum _Step { email, code, password, unavailable }

class _ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  final bool changing;
  const _ForgotPasswordSheet({required this.initialEmail, required this.changing});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _emailCtrl = TextEditingController(text: widget.initialEmail);
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();
  final _passCtrl = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(_onCodeChanged);
    _codeFocus.addListener(() { if (mounted) setState(() {}); });
    _passCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _email => _emailCtrl.text.trim();
  bool get _emailLooksValid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email);

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!_emailLooksValid) {
      setState(() => _error = tr(context, 'Enter the email address of your account.', 'Kirjoita tilisi sähköpostiosoite.'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    final res = await context.read<AuthService>().requestPasswordReset(_email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.status == 503) {
      setState(() => _step = _Step.unavailable);
      return;
    }
    if (!res.ok) {
      setState(() => _error = res.status == 404
          ? tr(context, 'Password reset is not available yet. Contact support and we will help you in.',
              'Salasanan palautus ei ole vielä käytössä. Ota yhteyttä tukeen, niin autamme sinut sisään.')
          : res.errorText(context));
      return;
    }
    _startCooldown();
    if (resend) {
      _codeCtrl.clear();
      MSnack.show(context, tr(context, 'A new code is on its way.', 'Uusi koodi on matkalla.'));
    }
    setState(() => _step = _Step.code);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  void _onCodeChanged() {
    final digits = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits != _codeCtrl.text) {
      _codeCtrl.value = TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
      return;
    }
    setState(() {});
    if (digits.length == 6 && _step == _Step.code) {
      // All six digits: straight on to the new password
      setState(() { _step = _Step.password; _error = null; });
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final match = RegExp(r'\d{6}').firstMatch(data?.text ?? '');
    if (!mounted) return;
    if (match == null) {
      setState(() => _error = tr(context, 'There is no 6-digit code on the clipboard.', 'Leikepöydällä ei ole 6-numeroista koodia.'));
      return;
    }
    setState(() => _error = null);
    _codeCtrl.text = match.group(0)!;
  }

  bool get _passwordOk => _passCtrl.text.length >= _minLength && _passCtrl.text.length <= _maxLength;

  Future<void> _savePassword() async {
    if (!_passwordOk) return;
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthService>();
    final res = await auth.resetPassword(_email, _codeCtrl.text, _passCtrl.text);
    if (!mounted) return;
    if (res.status == 503) {
      setState(() { _busy = false; _step = _Step.unavailable; });
      return;
    }
    if (!res.ok) {
      final wrongCode = res.status == 400 && !(res.error ?? '').toLowerCase().contains('password');
      setState(() {
        _busy = false;
        _error = res.status == 404
            ? tr(context, 'Password reset is not available yet. Contact support and we will help you in.',
                'Salasanan palautus ei ole vielä käytössä. Ota yhteyttä tukeen, niin autamme sinut sisään.')
            : res.errorText(context);
        if (wrongCode) {
          // Back to the code, the password the customer typed is kept
          _step = _Step.code;
          _codeCtrl.clear();
        }
      });
      if (wrongCode) _codeFocus.requestFocus();
      return;
    }
    // Saved. The server has ended every session, so sign in again with the new password.
    final signInError = await auth.login(_email, _passCtrl.text);
    if (!mounted) return;
    Navigator.of(context).pop(PasswordResetOutcome(_email, signInError == null));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, bottom + MSpace.xxl),
      child: SingleChildScrollView(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_step != _Step.unavailable) _StepDots(index: _step.index),
              const SizedBox(height: MSpace.lg),
              ...switch (_step) {
                _Step.email => _emailStep(context),
                _Step.code => _codeStep(context),
                _Step.password => _passwordStep(context),
                _Step.unavailable => _unavailableStep(context),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String text, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppTheme.display(context, size: 24)),
          const SizedBox(height: 6),
          Text(sub, style: TextStyle(fontSize: MTextSize.bodyM, height: 1.4, color: AppTheme.secondaryText(context))),
          const SizedBox(height: MSpace.xl),
        ],
      );

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: MSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: MPalette.red, size: 18),
              const SizedBox(width: MSpace.sm),
              Expanded(child: Text(_error!, style: const TextStyle(color: MPalette.red, fontSize: MTextSize.label, height: 1.35))),
            ],
          ),
        );

  Widget _primaryButton(String label, VoidCallback? onPressed) => SizedBox(
        width: double.infinity,
        child: MButton(label: label, loading: _busy, onPressed: _busy ? null : onPressed),
      );

  List<Widget> _emailStep(BuildContext context) => [
        _title(
          context,
          widget.changing ? tr(context, 'Change password', 'Vaihda salasana') : tr(context, 'Forgot your password?', 'Unohditko salasanan?'),
          widget.changing
              ? tr(context, 'We email you a 6-digit code to confirm it is you. Then you choose a new password.',
                  'Lähetämme sähköpostiisi 6-numeroisen koodin, jolla varmistamme, että kyse on sinusta. Sen jälkeen valitset uuden salasanan.')
              : tr(context, 'No problem. Enter your account email and we send you a 6-digit code.',
                  'Ei hätää. Kirjoita tilisi sähköpostiosoite, niin lähetämme sinulle 6-numeroisen koodin.'),
        ),
        TextField(
          controller: _emailCtrl,
          readOnly: widget.changing && widget.initialEmail.isNotEmpty,
          autofocus: widget.initialEmail.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendCode(),
          decoration: InputDecoration(
            labelText: tr(context, 'Email', 'Sähköposti'),
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
        ),
        _errorBox(),
        const SizedBox(height: MSpace.xl),
        _primaryButton(tr(context, 'Send code', 'Lähetä koodi'), _sendCode),
      ];

  List<Widget> _codeStep(BuildContext context) {
    final code = _codeCtrl.text;
    final border = AppTheme.cardBorder(context);
    final fill = AppTheme.inputBackground(context);
    return [
      _title(
        context,
        tr(context, 'Check your email', 'Tarkista sähköpostisi'),
        tr(context, 'If $_email has a Malvoya password, a 6-digit code is on its way. It works for 15 minutes.',
            'Jos osoitteella $_email on Malvoya-salasana, 6-numeroinen koodi on matkalla. Se on voimassa 15 minuuttia.'),
      ),
      // One real field under six boxes: typing, pasting, the keyboard's code suggestion and
      // backspace all work as usual, and the highlighted box moves along with the cursor.
      SizedBox(
        height: 60,
        child: Stack(
          children: [
            Row(
              children: List.generate(6, (i) {
                final filled = i < code.length;
                final active = _codeFocus.hasFocus && (i == code.length || (code.length == 6 && i == 5));
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == 5 ? 0 : MSpace.sm),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: filled ? AppTheme.pastel(context, AppTheme.lilac, AppTheme.primary) : fill,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd - 4),
                      border: Border.all(color: active ? AppTheme.primary : border, width: active ? 2 : 1),
                    ),
                    child: Text(filled ? code[i] : '',
                        style: AppTheme.display(context, size: 24, weight: FontWeight.w700)),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.011,
                child: TextField(
                  controller: _codeCtrl,
                  focusNode: _codeFocus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  showCursor: false,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                  ),
                  onTap: () => setState(() {}),
                ),
              ),
            ),
          ],
        ),
      ),
      _errorBox(),
      const SizedBox(height: MSpace.md),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _pasteCode,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: Text(tr(context, 'Paste code', 'Liitä koodi')),
          ),
          TextButton(
            onPressed: _cooldown > 0 || _busy ? null : () => _sendCode(resend: true),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(_cooldown > 0
                ? tr(context, 'Resend code in $_cooldown s', 'Lähetä uudelleen $_cooldown s kuluttua')
                : tr(context, 'Resend code', 'Lähetä koodi uudelleen')),
          ),
        ],
      ),
      const SizedBox(height: MSpace.xs),
      Text(
        tr(context, 'No email? Check the spam folder, or go back and check the address.',
            'Eikö viestiä näy? Katso roskapostikansio tai palaa tarkistamaan osoite.'),
        style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.secondaryText(context)),
      ),
      const SizedBox(height: MSpace.sm),
      TextButton(
        onPressed: () => setState(() { _step = _Step.email; _error = null; }),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(tr(context, 'Use another email', 'Käytä toista osoitetta')),
      ),
    ];
  }

  List<Widget> _passwordStep(BuildContext context) {
    final len = _passCtrl.text.length;
    return [
      _title(
        context,
        tr(context, 'Choose a new password', 'Valitse uusi salasana'),
        tr(context, 'You will be signed in with it straight away. Other phones where you were signed in are signed out.',
            'Kirjaudut sillä heti sisään. Muut puhelimet, joilla olit kirjautuneena, kirjataan ulos.'),
      ),
      TextField(
        controller: _passCtrl,
        autofocus: true,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _savePassword(),
        decoration: InputDecoration(
          labelText: tr(context, 'New password', 'Uusi salasana'),
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _obscure ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: MSpace.md),
      _Rule(ok: len >= _minLength, text: tr(context, 'At least $_minLength characters', 'Vähintään $_minLength merkkiä')),
      if (len > _maxLength)
        _Rule(ok: false, text: tr(context, 'At most $_maxLength characters', 'Enintään $_maxLength merkkiä')),
      _errorBox(),
      const SizedBox(height: MSpace.xl),
      _primaryButton(tr(context, 'Save and sign in', 'Tallenna ja kirjaudu'), _passwordOk ? _savePassword : null),
      const SizedBox(height: MSpace.xs),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => setState(() { _step = _Step.code; _error = null; }),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(tr(context, 'Back to the code', 'Takaisin koodiin')),
        ),
      ),
    ];
  }

  List<Widget> _unavailableStep(BuildContext context) => [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.support_agent_rounded, color: AppTheme.clayInk),
        ),
        const SizedBox(height: MSpace.lg),
        _title(
          context,
          tr(context, 'We can help you in', 'Autamme sinut sisään'),
          tr(context,
              'Resetting a password by email is not switched on yet. Send our support team a message from this address and we will get you back into your account. Please do not delete your account over it.',
              'Salasanan palautus sähköpostilla ei ole vielä käytössä. Lähetä tukitiimillemme viesti, niin autamme sinut takaisin tilillesi. Tiliä ei tarvitse poistaa tämän takia.'),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const SupportHubScreen()));
            },
            icon: const Icon(Icons.mail_outline_rounded),
            label: Text(tr(context, 'Contact support', 'Ota yhteyttä tukeen')),
          ),
        ),
        const SizedBox(height: MSpace.xs),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(tr(context, 'Close', 'Sulje')),
          ),
        ),
      ];
}

class _StepDots extends StatelessWidget {
  final int index;
  const _StepDots({required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final on = i <= index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: i == index ? 28 : 10,
          height: 8,
          decoration: BoxDecoration(
            color: on ? AppTheme.primary : AppTheme.cardBorder(context),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _Rule extends StatelessWidget {
  final bool ok;
  final String text;
  const _Rule({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppTheme.success : AppTheme.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MSpace.xs),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: color),
          const SizedBox(width: MSpace.sm),
          Text(text, style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
