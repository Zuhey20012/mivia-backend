import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/constants.dart';
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
    super.dispose();
  }

  Future<void> _createStore() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your store name.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendor_store_name', _nameCtrl.text.trim());
    await prefs.setString('vendor_store_category', _category);
    await prefs.setString('vendor_store_desc', _descCtrl.text.trim());
    await prefs.setBool('vendor_has_store', true);

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
        }),
      );
      if (res.statusCode == 201 || res.statusCode == 200 || res.statusCode == 409) {
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
        }
      } else {
        final body = jsonDecode(res.body);
        final msg = (body['message'] ?? body['error'] ?? '').toString();
        if (msg.toLowerCase().contains('already have a store')) {
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
          }
          return;
        }
        // Still navigate on any other error
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
        }
      }
    } catch (_) {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
      }
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
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        children: [
          // ── Premium dark header ────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1B2E), Color(0xFF0F172A)],
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
                              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
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
                    const Text(
                      'Avaa kauppasi\nOpen Your Store',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5),
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
                    color: isDone || isActive ? const Color(0xFF7C3AED) : Colors.white24,
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
          const Text('Kauppasi nimi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF14142B))),
          const SizedBox(height: 4),
          const Text('Step 1 of 3', style: TextStyle(color: Color(0xFF6E7191), fontSize: 13)),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'e.g. Kallio Vintage Boutique',
              hintStyle: TextStyle(fontSize: 16, color: Color(0xFF6E7191), fontWeight: FontWeight.w400),
              prefixIcon: Icon(Icons.store_outlined, color: Color(0xFF7C3AED)),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF6E7191)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kauppasi nimi näkyy asiakkaille / Visible to customers',
                  style: TextStyle(color: Color(0xFF6E7191), fontSize: 12),
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
          const Text('Kaupan kategoria', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF14142B))),
          const SizedBox(height: 4),
          const Text('Step 2 of 3', style: TextStyle(color: Color(0xFF6E7191), fontSize: 13)),
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
                            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected ? null : const Color(0xFFF4F4F8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF7C3AED) : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [const BoxShadow(color: Color(0x337C3AED), blurRadius: 8, offset: Offset(0, 3))]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        color: isSelected ? Colors.white : const Color(0xFF6E7191),
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (item['label'] as String).split('/').first.trim(),
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF14142B),
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
                            color: isSelected ? Colors.white70 : const Color(0xFF6E7191),
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
          const Text('Kuvaus ja kansikuva', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF14142B))),
          const SizedBox(height: 4),
          const Text('Step 3 of 3', style: TextStyle(color: Color(0xFF6E7191), fontSize: 13)),
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
          const SizedBox(height: 16),
          // Green info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2DC653).withOpacity(0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFF2DC653), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kauppasi tuotteet ilmestyvät automaattisesti Malvoya Reels -syötteeseen heti kun lisäät niitä!',
                    style: TextStyle(color: Color(0xFF1DA840), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
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
        border: Border(top: BorderSide(color: Color(0xFFEEEEF0))),
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            OutlinedButton(
              onPressed: _back,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: Color(0xFFEEEEF0)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF14142B)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: _loading
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(color: Color(0x447C3AED), blurRadius: 12, offset: Offset(0, 4))],
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
        const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: Color(0xFFE53E3E), fontSize: 13))),
      ]),
    );
  }
}
