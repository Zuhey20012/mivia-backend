import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the customer wants things delivered. Coordinates are only known when the address was
/// pinned on the map; they drive the distance-based delivery fee, delivery estimates, nearby
/// stores and the courier's drop-off area. They stay on this phone until an order is placed.
class DeliveryLocation extends ChangeNotifier {
  DeliveryLocation._();
  static final DeliveryLocation instance = DeliveryLocation._();

  static const _kAddress = 'malvoya_active_address';
  static const _kLat = 'malvoya_active_lat';
  static const _kLng = 'malvoya_active_lng';

  String? address;
  double? lat;
  double? lng;
  bool _loaded = false;

  bool get hasCoordinates => lat != null && lng != null;

  /// Query parameters for endpoints that rank or price by distance.
  Map<String, String> get query => hasCoordinates ? {'lat': lat!.toStringAsFixed(5), 'lng': lng!.toStringAsFixed(5)} : {};

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      address = prefs.getString(_kAddress);
      lat = prefs.getDouble(_kLat);
      lng = prefs.getDouble(_kLng);
      notifyListeners();
    } catch (_) {}
  }

  /// Sets the active address. Pass coordinates when the address was pinned on the map.
  Future<void> set(String newAddress, {double? latitude, double? longitude}) async {
    address = newAddress;
    lat = latitude;
    lng = longitude;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAddress, newAddress);
      if (latitude != null && longitude != null) {
        await prefs.setDouble(_kLat, latitude);
        await prefs.setDouble(_kLng, longitude);
      } else {
        await prefs.remove(_kLat);
        await prefs.remove(_kLng);
      }
    } catch (_) {}
  }
}
