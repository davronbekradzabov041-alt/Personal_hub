/// Снимок состояния модуля и откат (Этап 8.1-А).
///
/// Механизм общий для restore (.pmb) и будущего обновления, поэтому
/// проверяется здесь по контракту, а не по внутренностям: важно
/// СКОЛЬКО и ЧТО именно он возвращает, и что не трогает того, чего не
/// снимал.
library module_snapshot_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_api.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_snapshot.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

class _StubModule extends Module {
  _StubModule(this._manifest);

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> onInstall(ModuleApi api) async {}
}

class _FakeModuleStorage implements ModuleStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

class _FakeStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> records = <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => records.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => records[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async =>
      records[snapshot.moduleId] = snapshot;

  @override
  Future<void> delete(String moduleId) async => records.remove(moduleId);
}

ModuleManifest _manifest() => const ModuleManifest(
      id: 'notes',
      name: 'Заметки',
      version: '1.0.0',
      apiVersion: 1,
      author: 'Test',
    );

void main() {
  late Directory support;
  late ModuleManager manager;
  late _FakeModuleStorage storage;
  late _FakeStateStore store;
  late ModuleSnapshotService snapshots;

  setUp(() {
    ModuleRegistry.clear();
    support = Directory.systemTemp.createTempSync('module_snapshot_test');
    storage = _FakeModuleStorage();
    store = _FakeStateStore();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => storage,
    );
    // Строится именно здесь: `late ... = buildSnapshots()` вычислялся
    // бы один раз на весь файл и держал бы менеджер ПЕРВОГО теста —
    // откат во втором тесте пошёл бы по данным первого.
    snapshots = ModuleSnapshotService(
      moduleManager: manager,
      stateStore: store,
      assetsDirectoryResolver: (moduleId) async =>
          Directory('${support.path}/modules/$moduleId/assets'),
    );

    ModuleRegistry.register(_StubModule(_manifest()));
    manager.setStateForTesting('notes', ModuleState.enabled);
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  Directory assetsDir() => Directory('${support.path}/modules/notes/assets');

  group('снятие снимка', () {
    test('хранилище, состояние и ассеты попадают в снимок', () async {
      await storage.setString('note:1', 'черновик');
      await storage.setString('schema:version', '3');
      await store.save(ModuleStateSnapshot(
        moduleId: 'notes',
        state: 'enabled',
        installedVersion: '1.0.0',
        enabled: true,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      await assetsDir().create(recursive: true);
      File('${assetsDir().path}/logo.png').writeAsBytesSync([1, 2, 3]);

      final snapshot = await snapshots.capture(moduleId: 'notes');

      expect(snapshot.storage, {'note:1': 'черновик', 'schema:version': '3'});
      expect(snapshot.state?.installedVersion, '1.0.0');
      expect(snapshot.managerState, ModuleState.enabled);
      expect(snapshot.assets.keys, ['logo.png']);
      expect(snapshot.assets['logo.png'], [1, 2, 3]);
      expect(snapshot.assetsDirExisted, isTrue);
    });

    test('снимаются только запрошенные компоненты', () async {
      await storage.setString('note:1', 'черновик');
      await assetsDir().create(recursive: true);
      File('${assetsDir().path}/logo.png').writeAsBytesSync([9]);

      final snapshot = await snapshots.capture(
        moduleId: 'notes',
        components: const {ModuleSnapshotComponent.storage},
      );

      expect(snapshot.captured(ModuleSnapshotComponent.storage), isTrue);
      expect(snapshot.captured(ModuleSnapshotComponent.assets), isFalse);
      expect(snapshot.assets, isEmpty);
      expect(snapshot.storage.keys, ['note:1']);
    });
  });

  group('откат', () {
    test('возвращает перезаписанные значения и убирает новые ключи', () async {
      await storage.setString('note:1', 'черновик');
      await storage.setString('note:2', 'второй');

      final snapshot = await snapshots.capture(moduleId: 'notes');

      // Операция поверх снимка: перезаписала ключ, добавила ключ,
      // удалила ключ.
      await storage.setString('note:1', 'ПЕРЕЗАПИСАНО');
      await storage.setString('note:3', 'новый');
      await storage.remove('note:2');

      final rolledBack = await snapshots.rollback(
        snapshot,
        attemptedComponents: const [ModuleSnapshotComponent.storage],
      );

      expect(rolledBack, ['data']);
      expect(storage.data, {'note:1': 'черновик', 'note:2': 'второй'});
    });

    test('возвращает состояние и в хранилище, и в менеджере', () async {
      await store.save(ModuleStateSnapshot(
        moduleId: 'notes',
        state: 'enabled',
        installedVersion: '1.0.0',
        enabled: true,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      final snapshot = await snapshots.capture(
        moduleId: 'notes',
        components: const {ModuleSnapshotComponent.state},
      );

      // Операция успела перевести модуль в disabled и записать это в
      // хранилище состояния.
      await manager.disable('notes');
      await store.save(ModuleStateSnapshot(
        moduleId: 'notes',
        state: 'disabled',
        installedVersion: '1.1.0',
        enabled: false,
        installedAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      expect(manager.stateOf('notes'), ModuleState.disabled);

      await snapshots.rollback(
        snapshot,
        attemptedComponents: const [ModuleSnapshotComponent.state],
      );

      expect(manager.stateOf('notes'), ModuleState.enabled);
      expect(store.records['notes']!.state, 'enabled');
    });

    test('возвращает ассеты и удаляет добавленные', () async {
      await assetsDir().create(recursive: true);
      File('${assetsDir().path}/logo.png').writeAsBytesSync([1, 2, 3]);
      final snapshot = await snapshots.capture(moduleId: 'notes');

      File('${assetsDir().path}/logo.png').deleteSync();
      File('${assetsDir().path}/new.png').writeAsBytesSync([7]);

      await snapshots.rollback(
        snapshot,
        attemptedComponents: const [ModuleSnapshotComponent.assets],
      );

      expect(File('${assetsDir().path}/logo.png').readAsBytesSync(), [1, 2, 3]);
      expect(File('${assetsDir().path}/new.png').existsSync(), isFalse);
    });

    test('удаляет каталог ассетов, которого не было до операции', () async {
      final snapshot = await snapshots.capture(
        moduleId: 'notes',
        components: const {ModuleSnapshotComponent.assets},
      );
      expect(snapshot.assetsDirExisted, isFalse);

      await assetsDir().create(recursive: true);
      File('${assetsDir().path}/logo.png').writeAsBytesSync([1]);

      await snapshots.rollback(
        snapshot,
        attemptedComponents: const [ModuleSnapshotComponent.assets],
      );

      expect(assetsDir().existsSync(), isFalse);
    });

    test('не трогает то, чего не снимал', () async {
      await storage.setString('note:1', 'черновик');
      final snapshot = await snapshots.capture(
        moduleId: 'notes',
        components: const {ModuleSnapshotComponent.storage},
      );

      await storage.setString('note:9', 'чужое');

      // В attempted — ассеты, но снимок их не снимал: откат обязан
      // промолчать, а не «восстанавливать» неизвестное.
      final rolledBack = await snapshots.rollback(
        snapshot,
        attemptedComponents: const [ModuleSnapshotComponent.assets],
      );

      expect(rolledBack, isEmpty);
      expect(storage.getString('note:9'), completion('чужое'));
    });

    test('принимает и строковые имена компонентов — как у restore', () async {
      await storage.setString('note:1', 'черновик');
      final snapshot = await snapshots.capture(
        moduleId: 'notes',
        components: const {ModuleSnapshotComponent.storage},
      );
      await storage.setString('note:1', 'изменено');

      final rolledBack = await snapshots.rollback(
        snapshot,
        attemptedComponents: const ['data'],
      );

      expect(rolledBack, ['data']);
      expect(storage.getString('note:1'), completion('черновик'));
    });

    test('неизвестный компонент — явная ошибка, а не тихий успех', () async {
      final snapshot = await snapshots.capture(moduleId: 'notes');

      // Молча пропустить такой компонент означало бы «откат удался»,
      // хотя ничего не откатилось.
      await expectLater(
        snapshots.rollback(
          snapshot,
          attemptedComponents: const ['schema', 'data'],
        ),
        throwsA(isA<ModuleSnapshotRollbackException>()),
      );
    });
  });
}