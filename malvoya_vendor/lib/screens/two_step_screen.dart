import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Store → Two-step sign-in (API 2.13 `/me/mfa`, offered to stores since 2.16; optional).
/// With it on, signing in also asks for a code from an authenticator app, and payout links open
/// without asking for the password again. The secret is shown as text with a copy button and an
/// "open in authenticator app" link (the app has no QR package; the setup key works in every app).
class TwoStepScreen extends StatefulWidget {
  const TwoStepScreen({super.key});

  @override
  State<TwoStepScreen> createState() => _TwoStepScreenState();
}

class _TwoStepScreenState extends State<TwoStepScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Set-up in progress: the secret from POST /me/mfa/setup (shown once).
  String? _secret;
  String? _otpauthUrl;
  final _code = TextEditingController();
  String? _codeError;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);
  ApiClient get _api => ApiClient(_auth);
  bool get _enabled => _status?['enabled'] == true;
  bool get _needsPassword => _status?['needsPassword'] != false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _api.get('/me/mfa');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.ok ? null : res.errorMessage;
      if (res.ok) _status = res.data;
    });
  }

  Future<void> _startSetup() async {
    String? password;
    if (_needsPassword) {
      final answers = await askCredentials(context,
          title: tr(context, 'Confirm it is you', 'Vahvista henkilöllisyytesi'),
          action: tr(context, 'Continue', 'Jatka'),
          password: true);
      if (answers == null || !mounted) return;
      password = answers.password;
    }
    setState(() => _busy = true);
    final res = await _api.post('/me/mfa/setup', {if (password != null) 'password': password});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    final secret = res.data['secret'];
    if (secret is! String || secret.isEmpty) {
      MSnack.error(context, tr(context, 'The set-up key is missing. Please try again.', 'Asetusavain puuttuu. Yritä uudelleen.'));
      return;
    }
    setState(() {
      _secret = secret;
      _otpauthUrl = res.data['otpauthUrl'] is String ? res.data['otpauthUrl'] as String : null;
      _code.clear();
      _codeError = null;
    });
  }

  Future<void> _openAuthenticator() async {
    final url = _otpauthUrl;
    var opened = false;
    if (url != null) {
      try {
        opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!opened && mounted) {
      MSnack.show(context, tr(context, 'No authenticator app opened it. Copy the key and add it in the app by hand.',
          'Mikään todennussovellus ei avannut sitä. Kopioi avain ja lisää se sovellukseen käsin.'));
    }
  }

  Future<void> _enable() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (code.length != 6) {
      setState(() => _codeError = tr(context, 'Enter the 6-digit code from your authenticator app.', 'Anna todennussovelluksen 6-numeroinen koodi.'));
      return;
    }
    setState(() {
      _busy = true;
      _codeError = null;
    });
    final res = await _api.post('/me/mfa/enable', {'code': code});
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        _codeError = res.errorMessage;
      });
      return;
    }
    // Turning it on ends every older session (this one too) and returns a fresh one
    final err = await _auth.adoptSession(res.data);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _secret = null;
      _otpauthUrl = null;
      _code.clear();
    });
    if (err != null) MSnack.error(context, err);
    final codes = _codesFrom(res.data);
    if (codes.isNotEmpty) await Navigator.push(context, MaterialPageRoute(builder: (_) => RecoveryCodesScreen(codes: codes)));
    if (!mounted) return;
    MSnack.success(context, tr(context, 'Two-step sign-in is on. Other devices were signed out.', 'Kaksivaiheinen kirjautuminen on käytössä. Muut laitteet kirjattiin ulos.'));
    _load();
  }

  Future<void> _newRecoveryCodes() async {
    final answers = await askCredentials(context,
        title: tr(context, 'New recovery codes', 'Uudet palautuskoodit'),
        message: tr(context, 'Your old recovery codes stop working.', 'Vanhat palautuskoodisi lakkaavat toimimasta.'),
        action: tr(context, 'Make new codes', 'Luo uudet koodit'),
        code: true);
    if (answers == null || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.post('/me/mfa/recovery-codes', {'code': answers.code});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    final codes = _codesFrom(res.data);
    if (codes.isNotEmpty) await Navigator.push(context, MaterialPageRoute(builder: (_) => RecoveryCodesScreen(codes: codes)));
    if (mounted) _load();
  }

  Future<void> _disable() async {
    final answers = await askCredentials(context,
        title: tr(context, 'Turn two-step sign-in off?', 'Poistetaanko kaksivaiheinen kirjautuminen?'),
        message: tr(context, 'Signing in then needs only your password or sign-in code again, and payout links ask for your password.',
            'Kirjautumiseen riittää sen jälkeen taas salasana tai kirjautumiskoodi, ja tilityslinkit kysyvät salasanaasi.'),
        action: tr(context, 'Turn off', 'Poista käytöstä'),
        password: _needsPassword,
        code: true,
        codeHelper: tr(context, 'Or one of your recovery codes.', 'Tai yksi palautuskoodeistasi.'),
        danger: true);
    if (answers == null || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.post('/me/mfa/disable', {'code': answers.code, if (answers.password != null) 'password': answers.password});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    MSnack.success(context, tr(context, 'Two-step sign-in is off.', 'Kaksivaiheinen kirjautuminen on poistettu käytöstä.'));
    _load();
  }

  static List<String> _codesFrom(Map<String, dynamic> data) =>
      ((data['recoveryCodes'] as List?) ?? const []).map((c) => '$c').where((c) => c.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Two-step sign-in', 'Kaksivaiheinen kirjautuminen'))),
      body: _loading
          ? const MSkeletonList(count: 2, lines: 4, button: true)
          : _status == null
              ? MStateMessage.error(message: _error, onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })
              : ListView(
                  padding: const EdgeInsets.all(MSpace.lg),
                  children: _secret != null ? _setupSteps() : (_enabled ? _onView() : _offView()),
                ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _body(String text) => Text(text, style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: MTextSize.bodyM));

  List<Widget> _offView() => [
        _card([
          const Icon(Icons.shield_outlined, color: AppTheme.textSecondary),
          const SizedBox(height: MSpace.sm),
          Text(tr(context, 'Off', 'Ei käytössä'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title)),
          const SizedBox(height: MSpace.sm),
          _body(tr(context,
              'Protect your store and its payouts: when you sign in, Malvoya also asks for a 6-digit code from an authenticator app on your phone (for example Google Authenticator, Microsoft Authenticator or 1Password). Optional.',
              'Suojaa kauppasi ja sen tilitykset: kirjautuessasi Malvoya kysyy myös 6-numeroista koodia puhelimesi todennussovelluksesta (esimerkiksi Google Authenticator, Microsoft Authenticator tai 1Password). Vapaaehtoinen.')),
          const SizedBox(height: MSpace.sm),
          _body(tr(context, 'With it on, Stripe payout links open without asking for your password again.',
              'Kun se on käytössä, Stripen tilityslinkit avautuvat kysymättä salasanaa uudelleen.')),
          const SizedBox(height: MSpace.lg),
          MButton(label: tr(context, 'Turn on', 'Ota käyttöön'), icon: Icons.lock_outline_rounded, expand: true, loading: _busy, onPressed: _busy ? null : _startSetup),
        ]),
      ];

  List<Widget> _onView() {
    final enabledAt = parseApiDate(_status?['enabledAt']);
    final left = asInt(_status?['recoveryCodesLeft']);
    return [
      _card([
        const Icon(Icons.verified_user_rounded, color: AppTheme.primary),
        const SizedBox(height: MSpace.sm),
        Text(tr(context, 'On', 'Käytössä'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title, color: AppTheme.primary)),
        const SizedBox(height: MSpace.xs),
        if (enabledAt != null) _body(tr(context, 'Since ${dateText(context, enabledAt)}', '${dateText(context, enabledAt)} alkaen')),
        const SizedBox(height: MSpace.sm),
        _body(tr(context, 'Signing in asks for a code from your authenticator app. Keep your recovery codes somewhere safe in case you lose the phone.',
            'Kirjautuminen kysyy koodia todennussovelluksestasi. Säilytä palautuskoodit turvallisessa paikassa siltä varalta, että puhelin katoaa.')),
        if (left != null) ...[
          const SizedBox(height: MSpace.sm),
          Text(
            tr(context, 'Recovery codes left: $left', 'Palautuskoodeja jäljellä: $left'),
            style: TextStyle(fontWeight: FontWeight.w700, color: left <= 2 ? AppTheme.amberInk : AppTheme.textPrimary),
          ),
        ],
      ]),
      const SizedBox(height: MSpace.lg),
      MButton(label: tr(context, 'New recovery codes', 'Uudet palautuskoodit'), variant: MButtonVariant.secondary, icon: Icons.key_rounded, expand: true, onPressed: _busy ? null : _newRecoveryCodes),
      const SizedBox(height: MSpace.sm),
      MButton(label: tr(context, 'Turn off', 'Poista käytöstä'), variant: MButtonVariant.outline, expand: true, loading: _busy, onPressed: _busy ? null : _disable),
    ];
  }

  List<Widget> _setupSteps() {
    final grouped = _secret!.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim();
    return [
      _card([
        Text(tr(context, '1. Add Malvoya to your authenticator app', '1. Lisää Malvoya todennussovellukseesi'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
        const SizedBox(height: MSpace.sm),
        _body(tr(context, 'Open the link in your authenticator app on this phone, or add an account by hand ("Enter a setup key", time based) with this key:',
            'Avaa linkki tämän puhelimen todennussovelluksessa tai lisää tili käsin ("Anna asetusavain", aikaperusteinen) tällä avaimella:')),
        const SizedBox(height: MSpace.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(MSpace.md),
          decoration: BoxDecoration(color: AppTheme.sand, borderRadius: MRadius.brMd),
          child: SelectableText(grouped,
              style: const TextStyle(fontFamily: 'monospace', fontSize: MTextSize.bodyL, fontWeight: FontWeight.w700, letterSpacing: 1.2, height: 1.5)),
        ),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.xs, children: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _secret!));
              if (mounted) MSnack.show(context, tr(context, 'Key copied', 'Avain kopioitu'));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(tr(context, 'Copy key', 'Kopioi avain')),
          ),
          if (_otpauthUrl != null)
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _openAuthenticator,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(tr(context, 'Open in authenticator app', 'Avaa todennussovelluksessa')),
            ),
        ]),
        _body(tr(context, 'Keep the key private: anyone with it can make your codes.', 'Pidä avain omana tietonasi: sillä voi luoda koodejasi.')),
      ]),
      const SizedBox(height: MSpace.lg),
      _card([
        Text(tr(context, '2. Enter the code it shows', '2. Anna sen näyttämä koodi'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL)),
        const SizedBox(height: MSpace.md),
        MTextField(
          controller: _code,
          label: tr(context, '6-digit code', '6-numeroinen koodi'),
          prefixIcon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          errorText: _codeError,
          onChanged: (_) {
            if (_codeError != null) setState(() => _codeError = null);
          },
          onSubmitted: (_) => _enable(),
        ),
        const SizedBox(height: MSpace.md),
        MButton(label: tr(context, 'Turn on', 'Ota käyttöön'), expand: true, loading: _busy, onPressed: _busy ? null : _enable),
        const SizedBox(height: MSpace.sm),
        _body(tr(context, 'Turning it on signs out your other devices.', 'Käyttöönotto kirjaa muut laitteesi ulos.')),
      ]),
      const SizedBox(height: MSpace.sm),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: _busy ? null : () => setState(() => _secret = null),
        child: Text(tr(context, 'Cancel', 'Peruuta')),
      ),
    ];
  }
}

