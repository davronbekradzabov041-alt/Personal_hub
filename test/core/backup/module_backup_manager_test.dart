import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/backup/module_backup_reader.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

/// Минимальный тестовый модуль — как в module_state_persistence_test.
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

/// In-memory ModuleStateStore вместо Isar.
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

/// Хранилище, которое один раз «рвёт» запись конкретного ключа: значение
/// УЖЕ записано, и только потом приходит ошибка.
///
/// Именно такой сбой важен для проверки отката: если бы запись падала
/// до мутации, данные остались бы целыми и тест ничего не доказывал
/// бы. А после рваной записи значение испорчено, и вернуть его может
/// только pre-snapshot менеджера — в rollback самого
/// ModuleStorageSerializer прямо сказано, что изменённые значения
/// исходных ключей не восстанавливаются.
class _FailOnceModuleStorage implements ModuleStorage {
  _FailOnceModuleStorage(this._bucket);

  final Map<String, String> _bucket;
  String? failOnKey;
  bool _alreadyTorn = false;

  @override
  Future<String?> getString(String key) async => _bucket[key];

  @override
  Future<void> setString(String key, String value) async {
    _bucket[key] = value; // запись состоялась...
    if (!_alreadyTorn && key == failOnKey) {
      _alreadyTorn = true;
      throw StateError('имитация сбоя после записи ключа $key'); // ...и пришёл сбой
    }
  }

  @override
  Future<void> remove(String key) async {
    _bucket.remove(key);
  }

  @override
  Future<List<String>> keys() async => _bucket.keys.toList();
}

class _FakeModuleStorageFactory {
  final Map<String, Map<String, String>> buckets = {};
  final Map<String, _FailOnceModuleStorage> storages = {};

  ModuleStorage call(String moduleId) {
    final bucket = buckets.putIfAbsent(moduleId, () => {});
    return storages.putIfAbsent(moduleId, () => _FailOnceModuleStorage(bucket));
  }
}

ModuleManifest _manifestFor(String id) => ModuleManifest(
      id: id,
      name: id,
      version: '1.0.0',
      apiVersion: kCoreModuleApiVersion,
      author: 'Test',
    );

