import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../auth_service.dart';

/// A person this customer blocked: their comments and reviews are hidden from this account.
class BlockedUser {
  final int id;
  final String name;
  const BlockedUser(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Who the signed-in customer has blocked. The server (`/me/blocks`) is the record and also
/// hides their content; this copy hides it on the phone immediately and between reloads.
class BlockedUsers extends ChangeNotifier {
  BlockedUsers._();
  static final BlockedUsers instance = BlockedUsers._();

  final Map<int, BlockedUser> _users = {};
  int? _accountId;

  /// False when the server has no block list yet (older API): the block action is then hidden.
  bool available = true;

  List<BlockedUser> get users => _users.values.toList();
  bool isBlocked(dynamic userId) {
    final id = userId is int ? userId : int.tryParse('${userId ?? ''}');
    return id != null && _users.containsKey(id);
  }

  String _key(int accountId) => 'blocked_users_$accountId';

  Future<void> _save() async {
    final id = _accountId;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(id), jsonEncode(_users.values.map((u) => u.toJson()).toList()));
    } catch (_) {}
  }

  /// Loads the saved copy for this account, then the server's list (once per sign-in; the
  /// Blocked users screen refreshes it on demand).
  Future<void> load(AuthService auth) async {
    final id = auth.isAuthenticated ? auth.currentUser?.id : null;
    if (id == null) {
      if (_accountId != null) clear();
      return;
    }
    if (_accountId == id) return;
    {
      _accountId = id;
      _users.clear();
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_key(id));
        if (raw != null) {
          for (final u in (jsonDecode(raw) as List)) {
            final uid = u is Map ? int.tryParse('${u['id']}') : null;
            if (uid != null) _users[uid] = BlockedUser(uid, '${u['name'] ?? ''}');
          }
        }
      } catch (_) {}
      notifyListeners();
    }
    await refresh(auth);
  }

  /// Returns null on success, or a message the user can read.
  Future<String?> refresh(AuthService auth) async {
    final res = await ApiClient(auth).get('/me/blocks');
    if (res.status == 404) {
      available = false;
      notifyListeners();
      return null;
    }
    if (!res.ok) return res.error;
    available = true;
    final list = res.data['blocks'] ?? res.data['users'] ?? res.data['blocked'];
    if (list is List) {
      _users.clear();
      for (final item in list) {
        if (item is! Map) continue;
        final nested = item['user'] is Map ? item['user'] as Map : item;
        final uid = int.tryParse('${item['userId'] ?? item['blockedId'] ?? nested['id'] ?? ''}');
        if (uid == null) continue;
        final name = '${nested['name'] ?? item['name'] ?? nested['author'] ?? ''}';
        _users[uid] = BlockedUser(uid, name);
      }
      await _save();
      notifyListeners();
    }
    return null;
  }

  /// Hides the person's content right away; undone if the server refuses.
  Future<String?> block(AuthService auth, int userId, String name) async {
    _users[userId] = BlockedUser(userId, name);
    notifyListeners();
    final res = await ApiClient(auth).post('/me/blocks', {'userId': userId});
    if (!res.ok) {
      _users.remove(userId);
      if (res.status == 404) available = false;
      notifyListeners();
      return res.error;
    }
    await _save();
    return null;
  }

  Future<String?> unblock(AuthService auth, int userId) async {
    final res = await ApiClient(auth).delete('/me/blocks/$userId');
    // 404: the server has no such block (any more), so it is not blocked there either
    if (!res.ok && res.status != 404) return res.error;
    _users.remove(userId);
    await _save();
    notifyListeners();
    return null;
  }

  /// Sign-out: the next person on this phone starts with their own list.
  void clear() {
    _users.clear();
    _accountId = null;
    notifyListeners();
  }
}
