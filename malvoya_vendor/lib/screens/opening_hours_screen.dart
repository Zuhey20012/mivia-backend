import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../widgets/opening_hours_editor.dart';

/// Weekly opening hours in Finnish time. Outside them customers see "Closed" and cannot order,
/// so no order waits for a store that is not there.
class OpeningHoursScreen extends StatefulWidget {
  final int storeId;
  final Map<String, dynamic>? initial;
  const OpeningHoursScreen({super.key, required this.storeId, this.initial});

  @override
  State<OpeningHoursScreen> createState() => _OpeningHoursScreenState();
}

class _OpeningHoursScreenState extends State<OpeningHoursScreen> {
  late final OpeningHoursDraft _draft = OpeningHoursDraft.fromJson(widget.initial);
  bool _saving = false;

  Future<void> _save() async {
    final problem = _draft.validate(context);
    if (problem != null) {
      _snack(problem);
      return;
    }
    setState(() => _saving = true);
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).patch('/stores/${widget.storeId}', {'openingHours': _draft.toJson()});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      _snack(res.errorMessage);
    }
  }

  void _snack(String t) => MSnack.show(context, t);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Opening hours', 'Aukioloajat'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.sm, MSpace.lg, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Text(
              tr(context,
                  'Customers can only order while you are open. Times are Finnish time. Closing after midnight works too, e.g. 18:00–02:00.',
                  'Asiakkaat voivat tilata vain aukioloaikoina. Ajat ovat Suomen aikaa. Myös puolenyön yli toimii, esim. 18:00–02:00.'),
              style: const TextStyle(color: MPalette.amberInk, height: 1.4),
            ),
          ),
          const SizedBox(height: MSpace.md),
          OpeningHoursEditor(draft: _draft, onChanged: () => setState(() {})),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(MSpace.lg),
        child: SizedBox(
          height: 54,
          child: MButton(label: tr(context, 'Save', 'Tallenna'), loading: _saving, onPressed: _saving ? null : _save),
        ),
      ),
    );
  }
}
