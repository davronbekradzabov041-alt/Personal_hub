import 'package:flutter/material.dart';

import '../database/models/app_settings.dart';
import '../database/repositories/app_settings_repository.dart';

/// Контроллер настроек приложения.
///
/// ChangeNotifier выбран сознательно, без дополнительных
/// пакетов управления состоянием (provider/riverpod) — это
/// поведение ядра, а не бизнес-логика модуля, и Flutter SDK
/// уже даёт всё нужное через ListenableBuilder (см. app.dart).
///
/// Единственный источник правды по настройкам: любое изменение
/// сразу сохраняется в Isar через AppSettingsRepository.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._repository);

  final AppSettingsRepository _repository;

  ThemeMode _themeMode = ThemeMode.system;
  String _language = 'ru';

  ThemeMode get themeMode => _themeMode;
  String get language => _language;

  /// Загружает сохранённые настройки. Вызывается один раз
  /// в main.dart, до runApp(), чтобы не было "мигания" темой
  /// по умолчанию при старте.
  Future<void> load() async {
    final saved = await _repository.load();
    _themeMode = _themeModeFromString(saved.themeMode);
    _language = saved.language;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setLanguage(String languageCode) async {
    if (_language == languageCode) return;
    _language = languageCode;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final settings = AppSettings()
      ..themeMode = _themeModeToString(_themeMode)
      ..language = _language;
    await _repository.save(settings);
  }

  static ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
