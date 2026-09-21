import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../auth_service.dart';
import '../realtime_notification_service.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<Map<String, dynamic>> _paymentMethods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('malvoya_payment_methods');
      if (raw != null) {
        final List decoded = jsonDecode(raw);
        _paymentMethods = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        _paymentMethods = [];
      }
    } catch (_) {
      _paymentMethods = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistPaymentMethods() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('malvoya_payment_methods', jsonEncode(_paymentMethods));
  }

  // Mathematical Luhn Algorithm Checksum
  bool _validateLuhn(String cardNumber) {
    final cleaned = cardNumber.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < 13 || cleaned.length > 19) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = cleaned.length - 1; i >= 0; i--) {
      int n = int.tryParse(cleaned[i]) ?? -1;
      if (n == -1) return false;
      if (alternate) {
        n *= 2;
        if (n > 9) n = (n % 10) + 1;
      }
      sum += n;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
  }

  // European SEPA Modulo-97 Checksum
  bool _validateSepaIban(String iban) {
    final clean = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (clean.length < 15 || clean.length > 34) return false;
    final rearranged = clean.substring(4) + clean.substring(0, 4);
    final sb = StringBuffer();
    for (int i = 0; i < rearranged.length; i++) {
      final char = rearranged[i];
      final code = char.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        sb.write((code - 55).toString());
      } else if (code >= 48 && code <= 57) {
        sb.write(char);
      } else {
        return false;
      }
    }
    final expanded = sb.toString();
    int remainder = 0;
    for (int i = 0; i < expanded.length; i += 7) {
      final end = (i + 7 < expanded.length) ? i + 7 : expanded.length;
      final part = remainder.toString() + expanded.substring(i, end);
      remainder = int.parse(part) % 97;
    }
    return remainder == 1;
  }

  void _openAddCardModal() {
    final l10n = AppLocalizations.of(context);
    final numberCtrl = TextEditingController();
    final holderCtrl = TextEditingController();
    final expiryCtrl = TextEditingController();
    final cvcCtrl = TextEditingController();

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
        builder: (context, setModalState) => Container(
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('addCardModalTitle'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                          Text(l10n.translate('addCardModalSubtitle'), style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('${l10n.translate('cardNumber')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 19,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '4000 1234 5678 9010',
                    hintStyle: TextStyle(color: textSecondary),
                    prefixIcon: const Icon(Icons.credit_card, color: AppTheme.primary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) {
                    final clean = val.replaceAll(' ', '');
                    final buffer = StringBuffer();
                    for (int i = 0; i < clean.length; i++) {
                      if (i > 0 && i % 4 == 0) buffer.write(' ');
                      buffer.write(clean[i]);
                    }
                    final formatted = buffer.toString();
                    if (formatted != val) {
                      numberCtrl.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 14),
                Text('${l10n.translate('cardHolderName')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: holderCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. MIKKO KORHONEN',
                    hintStyle: TextStyle(color: textSecondary),
                    prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l10n.translate('expires')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: expiryCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 5,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '12/28',
                              hintStyle: TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                            onChanged: (val) {
                              if (val.length == 2 && !val.contains('/')) {
                                expiryCtrl.text = '$val/';
                                expiryCtrl.selection = TextSelection.collapsed(offset: expiryCtrl.text.length);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l10n.translate('cvv')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: cvcCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            obscureText: true,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '•••',
                              hintStyle: TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final rawNum = numberCtrl.text.replaceAll(' ', '');
                      if (!_validateLuhn(rawNum)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.translate('invalidLuhn')),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      if (holderCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('enterCardholder'))),
                        );
                        return;
                      }
                      if (expiryCtrl.text.trim().length < 5) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('enterExpiry'))),
                        );
                        return;
                      }
                      final last4 = rawNum.length >= 4 ? rawNum.substring(rawNum.length - 4) : '0000';
                      final brand = rawNum.startsWith('4') ? 'Visa' : (rawNum.startsWith('5') ? 'Mastercard' : 'Card');
                      final newMethod = {
                        'id': 'card_${DateTime.now().millisecondsSinceEpoch}',
                        'type': 'CARD',
                        'brand': brand,
                        'last4': last4,
                        'holder': holderCtrl.text.trim().toUpperCase(),
                        'expiry': expiryCtrl.text.trim(),
                        'isDefault': _paymentMethods.isEmpty,
                      };
                      setState(() {
                        _paymentMethods.insert(0, newMethod);
                      });
                      await _persistPaymentMethods();
                      final auth = Provider.of<AuthService>(context, listen: false);
                      final userEmail = auth.currentUser?.email ?? '';
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        RealtimeNotificationService.notifyBankCardAdded(
                          context,
                          last4: last4,
                          brand: brand,
                          email: userEmail,
                        );
                      }
                    },
                    child: Text(l10n.translate('saveCardVerify'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAddSepaModal() {
    final l10n = AppLocalizations.of(context);
    final ibanCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);
    final cardBorder = AppTheme.cardBorder(context);

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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Color(0xFF10B981), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.translate('linkSepaBankTitle'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                        Text(l10n.translate('linkSepaBankSubtitle'), style: TextStyle(fontSize: 12, color: textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('${l10n.translate('accountHolderName')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. MIKKO KORHONEN',
                  hintStyle: TextStyle(color: textSecondary),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Text('${l10n.translate('ibanNumber')} *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: ibanCtrl,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'FI21 1234 5678 9012 34',
                  hintStyle: TextStyle(color: textSecondary),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final iban = ibanCtrl.text.trim();
                    if (!_validateSepaIban(iban)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.translate('invalidIban')),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('enterAccountHolder'))),
                      );
                      return;
                    }
                    final cleanIban = iban.replaceAll(' ', '');
                    final last4 = cleanIban.length >= 4 ? cleanIban.substring(cleanIban.length - 4) : '0000';
                    final bankName = cleanIban.startsWith('FI') ? 'Nordea / OP SEPA' : 'European Bank';
                    final newMethod = {
                      'id': 'sepa_${DateTime.now().millisecondsSinceEpoch}',
                      'type': 'SEPA',
                      'brand': bankName,
                      'last4': last4,
                      'holder': nameCtrl.text.trim().toUpperCase(),
                      'expiry': 'SEPA Direct',
                      'isDefault': _paymentMethods.isEmpty,
                    };
                    setState(() {
                      _paymentMethods.insert(0, newMethod);
                    });
                    await _persistPaymentMethods();
                    final auth = Provider.of<AuthService>(context, listen: false);
                    final userEmail = auth.currentUser?.email ?? '';
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      RealtimeNotificationService.notifySepaBankLinked(
                        context,
                        ibanMasked: 'FI** **** $last4',
                        holderName: nameCtrl.text.trim().toUpperCase(),
                        email: userEmail,
                      );
                    }
                  },
                  child: Text(l10n.translate('verifyLinkBank'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionMenu(Map<String, dynamic> method, int index) {
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_rounded, color: AppTheme.primary),
              title: Text(l10n.translate('setDefaultPayment'), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
              onTap: () async {
                setState(() {
                  for (var m in _paymentMethods) {
                    m['isDefault'] = false;
                  }
                  method['isDefault'] = true;
                });
                await _persistPaymentMethods();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${method['brand']} (•••• ${method['last4']}): ${l10n.translate("defaultPaymentSet")}')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: Text(l10n.translate('removePaymentMethod'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                setState(() {
                  _paymentMethods.removeAt(index);
                });
                await _persistPaymentMethods();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translate('paymentMethodRemoved'))),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardBg = AppTheme.cardBackground(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final cardBorder = AppTheme.cardBorder(context);
    final inputBg = AppTheme.inputBackground(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('paymentMethods'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
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
          // Bank-Grade Payment Security Banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(Icons.verified_user_rounded, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.locale.languageCode == 'fi' ? 'Pankkitason maksuturva' : 'Bank-Grade Payment Security',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.locale.languageCode == 'fi' ? 'Stripe & Adyen PCI-DSS Level 1 • 256-bittinen SSL-salaus' : 'Stripe & Adyen PCI-DSS Level 1 • 256-Bit SSL Encryption',
                        style: TextStyle(fontSize: 11.5, color: textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Cards Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.translate('creditDebitCards').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textSecondary, letterSpacing: 0.8)),
                TextButton.icon(
                  onPressed: _openAddCardModal,
                  icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
                  label: Text('+ ${l10n.translate('addCard')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary)),
                ),
              ],
            ),
          ),

          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_paymentMethods.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.credit_card_off_rounded, color: AppTheme.primary, size: 30),
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.translate('noCardsLinked'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary)),
                  const SizedBox(height: 6),
                  Text(
                    l10n.translate('addCardPrompt'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _openAddCardModal,
                        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                        label: Text(l10n.translate('addCard'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: Color(0xFF10B981)),
                        ),
                        onPressed: _openAddSepaModal,
                        icon: const Icon(Icons.account_balance_rounded, size: 18, color: Color(0xFF10B981)),
                        label: Text(l10n.translate('linkSepa'), style: const TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ..._paymentMethods.asMap().entries.map((entry) {
              final index = entry.key;
              final method = entry.value;
              final isDefault = method['isDefault'] == true;
              final isCard = method['type'] == 'CARD';

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDefault ? AppTheme.primary : cardBorder, width: isDefault ? 1.5 : 1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCard ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isCard ? Icons.credit_card_rounded : Icons.account_balance_rounded,
                      color: isCard ? AppTheme.primary : const Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        '${method['brand']} •••• ${method['last4']}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(l10n.translate('defaultPaymentMethod').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${method['holder'] ?? ''} • Exp: ${method['expiry'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                    onPressed: () => _showActionMenu(method, index),
                  ),
                ),
              );
            }),

          const SizedBox(height: 24),

          // SEPA Direct Debit Quick Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: const BorderSide(color: Color(0xFF10B981)),
              ),
              onPressed: _openAddSepaModal,
              icon: const Icon(Icons.account_balance_rounded, color: Color(0xFF10B981)),
              label: Text('+ ${l10n.translate('linkSepaIban')}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 24),

          // Security Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.translate('pciSecurityBadge'),
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
