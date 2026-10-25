import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';

/// The one-time product safety pledge (GPSR Art. 22(10)(b)): GET / POST /stores/my/safety-pledge.
/// Shown before the first publish and from the onboarding checklist. Pops `true` once it is given
/// (or was given before).
class SafetyPledgeScreen extends StatefulWidget {
  /// Opened on the way to publishing: the button says so.
  final bool beforePublish;
  const SafetyPledgeScreen({super.key, this.beforePublish = false});

  /// Asks the server whether the pledge is given and opens the screen when it is not. True = given.
  static Future<bool> ensure(BuildContext context) async {
    final api = ApiClient(Provider.of<AuthService>(context, listen: false));
    final res = await api.get('/stores/my/safety-pledge');
    if (res.ok && (res.data['pledge'] as Map?)?['accepted'] == true) return true;
    if (!context.mounted) return false;
    final given = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SafetyPledgeScreen(beforePublish: true)));
    return given == true;
  }

  @override
  State<SafetyPledgeScreen> createState() => _SafetyPledgeScreenState();
}

class _SafetyPledgeScreenState extends State<SafetyPledgeScreen> {
  Map<String, dynamic>? _pledge;
  bool _loading = true;
  String? _error;
  bool _ticked = false;
  bool _saving = false;

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.get('/stores/my/safety-pledge');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok && res.data['pledge'] is Map) {
        _pledge = Map<String, dynamic>.from(res.data['pledge']);
      } else {
        _error = res.errorMessage;
      }
    });
  }

  Future<void> _accept() async {
    setState(() => _saving = true);
    final res = await _api.post('/stores/my/safety-pledge', {'accept': true});
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      MSnack.error(context, res.errorMessage);
      return;
    }
    Haptics.success();
    MSnack.success(context, tr(context, 'Thank you. The pledge is saved with your store.', 'Kiitos. Sitoumus on tallennettu kauppasi tietoihin.'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final accepted = _pledge?['accepted'] == true;
    final at = parseApiDate(_pledge?['acceptedAt']);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(tr(context, 'Product safety pledge', 'Tuoteturvallisuussitoumus'))),
      body: _loading
          ? const MSkeletonList(count: 3, lines: 4)
          : _error != null
              ? MStateMessage.error(message: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.x4l),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(MSpace.lg),
                      decoration: BoxDecoration(color: c.primarySoft, borderRadius: MRadius.brMd),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.verified_user_outlined, color: c.onPrimarySoft),
                        const SizedBox(width: MSpace.md),
                        Expanded(
                          child: Text(
                            tr(context,
                                'EU product safety law asks every seller on a marketplace to confirm this once. You give it one time for your store, before your first product is published.',
                                'EU:n tuoteturvallisuusasetus edellyttää, että jokainen kauppapaikan myyjä vahvistaa tämän kerran. Annat sitoumuksen kerran kauppaasi kohden ennen ensimmäisen tuotteen julkaisua.'),
                            style: MType.bodyM.copyWith(color: c.onPrimarySoft),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: MSpace.lg),
                    Container(
                      padding: const EdgeInsets.all(MSpace.lg),
                      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: c.outline)),
                      child: Text(localized(context, _pledge?['text']) ?? '', style: MType.bodyL),
                    ),
                    const SizedBox(height: MSpace.lg),
                    if (accepted)
                      MListTile(
                        icon: Icons.check_circle_rounded,
                        iconBackground: c.successSoft,
                        title: tr(context, 'Pledge given', 'Sitoumus annettu'),
                        subtitle: at == null ? null : tr(context, 'On ${dateText(context, at)}', '${dateText(context, at)}'),
                      )
                    else ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _ticked,
                        onChanged: _saving ? null : (v) => setState(() => _ticked = v ?? false),
                        title: Text(tr(context, 'I confirm the above for my store.', 'Vahvistan yllä olevan kauppani puolesta.'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: MSpace.md),
                      MButton(
                        label: widget.beforePublish ? tr(context, 'Confirm and continue', 'Vahvista ja jatka') : tr(context, 'Give the pledge', 'Anna sitoumus'),
                        expand: true,
                        loading: _saving,
                        onPressed: _ticked && !_saving ? _accept : null,
                      ),
                    ],
                    if (accepted) ...[
                      const SizedBox(height: MSpace.lg),
                      MButton(label: tr(context, 'Done', 'Valmis'), expand: true, onPressed: () => Navigator.pop(context, true)),
                    ],
                  ],
                ),
    );
  }
}
