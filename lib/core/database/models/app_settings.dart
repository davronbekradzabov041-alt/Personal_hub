import 'package:isar/isar.dart';

part 'app_settings.g.dart';

/// Общие настройки приложения.
///
/// Коллекция хранит ровно одну запись (singleton-паттерн):
/// id всегда фиксирован (см. AppSettings.fixedId), поэтому
/// put() с этим id всегда перезаписывает ту же запись, а не
/// создаёт новую.
@collection
class AppSettings {
  /// Фиксированный id единственной записи настроек.
  static const int fixedId = 0;

  Id id = fixedId;

  /// Режим темы: 'system' | 'light' | 'dark'.
  /// Хранится строкой, а не enum-индексом — так порядок
  /// значений в коде можно менять, не ломая сохранённые данные.
  String themeMode = 'system';

  /// Код языка интерфейса: 'ru' | 'uz' | 'en'.
  /// Пока используется только как сохранённое предпочтение —
  /// полноценная локализация строк не входит в Этап 4.
  String language = 'ru';

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'language': language,
  };
}
