import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import 'chatbot.dart';
import '../local_notification_service.dart';

class SupportHubScreen extends StatefulWidget {
  const SupportHubScreen({super.key});

  @override
  State<SupportHubScreen> createState() => _SupportHubScreenState();
}

class _SupportHubScreenState extends State<SupportHubScreen> {
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _topics = [
    {
      'id': 'orders',
      'title': 'Order Questions',
      'subtitle': 'Delivery tracking, courier arrival, item status & missing items',
      'icon': Icons.inventory_2_outlined,
      'color': const Color(0xFF6D2E8C),
      'examples': ['Where is my courier?', 'Change delivery address', 'Missing item in order'],
    },
    {
      'id': 'account',
      'title': 'Account Management',
      'subtitle': 'Email change, phone verification, transaction PIN & GDPR privacy',
      'icon': Icons.manage_accounts_outlined,
      'color': const Color(0xFF3B82F6),
      'examples': ['Change phone number', 'Reset 4-digit PIN', 'GDPR Article 17 erasure'],
    },
    {
      'id': 'payments',
      'title': 'Payments & Credits',
      'subtitle': 'Billing questions, Stripe card charges, SEPA refunds & receipts',
      'icon': Icons.credit_card_outlined,
      'color': const Color(0xFF248A52),
      'examples': ['Card declined assistance', 'SEPA refund status', 'Download VAT receipt'],
    },
    {
      'id': 'future',
      'title': 'Malvoya in the Future & Drops',
      'subtitle': 'Roadmap, Nordic city launches, creator program & drop invitations',
      'icon': Icons.rocket_launch_outlined,
      'color': const Color(0xFF9B5DB8),
      'examples': ['Upcoming city launches', 'Exclusive drops access', 'Creator program criteria'],
    },
    {
      'id': 'benefits',
      'title': 'Malvoya Advantages & Returns',
      'subtitle': 'Zero video spam drops, verified local boutiques & 14-day statutory returns',
      'icon': Icons.verified_outlined,
      'color': const Color(0xFFE08A00),
      'examples': ['Finnish 14-day return rights', 'Express local courier speeds', 'Verified boutique guarantee'],
    },
    {
      'id': 'partner',
      'title': 'Partner with Us',
      'subtitle': 'Merchant storefront onboarding, artisan registration & courier fleet',
      'icon': Icons.handshake_outlined,
      'color': const Color(0xFF6366F1),
      'examples': ['Apply as boutique merchant', 'Courier onboarding requirements', 'Platform fee structure'],
    },
    {
      'id': 'chats',
      'title': 'My Chats & Active Tickets',
      'subtitle': 'Conversation history with support agents and ticket resolution tracking',
      'icon': Icons.chat_bubble_outline_rounded,
      'color': const Color(0xFF8E4FAE),
      'examples': ['Ticket #MLV-9428', 'Chat with Malvoya Concierge', 'View closed cases'],
    },
  ];

  String _getTopicTitle(AppLocalizations l10n, Map<String, dynamic> topic) {
    switch (topic['id']) {
      case 'orders': return l10n.translate('supportOrderQuestions');
      case 'account': return l10n.translate('supportAccountMgmt');
      case 'payments': return l10n.translate('supportPaymentsCredits');
      case 'future': return l10n.translate('supportFutureRoadmap');
      case 'benefits': return l10n.translate('supportAdvantagesReturns');
      case 'partner': return l10n.translate('supportPartnerWithUs');
      case 'chats': return l10n.translate('supportMyChats');
      default: return topic['title'] as String;
    }
  }

  String _getTopicSubtitle(AppLocalizations l10n, Map<String, dynamic> topic) {
    switch (topic['id']) {
      case 'orders': return l10n.translate('supportOrderQuestionsSub');
      case 'account': return l10n.translate('supportAccountMgmtSub');
      case 'payments': return l10n.translate('supportPaymentsCreditsSub');
      case 'future': return l10n.translate('supportFutureRoadmapSub');
      case 'benefits': return l10n.translate('supportAdvantagesReturnsSub');
      case 'partner': return l10n.translate('supportPartnerWithUsSub');
      case 'chats': return l10n.translate('supportMyChatsSub');
      default: return topic['subtitle'] as String;
    }
  }

