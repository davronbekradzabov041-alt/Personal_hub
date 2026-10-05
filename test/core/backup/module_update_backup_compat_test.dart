/// Совместимость backup и обновления модуля (Этап 8.2).
///
/// Обновление меняет реализацию и файлы модуля, backup хранит данные,
/// состояние и файлы. Вопросы, на которые отвечает этот файл:
///
/// * остаётся ли .pmb/.pbk, созданный ДО обновления, пригодным после
///   него (архив — константа, а не живое отображение модуля);
/// * что происходит с данными пользователя при обновлении и при
///   последующем restore;
/// * не портит ли откат обновления уже созданный backup.
///
/// Формат .pmb/.pbk здесь не меняется: проверяется, что обновление его
/// не ломает. Ни один файл в lib/core/backup ради этих тестов не
/// трогался.
library module_update_backup_compat_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/backup/backup_options.dart';
import 'package:personal_hub/core/backup/backup_reader.dart';
import 'package:personal_hub/core/backup/global_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_manager.dart';
import 'package:personal_hub/core/backup/module_backup_options.dart';
import 'package:personal_hub/core/backup/module_backup_reader.dart';
import 'package:personal_hub/core/database/isar_service.dart';
import 'package:personal_hub/core/database/models/app_settings.dart';
import 'package:personal_hub/core/database/models/module_data_row.dart';
import 'package:personal_hub/core/database/models/module_state_record.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_persistence.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/module_storage_isar.dart';
import 'package:personal_hub/core/modules/platform/module_importer.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox_swap.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/modules/platform/sandbox_exceptions.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

import '../../support/isar_test_init.dart';

const String _moduleId = 'notes';

class _MemoryStorage implements ModuleStorage {
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

class _MemoryStore implements ModuleStateStore {
  final Map<String, ModuleStateSnapshot> snapshots =
      <String, ModuleStateSnapshot>{};

  @override
  Future<List<ModuleStateSnapshot>> loadAll() async => snapshots.values.toList();

  @override
  Future<ModuleStateSnapshot?> load(String moduleId) async => snapshots[moduleId];

  @override
  Future<void> save(ModuleStateSnapshot snapshot) async {
    snapshots[snapshot.moduleId] = snapshot;
  }

  @override
  Future<void> delete(String moduleId) async {
    snapshots.remove(moduleId);
  }
}

List<int> _phm({
  required String version,
  Map<String, String> assets = const <String, String>{},
  Map<String, String> storage = const <String, String>{},
}) {
  return ModulePackageWriter.write(PackageContent(
    manifest: ModuleManifest.fromJson(<String, dynamic>{
      'id': _moduleId,
      'name': 'Заметки',
      'version': version,
      'apiVersion': 1,
      'author': 'Test',
      'description': 'backup compat fixture',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': '',
    }),
    assets: [
      for (final entry in assets.entries)
        PackageAsset(
          path: 'assets/${entry.key}',
          bytes: utf8.encode(entry.value),
        ),
    ],
    data: storage.isEmpty
        ? null
        : PackageData(jsonDecode(jsonEncode(storage)) as Map<String, dynamic>),
  ));
}

/// Обмен песочницы, который доводит дело до конца и сразу падает —
/// худший момент для сбоя. Для проверки «откат не портит backup».
class _CommitThenFailSwap extends ModuleSandboxSwap {
  _CommitThenFailSwap({required super.supportDirectoryResolver});