ModuleStateSnapshot _snapshotFor(String moduleId, {String state = 'enabled'}) {
  return ModuleStateSnapshot(
    moduleId: moduleId,
    state: state,
    installedVersion: '1.0.0',
    enabled: true,
    installedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

void main() {
  late ModuleManager manager;
  late _FakeModuleStateStore store;
  late _FakeModuleStorageFactory storageFactory;
  late Directory tempRoot;
  late Map<String, Directory> assetsDirs;

  setUp(() {
    ModuleRegistry.clear();
    ModuleRegistry.register(_FakeModule(_manifestFor('alpha')));
    ModuleRegistry.register(_FakeModule(_manifestFor('beta')));

    storageFactory = _FakeModuleStorageFactory();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: storageFactory.call,
    );
    store = _FakeModuleStateStore();

    // Модули «установлены». setStateForTesting — @visibleForTesting и
    // используется ТОЛЬКО здесь, в тесте; production-код (.pmb manager)
    // его не вызывает.
    manager.setStateForTesting('alpha', ModuleState.enabled);
    manager.setStateForTesting('beta', ModuleState.enabled);

    tempRoot = Directory.systemTemp.createTempSync('pmb_test_');
    assetsDirs = {
      for (final id in ['alpha', 'beta'])
        id: Directory('${tempRoot.path}/$id/assets')..createSync(recursive: true),
    };
  });

  tearDown(() {
    manager.dispose();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  ModuleBackupManager makeManager() => ModuleBackupManager(
        moduleManager: manager,
        stateStore: store,
        assetsDirectoryResolver: (id) async => assetsDirs[id]!,
      );

  Future<List<int>> backupOf(
    String moduleId, {
    ModuleBackupOptions options = const ModuleBackupOptions(),
  }) async {
    final outDir = Directory('${tempRoot.path}/out')..createSync(recursive: true);
    final result = await makeManager().createBackup(
      moduleId: moduleId,
      outputDirectory: outDir,
      options: options,
    );
    return File(result.outputPath).readAsBytes();
  }

  group('createBackup', () {
    test('создаёт .pmb со всеми компонентами', () async {
      await storageFactory.call('alpha').setString('k1', 'v1');
      await store.save(_snapshotFor('alpha'));
      File('${assetsDirs['alpha']!.path}/note.txt')
          .writeAsStringSync('пользовательский файл');

      final bytes = await backupOf('alpha');

      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      expect(backup.moduleId, 'alpha');
      expect(backup.backupFormatVersion, 1);
      expect(backup.stateJson, isNotNull);
      expect(backup.dataJson, contains('v1'));
      expect(backup.assets.keys, contains('note.txt'));
      expect(utf8Decode(backup.assets['note.txt']!), 'пользовательский файл');
    });

    test('имя asset с кириллицей не ломает архив', () async {
      // Регрессия: длина имени писалась в UTF-16 code units, а в архив
      // шли UTF-8 байты — не-ASCII имя сдвигало все смещения.
      File('${assetsDirs['alpha']!.path}/заметка.txt').writeAsStringSync('данные');

      final bytes = await backupOf('alpha');
      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      expect(backup.assets.keys, contains('заметка.txt'));
      expect(utf8Decode(backup.assets['заметка.txt']!), 'данные');
    });

    test('частичный backup укладывается в выбранные компоненты', () async {
      await storageFactory.call('alpha').setString('k1', 'v1');
      await store.save(_snapshotFor('alpha'));

      final bytes = await backupOf('alpha', options: const ModuleBackupOptions.dataOnly());
      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      expect(backup.dataJson, isNotNull);
      expect(backup.stateJson, isNull);
      expect(backup.assets, isEmpty);
    });

    test('asset с неразрешённым расширением не попадает в архив', () async {
      // Иначе backup создастся успешно, а его же reader отвергнет.
      File('${assetsDirs['alpha']!.path}/note.txt').writeAsStringSync('ok');
      File('${assetsDirs['alpha']!.path}/blob.bin').writeAsStringSync('skip');

      final backup = await ModuleBackupReader.readModuleBackup(await backupOf('alpha'));

      expect(backup.assets.keys, ['note.txt']);
    });
  });

  group('restoreBackup', () {
    test('полный round-trip восстанавливает state, data и assets', () async {
      await storageFactory.call('alpha').setString('k1', 'original');
      await store.save(_snapshotFor('alpha', state: 'disabled'));
      File('${assetsDirs['alpha']!.path}/note.txt').writeAsStringSync('original asset');
      final bytes = await backupOf('alpha');

      // Портим модуль после backup.
      await storageFactory.call('alpha').setString('k1', 'changed');
      await storageFactory.call('alpha').setString('extra', 'junk');
      await store.save(_snapshotFor('alpha', state: 'enabled'));
      File('${assetsDirs['alpha']!.path}/stale.txt').writeAsStringSync('stale');

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'alpha',
      );

      expect(result.isSuccess, isTrue, reason: 'ошибка: ${result.error}');
      expect(result.appliedComponents, containsAll(['state', 'data', 'assets']));

      final storage = storageFactory.call('alpha');
      expect(await storage.getString('k1'), 'original');
      expect(await storage.getString('extra'), isNull,
          reason: 'ключ, отсутствующий в backup, должен быть удалён');
      expect((await store.load('alpha'))!.state, 'disabled');

      expect(File('${assetsDirs['alpha']!.path}/note.txt').existsSync(), isTrue);
      expect(File('${assetsDirs['alpha']!.path}/stale.txt').existsSync(), isFalse,
          reason: 'файл, отсутствующий в backup, должен быть удалён');
    });

    test('dataOnly не трогает state и assets', () async {
      await storageFactory.call('alpha').setString('k1', 'v1');
      await store.save(_snapshotFor('alpha', state: 'disabled'));
      File('${assetsDirs['alpha']!.path}/note.txt').writeAsStringSync('asset');
      final bytes = await backupOf('alpha');

      // Меняем всё три компонента.
      await store.save(_snapshotFor('alpha', state: 'enabled'));
      File('${assetsDirs['alpha']!.path}/note.txt').writeAsStringSync('changed asset');
      final storage = storageFactory.call('alpha');
      await storage.setString('k1', 'changed');
      await storage.setString('junk', 'junk');

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'alpha',
        options: const ModuleBackupOptions.dataOnly(),
      );

      expect(result.isSuccess, isTrue, reason: 'ошибка: ${result.error}');
      expect(result.appliedComponents, ['data']);

      expect(await storage.getString('k1'), 'v1');
      expect(await storage.getString('junk'), isNull);
      expect((await store.load('alpha'))!.state, 'enabled',
          reason: 'state не должен меняться при dataOnly');
      expect(
        File('${assetsDirs['alpha']!.path}/note.txt').readAsStringSync(),
        'changed asset',
        reason: 'assets не должны меняться при dataOnly',
      );
    });

    test('отказ при несовпадении moduleId и целевой модуль не изменён', () async {
      await storageFactory.call('alpha').setString('k1', 'original');
      final bytes = await backupOf('alpha');

      await storageFactory.call('beta').setString('k1', 'beta-original');

      await expectLater(
        makeManager().restoreBackup(archiveBytes: bytes, targetModuleId: 'beta'),
        throwsA(isA<ModuleIdMismatchException>()),
      );

      // Ни alpha, ни beta не тронуты.
      expect(await storageFactory.call('beta').getString('k1'), 'beta-original');
      expect(await storageFactory.call('alpha').getString('k1'), 'original');
    });

    test('отказ при попытке restore в неустановленный модуль', () async {
      // Backup именно этого модуля: иначе сработала бы проверка
      // идентичности (moduleId не совпадает), а не проверка установки.
      await storageFactory.call('beta').setString('k1', 'beta-backup');
      final bytes = await backupOf('beta');

      manager.setStateForTesting('beta', ModuleState.uninstalled);
      await storageFactory.call('beta').setString('k1', 'beta-current');

      await expectLater(
        makeManager().restoreBackup(archiveBytes: bytes, targetModuleId: 'beta'),
        throwsA(isA<ModuleNotInstalledException>()),
      );
      // .pmb не устанавливает модуль — данные не тронуты.
      expect(await storageFactory.call('beta').getString('k1'), 'beta-current');
    });

    test('отказ на подделанном архиве ничего не меняет', () async {
      await storageFactory.call('alpha').setString('k1', 'original');
      final bytes = await backupOf('alpha');

      // Портим байт в теле архива — checksum обязан не совпасть.
      final tampered = List<int>.from(bytes);
      final idx = bytes.length ~/ 3;
      tampered[idx] = tampered[idx] ^ 0xFF;

      await expectLater(
        makeManager().restoreBackup(archiveBytes: tampered, targetModuleId: 'alpha'),
        throwsA(isA<BackupException>()),
      );
      expect(await storageFactory.call('alpha').getString('k1'), 'original');
    });
  });

  group('откат', () {
    test('частичный сбой возвращает ПРЕЖНИЕ значения, а не пустое хранилище',
        () async {
      // Схема: state пишется первым и проходит, data рвётся уже во время
      // записи. Откат обязан вернуть и state, и прежнее значение ключа.
      await storageFactory.call('alpha').setString('boom', 'backup-value');
      await store.save(_snapshotFor('alpha', state: 'disabled'));
      final bytes = await backupOf('alpha');

      // Пользователь меняет модуль ПОСЛЕ backup — это и есть pre-state.
      final storage = storageFactory.call('alpha');
      await storage.setString('boom', 'current-value');
      await store.save(_snapshotFor('alpha', state: 'enabled'));

      // Единственная запись 'boom' внутри restore будет разорвана.
      (storage as _FailOnceModuleStorage).failOnKey = 'boom';

      final result = await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'alpha',
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);

      // Рваная запись оставила в хранилище значение ИЗ BACKUP.
      // Вернуть значение, которое было ДО restore, может только
      // pre-snapshot — rollback самого serializer этого не делает.
      expect(await storage.getString('boom'), 'current-value',
          reason: 'прежнее значение должно быть восстановлено, а не оставлено от backup');

      expect((await store.load('alpha'))!.state, 'enabled',
          reason: 'state откатывается к снимку, снятому ДО restore '
              '(состояние модуля перед восстановлением), а не к значению из архива');

      expect(result.rolledBackComponents, isNotEmpty);
    });

    test('откат не трогает модули, кроме целевого', () async {
      await storageFactory.call('alpha').setString('boom', 'alpha-old');
      await storageFactory.call('beta').setString('boom', 'beta-value');
      await store.save(_snapshotFor('alpha'));
      final bytes = await backupOf('alpha');

      final alphaStorage = storageFactory.call('alpha') as _FailOnceModuleStorage;
      alphaStorage.failOnKey = 'boom';

      await makeManager().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: 'alpha',
      );

      expect(await storageFactory.call('beta').getString('boom'), 'beta-value',
          reason: 'соседний модуль не должен пострадать при откате');
    });
  });

  group('изоляция и concurrency', () {
    test('restore одного модуля не затрагивает другой', () async {
      await storageFactory.call('alpha').setString('a', '1');
      await storageFactory.call('beta').setString('b', '2');
      final alphaBytes = await backupOf('alpha');

      await storageFactory.call('alpha').setString('a', 'changed');
      await makeManager().restoreBackup(
        archiveBytes: alphaBytes,
        targetModuleId: 'alpha',
      );

      expect(await storageFactory.call('alpha').getString('a'), '1');
      expect(await storageFactory.call('beta').getString('b'), '2');
    });

    test('параллельные restore одного модуля не пересекаются', () async {
      await storageFactory.call('alpha').setString('k', 'backup-value');
      final bytes = await backupOf('alpha');

      final storage = storageFactory.call('alpha');
      await storage.setString('k', 'user-value');

      final m = makeManager();
      final results = await Future.wait([
        m.restoreBackup(archiveBytes: bytes, targetModuleId: 'alpha'),
        m.restoreBackup(archiveBytes: bytes, targetModuleId: 'alpha'),
      ]);

      expect(results.every((r) => r.isSuccess), isTrue,
          reason: 'ошибки: ${results.map((r) => r.error).toList()}');
      // Сериализация обязана оставить согласованный результат, а не
      // состояние, где один откат затёр другой.
      expect(await storage.getString('k'), 'backup-value');
    });

    test('параллельные restore разных модулей выполняются вместе', () async {
      await storageFactory.call('alpha').setString('k', 'alpha-backup');
      await storageFactory.call('beta').setString('k', 'beta-backup');
      final alphaBytes = await backupOf('alpha');
      final betaBytes = await backupOf('beta');

      await storageFactory.call('alpha').setString('k', 'x');
      await storageFactory.call('beta').setString('k', 'y');

      final m = makeManager();
      final results = await Future.wait([
        m.restoreBackup(archiveBytes: alphaBytes, targetModuleId: 'alpha'),
        m.restoreBackup(archiveBytes: betaBytes, targetModuleId: 'beta'),
      ]);

      expect(results.every((r) => r.isSuccess), isTrue,
          reason: 'ошибки: ${results.map((r) => r.error).toList()}');
      expect(await storageFactory.call('alpha').getString('k'), 'alpha-backup');
      expect(await storageFactory.call('beta').getString('k'), 'beta-backup');
    });
  });
}

/// Мини-хелпер декодирования UTF-8 для содержимого assets.
String utf8Decode(List<int> bytes) => utf8.decode(bytes);
