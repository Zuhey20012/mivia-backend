import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
import 'map_address_picker.dart';

class LocationSelectorModal extends StatefulWidget {
  final String currentLocation;
  final Function(String location)? onLocationSelected;

  const LocationSelectorModal({
    super.key,
    required this.currentLocation,
    this.onLocationSelected,
  });

  @override
  State<LocationSelectorModal> createState() => _LocationSelectorModalState();
}

class _LocationSelectorModalState extends State<LocationSelectorModal> {
  bool _showManualForm = false;
  List<Map<String, dynamic>> _savedAddresses = [];
  bool _loadingAddresses = true;

  final _streetCtrl = TextEditingController();
  final _aptCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Helsinki');
  final _buzzerCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  Future<void> _loadSavedAddresses() async {
    setState(() => _loadingAddresses = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('malvoya_addresses');
      if (raw != null) {
        final List decoded = jsonDecode(raw);
        _savedAddresses = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        _savedAddresses = [];
      }
    } catch (_) {
      _savedAddresses = [];
    }
    if (mounted) setState(() => _loadingAddresses = false);
  }

  void _useSaved(Map<String, dynamic> addr) {
    final text = (addr['subtitle'] ?? addr['title'] ?? '').toString();
    widget.onLocationSelected?.call(text);
    DeliveryLocation.instance.use(addr);
  }