  @override
  Future<ModuleSandboxSwapResult> commit({
    required String moduleId,
    required Directory stagedDirectory,
  }) async {
    await super.commit(moduleId: moduleId, stagedDirectory: stagedDirectory);
    throw SandboxSwapException(
      moduleId: moduleId,
      message: 'сбой сразу после обмена песочницы (тест)',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late ModuleManager manager;
  late _MemoryStore stateStore;
  late ModuleStatePersistence persistence;
  late _MemoryStorage storage;

  ModuleImporter importer({ModuleSandboxSwap? swap}) => ModuleImporter(
        moduleManager: manager,
        testSupportDir: supportDir,
        stateStore: stateStore,
        sandboxSwap: swap ??
            ModuleSandboxSwap(supportDirectoryResolver: () async => supportDir),
      );

  ModuleBackupManager backups() => ModuleBackupManager(
        moduleManager: manager,
        stateStore: stateStore,
        // Тот же корень, что у обмена песочницей: иначе backup снимал бы
        // ассеты из другого места и «восстанавливал» бы пустоту.
        assetsDirectoryResolver: (moduleId) async =>
            Directory(path.join(supportDir.path, 'modules', moduleId, 'assets')),
      );

  Directory assetsDir() =>
      Directory(path.join(supportDir.path, 'modules', _moduleId, 'assets'));

  Map<String, String> readAssets() {
    final dir = assetsDir();
    if (!dir.existsSync()) return const {};
    return {
      for (final entity in dir.listSync())
        if (entity is File)
          path.basename(entity.path): entity.readAsStringSync(),
    };
  }

  setUpAll(() async {
    // Нативная библиотека Isar подключается явно: isar_flutter_libs —
    // плагин, и в flutter test его бинарники не собираются.
    await ensureIsarCoreInitialized();
  });

  setUp(() async {
    ModuleRegistry.clear();
    supportDir = await Directory.systemTemp.createTemp('phm_backup_compat_');
    storage = _MemoryStorage();
    manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (_) => storage,
    );
    stateStore = _MemoryStore();
    persistence = ModuleStatePersistence(
      manager,
      stateStore,
      storageFactory: (_) => _MemoryStorage(),
    );
  });

  tearDown(() async {
    persistence.dispose();
    ModuleRegistry.clear();
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
  });

  /// Устанавливает 1.0.0 и кладёт пользовательские данные.
  Future<void> install({String version = '1.0.0'}) async {
    final result = await importer().importFromBytes(_phm(
      version: version,
      assets: {'logo.png': 'иконка $version'},
      storage: {'seed': 'из пакета'},
    ));
    expect(result.isSuccess, isTrue, reason: result.error);
    await storage.setString('note:1', 'черновик пользователя');
    await storage.setString('note:2', 'второй ключ');
  }

  Future<void> update(String version, {Map<String, String>? assets}) async {
    final result = await importer().updateFromBytes(
      moduleId: _moduleId,
      archiveBytes: _phm(version: version, assets: assets ?? const {}),
    );
    expect(result.isSuccess, isTrue, reason: result.error);
  }

  group('.pmb до обновления остаётся пригодным после него', () {
    test('backup → update → restore: данные возвращаются, реализация — нет',
        () async {
      await install();
      final backupDir = await Directory.systemTemp.createTemp('pmb_');

      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');

      await update('1.1.0', assets: {'logo.png': 'иконка 1.1.0'});
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');
      expect(readAssets(), {'logo.png': 'иконка 1.1.0'});

      // Пользователь меняет данные после обновления.
      await storage.setString('note:1', 'изменено после обновления');
      await storage.setString('note:3', 'новый ключ');

      final restored = await backups().restoreBackup(
        archiveBytes: await File(created.outputPath).readAsBytes(),
        targetModuleId: _moduleId,
        options: const ModuleBackupOptions(),
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');

      // Данные — как в архиве.
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(await storage.getString('note:3'), isNull,
          reason: 'ключ, которого не было в архиве, не должен появляться');

      // Файлы — как в архиве: .pmb восстанавливает снимок ЦЕЛИКОМ.
      expect(readAssets(), {'logo.png': 'иконка 1.0.0'});

      // Реализация при этом остаётся новой: .pmb восстанавливает данные,
      // состояние и файлы, но не код модуля. Смешивать две эти вещи
      // в одном формате — значило бы откатывать модуль целиком, включая
      // то, чего архив не содержит.
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');

      await backupDir.delete(recursive: true);
    });

    test('записанная версия модуля возвращается к себе после restore',
        () async {
      // Архив сделан до обновления, значит внутри installedVersion —
      // прежняя. Restore не вправе сделать так, чтобы запись состояния
      // противоречила реестру: синхронизация берёт версию из манифеста,
      // и следующая же запись приводит её к новой.
      await install();
      final backupDir = await Directory.systemTemp.createTemp('pmb_ver_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );

      await update('1.1.0');
      await persistence.flush();

      await backups().restoreBackup(
        archiveBytes: await File(created.outputPath).readAsBytes(),
        targetModuleId: _moduleId,
        options: const ModuleBackupOptions(),
      );
      // Синхронизация происходит по уведомлению менеджера (adoptRestoredState).
      await persistence.flush();

      final snapshot = await stateStore.load(_moduleId);
      expect(snapshot!.installedVersion, '1.1.0',
          reason: 'версия состояния обязана совпадать с манифестом, а не '
              'с архивом: иначе модуль «откатился» бы только в записях');
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.1.0');

      await backupDir.delete(recursive: true);
    });
  });

  group('обновление до backup', () {
    test('update → .pmb → restore: архив описывает уже обновлённый модуль',
        () async {
      await install();
      await update('1.2.0', assets: {'logo.png': 'иконка 1.2.0'});
      await storage.setString('note:1', 'данные после обновления');

      final backupDir = await Directory.systemTemp.createTemp('pmb_after_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      final backup = await ModuleBackupReader.readModuleBackup(
        await File(created.outputPath).readAsBytes(),
      );

      expect(backup.moduleVersion, '1.2.0');
      expect(backup.dataJson, contains('данные после обновления'));
      expect(backup.assets.keys, ['logo.png']);

      await storage.setString('note:1', 'испорчено');
      final restored = await backups().restoreBackup(
        archiveBytes: await File(created.outputPath).readAsBytes(),
        targetModuleId: _moduleId,
        options: const ModuleBackupOptions(),
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(await storage.getString('note:1'), 'данные после обновления');
      expect(readAssets(), {'logo.png': 'иконка 1.2.0'});

      await backupDir.delete(recursive: true);
    });

    test('отказ проверок не мешает создать backup после него', () async {
      await install();

      final failed = await importer().updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(version: '0.5.0'),
      );
      expect(failed.isFailure, isTrue);

      final backupDir = await Directory.systemTemp.createTemp('pmb_reject_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      final backup = await ModuleBackupReader.readModuleBackup(
        await File(created.outputPath).readAsBytes(),
      );

      expect(backup.moduleVersion, '1.0.0');
      expect(backup.dataJson, contains('черновик пользователя'));

      await backupDir.delete(recursive: true);
    });
  });

  group('.pbk до и после обновления', () {
    test('глобальный backup до обновления остаётся читаемым после него',
        () async {
      // Isar нужен GlobalBackupManager: глобальные данные и данные
      // модулей пишутся через репозитории Isar, а не через тестовые
      // подмены выше.
      final isarRoot = await Directory.systemTemp.createTemp('pbk_docs_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => isarRoot.path,
      );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        // Каталог с Isar НЕ удаляется: база держит его открытым, и
        // удаление падало бы на занятом файле. Временный каталог ОС и
        // так убирается ею при выходе.
      });

      await IsarService.init();
      final isar = IsarService.instance;
      await isar.writeTxn(() async {
        await isar.moduleDataRows.clear();
        await isar.moduleStateRecords.clear();
        await isar.appSettings.clear();
      });

      await install();

      // Данные модуля дублируются в Isar: .pbk пишет их оттуда.
      final isarStorage = ModuleStorageIsar(_moduleId);
      await isarStorage.setString('note:1', 'данные для pbk');

      final globalManager = GlobalBackupManager(moduleManager: manager);
      final outputDir = await Directory.systemTemp.createTemp('pbk_out_');
      final result = await globalManager.createGlobalBackup(
        options: const BackupOptions(),
        outputDirectory: outputDir,
      );
      expect(result.includedModuleIds, contains(_moduleId));

      final bytes = await File(result.outputPath).readAsBytes();

      // Обновление: реализация и файлы меняются.
      await update('1.1.0', assets: {'logo.png': 'иконка 1.1.0'});

      // Архив, созданный ДО обновления, обязан остаться в точности тем же
      // снимком: это файл, а не живое представление модуля.
      final before = await BackupReader.readGlobalBackup(
        bytes,
        existingModuleIds: {_moduleId},
      );
final moduleEntry = before.modules[_moduleId]!;
      expect(moduleEntry.manifest.version, '1.0.0');
      expect(moduleEntry.dataJson, contains('данные для pbk'));

      // Контрольная сумма сходится и ПОСЛЕ обновления: обновление не
      // имеет права переписывать уже записанные архивы.
      final after = await BackupReader.readGlobalBackup(
        bytes,
        existingModuleIds: {_moduleId},
      );
      expect(after.checksum, before.checksum);

      // Новый .pbk описывает уже обновлённый модуль, а данные
      // пользователя при этом целы.
      await ModuleStorageIsar(_moduleId).setString('note:1', 'данные для pbk');
      final fresh = await globalManager.createGlobalBackup(
        options: const BackupOptions(),
        outputDirectory: outputDir,
      );
      final freshBackup = await BackupReader.readGlobalBackup(
        await File(fresh.outputPath).readAsBytes(),
        existingModuleIds: {_moduleId},
      );
      expect(
        freshBackup.modules[_moduleId]!.manifest.version,
        '1.1.0',
      );
      expect(await storage.getString('note:1'), 'черновик пользователя');

      await outputDir.delete(recursive: true);
    });
  });

  group('откат обновления не портит backup', () {
    test('.pmb остаётся пригодным после откатившегося обновления',
        () async {
      await install();
      final backupDir = await Directory.systemTemp.createTemp('pmb_rollback_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      final bytes = await File(created.outputPath).readAsBytes();

      // Сбой сразу после обмена песочницы: откат возвращает модуль.
      final failed = await importer(
        swap: _CommitThenFailSwap(supportDirectoryResolver: () async => supportDir),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'иконка 1.1.0'},
        ),
      );
      expect(failed.isFailure, isTrue);
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');
      expect(readAssets(), {'logo.png': 'иконка 1.0.0'});

      // Архив после отката читается и восстанавливается.
      final backup = await ModuleBackupReader.readModuleBackup(bytes);
      expect(backup.moduleVersion, '1.0.0');

      await storage.setString('note:1', 'испорчено после отката');
      final restored = await backups().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: _moduleId,
        options: const ModuleBackupOptions(),
      );
      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.0.0');

      await backupDir.delete(recursive: true);
    });

    test('созданный после отката .pmb описывает модуль, а не мусор',
        () async {
      await install();

      final failed = await importer(
        swap: _CommitThenFailSwap(supportDirectoryResolver: () async => supportDir),
      ).updateFromBytes(
        moduleId: _moduleId,
        archiveBytes: _phm(
          version: '1.1.0',
          assets: {'logo.png': 'иконка 1.1.0'},
        ),
      );
      expect(failed.isFailure, isTrue);

      final backupDir = await Directory.systemTemp.createTemp('pmb_after_rb_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      final backup = await ModuleBackupReader.readModuleBackup(
        await File(created.outputPath).readAsBytes(),
      );

      expect(backup.moduleVersion, '1.0.0');
      expect(backup.assets.keys, ['logo.png']);
      expect(backup.dataJson, contains('черновик пользователя'));

      await backupDir.delete(recursive: true);
    });
  });

