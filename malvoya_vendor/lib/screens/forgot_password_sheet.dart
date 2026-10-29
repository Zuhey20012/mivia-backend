import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// What the sign-in screen does after the sheet closes without signing in: fill in [email] and show
/// [message] (e.g. "Password changed, sign in with it" when the automatic sign-in was refused).
class ForgotPasswordResult {
  final String email;
  final String? message;
  const ForgotPasswordResult(this.email, [this.message]);
}

/// "Forgot password?": email → 6-digit code from the email → new password → signed in.
/// POST /auth/password/forgot never says whether an account exists; POST /auth/password/reset
/// checks the code (15 minutes, a few tries) and signs out every other session of the account.
Future<ForgotPasswordResult?> showForgotPasswordSheet(BuildContext context, {String? email}) {
  return showMSheet<ForgotPasswordResult>(context, builder: (_) => _ForgotPasswordSheet(initialEmail: email), isScrollControlled: true, useSafeArea: true);
}

enum _Step { email, code, password, unavailable }

class _ForgotPasswordSheet extends StatefulWidget {
  final String? initialEmail;
  const _ForgotPasswordSheet({this.initialEmail});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  static const _codeLength = 6;
  static const _resendSeconds = 60;
  static const _minPassword = 10; // API 2.16
  static const _maxPassword = 72; // the server's limit (bcrypt uses the first 72 bytes)
  static const _red = MPalette.red;

  late final _email = TextEditingController(text: _looksLikeEmail(widget.initialEmail ?? '') ? widget.initialEmail!.trim() : '');
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _password = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  int _resendIn = 0;
  bool _resent = false;
  Timer? _resendTimer;

  // Contacting support when email reset is not available
  bool _supportSent = false;
  String? _supportNote;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  static bool _looksLikeEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  /// Older servers (404) and servers that cannot send email (503) cannot reset passwords.
  bool _resetUnavailable(ApiResult res) => res.status == 503 || res.status == 404;

  Future<void> _sendCode({bool resend = false}) async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _error = tr(context, 'Enter the email address of your store account.', 'Anna kauppatilisi sähköpostiosoite.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _auth.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_resetUnavailable(res)) {
      setState(() => _step = _Step.unavailable);
      return;
    }
    if (!res.ok) {
      setState(() => _error = res.errorMessage);
      return;
    }
    HapticFeedback.selectionClick();
    _startCooldown();
    setState(() {
      _step = _Step.code;
      _code.clear();
    });
    _resent = resend;
    // Opens the keyboard for the code
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  void _onCodeChanged(String value) {
    if (_error != null) setState(() => _error = null);
    if (value.length == _codeLength) {
      HapticFeedback.selectionClick();
      _goToPassword();
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (!mounted) return;
    if (digits.length < _codeLength) {
      setState(() => _error = tr(context, 'There is no 6-digit code on the clipboard.', 'Leikepöydällä ei ole 6-numeroista koodia.'));
      return;
    }
    final code = digits.substring(0, _codeLength);
    _code.value = TextEditingValue(text: code, selection: const TextSelection.collapsed(offset: _codeLength));
    _onCodeChanged(code);
  }

  void _goToPassword() {
    if (_code.text.length != _codeLength) {
      setState(() => _error = tr(context, 'Enter the 6-digit code from the email.', 'Anna sähköpostin 6-numeroinen koodi.'));
      return;
    }
    setState(() {
      _step = _Step.password;
      _error = null;
    });
  }

  bool get _passwordOk => _password.text.length >= _minPassword && _password.text.length <= _maxPassword;

  Future<void> _save() async {
    if (!_passwordOk || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    final password = _password.text;
    final res = await _auth.resetPassword(email, _code.text, password);
    if (!mounted) return;
    if (_resetUnavailable(res)) {
      setState(() {
        _busy = false;
        _step = _Step.unavailable;
      });
      return;
    }
    if (!res.ok) {
      // A refused password (too short, or found in data breaches: API 2.16) keeps the code and asks
      // for another password; the server's message is shown as it is
      final passwordProblem = res.data['errors']?['fieldErrors']?['password'] != null ||
          '${res.data['code'] ?? ''}'.contains('PASSWORD') ||
          (res.rawError ?? '').toLowerCase().contains('password');
      setState(() {
        _busy = false;
        _error = res.errorMessage;
        // A wrong or expired code (400): type it again or ask for a new one
        if (res.status == 400 && !passwordProblem) {
          _step = _Step.code;
          _code.clear();
        }
      });
      if (_step == _Step.code) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _codeFocus.requestFocus();
        });
      }
      return;
    }

