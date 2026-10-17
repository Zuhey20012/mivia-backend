import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/haptics.dart';
import '../core/images.dart';
import '../core/strings.dart';

/// How long the store has to answer a paid order before the server refunds it (the order
/// watchdog's STORE_ACCEPT_MINUTES, 10 by default), counted from `paidAt`.
const storeAnswerMinutes = 10;

/// When an unanswered order is refunded automatically: the server's own deadline if it sends one,
/// otherwise payment time + [storeAnswerMinutes]. Null when the order carries no times.
DateTime? answerDeadline(Map<String, dynamic> o) {
  final explicit = DateTime.tryParse('${o['acceptDeadline'] ?? o['answerBy'] ?? ''}')?.toLocal();
  if (explicit != null) return explicit;
  final paid = DateTime.tryParse('${o['paidAt'] ?? ''}')?.toLocal();
  return paid?.add(const Duration(minutes: storeAnswerMinutes));
}

/// Full-screen "New order" moment, like a shop tablet: what was ordered, the total, the time left
/// to answer, and big Accept / Decline buttons. [onAnswer] runs the dashboard's own accept/decline
/// (including its decline confirmation) and returns true when the server took the answer.
///
/// The screen closes by itself when the order stops waiting (answered on another phone, or
/// refunded): [waitingIds] is the dashboard's live set of orders that still need an answer.
Future<void> showIncomingOrder(
  BuildContext context, {
  required Map<String, dynamic> order,
  required ValueNotifier<Set<Object?>> waitingIds,
  required Future<bool> Function(String status) onAnswer,
}) {
  Haptics.newOrder();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    fullscreenDialog: true,
    transitionDuration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => _IncomingOrderScreen(order: order, waitingIds: waitingIds, onAnswer: onAnswer),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class _IncomingOrderScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final ValueNotifier<Set<Object?>> waitingIds;
  final Future<bool> Function(String status) onAnswer;
  const _IncomingOrderScreen({required this.order, required this.waitingIds, required this.onAnswer});

  @override
  State<_IncomingOrderScreen> createState() => _IncomingOrderScreenState();
}

class _IncomingOrderScreenState extends State<_IncomingOrderScreen> {
  static const _red = Color(0xFFD93025);
  Timer? _tick;
  String? _busy; // the status being sent

