import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/strings.dart';

/// The vehicle types the server accepts (`PATCH /courier/me {vehicleType}`, API 2.11).
const kVehicleTypes = ['bicycle', 'ebike', 'moped', 'scooter', 'car', 'on_foot'];

IconData vehicleIcon(String? type) => switch (type) {
      'ebike' => Icons.electric_bike_rounded,
      'moped' => Icons.moped_rounded,
      'scooter' => Icons.electric_scooter_rounded,
      'car' => Icons.directions_car_rounded,
      'on_foot' => Icons.directions_walk_rounded,
      _ => Icons.pedal_bike_rounded,
    };

String vehicleLabel(BuildContext context, String type) => switch (type) {
      'bicycle' => tr(context, 'Bicycle', 'Polkupyörä'),
      'ebike' => tr(context, 'E-bike', 'Sähköpyörä'),
      'moped' => tr(context, 'Moped', 'Mopo'),
      'scooter' => tr(context, 'E-scooter', 'Sähköpotkulauta'),
      'car' => tr(context, 'Car', 'Auto'),
      'on_foot' => tr(context, 'On foot', 'Kävellen'),
      _ => type,
    };

/// Picks how the courier gets around and saves it at once. Returns the saved type, or null.
Future<String?> showVehiclePicker(BuildContext context, {String? current}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VehicleSheet(current: current),
    );

class _VehicleSheet extends StatefulWidget {
  final String? current;
  const _VehicleSheet({this.current});

  @override
  State<_VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends State<_VehicleSheet> {
  String? _saving;
  String? _error;

  Future<void> _pick(String type) async {
    if (_saving != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _saving = type;
      _error = null;
    });
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).patch('/courier/me', {'vehicleType': type});
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, type);
      return;
    }
    setState(() {
      _saving = null;
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'How do you deliver?', 'Millä toimitat?'), style: AppTheme.display(size: 22)),
          const SizedBox(height: 6),
          Text(
            tr(context, 'Shown to the Malvoya team with your application. You can change it at any time.',
                'Näkyy Malvoyan tiimille hakemuksesi yhteydessä. Voit vaihtaa sen milloin tahansa.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, box) {
            final columns = box.maxWidth > 420 ? 3 : 2;
            final width = (box.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final type in kVehicleTypes) SizedBox(width: width, child: _tile(type)),
            ]);
          }),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48), foregroundColor: AppTheme.textSecondary),
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Cancel', 'Peruuta')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(String type) {
    final selected = type == widget.current;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppTheme.sunshine : AppTheme.sand,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: _saving == null ? () => _pick(type) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _saving == type
                    ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Icon(vehicleIcon(type), size: 32, color: AppTheme.textPrimary),
                const SizedBox(height: 8),
                Text(vehicleLabel(context, type), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name and contact phone for the courier profile: the name through `PATCH /me/profile`, the
/// phone through `PATCH /courier/me {phone}`. True when something was saved.
Future<bool> showCourierProfileSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProfileSheet(),
    ) ==
    true;

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _savedName = '';
  String _savedPhone = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static final _phonePattern = RegExp(r'^\+?[0-9 ()-]{5,20}$');

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _savedName = _auth.currentUser?.name?.trim() ?? '';
    _name.text = _savedName;
    final res = await ApiClient(_auth).get('/courier/me');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _savedPhone = '${res.data['courier']?['phone'] ?? ''}'.trim();
        _phone.text = _savedPhone;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = tr(context, 'Enter your name (at most 80 characters).', 'Anna nimesi (enintään 80 merkkiä).'));
      return;
    }
    if (phone.isEmpty || !_phonePattern.hasMatch(phone)) {
      setState(() => _error = tr(context, 'Enter a phone number, for example +358 40 123 4567.', 'Anna puhelinnumero, esimerkiksi +358 40 123 4567.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = ApiClient(_auth);
    var changed = false;
    if (name != _savedName) {
      final res = await api.patch('/me/profile', {'name': name});
      if (!mounted) return;
      if (!res.ok) {
        setState(() {
          _saving = false;
          _error = res.error;
        });
        return;
      }
      _savedName = name;
      changed = true;
      await _auth.updateLocalName('${res.data['user']?['name'] ?? name}');
      if (!mounted) return;
    }
    if (phone != _savedPhone) {
      final res = await api.patch('/courier/me', {'phone': phone});
      if (!mounted) return;
      if (!res.ok) {
        setState(() {
          _saving = false;
          _error = res.error;
        });
        return;
      }
      _savedPhone = phone;
      changed = true;
    }
    Navigator.pop(context, changed);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(context, 'Name and phone', 'Nimi ja puhelin'), style: AppTheme.display(size: 22)),
            const SizedBox(height: 6),
            Text(
              tr(context, 'The Malvoya team uses your phone number to reach you about your application and deliveries.',
                  'Malvoyan tiimi käyttää puhelinnumeroasi tavoittaakseen sinut hakemukseesi ja toimituksiin liittyen.'),
              style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                maxLength: 80,
                decoration: InputDecoration(labelText: tr(context, 'Name', 'Nimi'), counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]'))],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(labelText: tr(context, 'Phone', 'Puhelin'), hintText: '+358 40 123 4567'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(tr(context, 'Save', 'Tallenna')),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(64, 48), foregroundColor: AppTheme.textSecondary),
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text(tr(context, 'Cancel', 'Peruuta')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
