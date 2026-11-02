import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../screens/two_step_screen.dart';

/// 403 `REAUTH_REQUIRED` (API 2.16): the request needs the password (or a two-step code) again
/// within the last 10 minutes, e.g. Stripe payout links.
bool isReauthRequired(ApiResult res) {
  if (res.status != 403) return false;
  final code = '${res.data['code'] ?? ''}'.toUpperCase();
  return code == 'REAUTH_REQUIRED' || code.contains('REAUTH');
}

/// Asks for the password or a two-step code and sends it to `POST /me/reauth`. True once the server
/// accepted it (it then allows such requests for 10 minutes), false when cancelled.
Future<bool> confirmIdentity(BuildContext context, AuthService auth) async {
  final ok = await showMSheet<bool>(context, builder: (_) => _ReauthSheet(auth: auth));
  return ok == true;
}

class _ReauthSheet extends StatefulWidget {
  final AuthService auth;
  const _ReauthSheet({required this.auth});

  @override
  State<_ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<_ReauthSheet> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _obscure = true;
  bool _hasPassword = true;
  bool _twoStepOn = false;
  bool _useCode = false;
  String? _error;

  ApiClient get _api => ApiClient(widget.auth);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Which proofs this account has: a password (GET /me `hasPassword`) and two-step sign-in (GET /me/mfa).
  Future<void> _load() async {
    final results = await Future.wait([_api.get('/me'), _api.get('/me/mfa')]);
    if (!mounted) return;
    final user = results[0].data['user'];
    setState(() {
      _loading = false;
      if (user is Map && user['hasPassword'] == false) _hasPassword = false;
      _twoStepOn = results[1].ok && results[1].data['enabled'] == true;
      _useCode = !_hasPassword && _twoStepOn;
    });
  }

  bool get _ready => _useCode ? _code.text.replaceAll(RegExp(r'\s'), '').length >= 6 : _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _api.post('/me/reauth', _useCode ? {'code': _code.text.replaceAll(RegExp(r'\s'), '')} : {'password': _password.text});
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = res.errorMessage;
      if (_useCode) {
        _code.clear();
      } else {
        _password.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(MSpace.x3l), child: Center(child: CircularProgressIndicator()));
    }
    // Neither a password nor two-step sign-in (a Google or phone-code account): two-step sign-in is the way
    if (!_hasPassword && !_twoStepOn) {
      return MSheet(
        title: tr(context, 'Confirm it is you', 'Vahvista henkilöllisyytesi'),
        actions: [
          MButton(
            label: tr(context, 'Set up two-step sign-in', 'Ota kaksivaiheinen kirjautuminen käyttöön'),
            expand: true,
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop(false);
              nav.push(MaterialPageRoute(builder: (_) => const TwoStepScreen()));
            },
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(bottom: MSpace.md),
          child: Text(
            tr(context,
                'Payout links need a second proof that it is you. Your account has no password, so turn on two-step sign-in (an authenticator app) and then open the link again.',
                'Tilityslinkit edellyttävät toista vahvistusta henkilöllisyydestäsi. Tililläsi ei ole salasanaa, joten ota kaksivaiheinen kirjautuminen (todennussovellus) käyttöön ja avaa linkki sitten uudelleen.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
          ),
        ),
      );
    }
    return MSheet(
      title: tr(context, 'Confirm it is you', 'Vahvista henkilöllisyytesi'),
      subtitle: tr(context, 'Payout links open your Stripe account, so Malvoya asks again. Valid for 10 minutes.',
          'Tilityslinkit avaavat Stripe-tilisi, joten Malvoya kysyy uudelleen. Voimassa 10 minuuttia.'),
      actions: [
        MButton(label: tr(context, 'Confirm', 'Vahvista'), expand: true, loading: _busy, onPressed: _ready && !_busy ? _submit : null),
        if (_hasPassword && _twoStepOn)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _useCode = !_useCode;
                      _error = null;
                    }),
            child: Text(_useCode
                ? tr(context, 'Use my password instead', 'Käytä salasanaa')
                : tr(context, 'Use a code from the authenticator app', 'Käytä todennussovelluksen koodia')),
          ),
      ],
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_useCode)
          MTextField(
            key: const ValueKey('code'),
            controller: _code,
            autofocus: true,
            label: tr(context, 'Code from the authenticator app', 'Todennussovelluksen koodi'),
            prefixIcon: Icons.password_rounded,
            keyboardType: TextInputType.number,
            maxLength: 6,
            errorText: _error,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          )
        else
          MTextField(
            key: const ValueKey('password'),
            controller: _password,
            autofocus: true,
            label: tr(context, 'Password', 'Salasana'),
            prefixIcon: Icons.lock_outline_rounded,
            obscure: _obscure,
            autofillHints: const [AutofillHints.password],
            errorText: _error,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              tooltip: _obscure ? tr(context, 'Show password', 'Näytä salasana') : tr(context, 'Hide password', 'Piilota salasana'),
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        const SizedBox(height: MSpace.md),
      ]),
    );
  }
}
