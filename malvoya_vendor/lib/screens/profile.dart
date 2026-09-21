import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import 'chatbot.dart';
import 'profile_detail.dart';
import '../locale_provider.dart';
import '../l10n.dart';

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

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: AppLocalizations.languages.entries.map((entry) {
                  final provider = Provider.of<LocaleProvider>(context, listen: false);
                  final isSelected = provider.locale.languageCode == entry.key;
                  return ListTile(
                    title: Text(entry.value, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.purple) : null,
                    onTap: () {
                      provider.setLocale(Locale(entry.key));
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Consumer<AuthService>(
            builder: (context, auth, _) {
              final user = auth.currentUser;
              final displayName = user?.name?.trim().isNotEmpty == true
                  ? user!.name!
                  : 'Malvoya Boutique Partner';
              final displayEmail = user?.email ?? 'merchant@malvoya.com';
              final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M';
              return Container(
                padding: const EdgeInsets.all(24),
                color: Theme.of(context).primaryColor.withOpacity(0.08),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: Text(initial, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(displayEmail, style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('VERIFIED MERCHANT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSection(context, 'Account', [
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Consumer<LocaleProvider>(
                builder: (context, provider, _) => Text(
                  AppLocalizations.languages[provider.locale.languageCode] ?? 'English',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context),
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
