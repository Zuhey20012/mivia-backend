import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../l10n.dart';
import 'map_address_picker.dart';

class AddressManagementScreen extends StatefulWidget {
  const AddressManagementScreen({super.key});

  @override
  State<AddressManagementScreen> createState() => _AddressManagementScreenState();
}

class _AddressManagementScreenState extends State<AddressManagementScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('malvoya_addresses');
      if (raw != null) {
        final List decoded = jsonDecode(raw);
        _addresses = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        _addresses = [];
      }
    } catch (_) {
      _addresses = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('malvoya_addresses', jsonEncode(_addresses));
  }

  void _openAddressForm({Map<String, dynamic>? existingAddress, int? editIndex}) {
    final l10n = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: existingAddress?['title'] ?? l10n.translate('labelHome'));
    final streetCtrl = TextEditingController(text: existingAddress?['street'] ?? '');
    final aptCtrl = TextEditingController(text: existingAddress?['apt'] ?? '');
    final postalCtrl = TextEditingController(text: existingAddress?['postal'] ?? '');
    final cityCtrl = TextEditingController(text: existingAddress?['city'] ?? 'Helsinki');
    final buzzerCtrl = TextEditingController(text: existingAddress?['buzzer'] ?? '');
    String labelType = existingAddress?['labelType'] ?? 'Home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final modalBg = isDark ? const Color(0xFF140D26) : Colors.white;
        final textPrimary = isDark ? Colors.white : AppTheme.textPrimary;
        final textSecondary = isDark ? const Color(0xFFA09BAC) : AppTheme.textSecondary;
        final inputBg = isDark ? const Color(0xFF1D1438) : const Color(0xFFF8F7FF);
        final cardBorder = isDark ? const Color(0xFF2E204A) : const Color(0xFFE2E8F0);

        return StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
              color: modalBg,
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
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
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
                        child: Icon(editIndex != null ? Icons.edit_location_alt_rounded : Icons.add_location_alt_rounded, color: AppTheme.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(editIndex != null ? l10n.translate('editAddress') : l10n.translate('addNewAddress'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text(l10n.translate('verifiedCourierZone'), style: TextStyle(fontSize: 12, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Live OpenStreetMap Pinpoint Shortcut
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push<AddressResult>(
                        context,
                        MaterialPageRoute(builder: (_) => const MapAddressPickerScreen()),
                      );
                      if (result != null) {
                        setModalState(() {
                          streetCtrl.text = result.street.isNotEmpty ? (result.houseNumber.isNotEmpty ? '${result.street} ${result.houseNumber}' : result.street) : '';
                          cityCtrl.text = result.city;
                          postalCtrl.text = result.postalCode;
                        });
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.irisFuchsiaGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.translate('autoFillMapPin'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.translate('addressLabel'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                const SizedBox(height: 8),
                Row(
                  children: ['Home', 'Work', 'Other'].map((l) {
                    final labelMap = {'Home': l10n.translate('labelHome'), 'Work': l10n.translate('labelWork'), 'Other': l10n.translate('labelOther')};
                    final isSel = labelType == l;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(labelMap[l] ?? l),
                        selected: isSel,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(color: isSel ? Colors.white : textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                        onSelected: (val) {
                          if (val) {
                            setModalState(() {
                              labelType = l;
                              titleCtrl.text = l;
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text('${l10n.translate('streetAddress')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: streetCtrl,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: l10n.translate('streetAddress'),
                    hintStyle: TextStyle(color: textSecondary),
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
                          Text(l10n.translate('apartmentSuite'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: aptCtrl,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'A 4',
                              hintStyle: TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l10n.translate('postalCode')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: postalCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '00100',
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l10n.translate('city')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: cityCtrl,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Helsinki',
                              hintStyle: TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('doorBuzzerCode'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: buzzerCtrl,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: l10n.translate('doorBuzzerHint'),
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
                      if (streetCtrl.text.trim().isEmpty || postalCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.translate('enterStreetPostal'))),
                        );
                        return;
                      }
                      HapticFeedback.mediumImpact();
                      final aptPart = aptCtrl.text.isNotEmpty ? ' ' + aptCtrl.text.trim() : '';
                      final fullText = '${streetCtrl.text.trim()}$aptPart, ${postalCtrl.text.trim()} ${cityCtrl.text.trim()}';
                      final updated = {
                        'id': existingAddress?['id'] ?? 'addr_${DateTime.now().millisecondsSinceEpoch}',
                        'title': titleCtrl.text.trim(),
                        'labelType': labelType,
                        'street': streetCtrl.text.trim(),
                        'apt': aptCtrl.text.trim(),
                        'postal': postalCtrl.text.trim(),
                        'city': cityCtrl.text.trim(),
                        'buzzer': buzzerCtrl.text.trim(),
                        'subtitle': fullText,
                        'isDefault': existingAddress?['isDefault'] ?? (_addresses.isEmpty),
                      };

                      setState(() {
                        if (editIndex != null) {
                          _addresses[editIndex] = updated;
                        } else {
                          _addresses.insert(0, updated);
                        }
                      });
                      await _persistAddresses();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(editIndex != null ? l10n.translate('addressUpdated') : l10n.translate('newAddressSaved')),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Text(editIndex != null ? l10n.translate('saveChanges') : l10n.translate('saveAddress'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final cardBg = isDark ? const Color(0xFF140D26) : Colors.white;
    final textPrimary = isDark ? Colors.white : AppTheme.textPrimary;
    final textSecondary = isDark ? const Color(0xFFA09BAC) : AppTheme.textSecondary;
    final borderColor = isDark ? const Color(0xFF2E204A) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.translate('deliveryAddresses'), style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
        backgroundColor: cardBg,
        foregroundColor: textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded, color: AppTheme.primary),
            tooltip: l10n.translate('addDeliveryAddress'),
            onPressed: () => _openAddressForm(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _addresses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_off_rounded, color: AppTheme.primary, size: 40),
                        ),
                        const SizedBox(height: 18),
                        Text(l10n.translate('noSavedAddresses'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textPrimary)),
                        const SizedBox(height: 8),
                        Text(
                          l10n.translate('noSavedAddressesSub'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: textSecondary),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            elevation: 0,
                          ),
                          onPressed: () => _openAddressForm(),
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          label: Text(l10n.translate('addDeliveryAddress'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, index) {
                    final addr = _addresses[index];
                    final isDefault = addr['isDefault'] == true;
                    final label = addr['labelType'] ?? 'Home';
                    IconData labelIcon = Icons.home_rounded;
                    if (label == 'Work') labelIcon = Icons.business_rounded;
                    if (label == 'Other') labelIcon = Icons.location_on_rounded;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDefault ? AppTheme.primary : borderColor, width: isDefault ? 1.5 : 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(labelIcon, color: AppTheme.primary, size: 22),
                        ),
                        title: Row(
                          children: [
                            Text(addr['title'] ?? 'Address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
                            if (isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(l10n.translate('defaultAddress').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(addr['subtitle'] ?? '', style: TextStyle(fontSize: 12, color: textSecondary)),
                              if (addr['buzzer'] != null && addr['buzzer'].toString().isNotEmpty)
                                Text('${l10n.translate('doorCodePrefix')}: ${addr['buzzer']}', style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        // Three Dots Menu for actions
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (action) async {
                            if (action == 'edit') {
                              _openAddressForm(existingAddress: addr, editIndex: index);
                            } else if (action == 'default') {
                              setState(() {
                                for (var a in _addresses) {
                                  a['isDefault'] = false;
                                }
                                addr['isDefault'] = true;
                              });
                              await _persistAddresses();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${addr['title']}: ${l10n.translate('defaultPaymentSet')}')),
                              );
                            } else if (action == 'delete') {
                              setState(() {
                                _addresses.removeAt(index);
                              });
                              await _persistAddresses();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.translate('addressRemoved'))),
                              );
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('editAddress'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'default',
                              child: Row(
                                children: [
                                  const Icon(Icons.star_outline_rounded, size: 18, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('setAsDefault'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('deleteAddress'), style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
