import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import 'vendor_dashboard.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _contractSigned = false;
  String? _signedDate;
  String? _savedIban;

  @override
  void initState() {
    super.initState();
    _loadContractStatus();
  }

  Future<void> _loadContractStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _contractSigned = prefs.getBool('vendor_contract_signed') ?? false;
        _signedDate = prefs.getString('vendor_contract_date');
        _savedIban = prefs.getString('vendor_iban');
      });
      if (!_contractSigned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_contractSigned) _showContractSigningModal(context);
        });
      }
    }
  }

  void _showContractSigningModal(BuildContext context) {
    final businessCtrl = TextEditingController();
    final yTunnusCtrl = TextEditingController();
    final ibanCtrl = TextEditingController();
    final signatoryCtrl = TextEditingController();
    bool agreed = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24, right: 24, top: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.history_edu_rounded, color: AppTheme.primary, size: 28),
                  SizedBox(width: 10),
                  Text('Merchant Partner Agreement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFF8F8FC), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                      child: const Text(
                        '''MALVOYA MERCHANT SERVICE AGREEMENT (FINLAND / EU)

1. Scope: Malvoya provides digital marketplace listing, on-demand courier dispatch, and secure card payment processing via Stripe.
2. Commission: Competitive 5%–10% platform commission on completed customer orders (customizable per merchant volume).
3. Automated Bank Payouts: Weekly direct bank transfers to your designated European IBAN account every Monday.
4. Merchant Standards: You agree to provide authentic products, uphold Finnish Consumer Protection (14-day statutory returns), and prepare orders within estimated preparation time.
5. Digital Signature: Electronic signatures submitted via this form are legally binding under EU eIDAS regulation.''',
                        style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF333333)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text('Official Business Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    TextField(
                      controller: businessCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Registered Company / Store Name', prefixIcon: Icon(Icons.business_outlined)),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: yTunnusCtrl,
                      decoration: const InputDecoration(labelText: 'Business ID (Y-tunnus) / VAT No.', prefixIcon: Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: ibanCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Payout Bank Account (IBAN: FIXX XXXX...)', prefixIcon: Icon(Icons.account_balance_outlined)),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: signatoryCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Authorized Signatory Full Name', prefixIcon: Icon(Icons.draw_outlined)),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Checkbox(
                          value: agreed,
                          activeColor: AppTheme.primary,
                          onChanged: (v) => setModalState(() => agreed = v ?? false),
                        ),
                        const Expanded(
                          child: Text('I have read, agree to, and digitally sign the Malvoya Merchant Partner Agreement.', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: (!agreed || businessCtrl.text.isEmpty || ibanCtrl.text.isEmpty || signatoryCtrl.text.isEmpty)
                          ? null
                          : () async {
                              final prefs = await SharedPreferences.getInstance();
                              final now = DateTime.now().toString().substring(0, 16);
                              await prefs.setBool('vendor_contract_signed', true);
                              await prefs.setString('vendor_contract_date', now);
                              await prefs.setString('vendor_iban', ibanCtrl.text.trim());
                              await prefs.setString('vendor_business_name', businessCtrl.text.trim());

                              setState(() {
                                _contractSigned = true;
                                _signedDate = now;
                                _savedIban = ibanCtrl.text.trim();
                              });

                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Merchant Agreement digitally signed & submitted!'),
                                  backgroundColor: Color(0xFF16A34A),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                        child: const Text('Sign & Submit Agreement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final name = auth.currentUser?.name?.split(' ').first ?? 'Vendor';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.storefront_outlined, size: 52, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 24),
              Text('Welcome, $name! 🏪', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Your store registration is undergoing verification.', style: TextStyle(fontSize: 15, color: AppTheme.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 28),

              // Contract Signing Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _contractSigned ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _contractSigned ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _contractSigned ? Icons.verified_rounded : Icons.pending_actions_rounded,
                          color: _contractSigned ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _contractSigned ? 'Partner Agreement Signed ✅' : 'Action Required: Sign Agreement',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: _contractSigned ? const Color(0xFF15803D) : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _contractSigned
                        ? 'Signed on $_signedDate\nPayout Account: ${_savedIban ?? 'IBAN on file'}\nYour store will be approved and go live shortly.'
                        : 'Sign your digital partner terms & submit your bank account (IBAN) so payments can enter your bank automatically every Monday.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _contractSigned ? const Color(0xFF166534) : const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _contractSigned ? const Color(0xFF16A34A) : AppTheme.primary,
                        ),
                        onPressed: () => _showContractSigningModal(context),
                        icon: Icon(_contractSigned ? Icons.edit_note_rounded : Icons.history_edu_rounded, size: 20),
                        label: Text(_contractSigned ? 'Review / Update Contract & Bank Details' : 'Sign Partner Agreement Now'),
                      ),
                    ),
                    if (_contractSigned) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VendorDashboard()));
                          },
                          icon: const Icon(Icons.storefront_rounded, color: Color(0xFF2E7D32), size: 20),
                          label: const Text(
                            'Open Store Dashboard & Add Products',
                            style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Email Notification Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF4F4F8), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline_rounded, color: AppTheme.textSecondary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Registered Email', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          Text(auth.currentUser?.email ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              TextButton.icon(
                onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
