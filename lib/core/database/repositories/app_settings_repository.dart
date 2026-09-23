import 'package:isar/isar.dart';

import '../isar_service.dart';
import '../models/app_settings.dart';

/// Репозиторий настроек приложения.
///
/// Не реализует BaseRepository — это не коллекция с множеством
/// записей, а единственная строка настроек (singleton-паттерн),
/// поэтому у него свой, более простой API: load()/save().
class AppSettingsRepository {
  Isar get _isar => IsarService.instance;

  /// Загружает настройки. Если записи ещё нет (первый запуск),
  /// возвращает значения по умолчанию из модели, не сохраняя их —
  /// запись появится при первом save().
  Future<AppSettings> load() async {
    final existing = await _isar.appSettings.get(AppSettings.fixedId);
    return existing ?? AppSettings();
  }

  /// Сохраняет настройки, перезаписывая единственную запись.
  Future<void> save(AppSettings settings) async {
    settings.id = AppSettings.fixedId;
    await _isar.writeTxn(() => _isar.appSettings.put(settings));
  }
}
