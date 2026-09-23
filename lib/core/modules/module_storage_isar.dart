import 'package:isar/isar.dart';

import '../database/isar_service.dart';
import '../database/models/module_data_row.dart';
import 'module_storage.dart';

/// Isar-реализация ModuleStorage (контракт — Этап 7).
///
/// Один экземпляр обслуживает один moduleId: все запросы
/// автоматически фильтруются по нему, поэтому данные разных модулей
/// физически лежат в одной коллекции (ModuleDataRow), но никогда не
/// смешиваются на уровне API — у модуля просто нет способа запросить
/// чужой moduleId, он ему не виден через ModuleStorage.
class ModuleStorageIsar implements ModuleStorage {
  ModuleStorageIsar(this.moduleId);

  final String moduleId;

  Isar get _isar => IsarService.instance;

  @override
  Future<String?> getString(String key) async {
    final row = await _findRow(key);
    return row?.jsonValue;
  }

  @override
  Future<void> setString(String key, String value) async {
    await _isar.writeTxn(() async {
      final existing = await _findRow(key);

      final row = ModuleDataRow()
        ..moduleId = moduleId
        ..key = key
        ..jsonValue = value;

      if (existing != null) {
        row.id = existing.id; // апсерт
      }

      await _isar.moduleDataRows.put(row);
    });
  }

  @override
  Future<void> remove(String key) async {
    await _isar.writeTxn(() async {
      final existing = await _findRow(key);
      if (existing != null) {
        await _isar.moduleDataRows.delete(existing.id);
      }
    });
  }

  @override
  Future<List<String>> keys() async {
    final rows = await _isar.moduleDataRows
        .filter()
        .moduleIdEqualTo(moduleId)
        .findAll();
    return rows.map((r) => r.key).toList();
  }

  Future<ModuleDataRow?> _findRow(String key) {
    return _isar.moduleDataRows
        .filter()
        .moduleIdEqualTo(moduleId)
        .keyEqualTo(key)
        .findFirst();
  }
}
