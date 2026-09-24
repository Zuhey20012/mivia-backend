import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/theme.dart';

enum AppThemeMode {
  light,
  dark,
  eyeComfort,
}

class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'malvoya_theme_preference';
  // Until the user picks a theme, follow the phone's light/dark setting.
  AppThemeMode _mode = _systemMode();

  static AppThemeMode _systemMode() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
          ? AppThemeMode.dark
          : AppThemeMode.light;

  AppThemeMode get mode => _mode;

  bool get isDark => _mode == AppThemeMode.dark || _mode == AppThemeMode.eyeComfort;

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.eyeComfort:
        return ThemeMode.dark;
    }
  }

  ThemeData get currentTheme {
    switch (_mode) {
      case AppThemeMode.dark:
        return AppTheme.darkTheme;
      case AppThemeMode.light:
        return AppTheme.lightTheme;
      case AppThemeMode.eyeComfort:
        return AppTheme.eyeComfortTheme;
    }
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        _mode = AppThemeMode.light;
      } else if (saved == 'eyeComfort') {
        _mode = AppThemeMode.eyeComfort;
      } else if (saved == 'dark') {
        _mode = AppThemeMode.dark;
      } else {
        _mode = _systemMode();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String val = 'light';
      if (mode == AppThemeMode.dark) val = 'dark';
      if (mode == AppThemeMode.eyeComfort) val = 'eyeComfort';
      await prefs.setString(_prefKey, val);
    } catch (_) {}
  }

  Future<void> setTheme(AppThemeMode mode) => setMode(mode);
}
