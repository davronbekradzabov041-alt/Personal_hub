import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/builtin_module_installer.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_restorer.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/modules/example/example_module.dart';

class _FakeModuleStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = {};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    _data.remove(moduleId);
  }
}

class _FakeModuleStorageFactory {
  final Map<String, Map<String, String>> buckets = {};

  ModuleStorage call(String moduleId) {
    final bucket = buckets.putIfAbsent(moduleId, () => {});
    return _FakeModuleStorage(bucket);
  }
}

class _FakeModuleStorage implements ModuleStorage {
  _FakeModuleStorage(this._bucket);
  final Map<String, String> _bucket;

  @override
  Future<String?> getString(String key) async => _bucket[key];

  @override
  Future<void> setString(String key, String value) async {
    _bucket[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _bucket.remove(key);
  }

  @override
  Future<List<String>> keys() async => _bucket.keys.toList();
}

/// Персистентность синхронизируется асинхронно, без ожидания —
/// эта пауза даёт фоновой записи шанс завершиться перед проверкой.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _FakeModuleStateStore store;
  late ModuleStatePersistence persistence;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(ExampleModule());

    searchService = GlobalSearchService();
    manager = ModuleManager(searchService: searchService);
    store = _FakeModuleStateStore();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: _FakeModuleStorageFactory().call,
    );
  });

  tearDown(() {
    persistence.dispose();
    ModuleRegistry.clear();
  });

  test('модуль автоматически регистрируется', () {
    expect(ModuleRegistry.contains('example'), isTrue);
    expect(ModuleRegistry.get('example')!.manifest.id, 'example');
    expect(ModuleRegistry.get('example')!.manifest.name, 'Модуль-пример');
  });

  test('install работает один раз', () async {
    await ensureBuiltinModulesInstalled(manager, store);
    await _flush();
    expect(manager.stateOf('example'), ModuleState.enabled);

    // Второй вызов — как второй запуск main() — не должен пытаться
    // install() уже известный модуль повторно (ensureBuiltinModulesInstalled
    // сам проверяет store.load() перед этим).
    await ensureBuiltinModulesInstalled(manager, store);
    expect(manager.stateOf('example'), ModuleState.enabled);
  });

  test('enable/disable сохраняются после перезапуска', () async {
    await manager.install('example');
    await manager.enable('example');
    await manager.disable('example');
    await _flush();

    final fresh = ModuleManager(searchService: GlobalSearchService());
    await ModuleStateRestorer(fresh, store).restore();
    expect(fresh.stateOf('example'), ModuleState.disabled);
  });

  test('uninstall очищает состояние и данные, но сохраняет tombstone', () async {
    await manager.install('example');
    await manager.enable('example');
    await manager.disable('example');
    await manager.uninstall('example');
    await _flush();

    final saved = await store.load('example');
    expect(saved, isNotNull);
    expect(saved!.state, 'uninstalled');
    expect(saved.enabled, isFalse);
  });

  test('повторная установка восстанавливает работу', () async {
    await manager.install('example');
    await manager.enable('example');
    await manager.disable('example');
    await manager.uninstall('example');
    await _flush();

    await manager.install('example');
    await manager.enable('example');

    expect(manager.stateOf('example'), ModuleState.enabled);
  });

  test('SearchProvider корректно регистрируется и удаляется', () async {
    expect(searchService.providerCount, 0);

    await manager.install('example');
    await manager.enable('example');
    expect(searchService.providerCount, 1);

    await manager.disable('example');
    expect(searchService.providerCount, 0);
  });
}