/// The one-time recovery codes after turning two-step sign-in on or renewing them. They are shown
/// only here; the server keeps hashes.
class RecoveryCodesScreen extends StatelessWidget {
  final List<String> codes;
  const RecoveryCodesScreen({super.key, required this.codes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Recovery codes', 'Palautuskoodit')), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(MSpace.lg), children: [
          Text(
            tr(context,
                'Save these codes somewhere safe, away from this phone (for example in a password manager or on paper). Each code signs you in once if you cannot use your authenticator app. They are not shown again.',
                'Tallenna nämä koodit turvalliseen paikkaan erilleen tästä puhelimesta (esimerkiksi salasanojen hallintaan tai paperille). Kukin koodi kirjaa sinut sisään kerran, jos et voi käyttää todennussovellusta. Niitä ei näytetä uudelleen.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.45, fontSize: MTextSize.bodyM),
          ),
          const SizedBox(height: MSpace.lg),
          Container(
            padding: const EdgeInsets.all(MSpace.lg),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.divider)),
            child: Wrap(
              spacing: MSpace.xl,
              runSpacing: MSpace.sm,
              children: [
                for (final c in codes)
                  SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontSize: MTextSize.bodyL, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(height: MSpace.md),
          MButton(
            label: tr(context, 'Copy all', 'Kopioi kaikki'),
            variant: MButtonVariant.secondary,
            icon: Icons.copy_rounded,
            expand: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              if (context.mounted) MSnack.show(context, tr(context, 'Codes copied', 'Koodit kopioitu'));
            },
          ),
          const SizedBox(height: MSpace.sm),
          MButton(label: tr(context, 'I have saved them', 'Olen tallentanut ne'), expand: true, onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}

/// What [askCredentials] collected.
class CredentialAnswers {
  final String? password;
  final String? code;
  const CredentialAnswers({this.password, this.code});
}

/// A small sheet asking for the password and/or a two-step code. Null when cancelled.
Future<CredentialAnswers?> askCredentials(
  BuildContext context, {
  required String title,
  required String action,
  String? message,
  bool password = false,
  bool code = false,
  String? codeHelper,
  bool danger = false,
}) {
  return showMSheet<CredentialAnswers>(context, builder: (ctx) => _CredentialSheet(
        title: title,
        action: action,
        message: message,
        askPassword: password,
        askCode: code,
        codeHelper: codeHelper,
        danger: danger,
      ));
}

class _CredentialSheet extends StatefulWidget {
  final String title;
  final String action;
  final String? message;
  final bool askPassword;
  final bool askCode;
  final String? codeHelper;
  final bool danger;
  const _CredentialSheet(
      {required this.title, required this.action, this.message, required this.askPassword, required this.askCode, this.codeHelper, required this.danger});

  @override
  State<_CredentialSheet> createState() => _CredentialSheetState();
}

class _CredentialSheetState extends State<_CredentialSheet> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _ready =>
      (!widget.askPassword || _password.text.isNotEmpty) && (!widget.askCode || _code.text.replaceAll(RegExp(r'\s'), '').length >= 6);

  void _submit() {
    if (!_ready) return;
    Navigator.pop(
        context,
        CredentialAnswers(
          password: widget.askPassword ? _password.text : null,
          code: widget.askCode ? _code.text.replaceAll(RegExp(r'\s'), '') : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return MSheet(
      title: widget.title,
      subtitle: widget.message,
      actions: [
        MButton(
          label: widget.action,
          variant: widget.danger ? MButtonVariant.danger : MButtonVariant.primary,
          expand: true,
          onPressed: _ready ? _submit : null,
        ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.askPassword)
          MTextField(
            controller: _password,
            autofocus: true,
            label: tr(context, 'Password', 'Salasana'),
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: widget.askCode ? TextInputAction.next : TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              tooltip: _obscure ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        if (widget.askPassword && widget.askCode) const SizedBox(height: MSpace.md),
        if (widget.askCode)
          MTextField(
            controller: _code,
            autofocus: !widget.askPassword,
            label: tr(context, 'Code from the authenticator app', 'Todennussovelluksen koodi'),
            helper: widget.codeHelper,
            prefixIcon: Icons.password_rounded,
            keyboardType: TextInputType.visiblePassword,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        const SizedBox(height: MSpace.md),
      ]),
    );
  }
}
