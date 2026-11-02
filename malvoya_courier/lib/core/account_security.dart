import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

// Account security (API 2.16): the second sign-in step, "I am 18 or older" for new accounts made
// with Google or a phone number, two-step sign-in in the account settings and the list of
// signed-in devices.

/// Minimum length of a new password (register, reset). The server checks it too.
const int kMinPasswordLength = 10;

// ── Sign-in: the second step ─────────────────────────────────────────────────

/// Asks for the code from the authenticator app (or a recovery code) and finishes the sign-in.
/// Null when signed in, otherwise the message to show.
Future<String?> showTwoStepSignIn(BuildContext context, AuthService auth, String mfaToken) async {
  final code = TextEditingController();
  var signedIn = false;
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> verify() async {
        if (busy || code.text.trim().length < 6) return;
        setLocal(() {
          busy = true;
          error = null;
        });
        final err = await auth.completeTwoStep(mfaToken, code.text);
        if (err == null) {
          signedIn = true;
          // Signing in closes every screen above the home screen, this dialog included
          if (ctx.mounted && (ModalRoute.of(ctx)?.isCurrent ?? false)) Navigator.pop(ctx);
          return;
        }
        if (!ctx.mounted) return;
        setLocal(() {
          busy = false;
          error = err;
        });
      }

      return AlertDialog(
        title: Text(tr(ctx, 'Two-step sign-in', 'Kaksivaiheinen kirjautuminen')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr(ctx, 'Enter the 6-digit code from your authenticator app. Lost the phone? Enter one of your recovery codes instead.',
                  'Anna todennussovelluksen 6-numeroinen koodi. Puhelin hukassa? Anna sen sijaan yksi varakoodeistasi.'),
              style: const TextStyle(height: 1.4, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: MSpace.md),
            TextField(
              controller: code,
              autofocus: true,
              maxLength: 20,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => verify(),
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(labelText: tr(ctx, 'Code', 'Koodi'), counterText: ''),
            ),
            if (error != null) ...[
              const SizedBox(height: MSpace.sm),
              Text(error!, style: const TextStyle(color: AppTheme.dangerInk, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          FilledButton(
            onPressed: busy || code.text.trim().length < 6 ? null : verify,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                : Text(tr(ctx, 'Sign in', 'Kirjaudu')),
          ),
        ],
      );
    }),
  );
  code.dispose();
  return signedIn ? null : AppLanguage.pick('Sign-in cancelled.', 'Kirjautuminen peruttiin.');
}

// ── Age ──────────────────────────────────────────────────────────────────────

/// "I am 18 or older", asked once when Google or a phone number would create a new account.
Future<bool> showAgeConfirmation(BuildContext context) async {
  var ticked = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr(ctx, 'Create your courier account', 'Luo lähettitilisi')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr(ctx, 'There is no Malvoya account for this sign-in yet. Couriers must be at least 18 years old.',
                'Tällä kirjautumisella ei ole vielä Malvoya-tiliä. Lähettien on oltava vähintään 18-vuotiaita.'),
            style: const TextStyle(height: 1.4, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: MSpace.sm),
          AgeCheckbox(value: ticked, onChanged: (v) => setLocal(() => ticked = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          FilledButton(onPressed: ticked ? () => Navigator.pop(ctx, true) : null, child: Text(tr(ctx, 'Continue', 'Jatka'))),
        ],
      ),
    ),
  );
  return ok == true;
}

/// The "I am 18 or older" checkbox (never pre-ticked).
class AgeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AgeCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => CheckboxListTile(
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppTheme.primary,
        title: Text(
          tr(context, 'I am 18 or older', 'Olen vähintään 18-vuotias'),
          style: const TextStyle(fontSize: MTextSize.bodyL, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
      );
}

// ── Account settings: two-step sign-in ───────────────────────────────────────

/// "Two-step sign-in" in the account sheet. Hidden when the server does not offer it to couriers.
class TwoStepTile extends StatefulWidget {
  const TwoStepTile({super.key});

  @override
  State<TwoStepTile> createState() => _TwoStepTileState();
}

class _TwoStepTileState extends State<TwoStepTile> {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _offered = true;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiClient(_auth).get('/me/mfa');
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 403/404: an older server that offers it to admins only
      _offered = res.ok || (res.status != 403 && res.status != 404);
      _state = res.ok ? res.data : null;
    });
  }

  Future<void> _open() async {
    final s = _state;
    if (s == null) {
      setState(() => _loading = true);
      await _load();
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TwoStepScreen(initial: s)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_offered) return const SizedBox.shrink();
    final on = _state?['enabled'] == true;
    final left = asInt(_state?['recoveryCodesLeft']);
    return ListTile(
      leading: Icon(on ? Icons.verified_user_rounded : Icons.shield_outlined, color: on ? AppTheme.success : null),
      title: Text(tr(context, 'Two-step sign-in', 'Kaksivaiheinen kirjautuminen'), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(_loading
          ? tr(context, 'Checking…', 'Tarkistetaan…')
          : _state == null
              ? tr(context, 'Could not load. Tap to try again.', 'Ei voitu ladata. Yritä uudelleen napauttamalla.')
              : on
                  ? '${tr(context, 'On', 'Päällä')}${left != null ? ' · ${tr(context, '$left recovery codes left', 'varakoodeja jäljellä $left')}' : ''}'
                  : tr(context, 'Off · a code from an authenticator app at sign-in', 'Pois · todennussovelluksen koodi kirjautuessa')),
      trailing: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right_rounded),
      onTap: _loading ? null : _open,
    );
  }
}

