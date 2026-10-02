import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One sound switch for every video in the app (product galleries and Drops), remembered between
/// launches: turn the sound on once and the next video plays with sound too.
class MediaSound extends ChangeNotifier {
  MediaSound._() {
    _load();
  }
  static final MediaSound instance = MediaSound._();

  static const _key = 'media_sound_on';
  bool _on = false; // videos start muted until the user asks for sound

  bool get on => _on;
  double get volume => _on ? 1 : 0;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_key) ?? false;
      if (saved != _on) {
        _on = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggle() => set(!_on);

  Future<void> set(bool on) async {
    if (on == _on) return;
    _on = on;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {}
  }
}
