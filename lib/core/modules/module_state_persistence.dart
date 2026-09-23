import 'module_manager.dart';
import 'module_registry.dart';
import 'module_state.dart';
import 'module_state_store.dart';
import 'module_storage.dart';
import 'module_storage_isar.dart';

/// Синхронизирует состояние ModuleManager с постоянным хранилищем
/// (Isar) на каждое изменение.
///
/// НЕ содержит ни строки изменений в module_manager.dart — этот файл
/// запрещено трогать на Этапе 9. Вместо этого подписывается на уже
/// существующий ChangeNotifier: ModuleManager и так вызывает
/// notifyListeners() после install/enable/disable/uninstall/update
/// (см. Этап 8) — этого достаточно, чтобы реагировать на все пять
/// операций извне, не меняя оркестратор.
///
/// На каждое уведомление — простая полная пересинхронизация всех
/// известных менеджеру модулей, а не точечный diff одного изменения:
/// проще, корректнее, и оправдано тем, что модулей ожидается немного.
/// Точечную оптимизацию можно добавить позже, не меняя это поведение.
class ModuleStatePersistence {
  ModuleStatePersistence(
    this._manager,
    this._store, {
    ModuleStorage Function(String moduleId)? storageFactory,
  }) : _storageFactory = storageFactory ?? ModuleStorageIsar.new {
    _manager.addListener(_onManagerChanged);
  }

  final ModuleManager _manager;
  final ModuleStateStore _store;
  final ModuleStorage Function(String moduleId) _storageFactory;

  void dispose() {
    _manager.removeListener(_onManagerChanged);
  }

  void _onManagerChanged() {
    // notifyListeners() у ChangeNotifier синхронный — запись в
    // хранилище идёт асинхронно "в фоне"; ошибка записи не должна
    // ронять поток, вызвавший install()/enable()/... .
    // ignore: discarded_futures
    _sync();
  }

  Future<void> _sync() async {
    for (final entry in _manager.states.entries) {
      final moduleId = entry.key;
      final state = entry.value;

      if (state == ModuleState.uninstalled) {
        await _store.delete(moduleId);
        await _clearModuleData(moduleId);
        continue;
      }

      final module = ModuleRegistry.get(moduleId);
      final existing = await _store.load(moduleId);

      await _store.save(ModuleStateSnapshot(
        moduleId: moduleId,
        state: state.name,
        installedVersion: module?.manifest.version ?? existing?.installedVersion ?? '',
        enabled: state == ModuleState.enabled,
        installedAt: existing?.installedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// Стирает все данные модуля через уже существующий контракт
  /// ModuleStorage (Этап 7) — keys()+remove(), без отдельного
  /// bespoke-метода "очистить всё", чтобы не тянуть в этот файл
  /// зависимость от чего-то, кроме уже установленных контрактов.
  Future<void> _clearModuleData(String moduleId) async {
    final storage = _storageFactory(moduleId);
    for (final key in await storage.keys()) {
      await storage.remove(key);
    }
  }
}
