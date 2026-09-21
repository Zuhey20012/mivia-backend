import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
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
  final _citySearchCtrl = TextEditingController();
  String _citySearchQuery = '';

  final List<Map<String, dynamic>> _cities = [
    // Finland - Capital Region
    {'name': 'Helsinki', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Live Radar', 'active': true},
    {'name': 'Espoo', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Live Radar', 'active': true},
    {'name': 'Vantaa', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Live Radar', 'active': true},
    {'name': 'Kauniainen', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Live Radar', 'active': true},
    // Finland - Key Metros
    {'name': 'Tampere', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Turku', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Oulu', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Jyväskylä', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Kuopio', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Lahti', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Pori', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Kouvola', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Joensuu', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Lappeenranta', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Hämeenlinna', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Vaasa', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Seinäjoki', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Rovaniemi', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Mikkeli', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Porvoo', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Kotka', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Kokkola', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Hyvinkää', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Järvenpää', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    {'name': 'Lohja', 'country': 'Finland', 'flag': '🇫🇮', 'status': 'Available', 'active': true},
    // Sweden
    {'name': 'Stockholm', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Nordic Hub', 'active': true},
    {'name': 'Göteborg', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Available', 'active': true},
    {'name': 'Malmö', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Available', 'active': true},
    {'name': 'Uppsala', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Available', 'active': true},
    {'name': 'Lund', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Available', 'active': true},
    {'name': 'Linköping', 'country': 'Sweden', 'flag': '🇸🇪', 'status': 'Available', 'active': true},
    // Norway
    {'name': 'Oslo', 'country': 'Norway', 'flag': '🇳🇴', 'status': 'Nordic Hub', 'active': true},
    {'name': 'Bergen', 'country': 'Norway', 'flag': '🇳🇴', 'status': 'Available', 'active': true},
    {'name': 'Trondheim', 'country': 'Norway', 'flag': '🇳🇴', 'status': 'Available', 'active': true},
    {'name': 'Stavanger', 'country': 'Norway', 'flag': '🇳🇴', 'status': 'Available', 'active': true},
    // Denmark
    {'name': 'Copenhagen', 'country': 'Denmark', 'flag': '🇩🇰', 'status': 'Nordic Hub', 'active': true},
    {'name': 'Aarhus', 'country': 'Denmark', 'flag': '🇩🇰', 'status': 'Available', 'active': true},
    {'name': 'Odense', 'country': 'Denmark', 'flag': '🇩🇰', 'status': 'Available', 'active': true},
    // Iceland & Baltics
    {'name': 'Reykjavík', 'country': 'Iceland', 'flag': '🇮🇸', 'status': 'Available', 'active': true},
    {'name': 'Tallinn', 'country': 'Estonia', 'flag': '🇪🇪', 'status': 'Available', 'active': true},
  ];

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

  Future<void> _saveNewManualAddress() async {
    if (_streetCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter street name.')));
      return;
    }
    HapticFeedback.mediumImpact();
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
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 Delivery address updated: $addressText'),
          backgroundColor: const Color(0xFF10B981),
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
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose Delivery Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                      Text('Fast courier radar: 38+ cities in Finland & Scandinavia', style: TextStyle(fontSize: 12, color: textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 20, color: cardBorder),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                // Live Interactive Google Map Pinpoint Shortcut
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final result = await Navigator.push<AddressResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MapAddressPickerScreen(),
                      ),
                    );
                    if (result != null && mounted) {
                      widget.onLocationSelected?.call(result.fullAddress);
                      final newAddress = {
                        'id': 'addr_${DateTime.now().millisecondsSinceEpoch}',
                        'title': result.street.isNotEmpty ? result.street : 'Pin Location',
                        'subtitle': result.fullAddress,
                        'buzzer': '',
                        'isDefault': _savedAddresses.isEmpty,
                      };
                      setState(() {
                        _savedAddresses.insert(0, newAddress);
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('malvoya_addresses', jsonEncode(_savedAddresses));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('📍 Delivery pin set: ${result.fullAddress}'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: AppTheme.irisFuchsiaGradient,
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
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.map_rounded, color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pin Exact Address on Live Map',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Satellite, Hybrid & 3D Google Maps pinpointing',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),

                // Quick Actions: Share Location & Enter Address Manually
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          final res = await Navigator.push<AddressResult>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MapAddressPickerScreen(),
                            ),
                          );
                          if (res != null && mounted) {
                            widget.onLocationSelected?.call(res.fullAddress);
                            final newAddress = {
                              'id': 'addr_${DateTime.now().millisecondsSinceEpoch}',
                              'title': res.street.isNotEmpty ? res.street : 'Live GPS Pin',
                              'subtitle': res.fullAddress,
                              'buzzer': '',
                              'isDefault': _savedAddresses.isEmpty,
                            };
                            setState(() {
                              _savedAddresses.insert(0, newAddress);
                            });
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('malvoya_addresses', jsonEncode(_savedAddresses));
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('📍 Live GPS pin saved: ${res.fullAddress}'),
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Share GPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showManualForm = !_showManualForm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_showManualForm ? Icons.expand_less_rounded : Icons.edit_location_alt_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              const Text('Enter Manually', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Expandable Manual Entry Form
                if (_showManualForm) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Street Address *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _streetCtrl,
                          style: TextStyle(color: textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. Aleksanterinkatu 15',
                            hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                            filled: true,
                            fillColor: cardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Apt / Door', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _aptCtrl,
                                    style: TextStyle(color: textPrimary, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'A 4',
                                      hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                                      filled: true,
                                      fillColor: cardBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  Text('Postal Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _postalCtrl,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: textPrimary, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: '00100',
                                      hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                                      filled: true,
                                      fillColor: cardBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('Door Buzzer Code (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textPrimary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _buzzerCtrl,
                          style: TextStyle(color: textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. #1234',
                            hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                            filled: true,
                            fillColor: cardBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _saveNewManualAddress,
                            child: const Text('Save & Select Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Saved Addresses Section
                Text('ALL SAVED ADDRESSES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8)),
                const SizedBox(height: 8),

                if (_loadingAddresses)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppTheme.primary)))
                else if (_savedAddresses.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_off_outlined, color: textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No saved delivery addresses yet. Tap "Enter Manually" or "Share GPS" above.',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._savedAddresses.map((addr) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.home_outlined, color: AppTheme.primary, size: 20),
                        ),
                        title: Text(addr['title'] ?? 'Address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
                        subtitle: Text(addr['subtitle'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                        trailing: IconButton(
                          icon: const Icon(Icons.check_circle_outline, color: AppTheme.primary),
                          onPressed: () {
                            widget.onLocationSelected?.call(addr['subtitle'] ?? addr['title']);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          widget.onLocationSelected?.call(addr['subtitle'] ?? addr['title']);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // Browse Malvoya Cities Section with Search Filter
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'BROWSE SCANDINAVIAN CITIES',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8),
                    ),
                    Text(
                      '38+ Nordic Cities',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Real-time City Search Filter Box
                Container(
                  height: 44,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder),
                  ),
                  child: TextField(
                    controller: _citySearchCtrl,
                    style: TextStyle(fontSize: 13, color: textPrimary),
                    onChanged: (v) => setState(() => _citySearchQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search city (Helsinki, Oulu, Tampere, Stockholm...)',
                      hintStyle: TextStyle(fontSize: 12, color: textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 18),
                      suffixIcon: _citySearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _citySearchCtrl.clear();
                                setState(() => _citySearchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),

                () {
                  final filteredCities = _cities.where((c) {
                    if (_citySearchQuery.isEmpty) return true;
                    final name = (c['name'] as String).toLowerCase();
                    final country = (c['country'] as String).toLowerCase();
                    return name.contains(_citySearchQuery) || country.contains(_citySearchQuery);
                  }).toList();

                  if (filteredCities.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No matching cities found for "$_citySearchQuery"',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.15,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filteredCities.length,
                    itemBuilder: (_, i) {
                      final city = filteredCities[i];
                      final isActive = city['active'] as bool;
                      final isCurrent = widget.currentLocation.toLowerCase().contains((city['name'] as String).toLowerCase());

                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final locName = '${city['name']}, ${city['country']}';
                          widget.onLocationSelected?.call(locName);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('📍 Delivery area updated: $locName'),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppTheme.primary.withValues(alpha: 0.12)
                                : (isActive ? cardBg : inputBg),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrent
                                  ? AppTheme.primary
                                  : (isActive ? cardBorder : cardBorder.withValues(alpha: 0.5)),
                              width: isCurrent ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(city['flag'] as String, style: const TextStyle(fontSize: 20)),
                              const SizedBox(height: 3),
                              Text(
                                city['name'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent ? AppTheme.primary : textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                city['status'] as String,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? AppTheme.primary
                                      : (isActive ? const Color(0xFF10B981) : textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
