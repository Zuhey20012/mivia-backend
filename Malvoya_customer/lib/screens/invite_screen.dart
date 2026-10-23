import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// Loads the customer's invite programme (`GET /me/referral`). Returns null when the server has
/// no referral endpoint, the programme is switched off or the request fails, so callers can hide
/// the entry entirely.
Future<Map<String, dynamic>?> loadReferral(AuthService auth) async {
  if (!auth.isAuthenticated) return null;
  final res = await ApiClient(auth).get('/me/referral');
  if (!res.ok || res.data['enabled'] != true) return null;
  final code = res.data['code'];
  if (code is! String || code.isEmpty) return null;
  return res.data;
}

/// "Invite a friend": the customer's own code and share link, the server's own terms and how
/// many friends have joined. Nothing here is computed on the phone.
class InviteScreen extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const InviteScreen({super.key, this.initial});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late Map<String, dynamic>? _data = widget.initial;
  bool _loading = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    if (_data == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await loadReferral(Provider.of<AuthService>(context, listen: false));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data != null) {
        _data = data;
        _unavailable = false;
      } else if (_data == null) {
        _unavailable = true;
      }
    });
  }

  String get _code => (_data?['code'] ?? '').toString();
  String? get _link {
    final url = _data?['shareUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  String _terms(BuildContext context) {
    final t = _data?['terms'];
    if (t is Map) return (isFinnish(context) ? t['fi'] : t['en'])?.toString() ?? '';
    if (t is String) return t;
    return '';
  }

  Future<void> _copy(String text, String done) async {
    Haptics.selection();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    MSnack.show(context, done);
  }

  Future<void> _share() async {
    Haptics.medium();
    final discount = asInt(_data?['discountCents']) ?? 0;
    final link = _link;
    final text = [
      discount > 0
          ? tr(context, 'Shop from local stores on Malvoya. Use my invite code $_code to get ${euro(context, discount)} off your first order.',
              'Osta lähikaupoista Malvoyassa. Käytä kutsukoodiani $_code, niin saat ${euro(context, discount)} alennusta ensimmäisestä tilauksestasi.')
          : tr(context, 'Shop from local stores on Malvoya. My invite code: $_code', 'Osta lähikaupoista Malvoyassa. Kutsukoodini: $_code'),
      if (link != null) link,
    ].join('\n');
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: tr(context, 'Malvoya invite', 'Kutsu Malvoyaan'),
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.secondaryText(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Invite a friend', 'Kutsu ystävä'))),
      body: _data == null
          ? (_loading || !_unavailable
              ? const MSkeletonDetail(heroHeight: 160)
              : MStateMessage.error(
                  message: tr(context, 'Invites aren’t available right now.', 'Kutsut eivät ole juuri nyt käytettävissä.'),
                  onRetry: _load,
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.lg, MSpace.x4l),
                children: [
                  _hero(context),
                  const SizedBox(height: 14),
                  _stats(context),
                  const SizedBox(height: 14),
                  if (_terms(context).isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground(context),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(context, 'How it works', 'Näin se toimii'), style: AppTheme.display(context, size: 18)),
                          const SizedBox(height: MSpace.sm),
                          Text(_terms(context), style: TextStyle(fontSize: MTextSize.bodyM, height: 1.45, color: muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _hero(BuildContext context) {
    final link = _link;
    return Container(
      padding: const EdgeInsets.all(MSpace.xl),
      decoration: BoxDecoration(
        color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'Your invite code', 'Kutsukoodisi'), style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: SelectableText(_code, style: AppTheme.display(context, size: 34).copyWith(letterSpacing: 2)),
                ),
              ),
              IconButton(
                tooltip: tr(context, 'Copy code', 'Kopioi koodi'),
                onPressed: () => _copy(_code, tr(context, 'Code copied', 'Koodi kopioitu')),
                icon: Icon(Icons.copy_rounded, color: AppTheme.primaryText(context)),
              ),
            ],
          ),
          if (link != null) ...[
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: tr(context, 'Copy invite link', 'Kopioi kutsulinkki'),
              child: InkWell(
                borderRadius: BorderRadius.circular(MRadius.sm),
                onTap: () => _copy(link, tr(context, 'Link copied', 'Linkki kopioitu')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 18, color: AppTheme.primaryText(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: MTextSize.label, color: AppTheme.primaryText(context), decoration: TextDecoration.underline)),
                    ),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(tr(context, 'Share invite', 'Jaa kutsu')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context) {
    Widget tile(String value, String label, Color light, Color hue) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(MSpace.lg),
            decoration: BoxDecoration(color: AppTheme.pastel(context, light, hue), borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: AppTheme.display(context, size: 26)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: MTextSize.caption, color: AppTheme.primaryText(context))),
            ]),
          ),
        );
    final invited = asInt(_data?['invited']) ?? 0;
    final rewarded = asInt(_data?['rewarded']) ?? 0;
    return Row(children: [
      tile('$invited', tr(context, 'Friends who used your code', 'Ystävää käytti koodiasi'), AppTheme.lilac, AppTheme.primary),
      const SizedBox(width: 10),
      tile('$rewarded', tr(context, 'Rewards earned', 'Palkkiota ansaittu'), AppTheme.mint, AppTheme.moss),
    ]);
  }
}
