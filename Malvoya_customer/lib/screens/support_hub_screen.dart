import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/strings.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'chatbot.dart';
import '../auth_service.dart';
import '../core/api_client.dart';

/// Contact: messages are stored by the server (admin panel → Support) and answered by email.
/// There is no phone line, live chat or SMS channel, so none is offered here.
class SupportHubScreen extends StatefulWidget {
  const SupportHubScreen({super.key});

  @override
  State<SupportHubScreen> createState() => _SupportHubScreenState();
}

class _Topic {
  final String id;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<String> examples;
  const _Topic(this.id, this.icon, this.color, this.title, this.subtitle, this.examples);
}

class _SupportHubScreenState extends State<SupportHubScreen> {
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_Topic> _topics(BuildContext context) => [
        _Topic(
          'orders',
          Icons.inventory_2_outlined,
          const Color(0xFF6D2E8C),
          tr(context, 'Orders and delivery', 'Tilaukset ja toimitus'),
          tr(context, 'Where your order is, a missing or wrong item', 'Missä tilauksesi on, puuttuva tai väärä tuote'),
          [
            tr(context, 'Where is my order?', 'Missä tilaukseni on?'),
            tr(context, 'An item is missing', 'Tuote puuttuu'),
            tr(context, 'I got the wrong item', 'Sain väärän tuotteen'),
          ],
        ),
        _Topic(
          'returns',
          Icons.assignment_return_outlined,
          const Color(0xFFE08A00),
          tr(context, 'Returns and refunds', 'Palautukset ja hyvitykset'),
          tr(context, '14-day withdrawal for purchases from business sellers, refund status',
              '14 päivän peruuttamisoikeus yritysmyyjiltä ostettaessa, hyvityksen tila'),
          [
            tr(context, 'When will I get my refund?', 'Milloin saan hyvityksen?'),
            tr(context, 'The item is faulty', 'Tuote on viallinen'),
            tr(context, 'Returning to a private seller', 'Palautus yksityismyyjälle'),
          ],
        ),
        _Topic(
          'payments',
          Icons.credit_card_outlined,
          const Color(0xFF248A52),
          tr(context, 'Payments', 'Maksut'),
          tr(context, 'Charges, declined payments and receipts', 'Veloitukset, hylätyt maksut ja kuitit'),
          [
            tr(context, 'My payment was declined', 'Maksuni hylättiin'),
            tr(context, 'I was charged twice', 'Minua veloitettiin kahdesti'),
            tr(context, 'I need a receipt', 'Tarvitsen kuitin'),
          ],
        ),
        _Topic(
          'account',
          Icons.manage_accounts_outlined,
          const Color(0xFF3B82F6),
          tr(context, 'Account and privacy', 'Tili ja tietosuoja'),
          tr(context, 'Signing in, your details and your data', 'Kirjautuminen, tietosi ja henkilötietosi'),
          [
            tr(context, 'I cannot sign in', 'En pääse kirjautumaan'),
            tr(context, 'Change my phone number', 'Puhelinnumeroni vaihto'),
            tr(context, 'A question about my data', 'Kysymys tiedoistani'),
          ],
        ),
        _Topic(
          'partner',
          Icons.handshake_outlined,
          const Color(0xFF6366F1),
          tr(context, 'Selling or delivering', 'Myyminen tai toimittaminen'),
          tr(context, 'Opening a store or becoming a courier', 'Kaupan avaaminen tai lähetiksi ryhtyminen'),
          [
            tr(context, 'How do I open a store?', 'Miten avaan kaupan?'),
            tr(context, 'How do I become a courier?', 'Miten minusta tulee lähetti?'),
          ],
        ),
        _Topic(
          'other',
          Icons.chat_bubble_outline_rounded,
          const Color(0xFF8E4FAE),
          tr(context, 'Something else', 'Jokin muu'),
          tr(context, 'Feedback, ideas or anything else', 'Palaute, ideat tai muu asia'),
          [
            tr(context, 'Feedback about the app', 'Palautetta sovelluksesta'),
          ],
        ),
      ];

  void _openMessageSheet(_Topic topic) {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final auth = Provider.of<AuthService>(context, listen: false);
    final messageCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    bool sending = false;

    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: cardBorder),
          ),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: topic.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(topic.icon, color: topic.color, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(topic.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary))),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l10n.translate('commonInquiries'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: topic.examples.map((example) {
                    return GestureDetector(
                      onTap: () => messageCtrl.text = example,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: inputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Text(example, style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Text(l10n.translate('describeYourRequest'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: messageCtrl,
                  maxLines: 4,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.translate('inquiryHint'),
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                // Signed-in customers get the reply at their account email; guests tell us where
                if (!auth.isAuthenticated) ...[
                  const SizedBox(height: 14),
                  Text(l10n.translate('yourReplyEmail'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'name@example.com',
                      hintStyle: TextStyle(color: textSecondary),
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: sending
                        ? null
                        : () async {
                            if (messageCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.translate('pleaseDescribeInquiry'))),
                              );
                              return;
                            }
                            setSheet(() => sending = true);
                            final res = await ApiClient(auth).post('/support', {
                              'app': 'customer',
                              'topic': topic.title,
                              'message': messageCtrl.text.trim(),
                              if (!auth.isAuthenticated && emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
                            });
                            if (!mounted) return;
                            if (ctx.mounted) setSheet(() => sending = false);
                            if (res.ok && ctx.mounted) Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(res.ok
                                  ? tr(context, 'Sent (#${res.data['id']}). We will reply to ${res.data['replyTo']}.',
                                      'Lähetetty (#${res.data['id']}). Vastaamme osoitteeseen ${res.data['replyTo']}.')
                                  : res.error!),
                            ));
                          },
                    child: sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l10n.translate('submitSupportRequest'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, _, __) {
        final l10n = AppLocalizations.of(context);
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final inputBg = AppTheme.inputBackground(context);
        final cardBorder = AppTheme.cardBorder(context);

        final query = _searchQuery.toLowerCase();
        final filteredTopics = _topics(context).where((t) {
          return t.title.toLowerCase().contains(query) || t.subtitle.toLowerCase().contains(query);
        }).toList();

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              l10n.translate('customerSupport'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textPrimary),
            ),
            backgroundColor: cardBg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.translate('howCanWeAssist'), style: AppTheme.display(context, size: 22)),
                    const SizedBox(height: 4),
                    Text(l10n.translate('howCanWeAssistSub'), style: TextStyle(fontSize: 13, color: textSecondary)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: textPrimary, fontSize: 14),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: l10n.translate('searchTopicsHint'),
                        hintStyle: TextStyle(fontSize: 13, color: textSecondary),
                        prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: inputBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Help assistant (ready-made answers, not a person and not AI)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.help_outline_rounded, color: AppTheme.primary, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr(context, 'Help assistant', 'Apuri'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(
                                  tr(context, 'Ready-made answers about orders, returns and sizes', 'Valmiit vastaukset tilauksista, palautuksista ja koosta'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l10n.translate('allTopicsHeader'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8),
                ),
              ),
              const SizedBox(height: 8),

              ...filteredTopics.map((topic) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: topic.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(topic.icon, color: topic.color, size: 24),
                    ),
                    title: Text(topic.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(topic.subtitle, style: TextStyle(fontSize: 12, color: textSecondary, height: 1.3)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () => _openMessageSheet(topic),
                  ),
                );
              }),

              const SizedBox(height: 56),
            ],
          ),
        );
      },
    );
  }
}
