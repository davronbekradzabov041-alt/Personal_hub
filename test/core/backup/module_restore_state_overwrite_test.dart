/// R-01: восстановленное из .pmb состояние не затирается следующей
/// синхронизацией ModuleStatePersistence.
///
/// Root cause: ModuleBackupManager._applyState() писал снимок напрямую в
/// ModuleStateStore, оставляя ModuleManager._states прежним. Persistence
/// читает источник истины именно из ModuleManager.states, поэтому любая
/// последующая синхронизация (а она запускается на ЛЮБОЕ
/// notifyListeners, то есть на lifecycle-операцию ЛЮБОГО модуля)
/// записывала старое состояние обратно — и результат restore исчез.
///
/// Фикс: ModuleManager.adoptRestoredState() — единственный вход, который
/// принимает внешний снимок как авторитетное состояние. Он же
/// используется при откате неудачного restore, поэтому «частично
/// обновлённый менеджер» невозможен.
///
/// Значения состояния и версии различаются намеренно: 'installed'/9.9.9
/// из архива нельзя перепутать с 'enabled'/1.0.0 из живого модуля.
library module_restore_state_overwrite_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_lifecycle_error.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ModuleManager manager;
  late _MemoryStateStore store;
  late ModuleStatePersistence persistence;
  late ModuleBackupManager backupManager;
  late Directory outputDir;

  // stateOnly(): интересует только компонент state, поэтому sandbox и
  // path_provider не нужны — их отсутствие не маскирует проверку.
  const stateOnly = ModuleBackupOptions.stateOnly();

  setUp(() async {
    ModuleRegistry.clear();
    ModuleRegistry.register(
      ExternalModuleAdapter(ModuleManifest.fromJson(_manifest('alpha'))),
    );
    ModuleRegistry.register(
      ExternalModuleAdapter(ModuleManifest.fromJson(_manifest('beta'))),
    );

    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => _MemoryModuleStorage(),
    );
    store = _MemoryStateStore();
    persistence = ModuleStatePersistence(
      manager,
      store,
      storageFactory: (_) => _MemoryModuleStorage(),
    );
    backupManager = ModuleBackupManager(
      moduleManager: manager,
      stateStore: store,
    );
    outputDir = await Directory.systemTemp.createTemp('r01_out_');
  });

  tearDown(() async {
    persistence.dispose();
    ModuleRegistry.clear();
    try {
      await outputDir.delete(recursive: true);
    } catch (_) {
      // временный каталог мог быть уже удалён
    }
  });

  /// Кладёт в архив состояние [archivedState]/[archivedVersion] и
  /// переключает живой модуль в [liveState]. Возвращает байты .pmb.
  Future<List<int>> archiveWith({
    required String moduleId,
    required String archivedState,
    required String archivedVersion,
    required ModuleState liveState,
    ModuleBackupOptions options = stateOnly,
  }) async {
    await manager.install(moduleId);
    store.seed(_snapshot(moduleId, archivedState, archivedVersion));

    final created = await backupManager.createBackup(
      moduleId: moduleId,
      outputDirectory: outputDir,
      options: options,
    );
    final archive = await File(created.outputPath).readAsBytes();

    await _moveTo(manager, moduleId, liveState);
    await persistence.flush();

    return archive;
  }

  group('R-01: переходы состояния после restore', () {
    test('enabled → installed: восстановленное состояние переживает sync',
        () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      final before = await store.load('alpha');
      expect(before!.state, 'enabled');
      expect(manager.stateOf('alpha'), ModuleState.enabled);

      final restored = await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(restored.appliedComponents, contains('state'));

      // Источник истины — менеджер. Если он не принял состояние из
      // архива, следующая синхронизация вернёт старое.
      expect(
        manager.stateOf('alpha'),
        ModuleState.installed,
        reason: 'ModuleManager обязан принять восстановленное состояние',
      );

      // Синхронизацию запускает операция СОВСЕМ ДРУГОГО модуля — так
      // и выглядел баг: чужое действие откатывало чужой restore.
      await manager.install('beta');
      await persistence.flush();

      final after = await store.load('alpha');
      expect(
        after!.state,
        'installed',
        reason: 'синхронизация не должна возвращать старое состояние поверх restore',
      );
      expect(manager.stateOf('alpha'), ModuleState.installed);
    });

    test('installed → enabled: модуль остаётся активным после sync', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'enabled',
        archivedVersion: '9.9.9',
        liveState: ModuleState.installed,
      );

      final restored = await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(manager.stateOf('alpha'), ModuleState.enabled);

      await manager.install('beta');
      await persistence.flush();

      final after = await store.load('alpha');
      expect(after!.state, 'enabled',
          reason: 'восстановленный enabled обязан уцелеть');
      expect(manager.stateOf('alpha'), ModuleState.enabled);
    });

    test('disabled → enabled: тоже принимается', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'enabled',
        archivedVersion: '2.0.0',
        liveState: ModuleState.disabled,
      );

      final restored = await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(manager.stateOf('alpha'), ModuleState.enabled);

      await persistence.flush();
      expect((await store.load('alpha'))!.state, 'enabled');
    });
  });

  group('R-01: один источник истины', () {
    test('менеджер и хранилище согласованы сразу после restore', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      await persistence.flush();

      final inMemory = manager.stateOf('alpha')!;
      final persisted = (await store.load('alpha'))!;
      expect(persisted.state, inMemory.name,
          reason: 'два источника истины разошлись — это и есть R-01 в чистом виде');
      expect(inMemory, ModuleState.installed);
    });

    test('версию хранилища определяет ModuleRegistry, а не архив', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      await persistence.flush();

      final persisted = (await store.load('alpha'))!;
      // Версия кода живёт в ModuleRegistry (manifest.version); колонка
      // installedVersion в хранилище — денормализованное зеркало, и
      // ModuleStatePersistence._sync() всегда переписывает его из
      // реестра. Значение 9.9.9 описывает архив, а не установленный код,
      // поэтому после sync оно обязано уступить версии реестра — иначе
      // в приложении появился бы второй источник истины о версии.
      expect(persisted.installedVersion, '1.0.0');
      expect(
        ModuleRegistry.get('alpha')!.manifest.version,
        persisted.installedVersion,
        reason: 'установленная версия обязана совпадать с реестром',
      );
      expect(persisted.state, 'installed',
          reason: 'версия не должна выкупать потерю состояния');
    });
  });

  group('R-01: обычный lifecycle работает относительно restore', () {
    test('enable() после restore в installed', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );
      await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      expect(manager.stateOf('alpha'), ModuleState.installed);

      await manager.enable('alpha');
      await persistence.flush();

      expect(manager.stateOf('alpha'), ModuleState.enabled);
      expect((await store.load('alpha'))!.state, 'enabled');
    });

    test('disable() после restore в enabled', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'enabled',
        archivedVersion: '9.9.9',
        liveState: ModuleState.installed,
      );
      await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );
      expect(manager.stateOf('alpha'), ModuleState.enabled);

      await manager.disable('alpha');
      await persistence.flush();

      expect(manager.stateOf('alpha'), ModuleState.disabled);
      expect((await store.load('alpha'))!.state, 'disabled');
    });

    test('enable() после restore в enabled отвергается как «уже включён»',
        () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'enabled',
        archivedVersion: '9.9.9',
        liveState: ModuleState.installed,
      );
      await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );

      await expectLater(
        manager.enable('alpha'),
        throwsA(isA<ModuleLifecycleError>()),
      );
    });
  });

  group('R-01: несуществующий и неустановленный модуль', () {
    test('restore в незарегистрированный moduleId отклоняется', () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      await expectLater(
        backupManager.restoreBackup(
          archiveBytes: archive,
          targetModuleId: 'gamma',
          options: stateOnly,
        ),
        throwsA(isA<BackupException>()),
      );

      expect(manager.stateOf('gamma'), isNull);
      expect(manager.stateOf('alpha'), ModuleState.enabled,
          reason: 'отказ не должен трогать другие модули');
    });

    test('restore в незарегистрированный модуль не пишет его состояние',
        () async {
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'installed',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      await expectLater(
        backupManager.restoreBackup(
          archiveBytes: archive,
          targetModuleId: 'gamma',
          options: stateOnly,
        ),
        throwsA(isA<BackupException>()),
      );
      expect(await store.load('gamma'), isNull);
    });

    test('adoptRestoredState отвергает незарегистрированный модуль', () async {
      await expectLater(
        manager.adoptRestoredState(_snapshot('gamma', 'installed', '1.0.0')),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('gamma'), isNull);
    });

    test('adoptRestoredState отвергает зарегистрированный, но не установленный',
        () async {
      expect(manager.stateOf('alpha'), isNull);

      await expectLater(
        manager.adoptRestoredState(_snapshot('alpha', 'enabled', '1.0.0')),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('alpha'), isNull,
          reason: 'отказ не должен создавать состояние');
    });
  });

  group('R-01: контракт adoptRestoredState', () {
    test('пустой moduleId отвергается', () async {
      await manager.install('alpha');

      await expectLater(
        manager.adoptRestoredState(_snapshot('   ', 'installed', '1.0.0')),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('alpha'), ModuleState.installed);
    });

    test('неизвестное имя состояния отвергается', () async {
      await manager.install('alpha');
      await manager.enable('alpha');

      await expectLater(
        manager.adoptRestoredState(_snapshot('alpha', 'frozen', '1.0.0')),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('alpha'), ModuleState.enabled,
          reason: 'битое состояние не должно менять живое');
    });

    test('принятие текущего состояния — тихий no-op без notify', () async {
      await manager.install('alpha');
      await manager.enable('alpha');

      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.adoptRestoredState(_snapshot('alpha', 'enabled', '1.0.0'));

      expect(notifications, 0,
          reason: 'ничего не изменилось — значит и слушателям нечего сообщать');
      expect(manager.stateOf('alpha'), ModuleState.enabled);
    });

    test('installed → disabled и обратно меняют только пометку', () async {
      await manager.install('alpha');

      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.adoptRestoredState(_snapshot('alpha', 'disabled', '1.0.0'));
      expect(manager.stateOf('alpha'), ModuleState.disabled);

      await manager.adoptRestoredState(_snapshot('alpha', 'installed', '1.0.0'));
      expect(manager.stateOf('alpha'), ModuleState.installed);

      expect(notifications, 2,
          reason: 'каждый переход — ровно одно уведомление, без промежуточных');
    });

    test('переход в uninstalled запрещён', () async {
      await manager.install('alpha');
      await manager.enable('alpha');

      await expectLater(
        manager.adoptRestoredState(_snapshot('alpha', 'uninstalled', '1.0.0')),
        throwsA(isA<ModuleLifecycleError>()),
      );
      expect(manager.stateOf('alpha'), ModuleState.enabled);
    });
  });

  group('R-01: builtin и tombstone-семантика', () {
    test('архив со state=uninstalled отклоняется и не стирает данные',
        () async {
      // uninstalled — это tombstone: ModuleStatePersistence на него
      // реагирует очисткой ВСЕХ данных модуля и записью, которая на
      // холодном старте запрещает авто-установку встроенного модуля.
      // .pmb восстанавливает данные, а не удаляет их, поэтому такое
      // состояние принять нельзя.
      final archive = await archiveWith(
        moduleId: 'alpha',
        archivedState: 'uninstalled',
        archivedVersion: '9.9.9',
        liveState: ModuleState.enabled,
      );

      await manager.apiFor('alpha').storage.setString('keep', 'me');

      final restored = await backupManager.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateOnly,
      );

      expect(restored.isSuccess, isFalse);
      expect(restored.error, isA<ModuleLifecycleError>());
      expect(restored.rolledBackComponents, contains('state'));

      expect(manager.stateOf('alpha'), ModuleState.enabled,
          reason: 'отказ не должен оставить модуль в tombstone');
      expect((await store.load('alpha'))!.state, 'enabled');

      await persistence.flush();
      expect((await store.load('alpha'))!.state, 'enabled',
          reason: 'синхронизация не должна превратить это в tombstone');
      expect(await manager.apiFor('alpha').storage.getString('keep'), 'me',
          reason: 'данные модуля обязаны уцелеть');
    });
  });

  group('R-01: неудачный restore не оставляет частичный manager state', () {
    test('сбой записи данных откатывает и состояние ModuleManager',
        () async {
      const stateAndData =
          ModuleBackupOptions(includeState: true, includeData: true, includeAssets: false);

      // 1. Архив: state=installed/9.9.9 + данные модуля.
      await manager.install('alpha');
      await manager.apiFor('alpha').storage.setString('k', 'v');
      store.seed(_snapshot('alpha', 'installed', '9.9.9'));

      final created = await backupManager.createBackup(
        moduleId: 'alpha',
        outputDirectory: outputDir,
        options: stateAndData,
      );
      final archive = await File(created.outputPath).readAsBytes();

      // 2. Отдельный менеджер, у которого запись в storage падает:
      //    state успеет примениться (и менеджер его примет), data — нет,
      //    после чего включится откат.
      final targetStore = _MemoryStateStore();
      final target = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (_) => _MemoryModuleStorage(failOnSet: true),
      );
      final targetPersistence = ModuleStatePersistence(
        target,
        targetStore,
        storageFactory: (_) => _MemoryModuleStorage(),
      );
      addTearDown(targetPersistence.dispose);

      final targetBackup = ModuleBackupManager(
        moduleManager: target,
        stateStore: targetStore,
      );

      await target.install('alpha');
      await target.enable('alpha');
      await targetPersistence.flush();
      expect(target.stateOf('alpha'), ModuleState.enabled);

      // 3. Restore обязан провалиться и откатить ВСЁ, включая память.
      final restored = await targetBackup.restoreBackup(
        archiveBytes: archive,
        targetModuleId: 'alpha',
        options: stateAndData,
      );

      expect(restored.isSuccess, isFalse);
      expect(restored.appliedComponents, contains('state'),
          reason: 'state к этому моменту уже применён — иначе тест не проверяет откат');
      expect(restored.rolledBackComponents, contains('state'));
      expect(restored.rolledBackComponents, contains('data'));

      expect(
        target.stateOf('alpha'),
        ModuleState.enabled,
        reason: 'менеджер обязан вернуться к состоянию ДО restore',
      );

      await targetPersistence.flush();
      expect((await targetStore.load('alpha'))!.state, 'enabled',
          reason: 'после отката синхронизация обязана писать прежнее состояние');
    });
  });
}

