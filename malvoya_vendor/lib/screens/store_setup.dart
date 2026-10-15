import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/media_upload.dart';
import '../core/strings.dart';
import '../widgets/account_sheet.dart';
import '../widgets/opening_hours_editor.dart';
import 'store_location_picker.dart';

/// Create the store, or edit it later. Who the seller is (business or private person) is shown
/// to shoppers, as EU marketplace law requires, and is checked during review.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _businessId = TextEditingController();

  Map<String, dynamic>? _existing;
  String _category = 'APPAREL';
  String _sellerType = 'BUSINESS';
  double _prepMinutes = 10;
  double? _lat;
  double? _lng;
  String? _logoUrl;
  String? _bannerUrl;
  double? _uploading;
  /// Opening hours chosen while creating the store (later they are edited in Store → Opening hours)
  final OpeningHoursDraft _hours = OpeningHoursDraft.fromJson(null, defaultOn: true);
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _categories = {
    'APPAREL': ['Clothing & fashion', 'Vaatteet ja muoti'],
    'THRIFT': ['Second hand & vintage', 'Kierrätys ja vintage'],
    'ACCESSORIES': ['Accessories, bags & jewellery', 'Asusteet, laukut ja korut'],
    'COSMETICS': ['Beauty & skincare', 'Kauneus ja ihonhoito'],
    'HANDMADE': ['Handmade', 'Käsintehty'],
    'ECO_FRIENDLY': ['Eco-friendly', 'Ekologinen'],
    'HOME_DECOR': ['Home', 'Koti'],
    'OTHER': ['Other', 'Muu'],
  };

  ApiClient get _api => ApiClient(Provider.of<AuthService>(context, listen: false));
  bool get _verified => _existing?['isVerified'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _phone, _businessId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _api.get('/stores/my');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) return;
      final s = Map<String, dynamic>.from(res.data['store']);
      _existing = s;
      _name.text = s['name'] ?? '';
      _description.text = s['description'] ?? '';
      _address.text = s['address'] ?? '';
      _phone.text = s['phone'] ?? '';
      _businessId.text = s['businessId'] ?? '';
      _category = _categories.containsKey(s['category']) ? s['category'] : 'OTHER';
      _sellerType = s['sellerType'] ?? 'BUSINESS';
      _prepMinutes = (asInt(s['prepMinutes']) ?? 10).toDouble();
      _lat = (s['latitude'] as num?)?.toDouble();
      _lng = (s['longitude'] as num?)?.toDouble();
      _logoUrl = s['logoUrl'];
      _bannerUrl = s['bannerUrl'];
    });
  }

  /// The map step: the owner puts the pin on the shop (couriers navigate to it).
  Future<void> _pickLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => StoreLocationPicker(initialLat: _lat, initialLng: _lng, address: _address.text.trim())),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
      _error = null;
    });
  }

  Future<void> _pickImage(bool logo) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: logo ? 800 : 2000, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploading = 0);
    try {
      final url = await MediaUpload.uploadImage(
        api: _api,
        kind: 'store_image',
        file: File(picked.path),
        onProgress: (p) => mounted ? setState(() => _uploading = p) : null,
      );
      setState(() => logo ? _logoUrl = url : _bannerUrl = url);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      setState(() =>
          _error = tr(context, 'Put your shop on the map so couriers can find you.', 'Merkitse kauppasi kartalle, jotta kuriirit löytävät sinut.'));
      return;
    }
    final hoursProblem = _existing == null ? _hours.validate(context) : null;
    if (hoursProblem != null) {
      setState(() => _error = hoursProblem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await _api.post('/stores', {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'address': _address.text.trim(),
      'latitude': _lat,
      'longitude': _lng,
      'prepMinutes': _prepMinutes.round(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (!_verified) 'sellerType': _sellerType,
      if (!_verified && _sellerType == 'BUSINESS') 'businessId': _businessId.text.trim(),
      if (_logoUrl != null) 'logoUrl': _logoUrl,
      if (_bannerUrl != null) 'bannerUrl': _bannerUrl,
      if (_existing == null) 'openingHours': _hours.toJson(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      setState(() => _error = res.error);
      return;
    }
    if (_existing == null) {
      // The app's home follows the store's state and switches to the dashboard by itself
      await Provider.of<AuthService>(context, listen: false).checkStore();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_existing == null ? tr(context, 'Set up your store', 'Perusta kauppasi') : tr(context, 'Store details', 'Kaupan tiedot')),
        actions: [
          // Before the store exists this is the home screen: help, sign out and account deletion live here
          if (_existing == null && !_loading)
            IconButton(
              tooltip: tr(context, 'Account and help', 'Tili ja apua'),
              icon: const Icon(Icons.manage_accounts_outlined),
              onPressed: () => showAccountSheet(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  if (_existing != null) ...[
                    _pictures(),
                    const SizedBox(height: 20),
                  ],
                  TextFormField(
                    controller: _name,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: tr(context, 'Store name', 'Kaupan nimi')),
                    validator: (v) => (v ?? '').trim().length < 2 ? tr(context, 'Enter the store name', 'Anna kaupan nimi') : null,
                  ),
                  TextFormField(
                    controller: _description,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: tr(context, 'What do you sell?', 'Mitä myyt?')),
                  ),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: InputDecoration(labelText: tr(context, 'Main category', 'Pääkategoria')),
                    items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(isFinnish(context) ? e.value[1] : e.value[0]))).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 20),
                  Text(tr(context, 'Who is selling?', 'Kuka myy?'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'BUSINESS', label: Text(tr(context, 'A business', 'Yritys')), icon: const Icon(Icons.business_rounded)),
                      ButtonSegment(value: 'PRIVATE', label: Text(tr(context, 'A private person', 'Yksityishenkilö')), icon: const Icon(Icons.person_outline_rounded)),
                    ],
                    selected: {_sellerType},
                    onSelectionChanged: _verified ? null : (s) => setState(() => _sellerType = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _sellerType == 'BUSINESS'
                        ? tr(context, 'Businesses give their Y-tunnus. Customers get the 14-day right of withdrawal and see your company details.',
                            'Yritykset antavat Y-tunnuksensa. Asiakkailla on 14 päivän peruuttamisoikeus, ja he näkevät yrityksesi tiedot.')
                        : tr(context, 'Only for people selling their own items occasionally. If you sell regularly for profit, you are a business.',
                            'Vain omia tavaroitaan satunnaisesti myyville. Jos myyt säännöllisesti voittoa tavoitellen, olet yritys.'),
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  if (_verified)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          tr(context, 'To change this after approval, write to the Malvoya team in Store → Help.',
                              'Muuttaaksesi tätä hyväksynnän jälkeen kirjoita Malvoyan tiimille kohdassa Kauppa → Apua.'),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ),
                  if (_sellerType == 'BUSINESS')
                    TextFormField(
                      controller: _businessId,
                      enabled: !_verified,
                      decoration: InputDecoration(labelText: 'Y-tunnus', hintText: '1234567-8'),
                      validator: (v) => RegExp(r'^\d{7}-\d$').hasMatch((v ?? '').trim()) ? null : tr(context, 'Format 1234567-8', 'Muoto 1234567-8'),
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _address,
                    decoration: InputDecoration(labelText: tr(context, 'Pickup address', 'Noutoosoite'), hintText: 'Mannerheimintie 1, 00100 Helsinki'),
                    validator: (v) => (v ?? '').trim().length < 5 ? tr(context, 'Enter the address couriers pick up from', 'Anna osoite, josta kuriirit noutavat') : null,
                  ),
                  const SizedBox(height: 8),
                  _locationCard(),
                  const SizedBox(height: 8),
                  TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: tr(context, 'Phone (for couriers, optional)', 'Puhelin (kuriireille, valinnainen)'))),
                  const SizedBox(height: 20),
                  Text('${tr(context, 'Time to pack an order', 'Tilauksen pakkausaika')}: ${_prepMinutes.round()} min', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Slider(value: _prepMinutes, min: 0, max: 60, divisions: 12, label: '${_prepMinutes.round()} min', onChanged: (v) => setState(() => _prepMinutes = v)),
                  Text(tr(context, 'Used for the delivery times customers see.', 'Käytetään asiakkaille näytettävissä toimitusajoissa.'),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  if (_existing == null) ...[
                    const SizedBox(height: 24),
                    Text(tr(context, 'Opening hours', 'Aukioloajat'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, 'Customers can only order while you are open (Finnish time). You can change these later in Store → Opening hours.',
                          'Asiakkaat voivat tilata vain aukioloaikoina (Suomen aikaa). Voit muuttaa niitä myöhemmin kohdassa Kauppa → Aukioloajat.'),
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
                    ),
                    OpeningHoursEditor(draft: _hours, onChanged: () => setState(() {})),
                  ],
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _saving || _uploading != null ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_existing == null ? tr(context, 'Create store', 'Luo kauppa') : tr(context, 'Save', 'Tallenna')),
                    ),
                  ),
                  if (_existing == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                          tr(context, 'You can add a logo and cover picture once the store is created. Our team reviews every store before it goes live.',
                              'Voit lisätä logon ja kansikuvan, kun kauppa on luotu. Tiimimme tarkistaa jokaisen kaupan ennen julkaisua.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                    ),
                ],
              ),
            ),
    );
  }

  /// The pin on a small map, or a call to set it.
  Widget _locationCard() {
    final pin = _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: AppTheme.divider)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pin != null)
          SizedBox(
            height: 140,
            child: IgnorePointer(
              child: FlutterMap(
                key: ValueKey(pin),
                options: MapOptions(initialCenter: pin, initialZoom: 16),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.malvoya.vendor'),
                  MarkerLayer(markers: [
                    Marker(point: pin, width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on_rounded, size: 40, color: AppTheme.primary)),
                  ]),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              pin != null
                  ? tr(context, 'Couriers come to this pin. Map © OpenStreetMap contributors', 'Kuriirit tulevat tähän neulaan. Kartta © OpenStreetMapin tekijät')
                  : tr(context, 'Put your shop on the map so couriers find the door.', 'Merkitse kauppasi kartalle, jotta kuriirit löytävät oven.'),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickLocation,
              icon: Icon(pin != null ? Icons.edit_location_alt_outlined : Icons.add_location_alt_outlined),
              label: Text(pin != null ? tr(context, 'Move the pin', 'Siirrä neulaa') : tr(context, 'Set the pin on the map', 'Aseta neula kartalle')),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _pictures() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: tr(context, 'Change cover picture', 'Vaihda kansikuva'),
            child: GestureDetector(
              onTap: () => _pickImage(false),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: _bannerUrl != null
                      ? CachedNetworkImage(imageUrl: _bannerUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.primaryLight,
                          child: Center(child: Text(tr(context, 'Add a cover picture', 'Lisää kansikuva'), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600))),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Semantics(
              button: true,
              label: tr(context, 'Change logo', 'Vaihda logo'),
              child: GestureDetector(
                onTap: () => _pickImage(true),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: AppTheme.primaryLight,
                  backgroundImage: _logoUrl != null ? CachedNetworkImageProvider(_logoUrl!) : null,
                  child: _logoUrl == null ? const Icon(Icons.add_a_photo_outlined, color: AppTheme.primary) : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(tr(context, 'Tap to change the logo or cover picture.', 'Vaihda logo tai kansikuva napauttamalla.'), style: const TextStyle(color: AppTheme.textSecondary))),
            if (_uploading != null) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(value: _uploading, strokeWidth: 3)),
          ]),
        ],
      );
}
