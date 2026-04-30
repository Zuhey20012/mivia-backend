import 'package:flutter/material.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String title;

  const ProfileDetailScreen({super.key, required this.title});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  // Real state mimicking a database
  List<Map<String, String>> _addresses = [
    {'title': 'Home', 'address': 'Mannerheimintie 12 A 4\n00100 Helsinki, Finland'},
  ];
  
  List<Map<String, String>> _cards = [
    {'title': 'Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ 4242', 'expiry': '12/28'},
  ];

  bool _notifications = true;
  bool _darkMode = false;

  void _addNewAddress() {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add New Address', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: ctrl1, decoration: const InputDecoration(labelText: 'Title (e.g. Work, Gym)')),
            const SizedBox(height: 16),
            TextField(controller: ctrl2, decoration: const InputDecoration(labelText: 'Full Address')),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (ctrl1.text.isNotEmpty && ctrl2.text.isNotEmpty) {
                    setState(() {
                      _addresses.add({'title': ctrl1.text, 'address': ctrl2.text});
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address Saved successfully')));
                  }
                },
                child: const Text('Save Address'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _addNewCard() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secure Payment Gateway Connecting...')));
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _cards.add({'title': 'Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢ 8888', 'expiry': '05/30'});
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Credit Card Added successfully')));
    });
  }

  Widget _buildSettings(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Receive order updates and promotions'),
          value: _notifications,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (v) => setState(() => _notifications = v),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('A soothing dark theme for nighttime'),
          value: _darkMode,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (v) => setState(() => _darkMode = v),
        ),
        const Divider(),
        ListTile(
          title: const Text('Language', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('English (US)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildDeliveryAddresses(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ..._addresses.map((addr) => Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1), child: Icon(Icons.location_on, color: Theme.of(context).primaryColor)),
            title: Text(addr['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text(addr['address']!),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () {
              setState(() => _addresses.remove(addr));
            }),
          ),
        )).toList(),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _addNewAddress,
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Add New Address', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )
      ],
    );
  }

  Widget _buildPaymentMethods(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ..._cards.map((card) => Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const Icon(Icons.credit_card, size: 40, color: Colors.indigo),
            title: Text(card['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2)),
            subtitle: Text('Expires ${card['expiry']}'),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
          ),
        )).toList(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _addNewCard,
          icon: const Icon(Icons.add),
          label: const Text('Add Credit/Debit Card', style: TextStyle(fontSize: 16)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutMalvoya(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
            child: const Icon(Icons.shopping_bag, size: 80, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text('Malvoya', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Text('Version 1.0.0 (Build 42)', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          const Text('Made with Ã¢ÂÂ¤Ã¯Â¸Â in Finland', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (widget.title) {
      case 'Settings': body = _buildSettings(context); break;
      case 'Delivery Addresses': body = _buildDeliveryAddresses(context); break;
      case 'Payment Methods': body = _buildPaymentMethods(context); break;
      case 'About Malvoya': body = _buildAboutMalvoya(context); break;
      default: body = const Center(child: Text('Connecting to real server...'));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }
}