/// Переводит модуль в [target] через настоящий lifecycle.
Future<void> _moveTo(ModuleManager manager, String moduleId, ModuleState target) async {
  switch (target) {
    case ModuleState.installed:
      // Модуль уже установлен архивом выше; снять активность.
      if (manager.stateOf(moduleId) == ModuleState.enabled) {
        await manager.disable(moduleId);
      }
    case ModuleState.enabled:
      if (manager.stateOf(moduleId) == ModuleState.installed) {
        await manager.enable(moduleId);
      }
    case ModuleState.disabled:
      if (manager.stateOf(moduleId) == ModuleState.enabled) {
        await manager.disable(moduleId);
      }
    case ModuleState.uninstalled:
      throw StateError('uninstall в фикстуре не используется');
  }
}

final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(1000000);

ModuleStateSnapshot _snapshot(
  String moduleId,
  String state,
  String installedVersion,
) {
  return ModuleStateSnapshot(
    moduleId: moduleId,
    state: state,
    installedVersion: installedVersion,
    enabled: state == 'enabled',
    installedAt: _t0,
    updatedAt: _t0,
  );
}

Map<String, dynamic> _manifest(String id, {String version = '1.0.0'}) {
  return {
    'id': id,
    'name': 'Module $id',
    'version': version,
    'apiVersion': 1,
    'author': 'Test',
    'description': 'R-01 fixture',
    'permissions': <String>[],
    'dependencies': <String>[],
    'icon': 'assets/icon.png',
  };
}

class _MemoryStateStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> _data = <String, ModuleStateSnapshot>{};

  void seed(ModuleStateSnapshot snapshot) => _data[snapshot.moduleId] = snapshot;

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => _data.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => _data[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    _data[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async => _data.remove(moduleId);
}

class _MemoryModuleStorage implements ModuleStorage {
  _MemoryModuleStorage({this.failOnSet = false});

  /// Моделирует отказ хранилища на середине restore: state к этому
  /// моменту уже применён, data — нет.
  final bool failOnSet;

  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failOnSet) throw StateError('хранилище недоступно');
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}