  /// Opens the map (centred on the phone's position with [locate]), then saves and uses the pin.
  Future<void> _fromMap({bool locate = false}) async {
    Haptics.light();
    final res = await Navigator.push<AddressResult>(
      context,
      MaterialPageRoute(builder: (_) => MapAddressPickerScreen(locateOnOpen: locate)),
    );
    if (res == null || !mounted) return;
    widget.onLocationSelected?.call(res.fullAddress);
    DeliveryLocation.instance.set(res.fullAddress, latitude: res.latitude, longitude: res.longitude);
    final newAddress = {
      'id': 'addr_${DateTime.now().millisecondsSinceEpoch}',
      'title': res.street.isNotEmpty ? res.street : tr(context, 'Pinned location', 'Merkitty sijainti'),
      'subtitle': res.fullAddress,
      'lat': res.latitude,
      'lng': res.longitude,
      'buzzer': '',
      'isDefault': _savedAddresses.isEmpty,
    };
    setState(() => _savedAddresses.insert(0, newAddress));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DeliveryLocation.savedAddressesKey, jsonEncode(_savedAddresses));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = tr(context, 'Delivery address: ${res.fullAddress}', 'Toimitusosoite: ${res.fullAddress}');
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: MPalette.green, behavior: SnackBarBehavior.floating));
  }

  Future<void> _saveNewManualAddress() async {
    if (_streetCtrl.text.trim().isEmpty) {
      MSnack.show(context, tr(context, 'Please enter the street.', 'Kirjoita katuosoite.'));
      return;
    }
    Haptics.medium();
    final aptPart = _aptCtrl.text.isNotEmpty ? ' ' + _aptCtrl.text.trim() : '';
    final addressText = '${_streetCtrl.text.trim()}$aptPart, ${_postalCtrl.text.trim()} ${_cityCtrl.text.trim()}';
    final newAddress = {
      'id': 'addr_${DateTime.now().millisecondsSinceEpoch}',
      'title': _streetCtrl.text.trim(),
      'subtitle': addressText,
      'buzzer': _buzzerCtrl.text.trim(),
      'isDefault': _savedAddresses.isEmpty,
    };
    setState(() {
      _savedAddresses.insert(0, newAddress);
      _showManualForm = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('malvoya_addresses', jsonEncode(_savedAddresses));
    widget.onLocationSelected?.call(addressText);
    final door = _buzzerCtrl.text.trim();
    DeliveryLocation.instance.set(addressText, doorCode: door.isEmpty ? null : door);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'Delivery address: $addressText', 'Toimitusosoite: $addressText')),
          backgroundColor: MPalette.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);
    final cardBorder = AppTheme.cardBorder(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: MSpace.md),
          const MSheetHandle(),
          const SizedBox(height: MSpace.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MSpace.xl),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(MSpace.sm),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(MRadius.sm),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: MSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'Choose delivery address', 'Valitse toimitusosoite'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
                      Text(tr(context, 'Pin your address for the exact delivery fee', 'Merkitse osoitteesi tarkkaa toimitusmaksua varten'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'Close', 'Sulje'),
                  icon: Icon(Icons.close_rounded, color: AppTheme.secondaryText(context)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 20, color: cardBorder),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.xxl),
              children: [
                // Pin the door on the OpenStreetMap map
                GestureDetector(
                  onTap: () => _fromMap(),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(MSpace.lg),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(MSpace.sm),
                          decoration: const BoxDecoration(color: MPalette.white, shape: BoxShape.circle),
                          child: const Icon(Icons.map_rounded, color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(context, 'Pin your door on the map', 'Merkitse ovesi kartalle'),
                                style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w800, fontSize: MTextSize.bodyM),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tr(context, 'For the exact delivery fee and an easy find for your courier',
                                    'Tarkka toimitusmaksu, ja kuriiri löytää perille helposti'),
                                style: TextStyle(color: AppTheme.onBrand.withValues(alpha: 0.7), fontSize: MTextSize.caption),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.onBrand, size: 14),
                      ],
                    ),
                  ),
                ),

                // Quick Actions: Share Location & Enter Address Manually
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _fromMap(locate: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: MSpace.md),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(MRadius.md),
                            boxShadow: [
                              BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.my_location_rounded, color: AppTheme.onBrand, size: 18),
                              const SizedBox(width: MSpace.sm),
                              Text(tr(context, 'Use my location', 'Käytä sijaintiani'), style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w800, fontSize: MTextSize.label)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showManualForm = !_showManualForm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: MSpace.md),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(MRadius.md),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_showManualForm ? Icons.expand_less_rounded : Icons.edit_location_alt_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: MSpace.sm),
                              Text(tr(context, 'Type it in', 'Kirjoita osoite'), style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: MTextSize.label)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Expandable Manual Entry Form
                if (_showManualForm) ...[
                  const SizedBox(height: MSpace.lg),
                  Container(
                    padding: const EdgeInsets.all(MSpace.lg),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(context, 'Street address *', 'Katuosoite *'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _streetCtrl,
                          style: TextStyle(color: textPrimary, fontSize: MTextSize.label),
                          decoration: InputDecoration(
                            hintText: tr(context, 'e.g. Aleksanterinkatu 15', 'esim. Aleksanterinkatu 15'),
                            hintStyle: TextStyle(color: textSecondary, fontSize: MTextSize.label),
                            filled: true,
                            fillColor: cardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.md),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr(context, 'Apartment', 'Asunto'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.bold, color: textPrimary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _aptCtrl,
                                    style: TextStyle(color: textPrimary, fontSize: MTextSize.label),
                                    decoration: InputDecoration(
                                      hintText: 'A 4',
                                      hintStyle: TextStyle(color: textSecondary, fontSize: MTextSize.label),
                                      filled: true,
                                      fillColor: cardBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.md),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr(context, 'Postcode', 'Postinumero'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.bold, color: textPrimary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _postalCtrl,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: textPrimary, fontSize: MTextSize.label),
                                    decoration: InputDecoration(
                                      hintText: '00100',
                                      hintStyle: TextStyle(color: textSecondary, fontSize: MTextSize.label),
                                      filled: true,
                                      fillColor: cardBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.md),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(tr(context, 'Door code (optional)', 'Ovikoodi (valinnainen)'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _buzzerCtrl,
                          style: TextStyle(color: textPrimary, fontSize: MTextSize.label),
                          decoration: InputDecoration(
                            hintText: tr(context, 'e.g. A 1234', 'esim. A 1234'),
                            hintStyle: TextStyle(color: textSecondary, fontSize: MTextSize.label),
                            filled: true,
                            fillColor: cardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: BorderSide(color: cardBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MRadius.sm), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.md),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.sm)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _saveNewManualAddress,
                            child: Text(tr(context, 'Save and use this address', 'Tallenna ja käytä tätä osoitetta'), style: TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: MSpace.xl),

                // Saved Addresses Section
                Text(tr(context, 'SAVED ADDRESSES', 'TALLENNETUT OSOITTEET'), style: TextStyle(fontSize: MTextSize.caption, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8)),
                const SizedBox(height: MSpace.sm),

                if (_loadingAddresses)
                  const Center(child: Padding(padding: EdgeInsets.all(MSpace.md), child: CircularProgressIndicator(color: AppTheme.primary)))
                else if (_savedAddresses.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(MSpace.lg),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(MRadius.md),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_off_outlined, color: textSecondary),
                        const SizedBox(width: MSpace.md),
                        Expanded(
                          child: Text(
                            tr(context, 'No saved addresses yet. Type one in or use your location above.', 'Ei vielä tallennettuja osoitteita. Kirjoita osoite tai käytä sijaintiasi yllä.'),
                            style: TextStyle(fontSize: MTextSize.caption, color: textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._savedAddresses.map((addr) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: MSpace.sm),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(MSpace.sm),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.home_outlined, color: AppTheme.primary, size: 20),
                        ),
                        title: Text('${addr['title'] ?? tr(context, 'Address', 'Osoite')}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyM, color: textPrimary)),
                        subtitle: Text(addr['subtitle'] ?? '', style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                        trailing: IconButton(
                          tooltip: tr(context, 'Use this address', 'Käytä tätä osoitetta'),
                          icon: const Icon(Icons.check_circle_outline, color: AppTheme.primary),
                          onPressed: () {
                            _useSaved(addr);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          _useSaved(addr);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  }),

              ],
            ),
          ),
        ],
      ),
    );
  }
}
