import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/external/in_memory_module_catalog.dart';
import 'package:personal_hub/core/modules/external/manifest_parser.dart';
import 'package:personal_hub/core/modules/external/module_import_result.dart';
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

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Тот же путь, что и AvailableSection._install() в UI — parse →
/// validate → register → install, без единой строчки, дублирующей
/// эту логику отдельно для тестов.
Future<Module?> _installFromCatalog(
  ModuleManager manager,
  ModuleCatalogEntry entry, {
  List<String>? errorsOut,
}) async {
  final existingIds = ModuleRegistry.modules.map((m) => m.id).toSet();
  final result = ModuleImportResult.from(
    manifestJson: entry.installManifestJson,
    existingModuleIds: existingIds,
  );
  if (!result.isSuccess) {
    errorsOut?.addAll(result.errors);
    return null;
  }
  final adapter = ExternalModuleAdapter(result.package!.manifest);
  ModuleRegistry.register(adapter);
  await manager.install(adapter.id);
  return adapter;
}

void main() {
  late GlobalSearchService searchService;
  late ModuleManager manager;
  late _FakeModuleStateStore store;
  late ModuleStatePersistence persistence;

  final notesLite =
      InMemoryModuleCatalog.entries.firstWhere((e) => e.id == 'notes-lite');
  final exampleEntry =
      InMemoryModuleCatalog.entries.firstWhere((e) => e.id == 'example');

  setUp(() {
    ModuleRegistry.clear();
    searchService = GlobalSearchService();
    manager = ModuleManager(
      searchService: searchService,
      storageFactory: _FakeModuleStorageFactory().call,
    );
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

  test('установка из каталога', () async {
    final module = await _installFromCatalog(manager, notesLite);
    expect(module, isNotNull);
    expect(manager.isInstalled('notes-lite'), isTrue);
    expect(ModuleRegistry.contains('notes-lite'), isTrue);
  });

  test('повторная установка запрещена', () async {
    await _installFromCatalog(manager, notesLite);

    final errors = <String>[];
    final second = await _installFromCatalog(manager, notesLite, errorsOut: errors);

    expect(second, isNull);
    expect(errors, isNotEmpty);
    expect(errors.any((e) => e.contains('уже занят')), isTrue);
  });

  test('установка "example" из каталога отклоняется — id уже занят встроенным модулем', () async {
    // Симулирует то, что в реальном приложении делает module_bootstrap.dart —
    // 'example' уже зарегистрирован кодом задолго до открытия Module Store.
    ModuleRegistry.register(_MinimalModule(const ModuleManifest(
      id: 'example',
      name: 'Встроенный пример',
      version: '0.1.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Personal Hub',
    )));

    final errors = <String>[];
    final result = await _installFromCatalog(manager, exampleEntry, errorsOut: errors);

    expect(result, isNull);
    expect(errors.any((e) => e.contains('уже занят')), isTrue);
  });

  test('enable/disable работают', () async {
    await _installFromCatalog(manager, notesLite);

    await manager.enable('notes-lite');
    expect(manager.stateOf('notes-lite'), ModuleState.enabled);

    await manager.disable('notes-lite');
    expect(manager.stateOf('notes-lite'), ModuleState.disabled);
  });

  test('uninstall удаляет состояние и данные, но сохраняет tombstone', () async {
    await _installFromCatalog(manager, notesLite);
    await manager.enable('notes-lite');
    await manager.disable('notes-lite');
    await manager.uninstall('notes-lite');
    await _flush();

    expect(manager.isInstalled('notes-lite'), isFalse);
    final saved = await store.load('notes-lite');
    expect(saved, isNotNull);
    expect(saved!.state, 'uninstalled');
    expect(saved.enabled, isFalse);
  });

  test('update меняет версию', () async {
    await _installFromCatalog(manager, notesLite);
    expect(ModuleRegistry.get('notes-lite')!.manifest.version, '1.0.0');

    final latest = ManifestParser().parse(notesLite.latestManifestJson);
    await manager.update(ExternalModuleAdapter(latest));

    expect(ModuleRegistry.get('notes-lite')!.manifest.version, '1.1.0');
  });

  test('после перезапуска состояние сохраняется', () async {
    await _installFromCatalog(manager, notesLite);
    await manager.enable('notes-lite');
    await _flush();

    // "Перезапуск": новый ModuleManager поверх того же хранилища.
    // ModuleRegistry сохраняет объект модуля (как и в реальном
    // приложении код модулей остаётся скомпилирован между запусками)
    // — восстановление работает через уже зарегистрированный adapter.
    final freshManager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: _FakeModuleStorageFactory().call,
    );
    await ModuleStateRestorer(freshManager, store).restore();

    expect(freshManager.stateOf('notes-lite'), ModuleState.enabled);
  });
}

class _MinimalModule extends Module {
  _MinimalModule(this._manifest);
  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => throw UnimplementedError();

  @override
  Widget buildPage(BuildContext context) => throw UnimplementedError();
}
