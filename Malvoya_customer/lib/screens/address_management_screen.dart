import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/delivery_location.dart';
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
      final raw = prefs.getString(DeliveryLocation.savedAddressesKey);
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
    await prefs.setString(DeliveryLocation.savedAddressesKey, jsonEncode(_addresses));
  }

  /// Whether this saved address is the one deliveries currently go to.
  bool _isActive(Map<String, dynamic> addr) {
    final active = DeliveryLocation.instance.address?.trim();
    return active != null && active.isNotEmpty && active == '${addr['subtitle'] ?? ''}'.trim();
  }

  /// Delivers to this address from now on (home, store list, checkout).
  Future<void> _useAddress(Map<String, dynamic> addr) async {
    Haptics.selection();
    await DeliveryLocation.instance.use(addr);
    if (!mounted) return;
    setState(() {});
    MSnack.show(context, tr(context, 'Delivering to ${addr['subtitle'] ?? ''}', 'Toimitus osoitteeseen ${addr['subtitle'] ?? ''}'));
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
    // Coordinates when the address was filled in from the map (exact fee and drop-off point)
    double? pinLat = (existingAddress?['lat'] as num?)?.toDouble();
    double? pinLng = (existingAddress?['lng'] as num?)?.toDouble();

    showMSheet(context, builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final modalBg = isDark ? MPalette.nightSurface : MPalette.white;
        final textPrimary = isDark ? MPalette.white : AppTheme.textPrimary;
        final textSecondary = isDark ? MPalette.nightLineStrong : AppTheme.textSecondary;
        final inputBg = isDark ? MPalette.nightSurfaceVariant : MPalette.birch;
        final cardBorder = isDark ? MPalette.nightRaised : MPalette.line;

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
                  const MSheetHandle(),
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
                      const SizedBox(width: MSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(editIndex != null ? l10n.translate('editAddress') : l10n.translate('addNewAddress'), style: TextStyle(fontSize: MTextSize.title, fontWeight: FontWeight.w800, color: textPrimary)),
                            Text(l10n.translate('verifiedCourierZone'), style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
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
                          pinLat = result.latitude;
                          pinLng = result.longitude;
                        });
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MSpace.md),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        boxShadow: [
                          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_rounded, color: AppTheme.onBrand, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.translate('autoFillMapPin'),
                              style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.w700, fontSize: MTextSize.label),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.onBrand, size: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.translate('addressLabel'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label, color: textPrimary)),
                const SizedBox(height: MSpace.sm),
                Row(
                  children: ['Home', 'Work', 'Other'].map((l) {
                    final labelMap = {'Home': l10n.translate('labelHome'), 'Work': l10n.translate('labelWork'), 'Other': l10n.translate('labelOther')};
                    final isSel = labelType == l;
                    return Padding(
                      padding: const EdgeInsets.only(right: MSpace.sm),
                      child: ChoiceChip(
                        label: Text(labelMap[l] ?? l),
                        selected: isSel,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(color: isSel ? AppTheme.onBrand : textPrimary, fontWeight: FontWeight.bold, fontSize: MTextSize.caption),
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
                Text('${l10n.translate('streetAddress')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                const SizedBox(height: 6),
                TextField(
                  controller: streetCtrl,
                  style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyM),
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
                          Text(l10n.translate('apartmentSuite'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: aptCtrl,
                            style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyM),
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
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l10n.translate('postalCode')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: postalCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyM),
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
                          Text('${l10n.translate('city')} *', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: cityCtrl,
                            style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyM),
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
                    const SizedBox(width: MSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('doorBuzzerCode'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.label)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: buzzerCtrl,
                            style: TextStyle(color: textPrimary, fontSize: MTextSize.bodyM),
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
                const SizedBox(height: MSpace.xxl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.md)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (streetCtrl.text.trim().isEmpty || postalCtrl.text.trim().isEmpty) {
                        MSnack.show(context, l10n.translate('enterStreetPostal'));
                        return;
                      }
                      Haptics.medium();
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
                        if (pinLat != null && pinLng != null) ...{'lat': pinLat, 'lng': pinLng},
                        'isDefault': existingAddress?['isDefault'] ?? (_addresses.isEmpty),
                      };
                      // Editing the address in use updates what deliveries go to
                      final wasActive = existingAddress != null && _isActive(existingAddress);

                      setState(() {
                        if (editIndex != null) {
                          _addresses[editIndex] = updated;
                        } else {
                          _addresses.insert(0, updated);
                        }
                      });
                      await _persistAddresses();
                      if (wasActive || _addresses.length == 1) await DeliveryLocation.instance.use(updated);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(editIndex != null ? l10n.translate('addressUpdated') : l10n.translate('newAddressSaved')),
                            backgroundColor: MPalette.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Text(editIndex != null ? l10n.translate('saveChanges') : l10n.translate('saveAddress'), style: const TextStyle(color: AppTheme.onBrand, fontSize: MTextSize.bodyL, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }, transparent: true, isScrollControlled: true, useSafeArea: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final cardBg = isDark ? MPalette.nightSurface : MPalette.white;
    final textPrimary = isDark ? MPalette.white : AppTheme.textPrimary;
    final textSecondary = isDark ? MPalette.nightLineStrong : AppTheme.textSecondary;
    final borderColor = isDark ? MPalette.nightRaised : MPalette.line;

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
                    padding: const EdgeInsets.symmetric(horizontal: MSpace.x3l),
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
                        Text(l10n.translate('noSavedAddresses'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.title, color: textPrimary)),
                        const SizedBox(height: MSpace.sm),
                        Text(
                          l10n.translate('noSavedAddressesSub'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: MTextSize.label, color: textSecondary),
                        ),
                        const SizedBox(height: MSpace.xl),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.md)),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: MSpace.md),
                            elevation: 0,
                          ),
                          onPressed: () => _openAddressForm(),
                          icon: const Icon(Icons.add_rounded, color: AppTheme.onBrand),
                          label: Text(l10n.translate('addDeliveryAddress'), style: const TextStyle(color: AppTheme.onBrand, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: MSpace.md),
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, index) {
                    final addr = _addresses[index];
                    final isDefault = addr['isDefault'] == true;
                    final inUse = _isActive(addr);
                    final label = addr['labelType'] ?? 'Home';
                    IconData labelIcon = Icons.home_rounded;
                    if (label == 'Work') labelIcon = Icons.business_rounded;
                    if (label == 'Other') labelIcon = Icons.location_on_rounded;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: MSpace.lg, vertical: 6),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDefault ? AppTheme.primary : borderColor, width: isDefault ? 1.5 : 1),
                        boxShadow: [
                          BoxShadow(color: MPalette.night.withValues(alpha: isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: ListTile(
                        onTap: () => _useAddress(addr),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: MSpace.sm),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(labelIcon, color: AppTheme.primary, size: 22),
                        ),
                        title: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 0,
                          runSpacing: 4,
                          children: [
                            Text('${addr['title'] ?? tr(context, 'Address', 'Osoite')}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: MTextSize.bodyL, color: textPrimary)),
                            if (isDefault) ...[
                              const SizedBox(width: MSpace.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(MRadius.xs),
                                ),
                                child: Text(l10n.translate('defaultAddress').toUpperCase(), style: const TextStyle(color: AppTheme.onBrand, fontSize: MTextSize.caption, fontWeight: FontWeight.w900)),
                              ),
                            ],
                            if (inUse) ...[
                              const SizedBox(width: MSpace.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: MSpace.sm, vertical: 2),
                                decoration: BoxDecoration(color: AppTheme.sunshine, borderRadius: BorderRadius.circular(MRadius.xs)),
                                child: Text(tr(context, 'IN USE', 'KÄYTÖSSÄ'), style: const TextStyle(color: AppTheme.ink, fontSize: MTextSize.caption, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: MSpace.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(addr['subtitle'] ?? '', style: TextStyle(fontSize: MTextSize.caption, color: textSecondary)),
                              if (addr['buzzer'] != null && addr['buzzer'].toString().isNotEmpty)
                                Text('${l10n.translate('doorCodePrefix')}: ${addr['buzzer']}', style: const TextStyle(fontSize: MTextSize.caption, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        // Three Dots Menu for actions
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, color: AppTheme.secondaryText(context)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MRadius.md)),
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
                              // Saved on this phone; the default is used whenever the app starts
                              await _persistAddresses();
                              await DeliveryLocation.instance.use(addr);
                              if (!context.mounted) return;
                              MSnack.show(context, '${addr['title']}: ${l10n.translate('defaultPaymentSet')}');
                            } else if (action == 'delete') {
                              setState(() {
                                _addresses.removeAt(index);
                              });
                              await _persistAddresses();
                              if (!context.mounted) return;
                              MSnack.show(context, l10n.translate('addressRemoved'));
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('editAddress'), style: const TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'default',
                              child: Row(
                                children: [
                                  const Icon(Icons.star_outline_rounded, size: 18, color: MPalette.amber),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('setAsDefault'), style: const TextStyle(fontSize: MTextSize.label, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline_rounded, size: 18, color: MPalette.red),
                                  const SizedBox(width: 10),
                                  Text(l10n.translate('deleteAddress'), style: const TextStyle(fontSize: MTextSize.label, color: MPalette.red, fontWeight: FontWeight.w600)),
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
