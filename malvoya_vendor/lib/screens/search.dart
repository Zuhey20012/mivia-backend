import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String selectedWhoFor = 'Myself';
  String selectedGender = 'Unisex';
  String selectedAgeGroup = 'Adults (20-55)';

  void _showDemographicsFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Demographics & Filters', style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 24),
                  
                  // Who is this for?
                  Text('Who is this for?', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: ['Myself', 'Someone Else (Gift)'].map((opt) => ChoiceChip(
                      label: Text(opt),
                      selected: selectedWhoFor == opt,
                      onSelected: (val) { if(val) setModalState(() => selectedWhoFor = opt); setState(() => selectedWhoFor = opt); },
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  
                  // Gender
                  Text('Gender', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: ['Men', 'Women', 'Unisex'].map((opt) => ChoiceChip(
                      label: Text(opt),
                      selected: selectedGender == opt,
                      onSelected: (val) { if(val) setModalState(() => selectedGender = opt); setState(() => selectedGender = opt); },
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  
                  // Age Group
                  Text('Age Group', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: ['Kids (0-12)', 'Teens (13-19)', 'Adults (20-55)', 'Seniors (55+)'].map((opt) => ChoiceChip(
                      label: Text(opt),
                      selected: selectedAgeGroup == opt,
                      onSelected: (val) { if(val) setModalState(() => selectedAgeGroup = opt); setState(() => selectedAgeGroup = opt); },
                    )).toList(),
                  ),
                  const SizedBox(height: 32),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Apply Filters'),
                    ),
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search for clothes, cosmetics...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.tune, color: Theme.of(context).primaryColor),
                    onPressed: _showDemographicsFilter,
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            // Display active filters
            Row(
              children: [
                const Icon(Icons.filter_list, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing items for $selectedGender, $selectedAgeGroup ($selectedWhoFor)',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.search, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('Start typing to find amazing local products.', style: TextStyle(color: Colors.grey)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
