import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/secure_storage.dart';

enum AppThemePreference {
  dark('dark', 'Sabit Koyu Tema'),
  light('light', 'Sabit Açık Tema'),
  system('system', 'Sisteme Göre'),
  scheduled('scheduled', 'Saate Göre (19:00 - 07:00)');

  final String key;
  final String label;
  const AppThemePreference(this.key, this.label);
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _storage = SecureStorage.instance;
  static const _kThemePrefKey = 'personel_theme_preference';

  AppThemePreference _preference = AppThemePreference.dark;
  AppThemePreference get preference => _preference;

  @override
  ThemeMode build() {
    Future.microtask(_loadSavedTheme);
    // Defaults to dark for 2026 personnel/kitchen UI
    return ThemeMode.dark;
  }

  Future<void> _loadSavedTheme() async {
    try {
      final saved = await _storage.read(key: _kThemePrefKey);
      if (saved == 'light') {
        _preference = AppThemePreference.light;
        state = ThemeMode.light;
      } else if (saved == 'system') {
        _preference = AppThemePreference.system;
        state = ThemeMode.system;
      } else if (saved == 'scheduled') {
        _preference = AppThemePreference.scheduled;
        state = _getScheduledThemeMode();
      } else {
        _preference = AppThemePreference.dark;
        state = ThemeMode.dark;
      }
    } catch (e) {
      debugPrint('[ThemeModeNotifier] Failed to read saved theme: $e');
      _preference = AppThemePreference.dark;
      state = ThemeMode.dark;
    }
  }

  ThemeMode _getScheduledThemeMode() {
    final hour = DateTime.now().hour;
    // 19:00 - 07:00 is dark, daytime is light
    if (hour >= 19 || hour < 7) {
      return ThemeMode.dark;
    } else {
      return ThemeMode.light;
    }
  }

  Future<void> setPreference(AppThemePreference pref) async {
    _preference = pref;
    if (pref == AppThemePreference.dark) {
      state = ThemeMode.dark;
    } else if (pref == AppThemePreference.light) {
      state = ThemeMode.light;
    } else if (pref == AppThemePreference.system) {
      state = ThemeMode.system;
    } else if (pref == AppThemePreference.scheduled) {
      state = _getScheduledThemeMode();
    }

    try {
      await _storage.write(key: _kThemePrefKey, value: pref.key);
    } catch (e) {
      debugPrint('[ThemeModeNotifier] Failed to persist theme: $e');
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      await setPreference(AppThemePreference.light);
    } else {
      await setPreference(AppThemePreference.dark);
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});
