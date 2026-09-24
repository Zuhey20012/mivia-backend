import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../l10n.dart';
import 'vendor_dashboard.dart';

class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});
  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _bannerCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locating = false;
  int _step = 0; // 0=Store Info, 1=Category, 2=Photos & Description
  String _category = 'Apparel';
  bool _loading = false;
  String? _error;

  // 9 categories with icons
  final _categoryItems = <Map<String, dynamic>>[
    {'label': 'Vaatteet / Apparel',         'value': 'Apparel',      'icon': Icons.checkroom_outlined},
    {'label': 'Second Hand',                 'value': 'Second Hand',  'icon': Icons.recycling_outlined},
    {'label': 'Kosmetiikka / Cosmetics',    'value': 'Cosmetics',    'icon': Icons.face_outlined},
    {'label': 'Ihonhoito / Skincare',       'value': 'Skincare',     'icon': Icons.spa_outlined},
    {'label': 'Asusteet / Accessories',     'value': 'Accessories',  'icon': Icons.watch_outlined},
    {'label': 'Lemmikkitarvikkeet / Pets',  'value': 'Pets',         'icon': Icons.pets_outlined},
    {'label': 'Ekologiset / Eco Friendly',  'value': 'Eco Friendly', 'icon': Icons.eco_outlined},
    {'label': 'Boutiques',                   'value': 'Boutiques',    'icon': Icons.style_outlined},
    {'label': 'Muu / Other',                 'value': 'Other',        'icon': Icons.more_horiz_outlined},
  ];

  final _categoryMap = <String, String>{
    'Apparel':      'APPAREL',
    'Second Hand':  'THRIFT',
    'Cosmetics':    'COSMETICS',
    'Skincare':     'COSMETICS',
    'Accessories':  'ACCESSORIES',
    'Pets':         'OTHER',
    'Eco Friendly': 'ECO_FRIENDLY',
    'Boutiques':    'APPAREL',
    'Other':        'OTHER',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _bannerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your store name.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    if (_addressCtrl.text.trim().length < 5 || _lat == null || _lng == null) {
      setState(() { _loading = false; _error = 'Add your store address and tap "Use my current location" while at the store.'; });
      return;
    }
    final banner = _bannerCtrl.text.trim();

    final auth = Provider.of<AuthService>(context, listen: false);
    final normalizedCategory = _categoryMap[_category] ?? _category.toUpperCase().replaceAll(' ', '_');

    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBase}/stores'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.accessToken}',
        },
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'category': normalizedCategory,
          'address': _addressCtrl.text.trim(),
          'latitude': _lat,
          'longitude': _lng,
          if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
          if (banner.startsWith('https://')) 'bannerUrl': banner,
        }),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 201 || res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('vendor_store_name', _nameCtrl.text.trim());
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
        }
      } else {
        String msg = 'Could not create the store. Please check the details.';
        try {
          final body = jsonDecode(res.body);
          msg = (body['error'] ?? msg).toString();
        } catch (_) {}
        if (mounted) setState(() { _loading = false; _error = msg; });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No connection. Your store was not saved — please try again.'; });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() { _locating = true; _error = null; });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission is needed to place your store on the map.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() { _lat = pos.latitude; _lng = pos.longitude; });
    } catch (_) {
      setState(() => _error = 'Could not get your location. Check that location services are on.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _next() {
    if (_step == 0 && _nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your store name.');
      return;
    }
    setState(() { _error = null; if (_step < 2) _step++; });
  }

  void _back() {
    if (_step > 0) setState(() { _step--; _error = null; });
  }

  String get _buttonLabel {
    switch (_step) {
      case 0: return 'Jatka / Continue';
      case 1: return 'Jatka / Continue';
      case 2: return 'Luo kauppa / Create Store';
      default: return 'Continue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF17131C),
      body: Column(
        children: [
          // ── Premium dark header ────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1B2E), Color(0xFF17131C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Malvoya gradient pill badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6D2E8C), Color(0xFF4F46E5)],
                            ),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Malvoya', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
                          child: const Text('Sign out', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context).translate('openYourStore'),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Myy tuotteitasi 20–45 min pikatoimituksella\nMalvoya-verkostosi kautta.',
                      style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    // Progress bar
                    _buildProgressBar(),
                  ],
                ),
              ),
            ),
          ),

          // ── Step content ───────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _buildStepContent(),
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final steps = ['Store Info', 'Category', 'Photos & Desc'];
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == _step;
        final isDone = i < _step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDone || isActive ? const Color(0xFF6D2E8C) : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white38,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return _buildStep1();
    }
  }

  // ── Step 1: Store Name ─────────────────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kauppasi nimi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1820))),
          const SizedBox(height: 4),
          const Text('Step 1 of 3', style: TextStyle(color: Color(0xFF6B6472), fontSize: 13)),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'e.g. Kallio Vintage Boutique',
              hintStyle: TextStyle(fontSize: 16, color: Color(0xFF6B6472), fontWeight: FontWeight.w400),
              prefixIcon: Icon(Icons.store_outlined, color: Color(0xFF6D2E8C)),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF6B6472)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kauppasi nimi näkyy asiakkaille / Visible to customers',
                  style: TextStyle(color: Color(0xFF6B6472), fontSize: 12),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _errorBox(_error!),
          ],
        ],
      ),
    );
  }

  // ── Step 2: Category Grid ──────────────────────────────────────────────────
  Widget _buildStep2() {
    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kaupan kategoria', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1820))),
          const SizedBox(height: 4),
          const Text('Step 2 of 3', style: TextStyle(color: Color(0xFF6B6472), fontSize: 13)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.85,
            children: _categoryItems.map((item) {
              final isSelected = _category == item['value'];
              return GestureDetector(
                onTap: () => setState(() => _category = item['value'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFF6D2E8C), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected ? null : const Color(0xFFEFEBF1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF6D2E8C) : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [const BoxShadow(color: Color(0x336D2E8C), blurRadius: 8, offset: Offset(0, 3))]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        color: isSelected ? Colors.white : const Color(0xFF6B6472),
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (item['label'] as String).split('/').first.trim(),
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF1C1820),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((item['label'] as String).contains('/'))
                        Text(
                          '/ ${(item['label'] as String).split('/').last.trim()}',
                          style: TextStyle(
                            color: isSelected ? Colors.white70 : const Color(0xFF6B6472),
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Description + Banner ───────────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      key: const ValueKey(2),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kuvaus ja kansikuva', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1820))),
          const SizedBox(height: 4),
          const Text('Step 3 of 3', style: TextStyle(color: Color(0xFF6B6472), fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Kaupan kuvaus (valinnainen)',
              hintText: 'Kerro asiakkaille mikä tekee kaupastasi erityisen...',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 52),
                child: Icon(Icons.description_outlined),
              ),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bannerCtrl,
            decoration: const InputDecoration(
              labelText: 'Kansikuva URL (valinnainen)',
              hintText: 'https://...',
              prefixIcon: Icon(Icons.image_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _addressCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Osoite / Store address',
              hintText: 'Katu 1, 00100 Helsinki',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Puhelin / Phone (valinnainen)',
              hintText: '+358 40 1234567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_lat != null ? Icons.check_circle_rounded : Icons.my_location_rounded),
            label: Text(_lat != null
                ? 'Location saved (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})'
                : 'Use my current location (at the store)'),
          ),
          const SizedBox(height: 16),
          // Green info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE4EFE9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E6B4F).withOpacity(0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFF2E6B4F), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kauppasi tuotteet ilmestyvät automaattisesti Malvoya Reels -syötteeseen heti kun lisäät niitä!',
                    style: TextStyle(color: Color(0xFF245740), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _errorBox(_error!),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E1EA))),
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            OutlinedButton(
              onPressed: _back,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: Color(0xFFE6E1EA)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1C1820)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: _loading
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6D2E8C), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6D2E8C), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(color: Color(0x446D2E8C), blurRadius: 12, offset: Offset(0, 4))],
                      ),
                      child: ElevatedButton(
                        onPressed: _step < 2 ? _next : _createStore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          _buttonLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Color(0xFFD93025), size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: Color(0xFFD93025), fontSize: 13))),
      ]),
    );
  }
}
