import 'package:flutter/material.dart';
import '../l10n.dart';
import 'catalogue.dart';

/// A home-screen category opens the catalogue with the matching filter.
class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  const CategoryDetailScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).translateCategory(categoryName);
    switch (categoryName) {
      case 'Vintage':
      case 'Second Hand':
        return CatalogueScreen(title: title, secondHand: true);
      case 'Eco-Friendly':
        return CatalogueScreen(title: title, eco: true);
      default:
        // Clothing, Shoes, Bags, Accessories, Jewelry, Beauty, Home — the categories stores pick from
        return CatalogueScreen(title: title, category: categoryName);
    }
  }
}
