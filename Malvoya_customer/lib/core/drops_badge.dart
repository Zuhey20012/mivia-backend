import 'package:flutter/foundation.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'delivery_location.dart';

/// The sunshine dot on the Drops tab: is there a drop newer than the customer's last visit?
///
/// The API has no badge field, so this compares the newest drop's `publishedAt` (the latest
/// chronological feed, one item) with the time the Drops tab was last opened, stored only on
/// this phone.
class DropsBadge extends ChangeNotifier {
  DropsBadge._();
  static final instance = DropsBadge._();

  static const _key = 'drops_last_seen_at';

  bool _hasNew = false;
  DateTime? _newest;
  bool _checking = false;

  bool get hasNew => _hasNew;

  /// Asks the server for the newest drop. Never throws; an unreachable server leaves the dot as is.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      await DeliveryLocation.instance.load();
      final res = await const ApiClient(null).get('/drops/feed', query: {
        'mode': 'latest',
        'limit': '1',
        ...DeliveryLocation.instance.query,
      });
      if (!res.ok) return;
      final drops = res.data['drops'];
      final first = drops is List && drops.isNotEmpty && drops.first is Map ? drops.first as Map : null;
      final newest = DateTime.tryParse('${first?['publishedAt'] ?? ''}');
      _newest = newest;
      final prefs = await SharedPreferences.getInstance();
      final seen = DateTime.tryParse(prefs.getString(_key) ?? '');
      final next = newest != null && (seen == null || newest.isAfter(seen));
      if (next != _hasNew) {
        _hasNew = next;
        notifyListeners();
      }
    } catch (_) {
      // Offline or storage unavailable: keep the current state
    } finally {
      _checking = false;
    }
  }

  /// The Drops tab was opened: everything published so far counts as seen.
  Future<void> markSeen() async {
    final at = _newest != null && _newest!.isAfter(DateTime.now()) ? _newest! : DateTime.now();
    if (_hasNew) {
      _hasNew = false;
      notifyListeners();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, at.toUtc().toIso8601String());
    } catch (_) {}
  }
}