  Map<String, dynamic> get o => widget.order;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.waitingIds.addListener(_onWaitingChanged);
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.waitingIds.removeListener(_onWaitingChanged);
    super.dispose();
  }

  /// Answered elsewhere or refunded meanwhile: nothing left to answer here.
  void _onWaitingChanged() {
    if (!mounted || _busy != null) return;
    if (!widget.waitingIds.value.contains(o['id'])) Navigator.of(context).maybePop();
  }

  Future<void> _answer(String status) async {
    if (_busy != null) return;
    setState(() => _busy = status);
    final ok = await widget.onAnswer(status);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = null);
    }
  }

  String _clock(Duration d) {
    final s = d.inSeconds.clamp(0, 99 * 60);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  bool get _pickup => '${o['fulfilment'] ?? ''}'.toUpperCase() == 'PICKUP';

  String? _slot() {
    final start = DateTime.tryParse('${o['scheduledStart'] ?? ''}')?.toLocal();
    final end = DateTime.tryParse('${o['scheduledEnd'] ?? ''}')?.toLocal();
    if (start == null || end == null) return null;
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final day = start.year == now.year && start.month == now.month && start.day == now.day
        ? tr(context, 'today', 'tänään')
        : (start.year == tomorrow.year && start.month == tomorrow.month && start.day == tomorrow.day)
            ? tr(context, 'tomorrow', 'huomenna')
            : '${start.day}.${start.month}.';
    return tr(context, 'Scheduled delivery $day ${hm(start)}–${hm(end)}', 'Ajastettu toimitus $day ${hm(start)}–${hm(end)}');
  }

  @override
  Widget build(BuildContext context) {
    final items = ((o['items'] as List?) ?? const []).whereType<Map>().toList();
    final deadline = answerDeadline(o);
    final left = deadline?.difference(DateTime.now());
    final pieces = items.fold<int>(0, (n, i) => n + (asInt(i['quantity']) ?? 1));
    final tip = asInt(o['tipCents']) ?? 0;
    final slot = _slot();
    return PopScope(
      canPop: _busy == null,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header: close (answer later, the alert keeps ringing) and the order number
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(children: [
                IconButton(
                  tooltip: tr(context, 'Answer later', 'Vastaa myöhemmin'),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _busy == null ? () => Navigator.of(context).pop() : null,
                  icon: const Icon(Icons.close_rounded),
                ),
                const Spacer(),
                Text('#${o['id']}', style: AppTheme.display(size: 22)),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'New order', 'Uusi tilaus'), style: AppTheme.display(size: 30)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        _pill(
                          _pickup ? Icons.storefront_rounded : Icons.delivery_dining_rounded,
                          _pickup ? tr(context, 'Collect in shop', 'Nouto kaupasta') : tr(context, 'Delivery', 'Toimitus'),
                          bg: _pickup ? AppTheme.primary : AppTheme.primaryLight,
                          fg: _pickup ? Colors.white : AppTheme.primary,
                        ),
                        _pill(Icons.shopping_bag_outlined, pieces == 1 ? tr(context, '1 item', '1 tuote') : tr(context, '$pieces items', '$pieces tuotetta')),
                      ]),
                    ]),
                  ),
                  if (left != null) _CountdownRing(left: left, total: const Duration(minutes: storeAnswerMinutes), label: _clock(left)),
                ]),
                if (slot != null) ...[
                  const SizedBox(height: 12),
                  _note(Icons.schedule_rounded, slot, bg: AppTheme.lilac, fg: AppTheme.malva),
                ],
                const SizedBox(height: 12),
                if (left != null)
                  _note(
                    Icons.hourglass_bottom_rounded,
                    left.inSeconds > 0
                        ? tr(context, 'Answer within ${_clock(left)}, or the order is refunded to the customer automatically.',
                            'Vastaa ${_clock(left)} kuluessa, muuten tilaus hyvitetään asiakkaalle automaattisesti.')
                        : tr(context, 'The answer time is up. Answer now — the order is about to be refunded.',
                            'Vastausaika on päättynyt. Vastaa nyt — tilaus hyvitetään pian.'),
                    bg: left.inMinutes < 3 ? const Color(0xFFFDECEA) : AppTheme.sunshineLight,
                    fg: left.inMinutes < 3 ? _red : const Color(0xFF6A4500),
                  ),
                const SizedBox(height: 16),
                for (final i in items) _item(i),
                const Divider(height: 24),
                Row(children: [
                  Expanded(child: Text(tr(context, 'Items total', 'Tuotteet yhteensä'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Text(euro(context, o['subtotalCents']), style: AppTheme.display(size: 24)),
                ]),
                if (tip > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${tr(context, 'Plus a tip for the courier', 'Lisäksi tippi kuriirille')} ${euro(context, tip)}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                if ('${o['notes'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _note(Icons.sticky_note_2_outlined, '${o['notes']}'.trim(), bg: AppTheme.sand, fg: AppTheme.textPrimary),
                ],
              ]),
            ),
            // One-hand reach: both answers at the bottom, Accept the larger one
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red, width: 1.5),
                      minimumSize: const Size(64, 64),
                    ),
                    onPressed: _busy == null ? () => _answer('CANCELLED') : null,
                    child: _busy == 'CANCELLED'
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _red))
                        : Text(tr(context, 'Decline', 'Hylkää')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 64), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    onPressed: _busy == null ? () => _answer('CONFIRMED') : null,
                    icon: _busy == 'CONFIRMED'
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: Text(tr(context, 'Accept', 'Hyväksy')),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, {Color bg = AppTheme.sand, Color fg = AppTheme.textPrimary}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13))),
        ]),
      );

  Widget _note(IconData icon, String text, {required Color bg, required Color fg}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, height: 1.35))),
        ]),
      );

  Widget _item(Map i) {
    final images = ((i['product']?['images'] as List?) ?? const []).map((e) => '$e').toList();
    final variant = i['variant'] as Map?;
    final options = [
      if ('${variant?['size'] ?? ''}'.isNotEmpty) '${tr(context, 'Size', 'Koko')} ${variant!['size']}',
      if ('${variant?['color'] ?? ''}'.isNotEmpty) '${tr(context, 'Colour', 'Väri')} ${variant!['color']}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        SizedBox(
          width: 56,
          height: 68,
          child: images.isEmpty
              ? Container(
                  decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.checkroom_rounded, color: AppTheme.primary),
                )
              : NetImage(images.first, width: 56, height: 68, radius: 10),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i['product']?['name'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(options.join(' · '), style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(10)),
          child: Text('${i['quantity']}×', textAlign: TextAlign.center, style: AppTheme.display(size: 18, color: AppTheme.primary)),
        ),
      ]),
    );
  }
}

/// Time left as a ring that empties; red in the last three minutes.
class _CountdownRing extends StatelessWidget {
  final Duration left;
  final Duration total;
  final String label;
  const _CountdownRing({required this.left, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    final fraction = (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final urgent = left.inMinutes < 3;
    final color = urgent ? const Color(0xFFD93025) : AppTheme.primary;
    return Semantics(
      label: tr(context, '$label left to answer', '$label aikaa vastata'),
      excludeSemantics: true,
      child: SizedBox(
        width: 92,
        height: 92,
        child: CustomPaint(
          painter: _RingPainter(fraction: fraction, color: color),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: AppTheme.display(size: 22, color: color)),
                  Text(tr(context, 'left', 'jäljellä'), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  _RingPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()
      ..color = AppTheme.sand
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * fraction, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}
