import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';

/// Help for sellers: straight answers, the seller terms, and a way to reach the Malvoya team.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _topic = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _topic.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().length < 5) return;
    setState(() => _sending = true);
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/support', {
      'app': 'store',
      'topic': _topic.text.trim().isEmpty ? 'Seller question' : _topic.text.trim(),
      'message': _message.text.trim(),
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      _topic.clear();
      _message.clear();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok
          ? tr(context, 'Sent (#${res.data['id']}). We reply by email to ${res.data['replyTo']}.', 'Lähetetty (#${res.data['id']}). Vastaamme sähköpostitse osoitteeseen ${res.data['replyTo']}.')
          : res.error!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final faq = [
      (tr(context, 'When does my store go live?', 'Milloin kauppani julkaistaan?'),
          tr(context, 'After our team has checked your details (Y-tunnus for businesses). You can add products and drops meanwhile.', 'Kun tiimimme on tarkistanut tietosi (yrityksiltä Y-tunnus). Voit lisätä tuotteita ja julkaisuja sillä välin.')),
      (tr(context, 'When am I paid?', 'Milloin saan rahat?'),
          tr(context, '15 days after delivery, when the 14-day return window has passed, to your Stripe account (Store → Payouts). Malvoya keeps the commission agreed in the seller terms.', '15 päivää toimituksen jälkeen, kun 14 päivän palautusaika on päättynyt, Stripe-tilillesi (Kauppa → Tilitykset). Malvoya pidättää myyjän ehdoissa sovitun provision.')),
      (tr(context, 'How do orders work?', 'Miten tilaukset toimivat?'),
          tr(context, 'You only see paid orders. Accept or decline, pack it, tap "Packed". A courier picks it up. Declined orders are refunded automatically.', 'Näet vain maksetut tilaukset. Hyväksy tai hylkää, pakkaa ja paina "Pakattu". Kuriiri noutaa tilauksen. Hylätyt tilaukset hyvitetään automaattisesti.')),
      (tr(context, 'How are drops shown?', 'Miten julkaisut näytetään?'),
          tr(context, 'In the Drops feed by how new they are, how people respond, how close your store is to the customer and your rating. Nobody can buy a better position.', 'Drops-syötteessä uutuuden, reaktioiden, etäisyyden ja arvosanasi perusteella. Parempaa sijoitusta ei voi ostaa.')),
      (tr(context, 'How do returns work?', 'Miten palautukset toimivat?'),
          tr(context, 'Customers of business sellers can return within 14 days of delivery. Approve the return, confirm when you get the items, then refund in the app.', 'Yritysmyyjien asiakkaat voivat palauttaa 14 päivän kuluessa. Hyväksy palautus, vahvista kun saat tuotteet ja hyvitä sovelluksessa.')),
    ];
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Help for sellers', 'Apua myyjille'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final q in faq)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text(q.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [Text(q.$2, style: const TextStyle(height: 1.45, color: AppTheme.textSecondary))],
              ),
            ),
          TextButton.icon(onPressed: () => openLegal('sellers'), icon: const Icon(Icons.gavel_rounded), label: Text(tr(context, 'Read the seller terms', 'Lue myyjän ehdot'))),
          const Divider(height: 32),
          Text(tr(context, 'Contact the Malvoya team', 'Ota yhteyttä Malvoyan tiimiin'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(controller: _topic, maxLength: 80, decoration: InputDecoration(labelText: tr(context, 'Subject', 'Aihe'))),
          TextField(controller: _message, maxLength: 4000, maxLines: 5, decoration: InputDecoration(labelText: tr(context, 'How can we help?', 'Miten voimme auttaa?'))),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr(context, 'Send', 'Lähetä')),
            ),
          ),
          const SizedBox(height: 6),
          Text(tr(context, 'We reply by email to your account address.', 'Vastaamme sähköpostitse tilisi osoitteeseen.'), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
