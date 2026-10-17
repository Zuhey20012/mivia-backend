import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while a delivery is in progress, like a navigation app, so the courier can
/// glance at the next step on a phone holder. It lets the screen sleep again when the battery is
/// low and not charging (at or below [lowBattery] %), or when the phone's battery saver is on.
class ScreenAwake extends ChangeNotifier {
  ScreenAwake._();
  static final ScreenAwake instance = ScreenAwake._();

  static const lowBattery = 20;

  final _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _levelCheck;
  bool _wanted = false;
  bool _held = false;
  bool _savingBattery = false;

  /// True while the screen is kept on.
  bool get isOn => _held;

  /// True while a delivery wants the screen on but the battery is too low for it.
  bool get pausedForBattery => _wanted && _savingBattery;

  /// Called with whether a delivery is in progress.
  Future<void> want(bool on) async {
    if (on == _wanted) return;
    _wanted = on;
    if (on) {
      _stateSub ??= _battery.onBatteryStateChanged.listen((_) => _check(), onError: (_) {});
      _levelCheck ??= Timer.periodic(const Duration(minutes: 2), (_) => _check());
    } else {
      await _stateSub?.cancel();
      _stateSub = null;
      _levelCheck?.cancel();
      _levelCheck = null;
    }
    await _check();
  }

  Future<void> _check() async {
    var saving = false;
    if (_wanted) {
      try {
        final level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        final charging = state == BatteryState.charging || state == BatteryState.full;
        final saver = await _battery.isInBatterySaveMode;
        saving = saver || (!charging && level <= lowBattery);
      } catch (_) {
        // Battery unknown (e.g. an emulator): keep the screen on as asked
      }
    }
    final hold = _wanted && !saving;
    final changed = hold != _held || saving != _savingBattery;
    _savingBattery = saving;
    if (hold != _held) {
      _held = hold;
      try {
        await WakelockPlus.toggle(enable: hold);
      } catch (e) {
        debugPrint('Wakelock: $e');
      }
    }
    if (changed) notifyListeners();
  }
}