/// Turning two-step sign-in on (key → first code → recovery codes) or off, and new recovery codes.
class TwoStepScreen extends StatefulWidget {
  final Map<String, dynamic> initial;

  const TwoStepScreen({super.key, required this.initial});

  @override
  State<TwoStepScreen> createState() => _TwoStepScreenState();
}

class _TwoStepScreenState extends State<TwoStepScreen> {
  late Map<String, dynamic> _state = widget.initial;
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  // Set-up in progress: the key from POST /me/mfa/setup
  String? _secret;
  String? _otpauthUrl;
  // Shown once, right after they were made
  List<String>? _recoveryCodes;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);
  bool get _enabled => _state['enabled'] == true;
  bool get _needsPassword => _state['needsPassword'] != false;

  @override
  void initState() {
    super.initState();
    _password.addListener(_changed);
    _code.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  List<String> _codesOf(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];

  Future<void> _reload() async {
    final res = await ApiClient(_auth).get('/me/mfa');
    if (mounted && res.ok) setState(() => _state = res.data);
  }

  Future<void> _startSetup() async {
    if (_needsPassword && _password.text.isEmpty) {
      return setState(() => _error = tr(context, 'Enter your password.', 'Anna salasanasi.'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ApiClient(_auth).post('/me/mfa/setup', {if (_needsPassword) 'password': _password.text});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok && res.data['secret'] is String) {
        _secret = res.data['secret'] as String;
        _otpauthUrl = res.data['otpauthUrl'] is String ? res.data['otpauthUrl'] as String : null;
        _password.clear();
      } else {
        _error = res.ok ? tr(context, 'Something went wrong. Please try again.', 'Jotain meni vikaan. Yritä uudelleen.') : res.errorMessage;
      }
    });
  }

  Future<void> _enable() async {
    if (_code.text.trim().length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ApiClient(_auth).post('/me/mfa/enable', {'code': _code.text.replaceAll(' ', '').trim()});
    if (!mounted) return;
    if (!res.ok) {
      return setState(() {
        _busy = false;
        _error = res.errorMessage;
      });
    }
    // Every older session ended on the server; this phone continues with the fresh one
    final err = await _auth.applyFreshSession(res.data);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _secret = null;
      _otpauthUrl = null;
      _code.clear();
      _recoveryCodes = _codesOf(res.data['recoveryCodes']);
      _state = {..._state, 'enabled': true, 'recoveryCodesLeft': _recoveryCodes!.length};
      if (err != null) _error = err;
    });
    await _reload();
  }

  Future<void> _disable() async {
    if (_code.text.trim().length < 6) return;
    if (_needsPassword && _password.text.isEmpty) {
      return setState(() => _error = tr(context, 'Enter your password.', 'Anna salasanasi.'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ApiClient(_auth).post('/me/mfa/disable', {
      'code': _code.text.replaceAll(' ', '').trim(),
      if (_needsPassword) 'password': _password.text,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!res.ok) _error = res.errorMessage;
    });
    if (!res.ok) return;
    MSnack.show(context, tr(context, 'Two-step sign-in is off.', 'Kaksivaiheinen kirjautuminen on pois päältä.'));
    Navigator.pop(context);
  }

  Future<void> _newRecoveryCodes() async {
    if (_code.text.trim().length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ApiClient(_auth).post('/me/mfa/recovery-codes', {'code': _code.text.replaceAll(' ', '').trim()});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _recoveryCodes = _codesOf(res.data['recoveryCodes']);
        _code.clear();
      } else {
        _error = res.errorMessage;
      }
    });
    if (res.ok) await _reload();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) MSnack.show(context, done);
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

  // ── UI ──

  Widget _title(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: AppTheme.display(size: 22)));

  Widget _body(String t) => Text(t, style: const TextStyle(color: AppTheme.textSecondary, height: 1.45));

  Widget _passwordField() => TextField(
        controller: _password,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: tr(context, 'Your password', 'Salasanasi'),
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _obscure ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );

  Widget _codeField({String? label}) => TextField(
        controller: _code,
        maxLength: 20,
        keyboardType: TextInputType.visiblePassword,
        autofillHints: const [AutofillHints.oneTimeCode],
        decoration: InputDecoration(
          labelText: label ?? tr(context, 'Code from the authenticator app', 'Todennussovelluksen koodi'),
          prefixIcon: const Icon(Icons.pin_outlined),
          counterText: '',
        ),
      );

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(top: MSpace.md),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppTheme.dangerLight, borderRadius: BorderRadius.circular(MRadius.sm)),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppTheme.dangerInk, size: 18),
            const SizedBox(width: MSpace.sm),
            Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.dangerInk, fontWeight: FontWeight.w600))),
          ]),
        );

  List<Widget> _recoveryView(List<String> codes) => [
        _title(tr(context, 'Save your recovery codes', 'Tallenna varakoodisi')),
        _body(tr(context,
            'Each code signs you in once if you lose the phone with the authenticator app. Keep them somewhere safe, outside this phone. They are shown only now.',
            'Jokaisella koodilla pääset kerran sisään, jos todennussovelluksen puhelin katoaa. Säilytä ne turvallisessa paikassa muualla kuin tässä puhelimessa. Ne näytetään vain nyt.')),
        const SizedBox(height: MSpace.lg),
        Container(
          padding: const EdgeInsets.all(MSpace.lg),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.md), border: Border.all(color: AppTheme.divider)),
          child: SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: MTextSize.bodyL, height: 1.6, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: MSpace.md),
        OutlinedButton.icon(
          onPressed: () => _copy(codes.join('\n'), tr(context, 'Recovery codes copied.', 'Varakoodit kopioitu.')),
          icon: const Icon(Icons.copy_rounded),
          label: Text(tr(context, 'Copy the codes', 'Kopioi koodit')),
        ),
        const SizedBox(height: MSpace.lg),
        MButton(label: tr(context, 'I have saved them', 'Olen tallentanut ne'), expand: true, onPressed: () => Navigator.pop(context)),
      ];

  List<Widget> _setupStart() => [
        _title(tr(context, 'Protect your account with a second step', 'Suojaa tilisi toisella vaiheella')),
        _body(tr(context,
            'After your password, Google or phone code, Malvoya also asks for a 6-digit code from an authenticator app (for example Google Authenticator or Microsoft Authenticator). Someone who learns your password still cannot sign in or change your payout account.',
            'Salasanan, Googlen tai puhelinkoodin jälkeen Malvoya kysyy myös 6-numeroisen koodin todennussovelluksesta (esimerkiksi Google Authenticator tai Microsoft Authenticator). Vaikka joku saisi salasanasi selville, hän ei pääse kirjautumaan tai muuttamaan tilitietojasi.')),
        const SizedBox(height: MSpace.lg),
        if (_needsPassword) _passwordField(),
        _errorBox(),
        const SizedBox(height: MSpace.lg),
        MButton(label: tr(context, 'Set it up', 'Ota käyttöön'), expand: true, loading: _busy, onPressed: _busy ? null : _startSetup),
      ];

  List<Widget> _setupKey(String secret) {
    final grouped = RegExp(r'.{1,4}').allMatches(secret).map((m) => m.group(0)).join(' ');
    return [
      _title(tr(context, 'Add Malvoya to your authenticator app', 'Lisää Malvoya todennussovellukseesi')),
      _body(tr(context,
          'Open the authenticator app with the button below, or add an account there by hand with this key (time-based). Never share the key with anyone.',
          'Avaa todennussovellus alla olevalla painikkeella tai lisää sinne tili käsin tällä avaimella (aikaperusteinen). Älä koskaan jaa avainta kenellekään.')),
      const SizedBox(height: MSpace.lg),
      Container(
        padding: const EdgeInsets.all(MSpace.lg),
        decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(MRadius.md)),
        child: SelectableText(grouped, style: const TextStyle(fontFamily: 'monospace', fontSize: MTextSize.bodyL, fontWeight: FontWeight.w700, height: 1.5)),
      ),
      const SizedBox(height: MSpace.sm),
      Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
        OutlinedButton.icon(
          onPressed: () => _copy(secret, tr(context, 'Key copied.', 'Avain kopioitu.')),
          icon: const Icon(Icons.copy_rounded),
          label: Text(tr(context, 'Copy the key', 'Kopioi avain')),
        ),
        if (_otpauthUrl != null)
          OutlinedButton.icon(
            onPressed: _openAuthenticator,
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(tr(context, 'Open authenticator app', 'Avaa todennussovellus')),
          ),
      ]),
      const SizedBox(height: MSpace.xl),
      _body(tr(context, 'Then enter the 6-digit code the app shows for Malvoya:', 'Anna sitten sovelluksen Malvoyalle näyttämä 6-numeroinen koodi:')),
      const SizedBox(height: MSpace.sm),
      _codeField(),
      _errorBox(),
      const SizedBox(height: MSpace.lg),
      MButton(
        label: tr(context, 'Turn on', 'Ota käyttöön'),
        expand: true,
        loading: _busy,
        onPressed: _busy || _code.text.trim().length < 6 ? null : _enable,
      ),
    ];
  }

  List<Widget> _enabledView() {
    final left = asInt(_state['recoveryCodesLeft']);
    return [
      Row(children: [
        const Icon(Icons.verified_user_rounded, color: AppTheme.success, size: 28),
        const SizedBox(width: MSpace.sm),
        Expanded(child: _title(tr(context, 'Two-step sign-in is on', 'Kaksivaiheinen kirjautuminen on päällä'))),
      ]),
      _body(left == null
          ? tr(context, 'Each sign-in asks for a code from your authenticator app.', 'Jokainen kirjautuminen kysyy todennussovelluksen koodin.')
          : tr(context, 'Each sign-in asks for a code from your authenticator app. Recovery codes left: $left.',
              'Jokainen kirjautuminen kysyy todennussovelluksen koodin. Varakoodeja jäljellä: $left.')),
      const SizedBox(height: MSpace.xl),
      _body(tr(context, 'To make new recovery codes or turn it off, enter a current code:', 'Anna voimassa oleva koodi tehdäksesi uudet varakoodit tai poistaaksesi toiminnon:')),
      const SizedBox(height: MSpace.sm),
      _codeField(label: tr(context, 'Authenticator or recovery code', 'Todennus- tai varakoodi')),
      if (_needsPassword) ...[
        const SizedBox(height: MSpace.md),
        _passwordField(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr(context, 'The password is needed only to turn it off.', 'Salasanaa tarvitaan vain poistamiseen.'),
              style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.textSecondary)),
        ),
      ],
      _errorBox(),
      const SizedBox(height: MSpace.lg),
      MButton(
        label: tr(context, 'Make new recovery codes', 'Tee uudet varakoodit'),
        expand: true,
        variant: MButtonVariant.secondary,
        loading: _busy,
        onPressed: _busy || _code.text.trim().length < 6 ? null : _newRecoveryCodes,
      ),
      const SizedBox(height: MSpace.sm),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _busy || _code.text.trim().length < 6 ? null : _disable,
          child: Text(tr(context, 'Turn two-step sign-in off', 'Poista kaksivaiheinen kirjautuminen'),
              style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final codes = _recoveryCodes;
    final secret = _secret;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Two-step sign-in', 'Kaksivaiheinen kirjautuminen'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MSpace.xxl, MSpace.md, MSpace.xxl, MSpace.x3l),
          children: codes != null
              ? _recoveryView(codes)
              : secret != null
                  ? _setupKey(secret)
                  : _enabled
                      ? _enabledView()
                      : _setupStart(),
        ),
      ),
    );
  }
}

