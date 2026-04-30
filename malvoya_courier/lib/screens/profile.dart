import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import 'admin_dashboard.dart';
import 'chatbot.dart';
import 'profile_detail.dart';
import '../locale_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _buildSection(BuildContext context, String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Container(
          color: Colors.white,
          child: Column(children: items),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showLegalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms of Service & Legal'),
        content: const SingleChildScrollView(
          child: Text(
            '''By using Malvoya, you agree to the following terms, strictly adhering to European Union business laws and the laws of Finland:

1. EU General Data Protection Regulation (GDPR)
We respect your privacy. Your personal data is securely processed and will not be shared with third parties without consent. You have the right to request deletion of your data at any time.

2. Finnish Consumer Protection Act (Kuluttajansuojalaki)
- 14-Day Right of Return: As a consumer, you have the right to return most purchased items within 14 days of receipt, provided the item is in its original condition.
- Defective Goods: If an item is defective, you have the right to a repair, replacement, or refund in accordance with Finnish law.

3. Platform Liability
Malvoya acts as a marketplace. While we verify Home Based Sellers, individual sellers are responsible for their product listings. 

4. EU E-commerce Directives
All prices are displayed including VAT (where applicable). Transparent pricing and clear checkout processes are strictly maintained.
''',
            style: TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('I Understand')),
        ],
      ),
    );
  }

  void _nav(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Text('M', style: TextStyle(fontSize: 32, color: Colors.white)),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Malvoya User', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('+358 40 123 4567', style: TextStyle(color: Colors.grey)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(context, 'Account', [
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              trailing: Consumer<LocaleProvider>(
                builder: (context, provider, _) {
                  return DropdownButton<String>(
                    value: provider.locale.languageCode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'fi', child: Text('Suomi')),
                    ],
                    onChanged: (val) {
                      if (val != null) provider.setLocale(Locale(val));
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), trailing: const Icon(Icons.chevron_right), onTap: () => _nav(context, const ProfileDetailScreen(title: 'Settings'))),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.credit_card), title: const Text('Payment methods'), trailing: const Icon(Icons.chevron_right), onTap: () => _nav(context, const ProfileDetailScreen(title: 'Payment Methods'))),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.location_on), title: const Text('Delivery addresses'), trailing: const Icon(Icons.chevron_right), onTap: () => _nav(context, const ProfileDetailScreen(title: 'Delivery Addresses'))),
          ]),
          _buildSection(context, 'Support', [
            ListTile(leading: const Icon(Icons.support_agent, color: Colors.blue), title: const Text('AI Chatbot Support', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), trailing: const Icon(Icons.chevron_right, color: Colors.blue), onTap: () => _nav(context, const ChatbotScreen())),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.help_outline), title: const Text('Customer Support'), trailing: const Icon(Icons.chevron_right), onTap: () => _nav(context, const ProfileDetailScreen(title: 'Customer Support'))),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.info_outline), title: const Text('About Malvoya'), trailing: const Icon(Icons.chevron_right), onTap: () => _nav(context, const ProfileDetailScreen(title: 'About Malvoya'))),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.gavel), 
              title: const Text('Terms of Service & Legal'), 
              trailing: const Icon(Icons.chevron_right), 
              onTap: () => _showLegalDialog(context),
            ),
          ]),
          Consumer<AuthService>(
            builder: (context, auth, _) {
              if (auth.isAdmin) {
                return _buildSection(context, 'Admin Controls', [
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Colors.purple), 
                    title: const Text('Owner Dashboard', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)), 
                    trailing: const Icon(Icons.chevron_right, color: Colors.purple), 
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
                    },
                  ),
                ]);
              }
              return const SizedBox.shrink();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () {
                Provider.of<AuthService>(context, listen: false).logout();
              },
              child: const Text('Log out', style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