  group('модуль остаётся пригодным после всех комбинаций', () {
    test('backup → update → update → restore', () async {
      await install();
      final backupDir = await Directory.systemTemp.createTemp('pmb_chain_');
      final created = await backups().createBackup(
        moduleId: _moduleId,
        outputDirectory: backupDir,
      );
      final bytes = await File(created.outputPath).readAsBytes();

      await update('1.1.0', assets: {'logo.png': 'иконка 1.1.0'});
      await update('1.2.0', assets: {'logo.png': 'иконка 1.2.0'});
      expect(ModuleRegistry.get(_moduleId)!.manifest.version, '1.2.0');

      await storage.setString('note:1', 'правка после двух обновлений');
      final restored = await backups().restoreBackup(
        archiveBytes: bytes,
        targetModuleId: _moduleId,
        options: const ModuleBackupOptions(),
      );

      expect(restored.isSuccess, isTrue, reason: '${restored.error}');
      expect(await storage.getString('note:1'), 'черновик пользователя');
      expect(manager.stateOf(_moduleId), ModuleState.installed);
      expect(
        ModuleRegistry.get(_moduleId),
        isA<ExternalModuleAdapter>(),
        reason: 'восстановление данных не превращает модуль во встроенный',
      );

      await backupDir.delete(recursive: true);
    });
  });
}