// ── Account settings: signed-in devices ──────────────────────────────────────

/// Settings → Signed-in devices: every session of this account, with sign-out per device or for
/// all others (`GET/DELETE /me/sessions`).
class SignedInDevicesScreen extends StatefulWidget {
  const SignedInDevicesScreen({super.key});

  @override
  State<SignedInDevicesScreen> createState() => _SignedInDevicesScreenState();
}

class _SignedInDevicesScreenState extends State<SignedInDevicesScreen> {
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};
  bool _busyAll = false;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiClient(_auth).get('/me/sessions');
    if (!mounted) return;
    final list = res.data['sessions'];
    setState(() {
      _loading = false;
      _error = res.ok ? null : (res.status == 404 ? tr(context, 'This is not available yet.', 'Tämä ei ole vielä käytettävissä.') : res.errorMessage);
      if (res.ok) {
        _sessions = (list is List ? list : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          ..sort((a, b) => (_isCurrent(b) ? 1 : 0) - (_isCurrent(a) ? 1 : 0));
      }
    });
  }

  bool _isCurrent(Map s) => s['current'] == true || s['isCurrent'] == true;

  String _device(Map s) {
    for (final k in ['device', 'deviceName', 'userAgentFamily', 'uaFamily', 'userAgent']) {
      final v = s[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final label = v['label'] ?? v['name'] ?? v['family'];
        if (label is String && label.trim().isNotEmpty) return label.trim();
      }
    }
    return tr(context, 'Unknown device', 'Tuntematon laite');
  }

  String? _when(dynamic v) {
    final t = v is String ? DateTime.tryParse(v)?.toLocal() : null;
    if (t == null) return null;
    final now = DateTime.now();
    final minutes = now.difference(t).inMinutes;
    if (minutes < 2) return tr(context, 'just now', 'juuri nyt');
    if (minutes < 60) return tr(context, '$minutes min ago', '$minutes min sitten');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.day}.${t.month}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _signOut(Map<String, dynamic> s) async {
    final id = '${s['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _busy.add(id));
    final res = await ApiClient(_auth).delete('/me/sessions/${Uri.encodeComponent(id)}');
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (!res.ok) {
      MSnack.show(context, res.errorMessage);
      return;
    }
    MSnack.show(context, tr(context, '${_device(s)} was signed out.', '${_device(s)} kirjattiin ulos.'));
    await _load();
  }

  Future<void> _signOutOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'Sign out every other device?', 'Kirjataanko kaikki muut laitteet ulos?')),
        content: Text(tr(ctx, 'This phone stays signed in. Others have to sign in again.', 'Tämä puhelin pysyy kirjautuneena. Muiden on kirjauduttava uudelleen.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'Cancel', 'Peruuta'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'Sign them out', 'Kirjaa ulos'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyAll = true);
    final res = await ApiClient(_auth).delete('/me/sessions');
    if (!mounted) return;
    setState(() => _busyAll = false);
    if (!res.ok) {
      MSnack.show(context, res.errorMessage);
      return;
    }
    MSnack.show(context, tr(context, 'Every other device was signed out.', 'Kaikki muut laitteet kirjattiin ulos.'));
    await _load();
  }

  Widget _tile(Map<String, dynamic> s) {
    final current = _isCurrent(s);
    final id = '${s['id'] ?? ''}';
    final created = _when(s['createdAt']);
    final used = _when(s['lastUsedAt'] ?? s['lastUsed']);
    final lines = [
      if (used != null) tr(context, 'Last active $used', 'Viimeksi käytössä $used'),
      if (created != null) tr(context, 'Signed in $created', 'Kirjautunut $created'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.sm),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(MRadius.md), border: Border.all(color: AppTheme.divider)),
      child: ListTile(
        leading: Icon(current ? Icons.smartphone_rounded : Icons.devices_other_rounded, color: current ? AppTheme.primary : AppTheme.textSecondary),
        title: Text(_device(s), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([if (current) tr(context, 'This phone', 'Tämä puhelin'), ...lines].join('\n'), style: const TextStyle(height: 1.35)),
        isThreeLine: lines.length > 1 || (current && lines.isNotEmpty),
        trailing: current
            ? null
            : _busy.contains(id)
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: id.isEmpty ? null : () => _signOut(s), child: Text(tr(context, 'Sign out', 'Kirjaa ulos'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final others = _sessions.where((s) => !_isCurrent(s)).length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Signed-in devices', 'Kirjautuneet laitteet'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? MStateMessage(
                  centered: true,
                  kind: MStateKind.error,
                  icon: Icons.cloud_off_rounded,
                  message: _error!,
                  onAction: () {
                    setState(() => _loading = true);
                    _load();
                  },
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x3l),
                    children: [
                      Text(
                        tr(context, 'Phones and browsers signed in to your courier account. Sign out any you do not recognise, then change your password.',
                            'Lähettitiliisi kirjautuneet puhelimet ja selaimet. Kirjaa ulos ne, joita et tunnista, ja vaihda sitten salasanasi.'),
                        style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: MSpace.lg),
                      for (final s in _sessions) _tile(s),
                      if (others > 0) ...[
                        const SizedBox(height: MSpace.md),
                        MButton(
                          label: tr(context, 'Sign out all other devices', 'Kirjaa ulos kaikki muut laitteet'),
                          expand: true,
                          variant: MButtonVariant.secondary,
                          loading: _busyAll,
                          onPressed: _busyAll ? null : _signOutOthers,
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
