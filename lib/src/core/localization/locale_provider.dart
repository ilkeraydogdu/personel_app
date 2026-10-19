import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/secure_storage.dart';

const _kLocaleStorageKey = 'app_personel_locale';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  static const _storage = SecureStorage.instance;

  LocaleNotifier() : super(const Locale('tr', 'TR')) {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    try {
      final code = await _storage.read(key: _kLocaleStorageKey);
      if (code != null && code.isNotEmpty) {
        state = _toLocale(code);
      }
    } catch (e) {
      debugPrint('[LocaleNotifier] Failed to load saved locale: $e');
    }
  }

  Future<void> setLocale(String languageCode) async {
    final newLocale = _toLocale(languageCode);
    state = newLocale;
    try {
      await _storage.write(key: _kLocaleStorageKey, value: languageCode);
    } catch (e) {
      debugPrint('[LocaleNotifier] Failed to persist locale: $e');
    }
  }

  Locale _toLocale(String code) {
    switch (code) {
      case 'en':
        return const Locale('en', 'US');
      case 'de':
        return const Locale('de', 'DE');
      case 'fr':
        return const Locale('fr', 'FR');
      case 'es':
        return const Locale('es', 'ES');
      case 'ru':
        return const Locale('ru', 'RU');
      case 'ar':
        return const Locale('ar', 'SA');
      case 'tr':
      default:
        return const Locale('tr', 'TR');
    }
  }
}
