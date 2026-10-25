import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../../auth_service.dart';
import 'certificates_screen.dart';
import 'operators_screen.dart';
import 'safety_pledge_screen.dart';

/// Store → Product safety: the pledge, the manufacturer / responsible person records and the
/// certificates, in one place.
class ProductSafetyScreen extends StatefulWidget {
  const ProductSafetyScreen({super.key});

  @override
  State<ProductSafetyScreen> createState() => _ProductSafetyScreenState();
}

class _ProductSafetyScreenState extends State<ProductSafetyScreen> {
  bool? _pledged;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).get('/stores/my/safety-pledge');
    if (!mounted) return;
    setState(() => _pledged = res.ok ? ((res.data['pledge'] as Map?)?['accepted'] == true) : null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(tr(context, 'Product safety', 'Tuoteturvallisuus'))),
      body: ListView(
        padding: const EdgeInsets.all(MSpace.lg),
        children: [
          Text(
            tr(context, 'What EU law asks of sellers, set up once and used in every product.',
                'Mitä EU-laki edellyttää myyjiltä: määritä kerran ja käytä jokaisessa tuotteessa.'),
            style: MType.bodyM.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: MSpace.lg),
          Container(
            decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brLg, border: Border.all(color: c.outline)),
            child: Column(children: [
              MListTile(
                icon: Icons.verified_user_outlined,
                title: tr(context, 'Product safety pledge', 'Tuoteturvallisuussitoumus'),
                subtitle: _pledged == true
                    ? tr(context, 'Given', 'Annettu')
                    : _pledged == false
                        ? tr(context, 'Needed before your first publish', 'Tarvitaan ennen ensimmäistä julkaisua')
                        : null,
                trailing: _pledged == false ? MBadge(tr(context, 'To do', 'Tekemättä'), tone: MBadgeTone.sunshine) : null,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyPledgeScreen()));
                  if (mounted) _load();
                },
              ),
              const Divider(height: 1),
              MListTile(
                icon: Icons.factory_outlined,
                title: tr(context, 'Manufacturers and responsible persons', 'Valmistajat ja vastuuhenkilöt'),
                subtitle: tr(context, 'Name and address shown on your products', 'Tuotteissasi näkyvä nimi ja osoite'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperatorsScreen())),
              ),
              const Divider(height: 1),
              MListTile(
                icon: Icons.workspace_premium_outlined,
                title: tr(context, 'Certificates', 'Sertifikaatit'),
                subtitle: tr(context, 'Ecolabels and other verified schemes', 'Ympäristömerkit ja muut todennetut järjestelmät'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CertificatesScreen())),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
