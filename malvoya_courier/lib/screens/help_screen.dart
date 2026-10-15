import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../core/api_client.dart';
import '../core/legal_links.dart';
import '../core/strings.dart';

/// Help for couriers: a message to the Malvoya team (POST /support, answered by email and shown
/// in the admin panel), optionally about the order being carried.
class HelpScreen extends StatefulWidget {
  /// The order the message is about, if any.
  final int? orderId;

  /// The courier had to stop in the middle of a delivery.
  final bool stoppingDelivery;

  const HelpScreen({super.key, this.orderId, this.stoppingDelivery = false});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _topic = TextEditingController();
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;
  bool _prefilled = false;
  String? _sent;

  AuthService get _auth => Provider.of<AuthService>(context, listen: false);

  /// Phone sign-ins have no real email address, so they give one to be answered at.
  bool get _needsEmail {
    final email = _auth.currentUser?.email ?? '';
    return email.isEmpty || email.endsWith('@phone.malvoya.app');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    if (widget.stoppingDelivery) {
      _topic.text = tr(context, 'I had to stop during a delivery', 'Jouduin keskeyttämään toimituksen');
    } else if (widget.orderId != null) {
      _topic.text = '${tr(context, 'Order', 'Tilaus')} #${widget.orderId}';
    }
  }

  @override
  void dispose() {
    _topic.dispose();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.length < 5) {
      _snack(tr(context, 'Write a few words about what happened.', 'Kirjoita muutama sana siitä, mitä tapahtui.'));
      return;
    }
    if (_needsEmail && !_email.text.contains('@')) {
      _snack(tr(context, 'Give an email address we can reply to.', 'Anna sähköpostiosoite, johon voimme vastata.'));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    final res = await ApiClient(_auth).post('/support', {
      'app': 'courier',
      'topic': _topic.text.trim().length < 2 ? 'Courier question' : _topic.text.trim(),
      'message': message,
      if (widget.orderId != null) 'orderId': widget.orderId,
      if (_needsEmail) 'email': _email.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res.ok) {
        _sent = tr(context, 'Sent (#${res.data['id']}). We reply by email to ${res.data['replyTo']}.',
            'Lähetetty (#${res.data['id']}). Vastaamme sähköpostitse osoitteeseen ${res.data['replyTo']}.');
        _message.clear();
      }
    });
    if (!res.ok) _snack(res.error!);
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(tr(context, 'Help', 'Apua'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.stoppingDelivery)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.sunshineLight, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
              child: Text(
                tr(context,
                    'Tell us where order #${widget.orderId} is now (still at the shop, with you, or somewhere else) and why you had to stop, so we can sort it out with the shop and the customer. The order stays assigned to you until we do.',
                    'Kerro, missä tilaus #${widget.orderId} on nyt (vielä kaupassa, mukanasi vai muualla) ja miksi jouduit keskeyttämään, niin selvitämme asian kaupan ja asiakkaan kanssa. Tilaus pysyy sinulla siihen asti.'),
                style: const TextStyle(color: Color(0xFF6A4500), height: 1.45),
              ),
            ),
          Text(tr(context, 'Contact the Malvoya team', 'Ota yhteyttä Malvoyan tiimiin'), style: AppTheme.display(size: 20)),
          const SizedBox(height: 6),
          Text(
            tr(context, 'Your message goes to the Malvoya team, and we reply by email.', 'Viestisi menee Malvoyan tiimille, ja vastaamme sähköpostitse.'),
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_sent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE6F3EC), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(child: Text(_sent!, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
              ]),
            ),
          TextField(controller: _topic, maxLength: 80, decoration: InputDecoration(labelText: tr(context, 'Subject', 'Aihe'))),
          TextField(
            controller: _message,
            maxLength: 4000,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(labelText: tr(context, 'What happened?', 'Mitä tapahtui?'), alignLabelWithHint: true),
          ),
          if (_needsEmail)
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: tr(context, 'Your email address', 'Sähköpostiosoitteesi'),
                helperText: tr(context, 'You signed in with your phone number, so tell us where to reply.',
                    'Kirjauduit puhelinnumerolla, joten kerro, mihin vastaamme.'),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(tr(context, 'Send to Malvoya', 'Lähetä Malvoyalle')),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => openLegal('couriers'),
            icon: const Icon(Icons.gavel_rounded),
            label: Text(tr(context, 'Read the courier agreement', 'Lue lähettisopimus')),
          ),
        ],
      ),
    );
  }
}
