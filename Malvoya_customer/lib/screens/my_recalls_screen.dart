import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../core/catalog.dart';
import '../widgets/app_image.dart';
import 'product_detail.dart';

/// "My recalls" in Profile: shown only when `GET /me/recalls` lists a recall of something the
/// customer bought. Tapping it opens the recalls with what to do.
class MyRecallsNotice extends StatefulWidget {
  const MyRecallsNotice({super.key});

  @override
  State<MyRecallsNotice> createState() => _MyRecallsNoticeState();
}

class _MyRecallsNoticeState extends State<MyRecallsNotice> {
  List<Map<String, dynamic>> _recalls = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) return;
    final res = await ApiClient(auth).get('/me/recalls');
    if (!mounted || !res.ok) return;
    setState(() => _recalls = ((res.data['recalls'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_recalls.isEmpty) return const SizedBox.shrink();
    final c = context.mColors;
    final active = _recalls.where((r) => r['status'] != 'CLOSED').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.md),
      child: Material(
        color: c.dangerSoft,
        borderRadius: MRadius.brMd,
        child: InkWell(
          borderRadius: MRadius.brMd,
          onTap: () {
            Haptics.light();
            Navigator.push(context, MaterialPageRoute(builder: (_) => MyRecallsScreen(recalls: _recalls)));
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: MSpace.md),
              child: Row(children: [
                Icon(Icons.report_rounded, color: c.onDangerSoft),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, 'My recalls', 'Takaisinvetoni'), style: MType.bodyL.copyWith(fontWeight: FontWeight.w800, color: c.onDangerSoft)),
                    Text(
                      active > 0
                          ? tr(context, 'A product you bought has been recalled. See what to do.', 'Ostamasi tuote on vedetty takaisin. Katso, mitä tehdä.')
                          : tr(context, 'Earlier recalls of products you bought.', 'Ostamiesi tuotteiden aiemmat takaisinvedot.'),
                      style: MType.bodyM.copyWith(color: c.onDangerSoft),
                    ),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.onDangerSoft),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The recalls of products the customer bought, with the hazard, the remedy and the public notice.
class MyRecallsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> recalls;
  const MyRecallsScreen({super.key, required this.recalls});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'My recalls', 'Takaisinvetoni'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.lg, MSpace.lg, MSpace.x4l),
        children: [
          for (final r in recalls)
            Container(
              margin: const EdgeInsets.only(bottom: MSpace.md),
              padding: const EdgeInsets.all(MSpace.lg),
              decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, border: Border.all(color: r['status'] == 'CLOSED' ? c.outline : c.danger, width: 1.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(localized(context, r['headline']) ?? tr(context, 'Product safety recall', 'Tuotteen turvallisuuteen liittyvä takaisinveto'),
                        style: MType.label.copyWith(color: r['status'] == 'CLOSED' ? c.onSurfaceVariant : c.danger)),
                  ),
                  if (r['status'] == 'CLOSED') MBadge(tr(context, 'Closed', 'Päättynyt'), tone: MBadgeTone.neutral),
                ]),
                const SizedBox(height: MSpace.xs),
                Text('${r['title'] ?? ''}', style: MType.title.copyWith(color: c.onSurface)),
                if (shortDate(context, r['publishedAt']).isNotEmpty)
                  Text(shortDate(context, r['publishedAt']), style: MType.caption.copyWith(color: c.onSurfaceVariant)),
                if (localized(context, r['hazard']) != null) ...[
                  const SizedBox(height: MSpace.sm),
                  Text(tr(context, 'The risk', 'Vaara'), style: MType.caption.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  Text(localized(context, r['hazard'])!, style: MType.bodyM.copyWith(color: c.onSurface)),
                ],
                if (localized(context, r['remedy']) != null) ...[
                  const SizedBox(height: MSpace.sm),
                  Text(tr(context, 'What to do', 'Mitä tehdä'), style: MType.caption.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  Text(localized(context, r['remedy'])!, style: MType.bodyM.copyWith(color: c.onSurface)),
                ],
                if ('${r['contact'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: MSpace.sm),
                  Text(tr(context, 'Contact', 'Yhteystiedot'), style: MType.caption.copyWith(color: c.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  SelectableText('${r['contact']}', style: MType.bodyM.copyWith(color: c.onSurface)),
                ],
                for (final p in ((r['products'] as List?) ?? const []).whereType<Map>())
                  MListTile(
                    title: '${p['name'] ?? ''}',
                    subtitle: [p['storeName'], if (p['productModel'] != null) p['productModel'], if (p['batchOrSerial'] != null) p['batchOrSerial']]
                        .where((x) => x != null && '$x'.isNotEmpty)
                        .join(' · '),
                    leading: p['image'] == null
                        ? null
                        : ClipRRect(borderRadius: MRadius.brXs, child: SizedBox(width: 44, height: 44, child: AppImage('${p['image']}'))),
                    onTap: asInt(p['id']) == null
                        ? null
                        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: asInt(p['id'])!))),
                  ),
                if ('${r['url'] ?? ''}'.isNotEmpty)
                  MButton(
                    label: tr(context, 'Read the full notice', 'Lue koko tiedote'),
                    variant: MButtonVariant.outline,
                    size: MButtonSize.sm,
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => launchUrl(Uri.parse('${r['url']}'), mode: LaunchMode.externalApplication),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}
