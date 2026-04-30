import 'package:flutter/material.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [
    {'sender': 'bot', 'text': 'Hei! I am Malvoya AI. I am here to help you with orders, returns, and navigating the marketplace. What can I assist you with today?'},
  ];

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    if (_ctrl.text.isEmpty) return;
    setState(() {
      _messages.add({'sender': 'user', 'text': _ctrl.text});
    });
    final text = _ctrl.text.toLowerCase();
    _ctrl.clear();
    _scrollToBottom();
    
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        if (text.contains('return') || text.contains('refund') || text.contains('broken')) {
          _messages.add({'sender': 'bot', 'text': 'I am sorry to hear that. Under Finnish consumer law, you have 14 days to return an item. Please navigate to the "Orders" tab, select your order, and tap "Request Return". I can also connect you to a human agent if needed.'});
        } else if (text.contains('where') || text.contains('track') || text.contains('delivery') || text.contains('courier')) {
          _messages.add({'sender': 'bot', 'text': 'Your active order is currently on the way! Courier Mikael K. is approximately 2.5km away (10 mins). You can view the live map tracking on your Home tab under "Active Delivery".'});
        } else if (text.contains('gift') || text.contains('recommend') || text.contains('skincare') || text.contains('clothes')) {
          _messages.add({'sender': 'bot', 'text': 'Malvoya has an excellent selection! For skincare, I highly recommend "Lumi Cosmetics". If you are looking for apparel, check out the "Nordic Vintage" boutique. Would you like me to filter the marketplace for these categories?'});
        } else if (text.contains('payment') || text.contains('card') || text.contains('stripe')) {
          _messages.add({'sender': 'bot', 'text': 'You can manage your saved cards securely via Stripe in your Profile -> Payment Methods. Malvoya supports all major credit cards and Apple/Google Pay.'});
        } else if (text.contains('hello') || text.contains('hi') || text.contains('hei')) {
          _messages.add({'sender': 'bot', 'text': 'Hello! How can I make your Malvoya experience better today?'});
        } else {
          _messages.add({'sender': 'bot', 'text': 'I understand. Let me check the system for you... An agent has been notified and will join this chat shortly to assist you further.'});
        }
      });
      _scrollToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Malvoya Support AI')),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
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
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isUser ? Theme.of(context).primaryColor : Colors.grey.shade200,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                      ),
                      child: Text(
                        msg['text'],
                        style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.3),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(context).primaryColor,
                        child: const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
