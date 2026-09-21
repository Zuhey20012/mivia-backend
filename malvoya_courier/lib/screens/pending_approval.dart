import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'courier_dashboard.dart';

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
        _contractSigned = prefs.getBool('courier_contract_signed') ?? false;
        _signedDate = prefs.getString('courier_contract_date');
        _savedIban = prefs.getString('courier_iban');
      });
      if (!_contractSigned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_contractSigned) _showContractSigningModal(context);
        });
      }
    }
  }

  void _showContractSigningModal(BuildContext context) {
    final legalNameCtrl = TextEditingController();
    final idNumberCtrl = TextEditingController();
    final ibanCtrl = TextEditingController();
    String vehicleType = 'Bicycle';
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
                  Text('Courier Partner Agreement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                        '''MALVOYA COURIER FRAMEWORK AGREEMENT (FINLAND / EU)

1. Independent Delivery Partner: You operate as an independent courier partner delivering retail and boutique goods.
2. Payout Structure: Guaranteed base payout of €3.00 per local delivery trip + distance bonuses + 100% of customer tips (negotiable based on fleet agreements).
3. Automated Bank Transfers: Payouts are transferred automatically every week directly to your European IBAN bank account.
4. Road & Package Safety: You agree to uphold Finnish road safety laws and deliver packages securely without damage.
5. Legal Binding: Electronic signatures submitted via this form are legally recognized under EU eIDAS regulation.''',
                        style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF333333)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text('Partner & Payout Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    TextField(
                      controller: legalNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full Legal Name (as on ID / Passport)', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: idNumberCtrl,
                      decoration: const InputDecoration(labelText: 'Personal ID (Henkilötunnus) / Passport No.', prefixIcon: Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: ibanCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Payout Bank Account (IBAN: FIXX XXXX...)', prefixIcon: Icon(Icons.account_balance_outlined)),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: vehicleType,
                      decoration: const InputDecoration(labelText: 'Delivery Vehicle', prefixIcon: Icon(Icons.delivery_dining_outlined)),
                      items: const [
                        DropdownMenuItem(value: 'Bicycle', child: Text('🚲 Bicycle / E-Bike')),
                        DropdownMenuItem(value: 'Scooter', child: Text('🛵 Electric Scooter / Moped')),
                        DropdownMenuItem(value: 'Car', child: Text('🚗 Car / Van')),
                      ],
                      onChanged: (v) => setModalState(() => vehicleType = v ?? 'Bicycle'),
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
                          child: Text('I have read, accept, and digitally sign the Malvoya Courier Partner Agreement.', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: (!agreed || legalNameCtrl.text.isEmpty || ibanCtrl.text.isEmpty || idNumberCtrl.text.isEmpty)
                          ? null
                          : () async {
                              final prefs = await SharedPreferences.getInstance();
                              final now = DateTime.now().toString().substring(0, 16);
                              await prefs.setBool('courier_contract_signed', true);
                              await prefs.setString('courier_contract_date', now);
                              await prefs.setString('courier_iban', ibanCtrl.text.trim());
                              await prefs.setString('courier_vehicle', vehicleType);

                              setState(() {
                                _contractSigned = true;
                                _signedDate = now;
                                _savedIban = ibanCtrl.text.trim();
                              });

                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Courier Agreement digitally signed & submitted!'),
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
    final l10n = AppLocalizations.of(context);
    final isFi = l10n.locale.languageCode == 'fi';
    final name = auth.currentUser?.name?.split(' ').first ?? 'Courier';

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
                  gradient: const LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.delivery_dining_rounded, size: 52, color: Color(0xFFE65100)),
              ),
              const SizedBox(height: 24),
              Text('Welcome, $name! 🚴', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Your delivery courier profile is undergoing verification.', style: TextStyle(fontSize: 15, color: AppTheme.textSecondary), textAlign: TextAlign.center),
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
                            _contractSigned ? l10n.translate('contractSigned') : (l10n.locale.languageCode == 'fi' ? 'Toimenpide vaaditaan: Allekirjoita sopimus' : 'Action Required: Sign Agreement'),
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
                        ? (l10n.locale.languageCode == 'fi'
                            ? 'Sopimus allekirjoitettu: $_signedDate\nPankkitili: ${_savedIban ?? 'IBAN tallennettu'}\nKuriirihubi avautuu välittömästi.'
                            : 'Signed on $_signedDate\nPayout Account: ${_savedIban ?? 'IBAN on file'}\nYour delivery hub unlocks as soon as compliance clears.')
                        : (l10n.locale.languageCode == 'fi'
                            ? 'Allekirjoita digitaalinen kuriirisopimus & syötä pankkitilisi (IBAN), jotta viikoittaiset toimitusansiosi (€3.00+/keikka + tipit) siirretään suoraan tilillesi.'
                            : 'Sign your digital partner terms & enter your bank account (IBAN) so your weekly delivery earnings (€3.00+/trip + tips) deposit directly into your bank.'),
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
                        label: Text(_contractSigned ? (isFi ? 'Tarkastele / Päivitä IBAN' : 'Review / Update Agreement & IBAN') : l10n.translate('contractSign')),
                      ),
                    ),
                    if (_contractSigned) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE65100), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CourierDashboard()));
                          },
                          icon: const Icon(Icons.delivery_dining_rounded, color: Color(0xFFE65100), size: 20),
                          label: Text(
                            isFi ? 'Avaa kuriirihubi ja toimitukset' : 'Open Courier Hub & Deliveries',
                            style: const TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Registered email card
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
