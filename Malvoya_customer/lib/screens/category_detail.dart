import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String categoryName;

  const CategoryDetailScreen({super.key, required this.categoryName});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  int _selectedSubCatIndex = 0;

  Map<String, List<String>> _subcategories = {
    'Accessories': ['All', 'Watches', 'Rings', 'Necklaces', 'Hats', 'Belts'],
    'Apparel': ['All', 'Shirts', 'Pants', 'Dresses', 'Jackets', 'Shoes'],
    'Cosmetics': ['All', 'Makeup', 'Fragrances', 'Tools', 'Palettes'],
    'Skincare': ['All', 'Moisturizers', 'Cleansers', 'Serums', 'Sunscreens'],
    'Pets': ['All', 'Food', 'Toys', 'Beds', 'Collars'],
  };

  @override
  Widget build(BuildContext context) {
    final subCats = _subcategories[widget.categoryName] ?? ['All', 'Featured', 'New Arrivals', 'Sales'];

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: Column(
        children: [
          // Sub-category Chips
          SizedBox(
            height: 60,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: subCats.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedSubCatIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(subCats[index], style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    selectedColor: Theme.of(context).primaryColor,
                    backgroundColor: Colors.grey.shade200,
                    onSelected: (selected) {
                      HapticFeedback.lightImpact();
                      if (selected) setState(() => _selectedSubCatIndex = index);
                    },
                  ),
                );
              },
            ),
          ),
          
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withOpacity(0.7)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Discover ${subCats[_selectedSubCatIndex]}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Find the best ${subCats[_selectedSubCatIndex].toLowerCase()} right here in Helsinki.', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Top Rated Stores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Dummy store item
                Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Theme.of(context).primaryColor.withOpacity(0.6), Theme.of(context).primaryColor.withOpacity(0.9)],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.local_mall, size: 64, color: Colors.white),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Premium $widget.categoryName Store', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, size: 16, color: Theme.of(context).primaryColor),
                                const Text(' 4.9 (120+)'),
                                const SizedBox(width: 16),
                                const Icon(Icons.delivery_dining, size: 16, color: Colors.grey),
                                const Text(' 10-20 min', style: TextStyle(color: Colors.grey)),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
