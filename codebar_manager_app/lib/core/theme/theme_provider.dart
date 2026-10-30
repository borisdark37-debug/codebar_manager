import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_stokage_service.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SecureStorageService _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.light) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final saved = await _storage.getThemeMode();
    if (saved == 'dark') {
      state = ThemeMode.dark;
    } else if (saved == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.light;
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      await _storage.saveThemeMode('light');
    } else {
      state = ThemeMode.dark;
      await _storage.saveThemeMode('dark');
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _storage.saveThemeMode(mode == ThemeMode.dark ? 'dark' : 'light');
  }

  bool get isDarkMode => state == ThemeMode.dark;
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(SecureStorageService());
});
