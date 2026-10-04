/// Сквозные интеграционные тесты Stage 6 Backup System.
///
/// Проверяют цепочку UI → [CoreBackupGateway] → core-менеджеры →
/// writer → архив → reader, а также изоляцию, concurrency и rollback
/// на реальных core-классах, а не на фейках.
///
/// Существующие тесты (global_backup_manager_test, module_backup_manager_test,
/// backup_screen_test) не дублируются: здесь закрывается то, чего они
/// не покрывают — слой [CoreBackupGateway], сквозной путь от UI до архива
/// на диске и взаимодействие global/module подсистем между собой.
library backup_integration_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/global_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/backup/module_backup_reader.dart';
import 'package:personal_hub/core/database/isar_service.dart';
// Импортируются ради Isar-расширений (moduleDataRows, moduleStateRecords,
// appSettings), которые объявлены в сгенерированных .g.dart.
import 'package:personal_hub/core/database/models/app_settings.dart';
import 'package:personal_hub/core/database/models/module_data_row.dart';
import 'package:personal_hub/core/database/models/module_state_record.dart';
import 'package:personal_hub/core/database/repositories/module_state_repository.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/module_storage_isar.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/ui/backup/backup_gateway.dart';
import 'package:personal_hub/ui/backup/core_backup_gateway.dart';
import 'package:path/path.dart' as path;

import '../../support/isar_test_init.dart';

/// In-memory ModuleStateStore. Нужен для .pmb: ModuleBackupManager
/// принимает его через конструктор, поэтому Isar не требуется.
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

/// Хранилище, которое умеет один раз «рвано» записать ключ: значение
/// записывается, затем приходит ошибка. Так проверяется откат
/// частично применённой операции (регрессия attempted vs applied).
class _TearOnceStorage implements ModuleStorage {
  _TearOnceStorage(this._bucket);

  final Map<String, String> _bucket;
  String? tearOnKey;
  bool _torn = false;

  @override
  Future<String?> getString(String key) async => _bucket[key];

  @override
  Future<void> setString(String key, String value) async {
    _bucket[key] = value;
    if (!_torn && key == tearOnKey) {
      _torn = true;
      throw StateError('сбой после записи $key');
    }
  }

  @override
  Future<void> remove(String key) async {
    _bucket.remove(key);
  }

  @override
  Future<List<String>> keys() async => _bucket.keys.toList();
}

String _manifestJson(String id) => jsonEncode({
      'id': id,
      'name': 'Модуль $id',
      'version': '1.0.0',
      'apiVersion': 1,
      'author': 'Test',
      'description': 'Integration test module',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': 'assets/icon.png',
    });

