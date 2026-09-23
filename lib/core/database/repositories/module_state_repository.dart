import 'package:isar/isar.dart';

import '../../modules/module_state_store.dart';
import '../isar_service.dart';
import '../models/module_state_record.dart';

/// Репозиторий постоянного состояния модулей — реализация
/// ModuleStateStore (core/modules) поверх Isar.
///
/// Апсерт сделан вручную (найти существующую запись по moduleId,
/// переиспользовать её id, затем put()), а не через `@Index(...,
/// replace: true)` — Isar такое умеет, но синтаксис для этой версии
/// пакета не проверен компилятором в этой среде, а ручной апсерт
/// использует только базовые операции Isar (filter/findFirst/put),
/// которые уже используются в остальном проекте (Этап 2).
class ModuleStateRepository implements ModuleStateStore {
  Isar get _isar => IsarService.instance;

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async {
    final records = await _isar.moduleStateRecords.where().findAll();
    return records.map(_toSnapshot).toList();
  }

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async {
    final record = await _findRecord(moduleId);
    return record == null ? null : _toSnapshot(record);
  }

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    await _isar.writeTxn(() async {
      final existing = await _findRecord(snapshot.moduleId);

      final record = ModuleStateRecord()
        ..moduleId = snapshot.moduleId
        ..state = snapshot.state
        ..installedVersion = snapshot.installedVersion
        ..enabled = snapshot.enabled
        ..installedAt = snapshot.installedAt
        ..updatedAt = snapshot.updatedAt;

      if (existing != null) {
        record.id = existing.id; // апсерт: тот же id — Isar обновит строку
      }

      await _isar.moduleStateRecords.put(record);
    });
  }

  @override
  Future<void> delete(String moduleId) async {
    await _isar.writeTxn(() async {
      final existing = await _findRecord(moduleId);
      if (existing != null) {
        await _isar.moduleStateRecords.delete(existing.id);
      }
    });
  }

  Future<ModuleStateRecord?> _findRecord(String moduleId) {
    return _isar.moduleStateRecords
        .filter()
        .moduleIdEqualTo(moduleId)
        .findFirst();
  }

  ModuleStateSnapshot _toSnapshot(ModuleStateRecord record) {
    return ModuleStateSnapshot(
      moduleId: record.moduleId,
      state: record.state,
      installedVersion: record.installedVersion,
      enabled: record.enabled,
      installedAt: record.installedAt,
      updatedAt: record.updatedAt,
    );
  }
}
