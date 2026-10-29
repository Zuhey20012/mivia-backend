import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/account_security.dart';
import 'help_screen.dart';

enum _Step { email, code, password, unavailable }

/// "Forgot password?": one sheet that walks through email → 6-digit code → new password, then
/// signs in with the new password. The server emails the code (`POST /auth/password/forgot`) and
/// answers the same whether or not an account exists, so the copy never says one does.
class ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordSheet({super.key, this.initialEmail = ''});

  /// False once the server answered 404 (an older server without password reset): the link is hidden.
  static bool available = true;

  /// Opens the sheet. Returns the email to fill in on the sign-in screen when the sheet closes
  /// without signing in (e.g. the password was changed but signing in failed).
  static Future<String?> show(BuildContext context, {String initialEmail = ''}) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // This sheet draws its own handle
        showDragHandle: false,
        builder: (_) => ForgotPasswordSheet(initialEmail: initialEmail),
      );

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  static const _codeLength = 6;
  static const _resendCooldown = Duration(seconds: 60);
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  DateTime? _resendAt;
  Timer? _tick;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail.contains('@') ? widget.initialEmail.trim() : '';
    _code.addListener(_onCodeChanged);
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Steps ────────────────────────────────────────────────────────────────

  int get _resendSeconds {
    final at = _resendAt;
    if (at == null) return 0;
    final s = at.difference(DateTime.now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  void _startCooldown() {
    _resendAt = DateTime.now().add(_resendCooldown);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_resendSeconds == 0) t.cancel();
      setState(() {});
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = tr(context, 'Enter the email address you signed up with.', 'Anna sähköpostiosoite, jolla rekisteröidyit.'));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await _auth.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.unavailable) {
      // An older server without password reset: the link is hidden from now on
      if (result.notSupported) ForgotPasswordSheet.available = false;
      setState(() => _step = _Step.unavailable);
      return;
    }
    if (!result.ok) {
      setState(() => _error = result.tooMany
          ? tr(context, 'Too many requests. Wait a minute and try again.', 'Liian monta pyyntöä. Odota hetki ja yritä uudelleen.')
          : result.error);
      if (result.tooMany && resend) _startCooldown();
      return;
    }
    _startCooldown();
    if (resend) _code.clear();
    setState(() {
      _step = _Step.code;
      _info = resend ? tr(context, 'A new code is on its way.', 'Uusi koodi on tulossa.') : null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  void _onCodeChanged() {
    final digits = _code.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > _codeLength ? digits.substring(0, _codeLength) : digits;
    if (clipped != _code.text) {
      _code.value = TextEditingValue(text: clipped, selection: TextSelection.collapsed(offset: clipped.length));
      return;
    }
    setState(() => _error = null);
    if (clipped.length == _codeLength && _step == _Step.code) _toPassword();
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (!mounted) return;
    if (digits.length < _codeLength) {
      setState(() => _error = tr(context, 'No 6-digit code found on the clipboard.', 'Leikepöydällä ei ole 6-numeroista koodia.'));
      return;
    }
    _code.text = digits.substring(0, _codeLength);
  }

  void _toPassword() {
    if (_code.text.length != _codeLength) {
      setState(() => _error = tr(context, 'Enter the 6-digit code from the email.', 'Anna sähköpostissa tullut 6-numeroinen koodi.'));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _step = _Step.password;
      _error = null;
      _info = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  bool get _longEnough => _password.text.length >= kMinPasswordLength;
  bool get _notTooLong => _password.text.length <= 72;
  bool get _notBlank => _password.text.trim().isNotEmpty;
  bool get _passwordOk => _longEnough && _notTooLong && _notBlank;

  Future<void> _reset() async {
    if (!_passwordOk || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    final result = await _auth.resetPassword(email, _code.text, _password.text);
    if (!mounted) return;
    if (result.ok && result.signInError == null) {
      // Signed in: the app closes this sheet and opens the courier view by itself; close it here
      // only if that has not happened already
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
    if (result.ok) {
      // The password changed, but signing in with it did not work (e.g. not a courier account)
      Navigator.of(context).pop(email);
      MSnack.show(context, '${tr(context, 'Your password was changed.', 'Salasanasi vaihdettiin.')} ${result.signInError}');
      return;
    }
    if (result.unavailable) {
      setState(() => _step = _Step.unavailable);
      return;
    }
    if (result.codeProblem) {
      _code.clear();
      setState(() {
        _step = _Step.code;
        _error = result.error ??
            tr(context, 'That code is wrong or has expired. Check the email or send a new code.',
                'Koodi on väärä tai vanhentunut. Tarkista sähköposti tai lähetä uusi koodi.');
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
      return;
    }
    setState(() => _error = result.error);
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _info = null;
      _step = _step == _Step.password ? _Step.code : _Step.email;
    });
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stepIndex = switch (_step) { _Step.email => 1, _Step.code => 2, _Step.password => 3, _Step.unavailable => 0 };
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(MRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.md, MSpace.xxl, MSpace.xxl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: MSpace.sm),
            Row(children: [
              if (_step == _Step.code || _step == _Step.password)
                IconButton(
                  tooltip: tr(context, 'Back', 'Takaisin'),
                  onPressed: _busy ? null : _back,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                const SizedBox(height: 48),
              const Spacer(),
              if (stepIndex > 0)
                Text(tr(context, 'Step $stepIndex of 3', 'Vaihe $stepIndex/3'),
                    style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
            ]),
            const SizedBox(height: MSpace.xs),
            ...switch (_step) {
              _Step.email => _emailStep(),
              _Step.code => _codeStep(),
              _Step.password => _passwordStep(),
              _Step.unavailable => _unavailableStep(),
            },
          ]),
        ),
      ),
    );
  }

  Widget _title(String text) => Text(text, style: AppTheme.display(size: 24));

  Widget _body(String text) => Padding(
        padding: const EdgeInsets.only(top: MSpace.sm),
        child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: MTextSize.bodyM)),
      );

  Widget _message() {
    final error = _error;
    final info = _info;
    if (error == null && info == null) return const SizedBox(height: MSpace.xs);
    final isError = error != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? MPalette.redLight : MPalette.mint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 18, color: isError ? AppTheme.danger : AppTheme.success),
        const SizedBox(width: MSpace.sm),
        Expanded(
          child: Text(error ?? info!,
              style: TextStyle(color: isError ? AppTheme.danger : AppTheme.successDark, fontSize: MTextSize.label, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _primary({required String label, required VoidCallback? onPressed}) => SizedBox(
        width: double.infinity,
        height: 56,
        child: MButton(label: label, loading: _busy, onPressed: _busy ? null : onPressed),
      );

  List<Widget> _emailStep() => [
        _title(tr(context, 'Reset your password', 'Vaihda salasana')),
        _body(tr(context, 'Enter the email address of your courier account. If it has a password, we email you a 6-digit code.',
            'Anna lähettitilisi sähköpostiosoite. Jos tilillä on salasana, lähetämme siihen 6-numeroisen koodin.')),
        const SizedBox(height: 18),
        TextField(
          controller: _email,
          autofocus: _email.text.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendCode(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: tr(context, 'Email', 'Sähköposti'),
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
        ),
        _message(),
        const SizedBox(height: 18),
        _primary(label: tr(context, 'Send code', 'Lähetä koodi'), onPressed: _sendCode),
        const SizedBox(height: MSpace.md),
        Text(
          tr(context, 'Signed up with your phone number or Google? Those accounts have no password: sign in with the same option instead.',
              'Rekisteröidyitkö puhelinnumerolla tai Googlella? Niillä tileillä ei ole salasanaa: kirjaudu samalla tavalla kuin rekisteröidyit.'),
          style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary, height: 1.4),
        ),
      ];

  List<Widget> _codeStep() {
    final wait = _resendSeconds;
    final mm = '${wait ~/ 60}:${(wait % 60).toString().padLeft(2, '0')}';
    return [
      _title(tr(context, 'Check your email', 'Tarkista sähköpostisi')),
      _body(tr(context, 'If ${_email.text.trim()} has a courier account with a password, a 6-digit code is on its way. It works for 15 minutes. Check the spam folder too.',
          'Jos osoitteella ${_email.text.trim()} on lähettitili ja salasana, 6-numeroinen koodi on tulossa. Se toimii 15 minuuttia. Katso myös roskapostikansio.')),
      const SizedBox(height: MSpace.xl),
      _CodeBoxes(controller: _code, focusNode: _codeFocus, length: _codeLength, onSubmitted: _toPassword),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _pasteCode,
          icon: const Icon(Icons.content_paste_rounded, size: 20),
          label: Text(tr(context, 'Paste code', 'Liitä koodi')),
        ),
      ),
      _message(),
      const SizedBox(height: 14),
      _primary(label: tr(context, 'Continue', 'Jatka'), onPressed: _code.text.length == _codeLength ? _toPassword : null),
      const SizedBox(height: MSpace.sm),
      Center(
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: wait > 0 || _busy ? null : () => _sendCode(resend: true),
          child: Text(wait > 0
              ? tr(context, 'Send a new code in $mm', 'Uusi koodi $mm kuluttua')
              : tr(context, 'Send a new code', 'Lähetä uusi koodi')),
        ),
      ),
    ];
  }

  List<Widget> _passwordStep() {
    Widget rule(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 18, color: ok ? AppTheme.success : AppTheme.textSecondary),
            const SizedBox(width: MSpace.sm),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600, color: ok ? AppTheme.successDark : AppTheme.textSecondary)),
            ),
          ]),
        );
    final typed = _password.text.isNotEmpty;
    return [
      _title(tr(context, 'Choose a new password', 'Valitse uusi salasana')),
      _body(tr(context, 'You are signed in with it straight away. Other phones signed in to this account are signed out.',
          'Sinut kirjataan sillä heti sisään. Muut tähän tiliin kirjautuneet puhelimet kirjataan ulos.')),
      const SizedBox(height: 18),
      TextField(
        controller: _password,
        focusNode: _passwordFocus,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _reset(),
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
      const SizedBox(height: 6),
      rule(_longEnough, tr(context, 'At least $kMinPasswordLength characters', 'Vähintään $kMinPasswordLength merkkiä')),
      if (!_notTooLong) rule(false, tr(context, 'At most 72 characters', 'Enintään 72 merkkiä')),
      if (typed && !_notBlank) rule(false, tr(context, 'Not only spaces', 'Ei pelkkiä välilyöntejä')),
      _message(),
      const SizedBox(height: 18),
      _primary(label: tr(context, 'Save and sign in', 'Tallenna ja kirjaudu'), onPressed: _passwordOk ? _reset : null),
    ];
  }

  List<Widget> _unavailableStep() => [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.support_agent_rounded, color: MPalette.amberInk, size: 30),
        ),
        const SizedBox(height: 14),
        _title(tr(context, 'We can help you get back in', 'Autamme sinut takaisin sisään')),
        _body(tr(context,
            'Resetting a password by email is not available right now. Send a message to the Malvoya team and we will help you get back into your account. If you also signed up with your phone number or Google, you can sign in with that.',
            'Salasanan vaihto sähköpostilla ei ole juuri nyt käytettävissä. Lähetä viesti Malvoyan tiimille, niin autamme sinut takaisin tilillesi. Jos rekisteröidyit myös puhelinnumerolla tai Googlella, voit kirjautua niillä.')),
        const SizedBox(height: MSpace.xl),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const HelpScreen()));
            },
            icon: const Icon(Icons.support_agent_rounded),
            label: Text(tr(context, 'Contact support', 'Ota yhteyttä tukeen')),
          ),
        ),
        const SizedBox(height: MSpace.sm),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'Back to sign-in', 'Takaisin kirjautumiseen')),
          ),
        ),
      ];
}

/// Six boxes over one invisible text field: typing moves to the next box by itself, backspace
/// goes back, and pasting or the keyboard's one-time-code suggestion fills all boxes at once.
class _CodeBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final VoidCallback onSubmitted;

  const _CodeBoxes({required this.controller, required this.focusNode, required this.length, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(context, '6-digit code', '6-numeroinen koodi'),
      textField: true,
      child: Stack(children: [
        ListenableBuilder(
          listenable: Listenable.merge([controller, focusNode]),
          builder: (context, _) {
            final text = controller.text;
            return Row(children: [
              for (var i = 0; i < length; i++) ...[
                if (i > 0) const SizedBox(width: MSpace.sm),
                Expanded(
                  child: AnimatedContainer(
                    duration: MMotion.fast,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.sand,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: focusNode.hasFocus && (i == text.length || (i == length - 1 && text.length == length))
                            ? AppTheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(i < text.length ? text[i] : '', style: AppTheme.display(size: 26)),
                  ),
                ),
              ],
            ]);
          },
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              showCursor: false,
              enableInteractiveSelection: true,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => onSubmitted(),
              decoration: const InputDecoration(filled: false, border: InputBorder.none, counterText: ''),
            ),
          ),
        ),
      ]),
    );
  }
}
