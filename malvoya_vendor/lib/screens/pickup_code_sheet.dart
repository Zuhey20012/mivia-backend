import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import '../auth_service.dart';
import '../config/theme.dart';

/// "Customer is here": the store types the 6-digit pickup code the customer shows in their app.
/// The store never sees the code; the server checks it. Returns the updated order on success
/// (an empty map if the server did not send one), or null when the sheet is closed.
Future<Map<String, dynamic>?> showPickupCodeSheet(BuildContext context, Map<String, dynamic> order) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickupCodeSheet(order: order),
    );

class _PickupCodeSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  const _PickupCodeSheet({required this.order});

  @override
  State<_PickupCodeSheet> createState() => _PickupCodeSheetState();
}

class _PickupCodeSheetState extends State<_PickupCodeSheet> {
  static const _length = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  bool _checking = false;
  bool _locked = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final code = _code.text;
    if (code.length != _length || _checking || _locked) return;
    HapticFeedback.selectionClick();
    setState(() {
      _checking = true;
      _error = null;
    });
    final res = await ApiClient(Provider.of<AuthService>(context, listen: false)).post('/orders/${widget.order['id']}/collect', {'code': code});
    if (!mounted) return;

    if (res.ok && res.data['ok'] != false) {
      HapticFeedback.mediumImpact();
      final updated = res.data['order'];
      Navigator.pop(context, updated is Map ? Map<String, dynamic>.from(updated) : <String, dynamic>{});
      return;
    }

    HapticFeedback.heavyImpact();
    final attemptsLeft = asInt(res.data['attemptsLeft']);
    final lockedUntil = DateTime.tryParse('${res.data['lockedUntil'] ?? ''}')?.toLocal();
    final locked = attemptsLeft == 0 || res.data['locked'] == true || lockedUntil != null || res.status == 423 || res.status == 429;
    setState(() {
      _checking = false;
      _locked = locked;
      _code.clear();
      if (locked) {
        _error = lockedUntil != null
            ? tr(context, 'Too many wrong codes. Code entry is locked until ${_hm(lockedUntil)}. Ask the customer to check the code in their Malvoya app.',
                'Liian monta väärää koodia. Koodin syöttö on lukittu klo ${_hm(lockedUntil)} asti. Pyydä asiakasta tarkistamaan koodi Malvoya-sovelluksesta.')
            : tr(context, 'Too many wrong codes. Code entry is locked for 15 minutes. Ask the customer to check the code in their Malvoya app.',
                'Liian monta väärää koodia. Koodin syöttö on lukittu 15 minuutiksi. Pyydä asiakasta tarkistamaan koodi Malvoya-sovelluksesta.');
      } else if (attemptsLeft != null) {
        _error = attemptsLeft == 1
            ? tr(context, 'That code is not right. 1 try left before a 15-minute lock.', 'Koodi ei täsmää. 1 yritys jäljellä ennen 15 minuutin lukitusta.')
            : tr(context, 'That code is not right. $attemptsLeft tries left before a 15-minute lock.', 'Koodi ei täsmää. $attemptsLeft yritystä jäljellä ennen 15 minuutin lukitusta.');
      } else {
        _error = res.error ?? tr(context, 'Could not check the code. Please try again.', 'Koodia ei voitu tarkistaa. Yritä uudelleen.');
      }
    });
    if (!locked) _focus.requestFocus();
  }

  Widget _box(int index) {
    final text = _code.text;
    final filled = index < text.length;
    final active = !_locked && _focus.hasFocus && (index == text.length || (index == _length - 1 && text.length == _length));
    final borderColor = _error != null && text.isEmpty
        ? AppTheme.accent
        : active
            ? AppTheme.primary
            : AppTheme.divider;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.xs),
        child: AspectRatio(
          aspectRatio: 0.82,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _locked ? AppTheme.sand : AppTheme.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: active || (_error != null && text.isEmpty) ? 2 : 1.2),
            ),
            child: Text(filled ? text[index] : '', style: AppTheme.display(size: 30)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List?) ?? const [];
    final count = items.fold<int>(0, (s, i) => s + (asInt((i as Map)['quantity']) ?? 1));
    final complete = _code.text.length == _length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Enter the pickup code', 'Syötä noutokoodi'), style: AppTheme.display(size: 22)),
            const SizedBox(height: MSpace.xs),
            Text(
              '${tr(context, 'Order', 'Tilaus')} #${widget.order['id']} · ${count == 1 ? tr(context, '1 item', '1 tuote') : tr(context, '$count items', '$count tuotetta')}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Text(
              tr(context, 'Ask the customer for the 6-digit code in their Malvoya app. Hand over the items only after the code is accepted.',
                  'Pyydä asiakkaalta 6-numeroinen koodi hänen Malvoya-sovelluksestaan. Luovuta tuotteet vasta, kun koodi on hyväksytty.'),
              style: const TextStyle(fontSize: MTextSize.label, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            Stack(children: [
              Row(children: [for (var i = 0; i < _length; i++) _box(i)]),
              // The real (invisible) field on top of the boxes: taps focus it and the numeric keyboard opens
              Positioned.fill(
                child: Semantics(
                  label: tr(context, 'Pickup code, 6 digits', 'Noutokoodi, 6 numeroa'),
                  child: Opacity(
                    opacity: 0,
                    alwaysIncludeSemantics: true,
                    child: TextField(
                      controller: _code,
                      focusNode: _focus,
                      autofocus: true,
                      enabled: !_locked,
                      readOnly: _checking,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_length)],
                      decoration: const InputDecoration(border: InputBorder.none, filled: false, counterText: ''),
                      onChanged: (v) {
                        setState(() {
                          if (v.isNotEmpty) _error = null;
                        });
                        if (v.length == _length) _submit();
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
              ),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.fromLTRB(MSpace.md, 10, MSpace.md, 10),
                      decoration: BoxDecoration(color: _locked ? AppTheme.sunshineLight : MPalette.redLight, borderRadius: BorderRadius.circular(14)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(_locked ? Icons.lock_clock_rounded : Icons.error_outline_rounded, size: 18, color: _locked ? MPalette.amberInk : MPalette.red),
                        const SizedBox(width: MSpace.sm),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(fontSize: MTextSize.label, height: 1.35, fontWeight: FontWeight.w600, color: _locked ? MPalette.amberInk : MPalette.red)),
                        ),
                      ]),
                    ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: MButton(label: _locked ? tr(context, 'Locked for now', 'Lukittu toistaiseksi') : tr(context, 'Confirm handover', 'Vahvista luovutus'), loading: _checking, onPressed: complete && !_checking && !_locked ? _submit : null),
            ),
          ],
        ),
      ),
    );
  }
}