    HapticFeedback.mediumImpact();
    // Signs in with the new password. On success the app switches to the store and closes this sheet.
    final err = await _auth.login(email, password);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).pop(ForgotPasswordResult(
      email,
      tr(context, 'Your password was changed, but signing in did not work: $err', 'Salasanasi vaihdettiin, mutta kirjautuminen ei onnistunut: $err'),
    ));
  }

  Future<void> _askSupport() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _error = tr(context, 'Enter the email address of your store account.', 'Anna kauppatilisi sähköpostiosoite.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await const ApiClient().post('/support', {
      'app': 'store',
      'topic': 'Password reset',
      'message': 'I forgot the password of my Malvoya Store account and cannot sign in. / Unohdin Malvoya Store -tilini salasanan enkä pääse kirjautumaan.',
      'email': email,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _supportSent = true;
        _supportNote = tr(context, 'Sent (#${res.data['id']}). We reply by email to ${res.data['replyTo'] ?? email}.',
            'Lähetetty (#${res.data['id']}). Vastaamme sähköpostitse osoitteeseen ${res.data['replyTo'] ?? email}.');
      } else {
        _error = res.errorMessage;
      }
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, MSpace.xxl),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_step) {
              _Step.email => _emailStep(),
              _Step.code => _codeStep(),
              _Step.password => _passwordStep(),
              _Step.unavailable => _unavailableStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _title(String text) => Text(text, style: AppTheme.display(size: 22));

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(top: MSpace.sm, bottom: 18),
        child: Text(text, style: const TextStyle(fontSize: MTextSize.bodyM, color: AppTheme.textSecondary, height: 1.45)),
      );

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: MSpace.md),
      padding: const EdgeInsets.all(MSpace.md),
      decoration: BoxDecoration(color: MPalette.redLight, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, color: _red, size: 20),
        const SizedBox(width: MSpace.sm),
        Expanded(child: Text(_error!, style: const TextStyle(color: _red, fontWeight: FontWeight.w600, height: 1.35))),
      ]),
    );
  }

  Widget _primary(String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: SizedBox(
          width: double.infinity,
          child: MButton(label: label, loading: _busy, onPressed: _busy ? null : onPressed),
        ),
      );

  List<Widget> _emailStep() => [
        _title(tr(context, 'Forgot your password?', 'Unohditko salasanan?')),
        _body(tr(context, 'Enter the email address of your store account. We send you a 6-digit code to choose a new password.',
            'Anna kauppatilisi sähköpostiosoite. Lähetämme sinulle 6-numeroisen koodin, jolla voit valita uuden salasanan.')),
        TextField(
          controller: _email,
          autofocus: _email.text.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _sendCode(),
          decoration: InputDecoration(
            labelText: tr(context, 'Email address', 'Sähköpostiosoite'),
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
        ),
        _errorBox(),
        _primary(tr(context, 'Send code', 'Lähetä koodi'), _sendCode),
      ];

  List<Widget> _codeStep() => [
        _title(tr(context, 'Check your email', 'Tarkista sähköpostisi')),
        _body(tr(context,
            'If ${_email.text.trim()} has a Malvoya account, we sent it an email with a 6-digit code (valid for 15 minutes), or with how to sign in if the account has no password. Check your spam folder too.',
            'Jos osoitteella ${_email.text.trim()} on Malvoya-tili, lähetimme siihen sähköpostin, jossa on 6-numeroinen koodi (voimassa 15 minuuttia) tai ohje kirjautumiseen, jos tilillä ei ole salasanaa. Katso myös roskapostikansio.')),
        _CodeBoxes(controller: _code, focusNode: _codeFocus, length: _codeLength, enabled: !_busy, onChanged: _onCodeChanged),
        if (_resent && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr(context, 'We sent a new code.', 'Lähetimme uuden koodin.'),
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
        _errorBox(),
        const SizedBox(height: MSpace.sm),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : _pasteCode,
            icon: const Icon(Icons.content_paste_rounded, size: 20),
            label: Text(tr(context, 'Paste code', 'Liitä koodi')),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy || _resendIn > 0 ? null : () => _sendCode(resend: true),
            child: Text(_resendIn > 0
                ? tr(context, 'Send a new code in $_resendIn s', 'Uusi koodi $_resendIn s kuluttua')
                : tr(context, 'Send a new code', 'Lähetä uusi koodi')),
          ),
        ]),
        _primary(tr(context, 'Continue', 'Jatka'), _goToPassword),
        const SizedBox(height: MSpace.xs),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTheme.textSecondary),
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _Step.email;
                    _error = null;
                  }),
          child: Text(tr(context, 'Use another email address', 'Käytä toista sähköpostiosoitetta')),
        ),
      ];

  Widget _rule(bool ok, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: ok ? AppTheme.success : AppTheme.textSecondary),
          const SizedBox(width: MSpace.sm),
          Expanded(child: Text(text, style: TextStyle(fontSize: MTextSize.label, color: ok ? AppTheme.success : AppTheme.textSecondary, fontWeight: FontWeight.w600))),
        ]),
      );

  List<Widget> _passwordStep() {
    final length = _password.text.length;
    return [
      _title(tr(context, 'Choose a new password', 'Valitse uusi salasana')),
      _body(tr(context, 'After saving you are signed in with it. Other phones signed in to this account are signed out.',
          'Tallennuksen jälkeen kirjaudut sillä sisään. Muut tähän tiliin kirjautuneet puhelimet kirjataan ulos.')),
      TextField(
        controller: _password,
        autofocus: true,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _save(),
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
      const SizedBox(height: MSpace.xs),
      _rule(length >= _minPassword, tr(context, 'At least $_minPassword characters', 'Vähintään $_minPassword merkkiä')),
      if (length > _maxPassword)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.cancel_rounded, size: 18, color: _red),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Text(tr(context, 'At most $_maxPassword characters', 'Enintään $_maxPassword merkkiä'),
                  style: const TextStyle(fontSize: MTextSize.label, color: _red, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      _errorBox(),
      _primary(tr(context, 'Save and sign in', 'Tallenna ja kirjaudu'), _passwordOk ? _save : null),
      const SizedBox(height: MSpace.xs),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTheme.textSecondary),
        onPressed: _busy
            ? null
            : () => setState(() {
                  _step = _Step.code;
                  _error = null;
                }),
        child: Text(tr(context, 'Back to the code', 'Takaisin koodiin')),
      ),
    ];
  }

  List<Widget> _unavailableStep() => [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppTheme.sunshineLight, shape: BoxShape.circle),
          child: const Icon(Icons.support_agent_rounded, color: MPalette.amberInk, size: 30),
        ),
        const SizedBox(height: 14),
        _title(tr(context, 'We can help you get back in', 'Autamme sinut takaisin tilillesi')),
        _body(tr(context,
            'Resetting a password by email is not available yet. If your account also uses Google or your phone number, you can sign in with those. Otherwise, ask Malvoya support: we reply by email.',
            'Salasanan vaihto sähköpostilla ei ole vielä käytössä. Jos tililläsi on myös Google tai puhelinnumero, voit kirjautua niillä. Muuten pyydä apua Malvoyan tuelta: vastaamme sähköpostitse.')),
        if (!_supportSent)
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: tr(context, 'Email for our reply', 'Sähköposti vastaustamme varten'),
              prefixIcon: const Icon(Icons.mail_outline_rounded),
            ),
          ),
        if (_supportNote != null)
          Container(
            padding: const EdgeInsets.all(MSpace.md),
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: MSpace.sm),
              Expanded(child: Text(_supportNote!, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, height: 1.35))),
            ]),
          ),
        _errorBox(),
        if (!_supportSent) _primary(tr(context, 'Ask support for help', 'Pyydä apua tuelta'), _askSupport),
        const SizedBox(height: MSpace.xs),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(ForgotPasswordResult(_email.text.trim())),
          child: Text(tr(context, 'Back to sign in', 'Takaisin kirjautumiseen')),
        ),
      ];
}

/// Six boxes for the code. One real text field lies over them, so typing moves to the next box by
/// itself, backspace goes back, and pasting or the keyboard's code suggestion fills all six at once.
class _CodeBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CodeBoxes({required this.controller, required this.focusNode, required this.length, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(context, '6-digit code', '6-numeroinen koodi'),
      child: SizedBox(
        height: 60,
        child: Stack(children: [
          ListenableBuilder(
            listenable: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final text = controller.text;
              return Row(children: [
                for (var i = 0; i < length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : MSpace.xs, right: i == length - 1 ? 0 : MSpace.xs),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.sand,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: focusNode.hasFocus && (i == text.length || (i == length - 1 && text.length == length)) ? AppTheme.primary : Colors.transparent,
                            width: 1.8,
                          ),
                        ),
                        child: Text(i < text.length ? text[i] : '', style: AppTheme.display(size: 26)),
                      ),
                    ),
                  ),
              ]);
            },
          ),
          // The real input: invisible, but it takes taps, typing, paste and code autofill
          Positioned.fill(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
              onChanged: onChanged,
              showCursor: false,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
