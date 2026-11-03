import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// A street route as a measured polyline (API 2.17 `GET /orders/:id/route`): the courier marker is
/// snapped onto it and moved along it, and the drawn line is split at the courier into the part
/// already travelled and the part still ahead. Distances are metres along the route.
class RoutePath {
  RoutePath._(this.points, this._cum);

  /// Null when there are fewer than two distinct points.
  static RoutePath? of(List<LatLng> points) {
    final pts = <LatLng>[];
    for (final p in points) {
      if (pts.isEmpty || pts.last.latitude != p.latitude || pts.last.longitude != p.longitude) pts.add(p);
    }
    if (pts.length < 2) return null;
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + metres(pts[i - 1], pts[i]));
    }
    return RoutePath._(List.unmodifiable(pts), cum);
  }

  /// Parses the API's `[[lat, lng], …]`.
  static RoutePath? fromJson(Object? raw) {
    if (raw is! List) return null;
    final pts = <LatLng>[];
    for (final p in raw) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        final lat = (p[0] as num).toDouble(), lng = (p[1] as num).toDouble();
        if (lat.abs() <= 90 && lng.abs() <= 180) pts.add(LatLng(lat, lng));
      }
    }
    return of(pts);
  }

  final List<LatLng> points;
  final List<double> _cum;

  double get length => _cum.last;
  LatLng get start => points.first;
  LatLng get end => points.last;

  static const _earth = 6371000.0;
  static double _rad(double d) => d * math.pi / 180;

  /// Great-circle distance in metres.
  static double metres(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude), dLng = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * _earth * math.asin(math.min(1, math.sqrt(h)));
  }

  /// The point of the route nearest to [p]: how far along the route it is ([along]) and how far
  /// [p] is from the route ([offset]). With [from] (the courier's current progress) a point more
  /// than 40 m behind it is only chosen when nothing ahead is within 60 m, so GPS jitter never
  /// sends the marker backwards along the street.
  ({double along, double offset}) project(LatLng p, {double? from}) {
    final kLat = _rad(1) * _earth;
    final kLng = kLat * math.cos(_rad(p.latitude));
    var best = (along: 0.0, offset: double.infinity);
    var bestAhead = (along: 0.0, offset: double.infinity);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final ax = (a.longitude - p.longitude) * kLng, ay = (a.latitude - p.latitude) * kLat;
      final bx = (b.longitude - p.longitude) * kLng, by = (b.latitude - p.latitude) * kLat;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final off = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
      final along = _cum[i - 1] + t * (_cum[i] - _cum[i - 1]);
      if (off < best.offset) best = (along: along, offset: off);
      if (from != null && along >= from - 40 && off < bestAhead.offset) bestAhead = (along: along, offset: off);
    }
    if (from != null && bestAhead.offset <= 60) return bestAhead;
    return best;
  }

  int _segmentAt(double d) {
    var lo = 1, hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The point [d] metres along the route (clamped to its ends).
  LatLng pointAt(double d) {
    if (d <= 0) return points.first;
    if (d >= length) return points.last;
    final i = _segmentAt(d);
    final seg = _cum[i] - _cum[i - 1];
    final t = seg == 0 ? 0.0 : (d - _cum[i - 1]) / seg;
    final a = points[i - 1], b = points[i];
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  /// Compass heading (radians, 0 = north, clockwise) of travel at [d], looking a few metres ahead
  /// so the marker turns smoothly through corners instead of snapping at every vertex.
  double headingAt(double d) {
    final a = pointAt(math.min(d, length - 1));
    final b = pointAt(math.min(d + 12, length));
    return bearing(a, b) ?? bearing(points[points.length - 2], points.last) ?? 0;
  }

  /// Heading from [a] to [b] in radians (0 = north, clockwise), or null when they are the same point.
  static double? bearing(LatLng a, LatLng b) {
    final y = math.sin(_rad(b.longitude - a.longitude)) * math.cos(_rad(b.latitude));
    final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
        math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(_rad(b.longitude - a.longitude));
    if (x.abs() < 1e-12 && y.abs() < 1e-12) return null;
    return math.atan2(y, x);
  }

  /// The route between [from] and [to] metres along it.
  List<LatLng> slice(double from, double to) {
    final a = from.clamp(0.0, length), b = to.clamp(0.0, length);
    if (b <= a) return [pointAt(a), pointAt(a)];
    final out = <LatLng>[pointAt(a)];
    for (var i = _segmentAt(a); i < points.length && _cum[i] < b; i++) {
      if (_cum[i] > a) out.add(points[i]);
    }
    out.add(pointAt(b));
    return out;
  }
}
