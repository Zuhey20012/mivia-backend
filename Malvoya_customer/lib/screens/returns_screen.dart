import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';
import '../local_notification_service.dart';
import '../ui/returns/return_condition_scanner.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReturns();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReturns() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('malvoya_returns');
      if (raw != null) {
        final List decoded = jsonDecode(raw);
        _returns = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        _returns = [];
      }
    } catch (_) {
      _returns = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistReturns() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('malvoya_returns', jsonEncode(_returns));
  }

  String _formatDispatchMethod(String method, AppLocalizations l10n) {
    if (method.trim().isEmpty) return l10n.locale.languageCode == 'fi' ? 'Putiikin palautusohje' : 'Standard return';
    return method;
  }

  String _formatRefundDestination(String dest, AppLocalizations l10n) {
    if (dest.contains('IBAN') || dest.contains('Bank') || dest.contains('SEPA') || dest.contains('tilisiirto')) {
      return l10n.translate('directSepaIban');
    }
    return l10n.translate('origPaymentCard');
  }

  String _formatReason(String reason, AppLocalizations l10n) {
    final r = reason.toLowerCase();
    if (r.contains('mind') || r.contains('mieli') || r.contains('muuttun')) {
      return l10n.translate('reasonChangedMind');
    }
    if (r.contains('size') || r.contains('koko') || r.contains('fit')) {
      return l10n.translate('reasonSizeMismatch');
    }
    if (r.contains('defective') || r.contains('viallinen') || r.contains('damag')) {
      return l10n.translate('reasonDefective');
    }
    if (r.contains('different') || r.contains('eroaa') || r.contains('kuvaukse')) {
      return l10n.translate('reasonNotAsDescribed');
    }
    return reason;
  }

  void _openStartReturnWizard() {
    final l10n = AppLocalizations.of(context);
    final orderIdCtrl = TextEditingController();
    final itemCtrl = TextEditingController();
    final ibanCtrl = TextEditingController();
    String reasonKey = 'reasonChangedMind';
    final dispatchMethodCtrl = TextEditingController();
    String refundDestination = 'Original Payment Card';

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
                      child: const Icon(Icons.assignment_return_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('euStatutoryReturn'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                          Text(l10n.translate('statutoryProtection14d'), style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(l10n.translate('itemNameDesc'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: itemCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.translate('itemHintLinen'),
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('orderRefOptional'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: orderIdCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.translate('orderRefHint'),
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('reasonForReturn'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: reasonKey,
                  dropdownColor: cardBg,
                  style: TextStyle(color: textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  items: [
                    DropdownMenuItem(value: 'reasonChangedMind', child: Text(l10n.translate('reasonChangedMind'), style: TextStyle(fontSize: 13, color: textPrimary))),
                    DropdownMenuItem(value: 'reasonSizeMismatch', child: Text(l10n.translate('reasonSizeMismatch'), style: TextStyle(fontSize: 13, color: textPrimary))),
                    DropdownMenuItem(value: 'reasonDefective', child: Text(l10n.translate('reasonDefective'), style: TextStyle(fontSize: 13, color: textPrimary))),
                    DropdownMenuItem(value: 'reasonNotAsDescribed', child: Text(l10n.translate('reasonNotAsDescribed'), style: TextStyle(fontSize: 13, color: textPrimary))),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => reasonKey = val);
                  },
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('returnDispatchMethod'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                TextField(
                  controller: dispatchMethodCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.locale.languageCode == 'fi' ? 'Toimitustapa / noutotoive (valinnainen)' : 'Dispatch method or return instructions (optional)',
                    hintStyle: TextStyle(color: textSecondary),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('refundDestination'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: refundDestination,
                  dropdownColor: cardBg,
                  style: TextStyle(color: textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  items: [
                    DropdownMenuItem(value: 'Original Payment Card', child: Text(l10n.translate('origPaymentCard'), style: TextStyle(fontSize: 13, color: textPrimary))),
                    DropdownMenuItem(value: 'European SEPA Bank Account (IBAN)', child: Text(l10n.translate('directSepaIban'), style: TextStyle(fontSize: 13, color: textPrimary))),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => refundDestination = val);
                  },
                ),
                if (refundDestination.contains('IBAN')) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: ibanCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'FI21 1234 5678 9012 34',
                      labelText: l10n.translate('directSepaIban'),
                      labelStyle: TextStyle(color: textSecondary),
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // AI Defect Scan Option
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      l10n.locale.languageCode == 'fi'
                          ? '📸 Käynnistä tekoälyskannaus ja palautus'
                          : '📸 Launch AI Garment Scanner & Return',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReturnConditionScanner(
                            orderId: orderIdCtrl.text.trim().isEmpty ? 'ORD-LIVE' : orderIdCtrl.text.trim(),
                            itemName: itemCtrl.text.trim().isEmpty ? (l10n.locale.languageCode == 'fi' ? 'Putiikkituote' : 'Boutique Apparel') : itemCtrl.text.trim(),
                          ),
                        ),
                      );
                      if (result != null) {
                        final retId = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                        final now = DateTime.now();
                        final dateStr = '${now.day}.${now.month}.${now.year}';
                        final newReturn = {
                          'id': retId,
                          'item': itemCtrl.text.trim().isEmpty ? (l10n.locale.languageCode == 'fi' ? 'Putiikkituote (AI-varmistettu)' : 'Boutique Piece (AI-Verified)') : itemCtrl.text.trim(),
                          'orderId': orderIdCtrl.text.trim().isEmpty ? '#MLV-${now.millisecondsSinceEpoch.toString().substring(8)}' : orderIdCtrl.text.trim(),
                          'reason': 'reasonChangedMind',
                          'dispatchMethod': 'Noutokuriiri (Riidaton)',
                          'refundDestination': refundDestination,
                          'iban': ibanCtrl.text.trim(),
                          'date': dateStr,
                          'statusStage': 1,
                          'statusLabel': l10n.translate('stageRequested'),
                          'aiInspected': true,
                          'tamperRibbonIntact': true,
                          'courierDirective': 'ACCEPT_PACKAGE_DO_NOT_ARGUE',
                        };
                        setState(() {
                          _returns.insert(0, newReturn);
                        });
                        await _persistReturns();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              content: Text(
                                l10n.locale.languageCode == 'fi'
                                    ? '✅ AI-tarkastus hyväksytty: Kuriirin nouto tilattu riidattomasti!'
                                    : '✅ AI Verified: Zero-conflict courier pickup requested!',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),

                const SizedBox(height: 12),

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
                      if (itemCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('itemNameDesc'))),
                        );
                        return;
                      }
                      HapticFeedback.mediumImpact();
                      final retId = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                      final now = DateTime.now();
                      final dateStr = '${now.day}.${now.month}.${now.year}';
                      final orderRef = orderIdCtrl.text.trim().isEmpty ? '#MLV-${now.millisecondsSinceEpoch.toString().substring(8)}' : orderIdCtrl.text.trim();

                      final newReturn = {
                        'id': retId,
                        'item': itemCtrl.text.trim(),
                        'orderId': orderRef,
                        'reason': reasonKey,
                        'dispatchMethod': dispatchMethodCtrl.text.trim(),
                        'refundDestination': refundDestination,
                        'iban': ibanCtrl.text.trim(),
                        'date': dateStr,
                        'statusStage': 1,
                        'statusLabel': l10n.translate('stageRequested'),
                      };
                      setState(() {
                        _returns.insert(0, newReturn);
                      });
                      await _persistReturns();

                      await LocalNotificationService.showNotification(
                        id: 201,
                        title: l10n.translate('returnSubmittedTitle').replaceAll('{id}', retId),
                        body: l10n.translate('returnSubmittedBody').replaceAll('{item}', itemCtrl.text.trim()).replaceAll('{method}', _formatDispatchMethod(dispatchMethodCtrl.text.trim(), l10n)),
                        payload: 'return_$retId',
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(child: Text(l10n.translate('returnSubmittedToast').replaceAll('{id}', retId))),
                              ],
                            ),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Text(l10n.translate('submitReturnBtn'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_return_outlined, color: AppTheme.primary, size: 44),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.translate('noReturnsRequested'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('noReturnsRequestedSub'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _openStartReturnWizard,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(l10n.translate('startReturnBtn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageStep(int stepIndex, int currentStage, String label, IconData icon, Color textPrimary, Color textSecondary) {
    final isDone = currentStage >= stepIndex;
    final isCurrent = currentStage == stepIndex;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDone ? AppTheme.primary : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2E204A) : Colors.grey.shade200),
              shape: BoxShape.circle,
              border: isCurrent ? Border.all(color: AppTheme.accent, width: 2.5) : null,
            ),
            child: Icon(isDone ? Icons.check : icon, color: isDone ? Colors.white : Colors.grey, size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isDone ? FontWeight.bold : FontWeight.w500,
              color: isDone ? textPrimary : textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnCard(AppLocalizations l10n, Map<String, dynamic> ret, Color cardBg, Color textPrimary, Color textSecondary, Color borderColor, Color inputBg) {
    final int stage = (ret['statusStage'] ?? 1) as int;
    final id = ret['id'] ?? 'RET-000';
    final date = ret['date'] ?? '';
    final item = ret['item'] ?? 'Artisan Item';
    final orderId = ret['orderId'] ?? '#MLV-000';
    final reason = ret['reason'] ?? 'reasonChangedMind';
    final dispatchMethod = ret['dispatchMethod'] ?? 'Courier Doorstep Pickup';
    final refundDestination = ret['refundDestination'] ?? 'Original Payment Card';

    final localizedMethod = _formatDispatchMethod(dispatchMethod, l10n);
    final localizedDest = _formatRefundDestination(refundDestination, l10n);
    final localizedReason = _formatReason(reason, l10n);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  id,
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              Text(
                date,
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.translate("orderNum")}: $orderId • $localizedReason',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 16),
          // 4-Stage Stepper
          Row(
            children: [
              _buildStageStep(1, stage, l10n.translate('stageRequested'), Icons.edit_document, textPrimary, textSecondary),
              Container(width: 14, height: 2, color: stage >= 2 ? AppTheme.primary : borderColor),
              _buildStageStep(2, stage, l10n.translate('stageApproved'), Icons.verified_outlined, textPrimary, textSecondary),
              Container(width: 14, height: 2, color: stage >= 3 ? AppTheme.primary : borderColor),
              _buildStageStep(3, stage, l10n.translate('stagePickup'), Icons.local_shipping_outlined, textPrimary, textSecondary),
              Container(width: 14, height: 2, color: stage >= 4 ? AppTheme.primary : borderColor),
              _buildStageStep(4, stage, l10n.translate('stageRefunded'), Icons.account_balance_wallet_outlined, textPrimary, textSecondary),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  dispatchMethod.contains('Posti') ? Icons.local_post_office_outlined : Icons.delivery_dining_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$localizedMethod → $localizedDest',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        final borderColor = AppTheme.cardBorder(context);
        final inputBg = AppTheme.inputBackground(context);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(l10n.translate('returnsAndExchanges'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
            backgroundColor: cardBg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary),
                tooltip: l10n.translate('startReturnBtn'),
                onPressed: _openStartReturnWizard,
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _returns.isEmpty
                  ? _buildEmptyState(l10n, textPrimary, textSecondary)
                  : RefreshIndicator(
                      onRefresh: _loadReturns,
                      color: AppTheme.primary,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _returns.length,
                        itemBuilder: (_, i) => _buildReturnCard(l10n, _returns[i], cardBg, textPrimary, textSecondary, borderColor, inputBg),
                      ),
                    ),
        );
      },
    );
  }
}
