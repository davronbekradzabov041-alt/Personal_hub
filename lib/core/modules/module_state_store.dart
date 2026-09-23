/// Снимок постоянного состояния одного модуля — DB-независимое
/// представление (никаких Isar-типов), чтобы код, который его
/// использует (ModuleStatePersistence, ModuleStateRestorer), не
/// зависел напрямую от core/database и было чем подменить хранилище
/// в тестах без реального Isar.
class ModuleStateSnapshot {
  final String moduleId;
  final String state;
  final String installedVersion;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;

  const ModuleStateSnapshot({
    required this.moduleId,
    required this.state,
    required this.installedVersion,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
  });
}

/// Контракт постоянного хранилища состояния модулей.
///
/// Реализация поверх Isar — ModuleStateRepository (core/database).
/// Тесты используют фейковую in-memory реализацию этого же контракта
/// вместо настоящего Isar (в этой среде нет Flutter/Dart SDK, чтобы
/// прогнать Isar-кодогенерацию и проверить, что Isar-путь компилируется).
abstract class ModuleStateStore {
  Future<List<ModuleStateSnapshot>> loadAll();
  Future<ModuleStateSnapshot?> load(String moduleId);
  Future<void> save(ModuleStateSnapshot snapshot);
  Future<void> delete(String moduleId);
}