  void _openTicketSheet(Map<String, dynamic> topic) {
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context);
    final messageCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);
    final cardBorder = AppTheme.cardBorder(context);
    final topicTitle = _getTopicTitle(l10n, topic);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: cardBorder),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
                      color: (topic['color'] as Color).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(topic['icon'] as IconData, color: topic['color'] as Color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(topicTitle, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text('${l10n.translate("orderNum")}: MLV-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}', style: TextStyle(fontSize: 12, color: textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(l10n.translate('commonInquiries'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: (topic['examples'] as List<String>).map((example) {
                  return GestureDetector(
                    onTap: () {
                      messageCtrl.text = example;
                    },
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
                maxLines: 3,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: l10n.translate('inquiryHint'),
                  hintStyle: TextStyle(color: textSecondary),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Text(l10n.translate('yourReplyEmail'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: emailCtrl,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'name@example.com',
                  hintStyle: TextStyle(color: textSecondary),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: topic['color'] as Color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    if (messageCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('pleaseDescribeInquiry'))),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    final ticketId = 'MLV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                    
                    await LocalNotificationService.showNotification(
                      id: 401,
                      title: 'Support Ticket #$ticketId',
                      body: 'Malvoya Concierge: $topicTitle request received.',
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(l10n.translate('ticketCreatedGuaranteed').replaceAll('{id}', ticketId)),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFF248A52),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Text(l10n.translate('submitSupportRequest'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                      ),
                      onPressed: () {
                        final desc = messageCtrl.text.trim();
                        LocalNotificationService.openEmailApp(
                          email: 'support@malvoya.com',
                          subject: 'Support Request: $topicTitle',
                          body: 'Topic: $topicTitle\n\nInquiry:\n${desc.isNotEmpty ? desc : "I require concierge assistance regarding this service."}',
                        );
                      },
                      icon: const Icon(Icons.email_outlined, size: 16, color: Color(0xFF3B82F6)),
                      label: Text(l10n.translate('sendViaEmail'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
                      ),
                      onPressed: () {
                        final desc = messageCtrl.text.trim();
                        LocalNotificationService.openSmsApp(
                          phone: '',
                          body: '[Malvoya Support - $topicTitle] ${desc.isNotEmpty ? desc : "Inquiry assistance requested."}',
                        );
                      },
                      icon: const Icon(Icons.sms_rounded, size: 16, color: AppTheme.primary),
                      label: Text(l10n.translate('sendViaSms'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ),
                  ),
                ],
              ),
            ],
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

        final filteredTopics = _topics.where((t) {
          final title = _getTopicTitle(l10n, t).toLowerCase();
          final subtitle = _getTopicSubtitle(l10n, t).toLowerCase();
          final query = _searchQuery.toLowerCase();
          return title.contains(query) || subtitle.contains(query);
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
              // Banner
              Container(
                padding: const EdgeInsets.all(20),
                color: cardBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('howCanWeAssist'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.translate('howCanWeAssistSub'),
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                    const SizedBox(height: 16),
                    // Search Bar
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

              // Instant AI Concierge Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: AppTheme.primary, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.translate('instantAiConcierge'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.translate('instantAiConciergeSub'),
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

              const SizedBox(height: 14),

              // Direct Channels (AI, Email & SMS)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotScreen())),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.smart_toy_outlined, color: Color(0xFF248A52), size: 22),
                              const SizedBox(height: 6),
                              Text(l10n.translate('aiSupport'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textPrimary)),
                              Text(l10n.translate('aiSupportSub'), style: TextStyle(fontSize: 10, color: textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => LocalNotificationService.openEmailApp(
                          email: 'support@malvoya.com',
                          subject: 'Customer Concierge Request',
                          body: 'Hello Malvoya Support Team,\n\nI need assistance with my customer account / order.',
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined, color: Color(0xFF3B82F6), size: 22),
                              const SizedBox(height: 6),
                              Text(l10n.translate('emailConcierge'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textPrimary)),
                              Text(l10n.translate('emailConciergeSub'), style: TextStyle(fontSize: 10, color: textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => LocalNotificationService.openSmsApp(
                          phone: '',
                          body: 'Malvoya Concierge: Customer priority inquiry regarding order / boutique dispatch.',
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.sms_rounded, color: AppTheme.primary, size: 22),
                              const SizedBox(height: 6),
                              Text(l10n.translate('smsConcierge'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textPrimary)),
                              Text(l10n.translate('smsConciergeSub'), style: TextStyle(fontSize: 10, color: textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '${l10n.translate("allTopicsHeader")} (${filteredTopics.length})',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8),
                ),
              ),
              const SizedBox(height: 8),

              // Topic Cards
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
                        color: (topic['color'] as Color).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(topic['icon'] as IconData, color: topic['color'] as Color, size: 24),
                    ),
                    title: Text(
                      _getTopicTitle(l10n, topic),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _getTopicSubtitle(l10n, topic),
                        style: TextStyle(fontSize: 12, color: textSecondary, height: 1.3),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    onTap: () => _openTicketSheet(topic),
                  ),
                );
              }),

              const SizedBox(height: 20),

              // Response Guarantee Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF248A52).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF248A52).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF248A52), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.translate('guaranteedResponseTitle'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textPrimary)),
                            Text(l10n.translate('guaranteedResponseSub'), style: TextStyle(fontSize: 11, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        );
      },
    );
  }
}
