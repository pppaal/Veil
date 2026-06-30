import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../storage/secure_storage_service.dart';

/// Holds the user-selected [ThemeMode] and persists it through the existing
/// [SecureStorageService]. Defaults to [ThemeMode.system] until a persisted
/// value loads (or when none has been saved).
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._storage) : super(ThemeMode.system) {
    unawaited(_load());
  }

  final SecureStorageService _storage;

  Future<void> _load() async {
    final stored = await _storage.readThemeMode();
    final mode = _decode(stored);
    if (mode != null) {
      state = mode;
    }
  }

  /// Update the active theme mode and persist it immediately.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state) {
      return;
    }
    state = mode;
    await _storage.persistThemeMode(_encode(mode));
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode? _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(secureStorageProvider));
});
