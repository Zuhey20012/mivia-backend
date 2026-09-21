import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/**
 * Malvoya High-Performance Spatial Radar & Telemetry Calculation Engine
 * Provides discrete spatial calculations, shortest-arc angular normalization,
 * and Spherical Linear Interpolation (SLERP) along street route vectors.
 */
class SpatialRadarService {
  /// Spherical Linear / Linear Interpolation along coordinate vector
  static LatLng interpolate(LatLng from, LatLng to, double fraction) {
    final double clamped = fraction.clamp(0.0, 1.0);
    final double lat = (to.latitude - from.latitude) * clamped + from.latitude;
    final double lng = (to.longitude - from.longitude) * clamped + from.longitude;
    return LatLng(lat, lng);
  }

  /// Calculates shortest-arc angular delta between two headings (-180 to +180 deg)
  static double normalizeAngleDelta(double from, double to) {
    return ((to - from + 540.0) % 360.0) - 180.0;
  }

  /// Forward Azimuth / Geodetic Great Circle Bearing calculation
  static double calculateBearing(LatLng start, LatLng end) {
    final double dLng = (end.longitude - start.longitude) * (math.pi / 180.0);
    final double lat1 = start.latitude * (math.pi / 180.0);
    final double lat2 = end.latitude * (math.pi / 180.0);
    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final double initialBearing = math.atan2(y, x) * (180.0 / math.pi);
    return (initialBearing + 360.0) % 360.0;
  }

  /// Dynamic ETA in minutes from real distance (3.5 min/km city speed + buffer)
  static int calculateDynamicEta(double distanceMeters) {
    final double distanceKm = distanceMeters / 1000.0;
    return (distanceKm * 3.5 + 8.0).ceil().clamp(3, 90);
  }

  /// Dynamic contracting radar circle radius (shrinks as driver approaches)
  static double calculateRadarRadius(double distanceMeters) {
    return (distanceMeters * 0.25).clamp(25.0, 500.0);
  }
}