ModuleStateSnapshot _snapshot(String moduleId, {String state = 'enabled'}) {
  return ModuleStateSnapshot(
    moduleId: moduleId,
    state: state,
    installedVersion: '1.0.0',
    enabled: true,
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

/// Полная очистка состояния Isar между тестами — иначе данные одного
/// теста протекают в следующий и результаты зависят от порядка.
Future<void> _clearIsar() async {
  final isar = IsarService.instance;
  await isar.writeTxn(() async {
    await isar.moduleDataRows.clear();
    await isar.moduleStateRecords.clear();
    await isar.appSettings.clear();
  });
}

Future<void> _clearSandbox(Directory sandboxRoot) async {
  // ModuleSandbox строит путь как
  // <appDocuments>/personal_hub_modules/modules/<id>, поэтому чистить
  // нужно именно personal_hub_modules, а не modules.
  final modules = Directory(
    path.join(sandboxRoot.path, 'personal_hub_modules', 'modules'),
  );
  if (await modules.exists()) {
    await modules.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandboxRoot;
  late ModuleManager manager;
  late _FakeModuleStateStore stateStore;
  late Map<String, Map<String, String>> moduleBuckets;
  late Map<String, _TearOnceStorage> moduleStorages;
  late CoreBackupGateway gateway;

  setUpAll(() async {
    // Нативная библиотека Isar подключается явно: isar_flutter_libs
    // — плагин, и в flutter test его бинарники не собираются.
    await ensureIsarCoreInitialized();

    sandboxRoot = await Directory.systemTemp.createTemp('backup_it_sandbox_');

    // ModuleSandbox и IsarService оба идут в path_provider, поэтому
    // один мок обслуживает и файловую систему модулей, и базу.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => sandboxRoot.path,
    );

    await IsarService.init();
  });

  setUp(() async {
    ModuleRegistry.clear();
    ModuleRegistry.registerAll([
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson('alpha'))),
      ),
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson('beta'))),
      ),
    ]);

    // Buckets создаются сразу, а не лениво в storageFactory: тесты
    // обращаются к ним напрямую, иначе первый доступ даёт null.
    moduleBuckets = {
      'alpha': <String, String>{},
      'beta': <String, String>{},
    };
    moduleStorages = {};
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (moduleId) {
        final bucket = moduleBuckets.putIfAbsent(moduleId, () => {});
        return moduleStorages.putIfAbsent(
          moduleId,
          () => _TearOnceStorage(bucket),
        );
      },
    );
    manager.setStateForTesting('alpha', ModuleState.enabled);
    manager.setStateForTesting('beta', ModuleState.enabled);

    stateStore = _FakeModuleStateStore();

    gateway = CoreBackupGateway(
      globalManager: GlobalBackupManager(moduleManager: manager),
      moduleManager: ModuleBackupManager(
        moduleManager: manager,
        stateStore: stateStore,
        assetsDirectoryResolver: (id) => ModuleSandbox.getAssetsDirectory(id),
      ),
      appModuleManager: manager,
    );

    await _clearIsar();
    await _clearSandbox(sandboxRoot);
  });

  tearDown(() async {
    manager.dispose();
  });

  Future<void> seedIsarData(String moduleId, Map<String, String> data) async {
    final storage = ModuleStorageIsar(moduleId);
    for (final entry in data.entries) {
      await storage.setString(entry.key, entry.value);
    }
  }

  Future<Map<String, String>> readIsarData(String moduleId) async {
    final storage = ModuleStorageIsar(moduleId);
    final result = <String, String>{};
    for (final key in await storage.keys()) {
      final value = await storage.getString(key);
      if (value != null) result[key] = value;
    }
    return result;
  }

  Future<void> seedAsset(String moduleId, String name, String content) async {
    await ModuleSandbox.ensureModuleDirectories(moduleId);
    final dir = await ModuleSandbox.getAssetsDirectory(moduleId);
    await File(path.join(dir.path, name)).writeAsString(content);
  }

  Future<Map<String, String>> readAssets(String moduleId) async {
    final dir = await ModuleSandbox.getAssetsDirectory(moduleId);
    final result = <String, String>{};
    if (!await dir.exists()) return result;
    for (final entity in await dir.list().toList()) {
      if (entity is File) {
        result[path.basename(entity.path)] = await entity.readAsString();
      }
    }
    return result;
  }

  const fullOptions = ModuleBackupOptions();

  // ==================================================================
  // Global Backup: UI → Gateway → Manager → Writer → .pbk → Reader
  // ==================================================================
  group('Global Backup сквозная цепочка', () {
    test('.pbk создаётся, читается и проходит проверку checksum', () async {
      await seedIsarData('alpha', {'k': 'value-a'});
      await seedAsset('alpha', 'note.txt', 'файл A');

      final artifact = await gateway.createGlobalBackup(
        const GlobalBackupSelection(
          moduleIds: {},
          allInstalled: true,
        ),
      );

      expect(artifact.fileName, endsWith('.pbk'));
      expect(artifact.bytes, isNotEmpty);

      // Читаем тем же кодом, что и приложение.
      final preview = await gateway.inspectGlobalBackup(artifact.bytes);

      expect(preview.title, 'Глобальный backup');
      expect(preview.moduleIds, contains('alpha'));
      expect(preview.includesSettings, isTrue);
      expect(preview.includesData, isTrue);
      expect(preview.includesAssets, isTrue);
    });

    test('в .pbk попадают только выбранные модули', () async {
      await seedIsarData('alpha', {'a': '1'});
      await seedIsarData('beta', {'b': '2'});

      final artifact = await gateway.createGlobalBackup(
        const GlobalBackupSelection(
          moduleIds: {'alpha'},
          allInstalled: false,
        ),
      );

      final preview = await gateway.inspectGlobalBackup(artifact.bytes);

      expect(preview.moduleIds, ['alpha']);
      expect(preview.moduleIds, isNot(contains('beta')));
    });

    test('состав выбранных модулей фиксируется в архиве', () async {
      await seedIsarData('alpha', {'a': '1'});
      await seedIsarData('beta', {'b': '2'});

      final artifact = await gateway.createGlobalBackup(
        const GlobalBackupSelection(
          moduleIds: {'alpha', 'beta'},
          allInstalled: false,
          includeModuleData: false,
          includeAssets: false,
          includeGlobalSettings: false,
        ),
      );

      // Без данных и файлов архив всё равно остаётся читаемым и
      // перечисляет оба модуля.
      final preview = await gateway.inspectGlobalBackup(artifact.bytes);
      expect(preview.moduleIds, ['alpha', 'beta']);
    });

    test('данные модуля записываются в .pbk без потерь', () async {
      await seedIsarData('alpha', {'ключ': 'значение', 'second': 'two'});

      final artifact = await gateway.createGlobalBackup(
        const GlobalBackupSelection(
          moduleIds: {'alpha'},
          allInstalled: false,
          includeAssets: false,
        ),
      );

      final text = utf8.decode(artifact.bytes, allowMalformed: true);
      // JSON внутри STORED-записи лежит как есть, поэтому значения
      // видны в байтах архива.
      expect(text, contains('значение'));
      expect(text, contains('second'));
    });
  });

  // ==================================================================
  // Module Backup: Gateway → Manager → Writer → .pmb → Reader
  // ==================================================================
  group('Module Backup сквозная цепочка', () {
    test('полный .pmb проходит проверку и содержит все компоненты',
        () async {
      moduleBuckets['alpha']!['k'] = 'v';
      await stateStore.save(_snapshot('alpha'));
      await seedAsset('alpha', 'photo.png', 'bytes');

      final artifact = await gateway.createModuleBackup('alpha', fullOptions);
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(artifact.fileName, endsWith('.pmb'));
      expect(backup.moduleId, 'alpha');
      expect(backup.moduleVersion, '1.0.0');
      expect(backup.stateJson, isNotNull);
      expect(backup.dataJson, contains('"v"'));
      expect(backup.assets.keys, contains('photo.png'));
    });

    test('state only содержит только состояние', () async {
      moduleBuckets['alpha']!['k'] = 'v';
      await stateStore.save(_snapshot('alpha', state: 'disabled'));

      final artifact = await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.stateOnly(),
      );
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.stateJson, isNotNull);
      expect(backup.dataJson, isNull);
      expect(backup.assets, isEmpty);
    });

    test('data only содержит только данные', () async {
      moduleBuckets['alpha']!['k'] = 'v';
      await stateStore.save(_snapshot('alpha'));

      final artifact = await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataOnly(),
      );
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.dataJson, isNotNull);
      expect(backup.stateJson, isNull);
    });

    test('assets only содержит только файлы', () async {
      moduleBuckets['alpha']!['k'] = 'v';
      await seedAsset('alpha', 'doc.txt', 'text');

      final artifact = await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.assetsOnly(),
      );
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.assets.keys, ['doc.txt']);
      expect(backup.dataJson, isNull);
      expect(backup.stateJson, isNull);
    });

    test('data + assets содержит данные и файлы, но не состояние', () async {
      moduleBuckets['alpha']!['k'] = 'v';
      await stateStore.save(_snapshot('alpha'));
      await seedAsset('alpha', 'doc.txt', 'text');

      final artifact = await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataAndAssets(),
      );
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.dataJson, isNotNull);
      expect(backup.assets.keys, ['doc.txt']);
      expect(backup.stateJson, isNull);
    });

    test('минимальный backup пуст, но всё равно валиден', () async {
      final artifact = await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions(
          includeState: false,
          includeData: false,
          includeAssets: false,
        ),
      );
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.moduleId, 'alpha');
      expect(backup.stateJson, isNull);
      expect(backup.dataJson, isNull);
      expect(backup.assets, isEmpty);
    });

    test('module identity сохраняется в .pmb', () async {
      final artifact = await gateway.createModuleBackup('alpha', fullOptions);
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      // Идентичность обязана совпадать и в манифесте, и быть ровно
      // одним модулем — иначе restore не знает, куда восстанавливать.
      expect(backup.moduleId, 'alpha');
      expect(utf8.decode(artifact.bytes, allowMalformed: true), contains('alpha'));
    });
  });

  // ==================================================================
  // Restore
  // ==================================================================
  group('Restore сквозная цепочка', () {
    Future<List<int>> backupAlpha({ModuleBackupOptions options = fullOptions}) async {
      moduleBuckets['alpha']!['key'] = 'original';
      await stateStore.save(_snapshot('alpha', state: 'disabled'));
      await seedAsset('alpha', 'a.txt', 'original asset');
      final artifact = await gateway.createModuleBackup('alpha', options);
      return artifact.bytes;
    }

    void dirtyAlpha() {
      moduleBuckets['alpha']!['key'] = 'changed';
      moduleBuckets['alpha']!['extra'] = 'junk';
    }

    test('full restore возвращает state, data и assets', () async {
      final bytes = await backupAlpha();
      dirtyAlpha();
      await stateStore.save(_snapshot('alpha', state: 'enabled'));
      await seedAsset('alpha', 'stale.txt', 'stale');

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: fullOptions,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.appliedComponents, containsAll(['state', 'data', 'assets']));

      expect(moduleBuckets['alpha']!['key'], 'original');
      expect(moduleBuckets['alpha']!['extra'], isNull);
      expect((await stateStore.load('alpha'))!.state, 'disabled');
      expect(await readAssets('alpha'),
          {'a.txt': 'original asset'});
    });

    test('data only restore не трогает state и assets', () async {
      final bytes = await backupAlpha(
        options: const ModuleBackupOptions.dataOnly(),
      );
      dirtyAlpha();

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.appliedComponents, ['data']);
      expect(moduleBuckets['alpha']!['key'], 'original');
      // Deserialize делает exact-match: ключ, которого нет в архиве,
      // удаляется. Это ожидаемое поведение data only.
      expect(moduleBuckets['alpha']!['extra'], isNull);
    });

    test('state only restore меняет только состояние', () async {
      final bytes = await backupAlpha(
        options: const ModuleBackupOptions.stateOnly(),
      );
      dirtyAlpha();
      await stateStore.save(_snapshot('alpha', state: 'enabled'));

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.stateOnly(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.appliedComponents, ['state']);
      expect((await stateStore.load('alpha'))!.state, 'disabled');
      expect(moduleBuckets['alpha']!['key'], 'changed',
          reason: 'data не должна была восстанавливаться');
    });

    test('assets only restore меняет только файлы', () async {
      final bytes = await backupAlpha(
        options: const ModuleBackupOptions.assetsOnly(),
      );
      await seedAsset('alpha', 'other.txt', 'other');

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.assetsOnly(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.appliedComponents, ['assets']);
      expect(await readAssets('alpha'), {'a.txt': 'original asset'});
    });

    test('data + assets restore не трогает состояние', () async {
      final bytes = await backupAlpha(
        options: const ModuleBackupOptions.dataAndAssets(),
      );
      dirtyAlpha();
      await stateStore.save(_snapshot('alpha', state: 'enabled'));

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataAndAssets(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(moduleBuckets['alpha']!['key'], 'original');
      expect((await stateStore.load('alpha'))!.state, 'enabled',
          reason: 'состояние в архив не входило и не восстанавливалось');
    });

    test('moduleId mismatch отклоняется, данные целы', () async {
      final bytes = await backupAlpha();
      dirtyAlpha();

      await expectLater(
        gateway.restoreModuleBackup(
          archiveBytes: bytes,
          moduleId: 'beta',
          options: fullOptions,
        ),
        throwsA(isA<ModuleIdMismatchException>()),
      );
      expect(moduleBuckets['alpha']!['key'], 'changed');
    });

    test('восстановление в неустановленный модуль отклоняется', () async {
      // Backup именно beta: с архивом alpha сработала бы проверка
      // идентичности, а не проверка установки.
      moduleBuckets['beta']!['key'] = 'beta-backup';
      final bytes =
          (await gateway.createModuleBackup('beta', fullOptions)).bytes;

      manager.setStateForTesting('beta', ModuleState.uninstalled);
      moduleBuckets['beta']!['key'] = 'beta-current';

      await expectLater(
        gateway.restoreModuleBackup(
          archiveBytes: bytes,
          moduleId: 'beta',
          options: fullOptions,
        ),
        throwsA(isA<ModuleNotInstalledException>()),
      );
      expect(moduleBuckets['beta']!['key'], 'beta-current');
    });

    test('повреждённый архив отклоняется без изменения данных', () async {
      final bytes = await backupAlpha();
      dirtyAlpha();

      final corrupted = List<int>.from(bytes);
      corrupted[corrupted.length ~/ 3] ^= 0xFF;

      await expectLater(
        gateway.restoreModuleBackup(
          archiveBytes: corrupted,
          moduleId: 'alpha',
          options: fullOptions,
        ),
        throwsA(isA<BackupException>()),
      );
      expect(moduleBuckets['alpha']!['key'], 'changed');
    });
  });

  // ==================================================================
  // Isolation
  // ==================================================================
  group('Изоляция модулей', () {
    test('backup A не содержит данных B', () async {
      moduleBuckets['alpha']!['secret'] = 'alpha-value';
      moduleBuckets['beta']!['secret'] = 'beta-value';

      final artifact = await gateway.createModuleBackup('alpha', fullOptions);
      final backup = await ModuleBackupReader.readModuleBackup(artifact.bytes);

      expect(backup.dataJson, contains('alpha-value'));
      expect(backup.dataJson, isNot(contains('beta-value')));
    });

    test('restore A не изменяет B', () async {
      moduleBuckets['alpha']!['key'] = 'alpha-backup';
      moduleBuckets['beta']!['key'] = 'beta-current';
      await stateStore.save(_snapshot('alpha'));
      await stateStore.save(_snapshot('beta', state: 'disabled'));

      final bytes = (await gateway.createModuleBackup('alpha', fullOptions)).bytes;
      moduleBuckets['alpha']!['key'] = 'changed';

      await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: fullOptions,
      );

      expect(moduleBuckets['alpha']!['key'], 'alpha-backup');
      expect(moduleBuckets['beta']!['key'], 'beta-current');
      expect((await stateStore.load('beta'))!.state, 'disabled');
    });

    test('partial restore A не изменяет B', () async {
      moduleBuckets['alpha']!['key'] = 'a';
      moduleBuckets['beta']!['key'] = 'b';
      await seedAsset('beta', 'b.txt', 'beta asset');

      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataOnly(),
      )).bytes;

      await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(moduleBuckets['beta']!['key'], 'b');
      expect(await readAssets('beta'), {'b.txt': 'beta asset'});
    });

    test('глобальный backup A не смешивает данные с B', () async {
      await seedIsarData('alpha', {'only': 'alpha'});
      await seedIsarData('beta', {'only': 'beta'});

      final artifact = await gateway.createGlobalBackup(
        const GlobalBackupSelection(
          moduleIds: {'alpha'},
          allInstalled: false,
        ),
      );
      final text = utf8.decode(artifact.bytes, allowMalformed: true);

      expect(text, contains('modules/alpha/'));
      expect(text, isNot(contains('modules/beta/')));
    });
  });

  // ==================================================================
  // Concurrency
  // ==================================================================
  group('Concurrency', () {
    test('два restore одного moduleId не пересекаются', () async {
      moduleBuckets['alpha']!['key'] = 'backup-value';
      final bytes = (await gateway.createModuleBackup('alpha', fullOptions)).bytes;
      moduleBuckets['alpha']!['key'] = 'user-value';

      final outcomes = await Future.wait([
        gateway.restoreModuleBackup(
          archiveBytes: bytes,
          moduleId: 'alpha',
          options: fullOptions,
        ),
        gateway.restoreModuleBackup(
          archiveBytes: bytes,
          moduleId: 'alpha',
          options: fullOptions,
        ),
      ]);

      expect(outcomes.every((o) => o.isSuccess), isTrue);
      expect(moduleBuckets['alpha']!['key'], 'backup-value',
          reason: 'откат одной операции не должен затереть результат другой');
    });

    test('два restore разных moduleId идут независимо', () async {
      moduleBuckets['alpha']!['key'] = 'a-backup';
      moduleBuckets['beta']!['key'] = 'b-backup';

      final alphaBytes =
          (await gateway.createModuleBackup('alpha', fullOptions)).bytes;
      final betaBytes =
          (await gateway.createModuleBackup('beta', fullOptions)).bytes;

      moduleBuckets['alpha']!['key'] = 'x';
      moduleBuckets['beta']!['key'] = 'y';

      final outcomes = await Future.wait([
        gateway.restoreModuleBackup(
          archiveBytes: alphaBytes,
          moduleId: 'alpha',
          options: fullOptions,
        ),
        gateway.restoreModuleBackup(
          archiveBytes: betaBytes,
          moduleId: 'beta',
          options: fullOptions,
        ),
      ]);

      expect(outcomes.every((o) => o.isSuccess), isTrue);
      expect(moduleBuckets['alpha']!['key'], 'a-backup');
      expect(moduleBuckets['beta']!['key'], 'b-backup');
    });

    test('параллельные backup разных модулей не смешиваются', () async {
      moduleBuckets['alpha']!['k'] = 'a';
      moduleBuckets['beta']!['k'] = 'b';

      final artifacts = await Future.wait([
        gateway.createModuleBackup('alpha', fullOptions),
        gateway.createModuleBackup('beta', fullOptions),
      ]);

      final alpha = await ModuleBackupReader.readModuleBackup(artifacts[0].bytes);
      final beta = await ModuleBackupReader.readModuleBackup(artifacts[1].bytes);

      expect(alpha.moduleId, 'alpha');
      expect(beta.moduleId, 'beta');
    });
  });

  // ==================================================================
  // Rollback
  // ==================================================================
  group('Rollback', () {
    test('частично применённый data откатывается (regression)', () async {
      // Регрессия attempted vs applied: компонент, упавший ПОСЕРЕДИНЕ
      // записи, не попадает в applied, но уже испортил значение. Если
      // откатывать только applied, значение из backup осталось бы в
      // модуле навсегда.
      moduleBuckets['alpha']!['boom'] = 'backup-value';
      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataOnly(),
      )).bytes;

      // Пользователь меняет значение ПОСЛЕ backup — это pre-state.
      moduleBuckets['alpha']!['boom'] = 'current-value';
      moduleStorages['alpha']!.tearOnKey = 'boom';

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(outcome.isSuccess, isFalse);
      expect(moduleBuckets['alpha']!['boom'], 'current-value',
          reason: 'прежнее значение обязано вернуться');
      expect(outcome.rolledBackComponents, isNotEmpty);
    });

    test('при падении раннего этапа assets не тронуты', () async {
      // Порядок этапов restore: state → data → assets. Assets применяются
      // последними, поэтому естественным сбоем (рваной записью в data)
      // откат assets недостижим: к моменту падения файлы ещё не
      // менялись. Проверяем именно это — что файлы модуля целы.
      moduleBuckets['alpha']!['boom'] = 'backup-value';
      await seedAsset('alpha', 'keep.txt', 'keep');

      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataAndAssets(),
      )).bytes;

      moduleBuckets['alpha']!['boom'] = 'alpha-current';
      moduleStorages['alpha']!.tearOnKey = 'boom';

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataAndAssets(),
      );

      expect(outcome.isSuccess, isFalse);
      expect(await readAssets('alpha'), {'keep.txt': 'keep'},
          reason: 'assets не должны были применяться до падения data');
    });

    test('assets restore заменяет состав файлов целиком', () async {
      await seedAsset('alpha', 'old.txt', 'old');

      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.assetsOnly(),
      )).bytes;

      await seedAsset('alpha', 'extra.txt', 'extra');

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.assetsOnly(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(await readAssets('alpha'), {'old.txt': 'old'},
          reason: 'файл, отсутствующий в архиве, должен быть удалён');
    });

    test('AUD-32: после restore не остаётся временный каталог', () async {
      // Assets сначала пишутся в `<assets>.pmb_restore_tmp` и только
      // потом переносятся на место. Если временный каталог останется,
      // следующий restore решит, что каталог «уже есть», и поведёт
      // себя иначе — это мусор, который обязан удаляться.
      await seedAsset('alpha', 'photo.png', 'png-bytes');

      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.assetsOnly(),
      )).bytes;

      final assetsDir = await ModuleSandbox.getAssetsDirectory('alpha');
      await seedAsset('alpha', 'extra.txt', 'extra');

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.assetsOnly(),
      );

      expect(outcome.isSuccess, isTrue);
      expect(await readAssets('alpha'), {'photo.png': 'png-bytes'});

      final staging = Directory('${assetsDir.path}.pmb_restore_tmp');
      expect(
        await staging.exists(),
        isFalse,
        reason: 'временный каталог восстановления обязан быть удалён',
      );
    });

    test('откат модуля A не затрагивает B', () async {
      moduleBuckets['alpha']!['boom'] = 'backup-value';
      moduleBuckets['beta']!['boom'] = 'beta-value';
      moduleBuckets['beta']!['other'] = 'beta-other';
      await seedAsset('beta', 'b.txt', 'beta asset');

      final bytes = (await gateway.createModuleBackup(
        'alpha',
        const ModuleBackupOptions.dataOnly(),
      )).bytes;

      moduleBuckets['alpha']!['boom'] = 'alpha-current';
      moduleStorages['alpha']!.tearOnKey = 'boom';

      final outcome = await gateway.restoreModuleBackup(
        archiveBytes: bytes,
        moduleId: 'alpha',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(outcome.isSuccess, isFalse);
      expect(moduleBuckets['beta']!['boom'], 'beta-value');
      expect(moduleBuckets['beta']!['other'], 'beta-other');
      expect(await readAssets('beta'), {'b.txt': 'beta asset'});
    });
  });

  group('Isar и global backup', () {
    test('модульные данные в Isar изолированы по moduleId', () async {
      await seedIsarData('alpha', {'key': 'alpha'});
      await seedIsarData('beta', {'key': 'beta'});

      expect(await readIsarData('alpha'), {'key': 'alpha'});
      expect(await readIsarData('beta'), {'key': 'beta'});
    });

    test('состояние модуля в Isar читается репозиторием', () async {
      await ModuleStateRepository().save(_snapshot('alpha', state: 'disabled'));

      final loaded = await ModuleStateRepository().load('alpha');
      expect(loaded!.state, 'disabled');
    });
  });
}
