import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final l10n = AppLocalizations.of(context);
      _messages.add({
        'sender': 'bot',
        'text': l10n.translate('botWelcomeMsg'),
        'time': l10n.translate('justNow'),
      });
    }
  }

  List<String> _getSuggestions(AppLocalizations l10n) => [
    l10n.translate('botDeliverySuggestion'),
    l10n.translate('botReturnsSuggestion'),
    l10n.translate('botSizingSuggestion'),
    l10n.translate('botPaymentsSuggestion'),
    l10n.translate('botEmailSuggestion'),
  ];

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSuggestionTap(String query, AppLocalizations l10n) {
    if (query == l10n.translate('botEmailSuggestion')) {
      _showEmailSupportModal(context, l10n);
      return;
    }
    _ctrl.text = query.replaceFirst(RegExp(r'^[^ws]+s*'), '');
    _sendMessage(l10n);
  }

  void _sendMessage(AppLocalizations l10n) {
    final rawText = _ctrl.text.trim();
    if (rawText.isEmpty) return;

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': rawText,
        'time': l10n.translate('justNow'),
      });
    });
    final text = rawText.toLowerCase();
    _ctrl.clear();
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        if (text.contains('return') || text.contains('palaut') || text.contains('vaiht') || text.contains('refund') || text.contains('exchange') || text.contains('broken')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseReturns'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('delivery') || text.contains('toimit') || text.contains('kuriiri') || text.contains('time') || text.contains('track') || text.contains('seura') || text.contains('where') || text.contains('gps')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseDelivery'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('size') || text.contains('koko') || text.contains('sovitt') || text.contains('fit') || text.contains('measure') || text.contains('mitat') || text.contains('clothes') || text.contains('vaatte')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseSizing'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('payment') || text.contains('maksu') || text.contains('kortti') || text.contains('card') || text.contains('iban') || text.contains('bank') || text.contains('mobilepay') || text.contains('sepa')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponsePayment'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('shop') || text.contains('store') || text.contains('kauppa') || text.contains('putiikki') || text.contains('brand') || text.contains('partner') || text.contains('merchant')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseStore'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('email') || text.contains('contact') || text.contains('human') || text.contains('agent') || text.contains('help') || text.contains('tuki') || text.contains('apua')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseEmail'),
            'time': l10n.translate('justNow'),
          });
        } else if (text.contains('hello') || text.contains('hi') || text.contains('hei') || text.contains('terve') || text.contains('moro') || text.contains('paivaa')) {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseHello'),
            'time': l10n.translate('justNow'),
          });
        } else {
          _messages.add({
            'sender': 'bot',
            'text': l10n.translate('botResponseFallback'),
            'time': l10n.translate('justNow'),
          });
        }
      });
      _scrollToBottom();
    });
  }

  void _showEmailSupportModal(BuildContext context, AppLocalizations l10n) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final emailCtrl = TextEditingController(text: auth.currentUser?.email ?? '');
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String selectedCategory = l10n.translate('catExpressDelivery');

    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);
    final cardBorder = AppTheme.cardBorder(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.only(
            top: 20, left: 24, right: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.mark_email_read_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('directEmailSupport'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                          Text(l10n.translate('directEmailSupportSub'), style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(l10n.translate('yourEmailAddress'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'your.name@example.com',
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('category'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCategory,
                      dropdownColor: cardBg,
                      isExpanded: true,
                      style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      items: [
                        DropdownMenuItem(value: l10n.translate('catExpressDelivery'), child: Text(l10n.translate('catExpressDelivery'))),
                        DropdownMenuItem(value: l10n.translate('catReturns14d'), child: Text(l10n.translate('catReturns14d'))),
                        DropdownMenuItem(value: l10n.translate('catCardSepa'), child: Text(l10n.translate('catCardSepa'))),
                        DropdownMenuItem(value: l10n.translate('catBoutiquePartner'), child: Text(l10n.translate('catBoutiquePartner'))),
                        DropdownMenuItem(value: l10n.translate('catGeneralInquiry'), child: Text(l10n.translate('catGeneralInquiry'))),
                      ],
                      onChanged: (v) {
                        if (v != null) setModal(() => selectedCategory = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('subject'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: subjectCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Question regarding order #MLV-8942',
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('messageDetails'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: messageCtrl,
                  maxLines: 4,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.translate('describeYourRequest'),
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    label: Text(l10n.translate('sendTicket'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    onPressed: () {
                      if (subjectCtrl.text.trim().isEmpty || messageCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('pleaseEnterSubjectMsg'))),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      final ticketId = 'MLV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                      setState(() {
                        _messages.add({
                          'sender': 'bot',
                          'text': '✅ ${l10n.translate("ticketCreatedGuaranteed").replaceAll("{id}", ticketId)}\n\n${l10n.translate("category")}: $selectedCategory\n${l10n.translate("subject")}: ${subjectCtrl.text.trim()}',
                          'time': l10n.translate('justNow'),
                        });
                      });
                      _scrollToBottom();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.translate('ticketSentToEmail').replaceAll('{id}', ticketId)),
                          backgroundColor: const Color(0xFF248A52),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
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
        final scaffoldBg = AppTheme.scaffoldBackground(context);
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final cardBorder = AppTheme.cardBorder(context);
        final inputBg = AppTheme.inputBackground(context);
        final suggestions = _getSuggestions(l10n);

        return Scaffold(
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('malvoyaConciergeAi'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
                Text(l10n.translate('onlineOfficialSupport'), style: const TextStyle(fontSize: 12, color: Color(0xFF248A52), fontWeight: FontWeight.w600)),
              ],
            ),
            backgroundColor: cardBg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.email_outlined, size: 18),
                label: Text(l10n.translate('emailDesk'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _showEmailSupportModal(context, l10n),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Quick Suggestions Rail
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: cardBg,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: suggestions.map((q) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          backgroundColor: inputBg,
                          side: BorderSide(color: cardBorder),
                          label: Text(q, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
                          onPressed: () => _handleSuggestionTap(q, l10n),
                        ),
                      )).toList(),
                    ),
                  ),
                ),

                Divider(height: 1, color: cardBorder),

                // Message Stream
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final msg = _messages[i];
                      final isUser = msg['sender'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: isUser ? AppTheme.primary : cardBg,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 18),
                            ),
                            border: isUser ? null : Border.all(color: cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['text'],
                                style: TextStyle(
                                  color: isUser ? Colors.white : textPrimary,
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg['time'] ?? '',
                                style: TextStyle(
                                  color: isUser ? Colors.white70 : textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Input Bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    border: Border(top: BorderSide(color: cardBorder)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            onSubmitted: (_) => _sendMessage(l10n),
                            style: TextStyle(fontSize: 14, color: textPrimary),
                            decoration: InputDecoration(
                              hintText: l10n.translate('botInputHint'),
                              hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cardBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cardBorder)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                              filled: true,
                              fillColor: inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _sendMessage(l10n),
                          child: const CircleAvatar(
                            radius: 22,
                            backgroundColor: AppTheme.primary,
                            child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
