import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_restorer.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

/// Минимальный тестовый модуль — не завязан на Isar/Flutter-виджеты,
/// buildPage не проверяется этими тестами.
class _FakeModule extends Module {
  _FakeModule(this._manifest);
  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

/// Фейковая in-memory реализация ModuleStateStore — заменяет Isar,
/// которого в этой среде нет возможности прогнать через кодогенерацию.
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

/// Фейковая фабрика ModuleStorage — один общий backing-map на moduleId,
/// доступный тесту напрямую, чтобы проверить, что uninstall действительно
/// стирает данные модуля (а не только запись состояния).
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

/// ModuleStatePersistence реагирует на notifyListeners() асинхронно,
/// без ожидания (fire-and-forget) — эта задержка даёт фоновой записи
/// шанс завершиться перед проверкой.
Future<void> _letSyncFinish() => Future<void>.delayed(Duration.zero);

void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _FakeModuleStateStore store;
  late _FakeModuleStorageFactory storageFactory;
  late ModuleStatePersistence persistence;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(_FakeModule(const ModuleManifest(
      id: 'demo',
      name: 'Demo',
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    )));

    searchService = GlobalSearchService();
    manager = ModuleManager(searchService: searchService);
    store = _FakeModuleStateStore();
    storageFactory = _FakeModuleStorageFactory();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: storageFactory.call,
    );
  });

  tearDown(() {
    persistence.dispose();
    ModuleRegistry.clear();
  });

  test('install → сохраняется', () async {
    await manager.install('demo');
    await _letSyncFinish();

    final saved = await store.load('demo');
    expect(saved, isNotNull);
    expect(saved!.state, 'installed');
    expect(saved.enabled, isFalse);
  });

  test('enable → сохраняется', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await _letSyncFinish();

    final saved = await store.load('demo');
    expect(saved!.state, 'enabled');
    expect(saved.enabled, isTrue);
  });

  test('disable → сохраняется', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await manager.disable('demo');
    await _letSyncFinish();

    final saved = await store.load('demo');
    expect(saved!.state, 'disabled');
    expect(saved.enabled, isFalse);
  });

  test('uninstall → запись и данные удаляются', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await storageFactory.call('demo').setString('note', 'hello');
    await manager.disable('demo');
    await manager.uninstall('demo');
    await _letSyncFinish();

    final saved = await store.load('demo');
    expect(saved, isNull);
    expect(storageFactory.buckets['demo'], isEmpty);
  });

  test('restart → состояние восстанавливается', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await _letSyncFinish();

    // "Перезапуск": новый ModuleManager поверх того же хранилища —
    // как при холодном старте приложения (main.dart создаёт менеджер
    // заново на каждый запуск, состояние переживает только в Isar).
    final freshManager = ModuleManager(searchService: GlobalSearchService());
    await ModuleStateRestorer(freshManager, store).restore();

    expect(freshManager.stateOf('demo'), ModuleState.enabled);
  });

  test('restart → disabled модуль восстанавливается как disabled', () async {
    await manager.install('demo');
    await manager.enable('demo');
    await manager.disable('demo');
    await _letSyncFinish();

    final freshManager = ModuleManager(searchService: GlobalSearchService());
    await ModuleStateRestorer(freshManager, store).restore();

    expect(freshManager.stateOf('demo'), ModuleState.disabled);
  });
}
