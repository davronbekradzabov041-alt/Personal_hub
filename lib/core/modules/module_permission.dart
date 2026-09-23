/// Разрешение, которое модуль запрашивает в своём манифесте.
///
/// Намеренно не enum: внешний модуль (Этап 11) может указать в
/// manifest.json разрешение, о котором текущее ядро ещё не знает.
/// Enum потребовал бы пересборки ядра под каждое новое разрешение —
/// это противоречит идее внешних модулей. Вместо этого — простой
/// value-объект поверх строки, плюс список того, что ядро уже
/// умеет проверять ([known]).
///
/// Как именно ModuleManager реагирует на неизвестные/недостающие
/// разрешения — вопрос Этапа 8 (проверка) и Этапа 13 (безопасность),
/// не этого файла.
class ModulePermission {
  final String id;
  const ModulePermission(this.id);

  /// Разрешение регистрировать свои данные в глобальном поиске
  /// ядра (GlobalSearchService, Этап 5). Единственное разрешение,
  /// у которого в ядре уже есть реальная защищаемая возможность —
  /// остальные появятся вместе с самими возможностями, а не заранее.
  static const ModulePermission coreSearch = ModulePermission('core.search');

  /// Все разрешения, которые ядро на данный момент понимает.
  static const List<ModulePermission> known = [coreSearch];

  @override
  bool operator ==(Object other) =>
      other is ModulePermission && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}
