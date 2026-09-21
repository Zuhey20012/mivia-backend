import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';

class AddProductScreen extends StatefulWidget {
  final int storeId;
  const AddProductScreen({super.key, required this.storeId});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '10');

  String _category = 'Apparel';
  bool _canBeSold = true;
  bool _canBeRented = false;
  bool _loading = false;
  String? _error;

  final Set<String> _selectedSizes = {};
  final Set<String> _selectedColors = {};

  static const _categories = [
    'Apparel', 'Second Hand', 'Cosmetics', 'Skincare',
    'Accessories', 'Pets', 'Eco Friendly', 'Boutiques', 'Other',
  ];

  static const _sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size'];
  static const _colors = ['Black', 'White', 'Grey', 'Beige', 'Blue', 'Red', 'Green', 'Brown', 'Multi'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _imageCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _priceCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name and price are required.');
      return;
    }
    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price <= 0) {
      setState(() => _error = 'Please enter a valid price.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthService>(context, listen: false);
    final sizesStr = _selectedSizes.join(',');
    final colorsStr = _selectedColors.join(',');
    final salePriceCents = _canBeSold ? (price * 100).round() : null;

    try {
      final res = await http.post(
        Uri.parse('${AppConstants.apiBase}/products'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.accessToken}',
        },
        body: jsonEncode({
          'storeId': widget.storeId,
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'category': _category,
          'imageUrl': _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
          'salePriceCents': salePriceCents,
          'stockQuantity': int.tryParse(_stockCtrl.text) ?? 10,
          'sizes': sizesStr,
          'colors': colorsStr,
          'canBeSold': _canBeSold,
          'canBeRented': _canBeRented,
          'isAvailable': true,
        }),
      );

      Map<String, dynamic>? responseProduct;
      if (res.statusCode == 201 || res.statusCode == 200) {
        try { responseProduct = jsonDecode(res.body) as Map<String, dynamic>?; } catch (_) {}
        await _saveLocalDrop(responseProduct, salePriceCents, sizesStr, colorsStr);
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Tuote lisätty onnistuneesti! / Product added successfully!')),
          );
        }
      } else {
        // Even on API error, save locally and proceed
        await _saveLocalDrop(null, salePriceCents, sizesStr, colorsStr);
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Tuote tallennettu paikallisesti!')),
          );
        }
      }
    } catch (_) {
      // Offline — save locally
      await _saveLocalDrop(null, salePriceCents, sizesStr, colorsStr);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Tuote tallennettu paikallisesti!')),
        );
      }
    }
  }

  Future<void> _saveLocalDrop(Map<String, dynamic>? apiProduct, int? salePriceCents, String sizesStr, String colorsStr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeName = prefs.getString('vendor_store_name') ?? 'My Store';
      final existing = prefs.getString('vendor_local_drops');
      final List<dynamic> drops = existing != null ? jsonDecode(existing) : [];
      final newDrop = <String, dynamic>{
        'id': apiProduct?['id'] ?? DateTime.now().millisecondsSinceEpoch,
        'storeId': widget.storeId,
        'storeName': storeName,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'imageUrl': _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
        'salePriceCents': salePriceCents,
        'sizes': sizesStr,
        'colors': colorsStr,
        'isAvailable': true,
        'stockQuantity': int.tryParse(_stockCtrl.text) ?? 10,
        'createdAt': DateTime.now().toIso8601String(),
      };
      drops.insert(0, newDrop);
      await prefs.setString('vendor_local_drops', jsonEncode(drops));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Lisää tuote / Add Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // ── Product Name ───────────────────────────────────────────────
            _sectionLabel('Tuotteen nimi *'),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Vintage Denim Jacket',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 14),

            // ── Description ────────────────────────────────────────────────
            _sectionLabel('Kuvaus (valinnainen)'),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Kuvaile tuotetta...',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.description_outlined),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),

            // ── Category ───────────────────────────────────────────────────
            _sectionLabel('Kategoria'),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined)),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 14),

            // ── Image URL ──────────────────────────────────────────────────
            _sectionLabel('Tuotekuva URL (valinnainen)'),
            TextField(
              controller: _imageCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://...',
                prefixIcon: Icon(Icons.image_outlined),
                labelText: 'Product Photo URL (optional)',
              ),
            ),
            const SizedBox(height: 14),

            // ── Price + Stock ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Hinta (€) *'),
                      TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.euro_outlined)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Varasto'),
                      TextField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.inventory_outlined)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Sizes ──────────────────────────────────────────────────────
            _sectionLabel('Koot / Sizes'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _sizes.map((s) {
                final sel = _selectedSizes.contains(s);
                return FilterChip(
                  label: Text(s, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? AppTheme.primary : AppTheme.textPrimary, fontSize: 13)),
                  selected: sel,
                  selectedColor: AppTheme.primaryLight,
                  backgroundColor: const Color(0xFFF4F4F8),
                  checkmarkColor: AppTheme.primary,
                  side: BorderSide(color: sel ? AppTheme.primary.withOpacity(0.4) : Colors.transparent),
                  onSelected: (v) => setState(() { if (v) _selectedSizes.add(s); else _selectedSizes.remove(s); }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Colors ─────────────────────────────────────────────────────
            _sectionLabel('Värit / Colors'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _colors.map((c) {
                final sel = _selectedColors.contains(c);
                return FilterChip(
                  label: Text(c, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? AppTheme.primary : AppTheme.textPrimary, fontSize: 13)),
                  selected: sel,
                  selectedColor: AppTheme.primaryLight,
                  backgroundColor: const Color(0xFFF4F4F8),
                  checkmarkColor: AppTheme.primary,
                  side: BorderSide(color: sel ? AppTheme.primary.withOpacity(0.4) : Colors.transparent),
                  onSelected: (v) => setState(() { if (v) _selectedColors.add(c); else _selectedColors.remove(c); }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Listing type ───────────────────────────────────────────────
            _sectionLabel('Myyntitapa / Listing Type'),
            const SizedBox(height: 10),
            _toggleOption(
              icon: Icons.sell_outlined,
              title: 'Available for Sale / Myynti',
              subtitle: 'Customers can purchase this item',
              value: _canBeSold,
              onChanged: (v) => setState(() => _canBeSold = v),
            ),
            const SizedBox(height: 8),
            _toggleOption(
              icon: Icons.loop_outlined,
              title: 'Available for Rent / Vuokraus',
              subtitle: 'Customers can rent this item by the day',
              value: _canBeRented,
              onChanged: (v) => setState(() => _canBeRented = v),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFE53E3E), fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 28),

            // ── Submit button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: _loading
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: const Text('Lisää tuote kauppaan / Add to Store',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    );
  }

  Widget _toggleOption({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      decoration: BoxDecoration(
        color: value ? AppTheme.primaryLight : const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: value ? AppTheme.primary.withOpacity(0.3) : Colors.transparent),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.primary,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        secondary: Icon(icon, color: value ? AppTheme.primary : AppTheme.textSecondary, size: 22),
      ),
    );
  }
}
