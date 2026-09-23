import 'package:isar/isar.dart';

part 'module_state_record.g.dart';

/// Постоянная запись состояния ОДНОГО модуля.
///
/// Одна строка на moduleId. Хранит только то, что нужно для
/// восстановления жизненного цикла после перезапуска — сами данные
/// модуля лежат отдельно, в ModuleDataRow (generic key-value,
/// см. аудит Этапа 6: у внешнего модуля нет своего Dart-кода, значит
/// нет и своей типизированной Isar-модели).
@collection
class ModuleStateRecord {
  Id id = Isar.autoIncrement;

  /// Уникальный id модуля. Индекс — для быстрого поиска по moduleId.
  /// Апсерт (создать-или-обновить) делается вручную в репозитории:
  /// находим существующую запись по moduleId и переиспользуем её
  /// Isar id перед put(). Уникальный индекс здесь — не механизм
  /// апсерта, а защитный барьер на уровне БД: если в апсерт-логике
  /// когда-нибудь появится ошибка, Isar бросит исключение вместо
  /// того, чтобы тихо завести дубликат строки на один и тот же модуль.
  @Index(unique: true)
  late String moduleId;

  /// Состояние жизненного цикла — строка ('installed' | 'enabled' |
  /// 'disabled' | 'uninstalled'), т.е. ModuleState.name. Строка, а не
  /// индекс enum: тот же приём, что и AppSettings.themeMode — порядок
  /// значений enum в коде можно менять, не ломая сохранённые данные.
  late String state;

  /// Версия модуля на момент установки/последнего update().
  late String installedVersion;

  /// Денормализованное зеркало (state == 'enabled'), отдельным полем
  /// по прямому требованию Этапа 9 — позволяет фильтровать по
  /// enabled, не разбирая строку state.
  bool enabled = false;

  late DateTime installedAt;
  late DateTime updatedAt;
}
