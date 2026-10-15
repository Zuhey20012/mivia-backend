import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A friend's invite code (from a malvoya.../r/<code> link) kept until the next checkout, where
/// it is filled into the promo-code field. The server decides whether it can be used.
class PendingPromo extends ValueNotifier<String?> {
  PendingPromo._() : super(null);
  static final instance = PendingPromo._();

  static const _key = 'malvoya_pending_invite_code';
  bool _loaded = false;

  Future<String?> load() async {
    if (_loaded) return value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(_key);
    } catch (_) {}
    return value;
  }

  Future<void> save(String code) async {
    _loaded = true;
    value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    } catch (_) {}
  }

  Future<void> clear() async {
    _loaded = true;
    value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
