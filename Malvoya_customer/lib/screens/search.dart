import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'store_detail.dart';

/**
 * Malvoya Universal Search & Discovery Hub
 * Fully localized across 25 languages with dynamic category filtering,
 * debounced API querying, and instant fashion boutique discovery.
 */

class SearchScreen extends StatefulWidget {
  final bool isTab;
  const SearchScreen({super.key, this.isTab = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List _results = [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final res = await http
          .get(
            Uri.parse('${AppConstants.apiBase}/stores?search=${Uri.encodeComponent(query)}'),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _results = data['stores'] ?? data ?? [];
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
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final cardBg = AppTheme.cardBackground(context);
    final cardBorder = AppTheme.cardBorder(context);

    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: cardBg,
            titleSpacing: widget.isTab ? 16 : 0,
            leading: widget.isTab
                ? Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
            actions: const [],
            title: TextField(
              controller: _searchCtrl,
              autofocus: !widget.isTab,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l10n.translate('searchHint'),
                hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7), fontSize: 14),
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                prefixIcon: Icon(Icons.search_rounded, color: textSecondary),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: textSecondary, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _results = [];
                            _searched = false;
                          });
                        },
                      )
                    : null,
              ),
              style: TextStyle(fontSize: 15, color: textPrimary),
            ),
          ),
          body: Column(
            children: [
              Divider(height: 1, color: cardBorder),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5))
                    : !_searched
                        ? _buildInitialState(l10n, textPrimary, textSecondary)
                        : _results.isEmpty
                            ? _buildNoResultsState(l10n, textPrimary, textSecondary)
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                physics: const BouncingScrollPhysics(),
                                itemCount: _results.length,
                                itemBuilder: (ctx, i) => _buildResultCard(
                                  _results[i],
                                  cardBg,
                                  cardBorder,
                                  textPrimary,
                                  textSecondary,
                                ),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInitialState(AppLocalizations l10n, Color textPrimary, Color textSecondary) {
    final rawSuggestions = ['Vintage', 'Cosmetics', 'Recycled', 'Serums', 'Shoes', 'Jackets', 'Dresses'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.translate('popularSearches'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rawSuggestions.map((s) {
              final localizedTag = l10n.translateSubcategory(s);

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _searchCtrl.text = s;
                  _search(s);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 13, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        localizedTag,
                        style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
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

  Widget _buildNoResultsState(AppLocalizations l10n, Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 48, color: textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              '${l10n.translate('noSearchResults')} "${_searchCtrl.text}"',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('tryDifferentKeywords'),
              style: TextStyle(color: textSecondary, height: 1.5, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(
    Map<String, dynamic> store,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store['name'] ?? 'Boutique Store',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    store['category'] ?? store['description'] ?? 'Nordic Fashion Boutique',
                    style: TextStyle(color: textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSecondary),
          ],
        ),
      ),
    );
  }
}
