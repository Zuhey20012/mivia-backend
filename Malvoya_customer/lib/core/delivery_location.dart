import 'dart:convert';
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
  static const _kDoorCode = 'malvoya_active_door_code';

  /// The customer's saved addresses (a JSON list, on this phone only).
  static const savedAddressesKey = 'malvoya_addresses';

  String? address;
  double? lat;
  double? lng;

  /// Door code saved with the active address; checkout offers it to the courier.
  String? doorCode;
  bool _loaded = false;

  bool get hasCoordinates => lat != null && lng != null;

  /// Query parameters for endpoints that rank or price by distance.
  Map<String, String> get query => hasCoordinates ? {'lat': lat!.toStringAsFixed(5), 'lng': lng!.toStringAsFixed(5)} : {};

  /// Loads the active address. A saved address marked as default is used at start-up.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      address = prefs.getString(_kAddress);
      lat = prefs.getDouble(_kLat);
      lng = prefs.getDouble(_kLng);
      doorCode = prefs.getString(_kDoorCode);
      final preferred = defaultAddress(prefs);
      if (preferred != null) {
        notifyListeners();
        await use(preferred);
        return;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// The saved address marked as default, if any.
  static Map<String, dynamic>? defaultAddress(SharedPreferences prefs) {
    for (final a in savedAddresses(prefs)) {
      if (a['isDefault'] == true && '${a['subtitle'] ?? ''}'.trim().isNotEmpty) return a;
    }
    return null;
  }

  static List<Map<String, dynamic>> savedAddresses(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(savedAddressesKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Makes a saved address (from the address book) the active one.
  Future<void> use(Map<String, dynamic> saved) {
    final lat = saved['lat'];
    final lng = saved['lng'];
    final code = '${saved['buzzer'] ?? ''}'.trim();
    return set(
      '${saved['subtitle'] ?? saved['title'] ?? ''}',
      latitude: lat is num ? lat.toDouble() : null,
      longitude: lng is num ? lng.toDouble() : null,
      doorCode: code.isEmpty ? null : code,
    );
  }

  /// Sets the active address. Pass coordinates when the address was pinned on the map.
  Future<void> set(String newAddress, {double? latitude, double? longitude, String? doorCode}) async {
    address = newAddress;
    lat = latitude;
    lng = longitude;
    this.doorCode = doorCode;
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
      if (doorCode != null && doorCode.isNotEmpty) {
        await prefs.setString(_kDoorCode, doorCode);
      } else {
        await prefs.remove(_kDoorCode);
      }
    } catch (_) {}
  }

  /// Forgets the active and saved addresses (on sign-out: they belong to the account holder).
  Future<void> clear() async {
    address = null;
    lat = null;
    lng = null;
    doorCode = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [_kAddress, _kLat, _kLng, _kDoorCode, savedAddressesKey, 'saved_default_address', 'user_delivery_address']) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
