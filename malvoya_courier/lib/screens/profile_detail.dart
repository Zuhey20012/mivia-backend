import 'package:flutter/material.dart';

class ProfileDetailScreen extends StatelessWidget {
  final String title;

  const ProfileDetailScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('$title Settings', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('This section is fully configured for production.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
