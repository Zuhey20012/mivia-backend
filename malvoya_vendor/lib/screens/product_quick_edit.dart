import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../config/theme.dart';
import '../core/agreements.dart';
import '../core/images.dart';

/// What the store chose in the quick-edit sheet.
sealed class QuickEditResult {}

/// Saved: [product] is the server's updated product (or null when the server sent none back).
class QuickEditSaved extends QuickEditResult {
  final Map<String, dynamic>? product;
  final Map<String, dynamic> sent;

  /// "Seller Terms accepted…" when the agreement sheet was shown on the way (API 2.11).
  final String? notice;
  QuickEditSaved(this.product, this.sent, {this.notice});
}

/// Open the full editor instead.
class QuickEditOpenEditor extends QuickEditResult {}

/// Remove the product (the dashboard removes it with an undo window).
class QuickEditRemove extends QuickEditResult {}

/// Price, stock and visibility without opening the full editor. Saving sends only these fields
/// (PATCH /products/:id is partial; options keep their sku and price adjustment).
Future<QuickEditResult?> showProductQuickEdit(BuildContext context, {required Map<String, dynamic> product, required ApiClient api}) =>
    showMSheet<QuickEditResult>(context, builder: (_) => _QuickEditSheet(product: product, api: api), isScrollControlled: true, useSafeArea: true);

class _QuickEditSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final ApiClient api;
  const _QuickEditSheet({required this.product, required this.api});

  @override
  State<_QuickEditSheet> createState() => _QuickEditSheetState();
}

class _QuickEditSheetState extends State<_QuickEditSheet> {
  static const _red = MPalette.red;
  Map<String, dynamic> get p => widget.product;

  late final _price = TextEditingController(
      text: p['salePriceCents'] is num ? ((p['salePriceCents'] as num) / 100).toStringAsFixed(2).replaceAll('.', ',') : '');
  late int _stock = asInt(p['stockQuantity']) ?? 0;
  late final List<Map<String, dynamic>> _variants =
      ((p['variants'] as List?) ?? const []).whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
  late bool _visible = p['isAvailable'] != false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  int? _priceCents() {
    final v = double.tryParse(_price.text.trim().replaceAll(',', '.').replaceAll('€', '').replaceAll(' ', ''));
    return v == null || v <= 0 ? null : (v * 100).round();
  }

  Future<void> _save() async {
    final cents = _priceCents();
    if (cents == null) {
      setState(() => _error = tr(context, 'Enter a price', 'Anna hinta'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'salePriceCents': cents,
      'isAvailable': _visible,
      if (_variants.isEmpty) 'stockQuantity': _stock,
      if (_variants.isNotEmpty)
        'variants': [
          for (final v in _variants)
            {
              if (v['id'] != null) 'id': asInt(v['id']),
              if ('${v['size'] ?? ''}'.isNotEmpty) 'size': v['size'],
              if ('${v['color'] ?? ''}'.isNotEmpty) 'color': v['color'],
              if ('${v['sku'] ?? ''}'.isNotEmpty) 'sku': v['sku'],
              if (v['priceAdjustCents'] is num) 'priceAdjustCents': asInt(v['priceAdjustCents']),
              'stock': asInt(v['stock']) ?? 0,
            }
        ],
    };
    // A visible product needs the Seller Terms in force (428 → agreement sheet → saved again)
    final res = await withAgreement(context, widget.api, () => widget.api.patch('/products/${p['id']}', body), announce: false);
    if (!mounted) return;
    if (!res.ok) {
      Haptics.warning();
      setState(() {
        _saving = false;
        _error = res.errorMessage;
      });
      return;
    }
    Haptics.success();
    final updated = res.data['product'] is Map ? Map<String, dynamic>.from(res.data['product']) : null;
    Navigator.pop(context, QuickEditSaved(updated, body, notice: res.notice));
  }

  Widget _stepper({required int value, required ValueChanged<int> onChanged, required String label}) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: tr(context, 'One less', 'Yksi vähemmän'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: value > 0 && !_saving
              ? () {
                  Haptics.selection();
                  onChanged(value - 1);
                }
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Semantics(
          label: '$label: $value',
          excludeSemantics: true,
          child: SizedBox(width: 44, child: Text('$value', textAlign: TextAlign.center, style: AppTheme.display(size: 20))),
        ),
        IconButton(
          tooltip: tr(context, 'One more', 'Yksi lisää'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: value < 10000 && !_saving
              ? () {
                  Haptics.selection();
                  onChanged(value + 1);
                }
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final images = ((p['images'] as List?) ?? const []).map((e) => '$e').toList();
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(MSpace.xl, 0, MSpace.xl, MSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 48,
              height: 58,
              child: images.isEmpty
                  ? Container(
                      decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.image_outlined, color: AppTheme.primary),
                    )
                  : NetImage(images.first, width: 48, height: 58, radius: 10),
            ),
            const SizedBox(width: MSpace.md),
            Expanded(child: Text('${p['name'] ?? ''}', style: AppTheme.display(size: 19), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: MSpace.lg),
          TextField(
            controller: _price,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr(context, 'Price (€, VAT included)', 'Hinta (€, sis. ALV)'), prefixIcon: const Icon(Icons.euro_rounded)),
          ),
          const SizedBox(height: 14),
          Text(tr(context, 'In stock', 'Varastossa'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: MTextSize.bodyL)),
          if (_variants.isEmpty)
            Row(children: [
              Expanded(child: Text(tr(context, 'Pieces', 'Kappaletta'), style: const TextStyle(color: AppTheme.textSecondary))),
              _stepper(value: _stock, label: tr(context, 'In stock', 'Varastossa'), onChanged: (v) => setState(() => _stock = v)),
            ])
          else
            for (final v in _variants)
              Row(children: [
                Expanded(
                  child: Text(
                    [
                      if ('${v['size'] ?? ''}'.isNotEmpty) '${v['size']}',
                      if ('${v['color'] ?? ''}'.isNotEmpty) '${v['color']}',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _stepper(
                  value: asInt(v['stock']) ?? 0,
                  label: '${v['size'] ?? v['color'] ?? ''}',
                  onChanged: (n) => setState(() => v['stock'] = n),
                ),
              ]),
          const SizedBox(height: MSpace.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _visible,
            onChanged: _saving ? null : (v) => setState(() => _visible = v),
            title: Text(tr(context, 'Visible to shoppers', 'Näkyy asiakkaille'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(context, 'Off = hidden, nothing is deleted', 'Pois = piilossa, mitään ei poisteta')),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MSpace.sm),
              child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: MSpace.sm),
          MButton(label: tr(context, 'Save', 'Tallenna'), loading: _saving, onPressed: _saving ? null : _save),
          const SizedBox(height: MSpace.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                onPressed: _saving ? null : () => Navigator.pop(context, QuickEditOpenEditor()),
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr(context, 'Full editor', 'Koko muokkaus')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red, width: 1.5), minimumSize: const Size(64, 52)),
                onPressed: _saving ? null : () => Navigator.pop(context, QuickEditRemove()),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(tr(context, 'Remove', 'Poista')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
