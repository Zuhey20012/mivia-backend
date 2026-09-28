import 'package:flutter/material.dart';
import 'catalogue.dart';

/// The Search tab: the catalogue with every store and item.
class SearchScreen extends StatelessWidget {
  final bool isTab;
  const SearchScreen({super.key, this.isTab = false});

  @override
  Widget build(BuildContext context) => CatalogueScreen(isTab: isTab);
}
