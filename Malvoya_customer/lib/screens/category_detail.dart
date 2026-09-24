import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'store_detail.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String categoryName;

  const CategoryDetailScreen({super.key, required this.categoryName});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  int _selectedSubCatIndex = 0;
  List _stores = [];
  bool _loading = true;

  final Map<String, List<String>> _subcategories = {};

  @override
  void initState() {
    super.initState();
    _fetchCategoryStores();
  }

  Future<void> _fetchCategoryStores() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('${AppConstants.apiBase}/stores')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final rawStores = (data['stores'] ?? data ?? []) as List;
        // Filter out dummy/seed demo stores
        final filtered = rawStores.where((s) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          final isSeed = name.contains("sarah's crochet") || name.contains("elena's eco") || name.contains("leo's retro");
          if (isSeed) return false;
          final cat = (s['category'] ?? '').toString().toUpperCase();
          final target = widget.categoryName.toUpperCase().replaceAll(' ', '_');
          return cat == target || cat == 'MARKETPLACE' || cat == 'ALL';
        }).toList();

        setState(() {
          _stores = filtered;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catName = l10n.translateCategory(widget.categoryName);
    final subCats = _subcategories[widget.categoryName] ?? [];
    final scaffoldBg = AppTheme.scaffoldBackground(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final cardBorder = AppTheme.cardBorder(context);
    final inputBg = AppTheme.inputBackground(context);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        title: Text(catName, style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          if (subCats.isNotEmpty) ...[
            Container(
              color: cardBg,
              height: 52,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: subCats.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedSubCatIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(
                        AppLocalizations.of(context).translateSubcategory(subCats[index]),
                        style: TextStyle(
                          color: isSelected ? Colors.white : textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: inputBg,
                      checkmarkColor: Colors.white,
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: isSelected ? AppTheme.primary : cardBorder),
                      ),
                      onSelected: (selected) {
                        HapticFeedback.lightImpact();
                        if (selected) setState(() => _selectedSubCatIndex = index);
                      },
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: cardBorder),
          ],

          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchCategoryStores,
              color: AppTheme.primary,
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.all(20),
                children: [
                  // Category Header Banner
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9B5DB8), Color(0xFF6D2E8C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$catName - ${l10n.translate('collection')}',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.locale.languageCode == 'fi'
                            ? 'Löydä uniikkeja tuotteita paikallisista putiikeista pikatoimituksella.'
                            : 'Discover unique items from local boutiques with fast delivery.',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('${l10n.translate('storesIn')} $catName', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                  const SizedBox(height: 16),

                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                  else if (_stores.isEmpty)
                    _buildCategoryEmptyState(l10n, catName)
                  else
                    ..._stores.map((s) => _buildStoreCard(s, l10n)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryEmptyState(AppLocalizations l10n, String catName) {
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.store_mall_directory_outlined, size: 32, color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('noStoresInCategory'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('merchantsRegistering'),
            style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.translate('notificationSetMsg')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: Text(l10n.translate('notifyMeBtn')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> store, AppLocalizations l10n) {
    final rating = store['rating'] ?? 4.9;
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cardBorder, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF9B5DB8), Color(0xFF6D2E8C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: const Center(child: Icon(Icons.storefront_outlined, size: 54, color: Colors.white38)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store['name'] ?? 'Local Store', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                      Text(' $rating', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                      const SizedBox(width: 14),
                      Icon(Icons.delivery_dining_outlined, size: 16, color: textSecondary),
                      Text(' Express Delivery', style: TextStyle(color: textSecondary, fontSize: 13)),
                      const SizedBox(width: 14),
                      Text('€2.99 ${l10n.translate('deliveryFee')}', style: TextStyle(color: textSecondary, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
