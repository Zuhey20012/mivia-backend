import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/strings.dart';

/// A small schematic of a job: you → shop → drop-off area, drawn to scale from the coordinates the
/// server sent (the drop-off is the rounded delivery area until the job is accepted). It is not a
/// map: no streets, so it never suggests a route that was not calculated.
class MiniRoute extends StatelessWidget {
  final ({double lat, double lng})? me;
  final ({double lat, double lng}) store;
  final ({double lat, double lng})? dropOff;
  final String? toStoreText;
  final String? dropText;
  final double height;
  const MiniRoute({super.key, this.me, required this.store, this.dropOff, this.toStoreText, this.dropText, this.height = 120});

  @override
  Widget build(BuildContext context) {
    final contrast = MediaQuery.of(context).highContrast;
    final parts = [
      if (toStoreText != null) '${tr(context, 'You to the shop', 'Sinä kauppaan')} $toStoreText',
      if (dropText != null) '${tr(context, 'shop to the drop-off area', 'kaupasta toimitusalueelle')} $dropText',
    ];
    return Semantics(
      label: parts.isEmpty ? tr(context, 'Route sketch', 'Reittikaavio') : parts.join(', '),
      excludeSemantics: true,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: contrast ? Border.all(color: AppTheme.textPrimary) : null),
        child: CustomPaint(
          painter: _RoutePainter(me: me, store: store, dropOff: dropOff, contrast: contrast),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final ({double lat, double lng})? me;
  final ({double lat, double lng}) store;
  final ({double lat, double lng})? dropOff;
  final bool contrast;
  _RoutePainter({this.me, required this.store, this.dropOff, required this.contrast});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [if (me != null) me!, store, if (dropOff != null) dropOff!];
    // Equirectangular projection around the shop: fine for a few kilometres
    final k = math.cos(store.lat * math.pi / 180);
    Offset raw(({double lat, double lng}) p) => Offset((p.lng - store.lng) * k, -(p.lat - store.lat));
    final rs = pts.map(raw).toList();
    var minX = rs.map((o) => o.dx).reduce(math.min), maxX = rs.map((o) => o.dx).reduce(math.max);
    var minY = rs.map((o) => o.dy).reduce(math.min), maxY = rs.map((o) => o.dy).reduce(math.max);
    final span = math.max(math.max(maxX - minX, maxY - minY), 1e-4);
    const pad = 26.0;
    final scale = math.min((size.width - 2 * pad) / span, (size.height - 2 * pad) / span);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    Offset at(({double lat, double lng}) p) {
      final r = raw(p);
      return Offset(size.width / 2 + (r.dx - cx) * scale, size.height / 2 + (r.dy - cy) * scale);
    }

    final storeAt = at(store);
    final line = Paint()
      ..strokeWidth = contrast ? 4 : 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (me != null) {
      // You → shop, dashed: you choose your own way there
      final a = at(me!);
      line.color = AppTheme.textSecondary;
      final d = storeAt - a;
      final len = d.distance;
      if (len > 0) {
        final dir = d / len;
        for (double t = 0; t < len; t += 10) {
          canvas.drawLine(a + dir * t, a + dir * math.min(t + 5, len), line);
        }
      }
    }
    if (dropOff != null) {
      line.color = AppTheme.primary;
      canvas.drawLine(storeAt, at(dropOff!), line);
    }
    void dot(Offset o, Color c, double r) {
      canvas.drawCircle(o, r + 3, Paint()..color = Colors.white);
      canvas.drawCircle(o, r, Paint()..color = c);
    }

    if (me != null) dot(at(me!), const Color(0xFF2563EB), 7);
    dot(storeAt, AppTheme.textPrimary, 8);
    if (dropOff != null) {
      // The drop-off is an area until the job is accepted
      final d = at(dropOff!);
      canvas.drawCircle(d, 16, Paint()..color = AppTheme.primary.withValues(alpha: 0.18));
      dot(d, AppTheme.primary, 8);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.me != me || old.store != store || old.dropOff != dropOff || old.contrast != contrast;
}

/// The legend under a [MiniRoute].
class MiniRouteLegend extends StatelessWidget {
  final bool showMe;
  const MiniRouteLegend({super.key, this.showMe = true});

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 14, runSpacing: 4, children: [
        if (showMe) item(const Color(0xFF2563EB), tr(context, 'You', 'Sinä')),
        item(AppTheme.textPrimary, tr(context, 'Shop', 'Kauppa')),
        item(AppTheme.primary, tr(context, 'Drop-off area', 'Toimitusalue')),
      ]),
    );
  }
}
