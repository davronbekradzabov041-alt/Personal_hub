/// Module backup manager — создание и восстановление .pmb.
///
/// Инварианты этого файла:
///
/// 1. **Идентичность.** Restore идёт ТОЛЬКО в модуль с тем же
///    `moduleId`, что и в backup. `moduleId` — неизменная
///    идентичность: новый id не создаётся, модуль из .pmb не
///    устанавливается (.pmb — не .phm).
///
/// 2. **Атомарность через предварительный снимок.** До любой записи
///    снимается полный снимок того, что будет изменено (storage,
///    state, assets). Откат = восстановление этого снимка, а НЕ
///    «очистить хранилище»: очистка уничтожила бы данные,
///    существовавшие ДО restore.
///
/// 3. **Изоляция.** Всё идёт через `apiFor(moduleId).storage` и
///    assets-каталог конкретного модуля. Другой модуль не затрагивается.
///
/// 4. **Concurrency.** Restore одного moduleId сериализован, поэтому
///    откат одного restore не может уничтожить другой. Restore разных
///    moduleId выполняется параллельно, без взаимной блокировки.
library module_backup_manager;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../modules/module_manager.dart';
import '../modules/module_registry.dart' show ModuleRegistry;
import '../modules/module_state.dart';
import '../modules/module_state_store.dart';
import '../modules/platform/module_storage_serializer.dart';
import '../modules/platform/module_sandbox.dart';
import 'backup_exceptions.dart';
import 'atomic_file_writer.dart';
import 'module_backup_options.dart';
import 'module_backup_reader.dart';
import 'module_backup_writer.dart';

/// Результат создания .pmb.
class ModuleBackupResult {
  final String outputPath;
  final int sizeBytes;
  final DateTime createdAt;
  final String moduleId;
  final String moduleVersion;
  final ModuleBackupOptions options;

  const ModuleBackupResult({
    required this.outputPath,
    required this.sizeBytes,
    required this.createdAt,
    required this.moduleId,
    required this.moduleVersion,
    required this.options,
  });
}

/// Результат восстановления из .pmb.
class ModuleRestoreResult {
  final bool isSuccess;
  final String moduleId;

  /// Компоненты, реально применённые (`state` / `data` / `assets`).
  final List<String> appliedComponents;

  /// Компоненты, возвращённые в прежнее состояние при неудаче.
  final List<String> rolledBackComponents;

  final Object? error;

  const ModuleRestoreResult._({
    required this.isSuccess,
    required this.moduleId,
    this.appliedComponents = const [],
    this.rolledBackComponents = const [],
    this.error,
  });

  const ModuleRestoreResult.success({
    required String moduleId,
    required List<String> appliedComponents,
  }) : this._(
          isSuccess: true,
          moduleId: moduleId,
          appliedComponents: appliedComponents,
        );

  const ModuleRestoreResult.failure({
    required String moduleId,
    required Object error,
    List<String> appliedComponents = const [],
    List<String> rolledBackComponents = const [],
  }) : this._(
          isSuccess: false,
          moduleId: moduleId,
          appliedComponents: appliedComponents,
          rolledBackComponents: rolledBackComponents,
          error: error,
        );
}

/// Снимок текущего содержимого модуля — полная основа для отката.
///
/// Содержит ТОЛЬКО те компоненты, которые restore будет менять: если
/// assets не участвуют, снимок по ним не снимается, чтобы откат не
/// трогал то, что он не менял.
class _ModuleSnapshot {
  final String moduleId;
  final Map<String, String> storage;
  final ModuleStateSnapshot? state;

  /// Состояние в ModuleManager ДО restore.
  ///
  /// Откат обязан вернуть и его: одного лишь хранилища мало, иначе после
  /// неудачного restore менеджер остался бы с состоянием из архива, а
  /// следующая синхронизация записала бы его в хранилище — модуль был бы
  /// «наполовину восстановлен».
  ///
  /// null/uninstalled невозможны: restoreBackup отказывается работать с
  /// неустановленным модулем.
  final ModuleState? managerState;

  final Map<String, List<int>> assets;
  final bool assetsDirExisted;

  const _ModuleSnapshot({
    required this.moduleId,
    required this.storage,
    required this.state,
    required this.managerState,
    required this.assets,
    required this.assetsDirExisted,
  });
}

/// Создаёт и восстанавливает .pmb для одного установленного модуля.
///
/// [stateStore] и [assetsDirectoryResolver] — внедряемые зависимости.
/// Без них используется боевая реализация (Isar-репозиторий и
/// ModuleSandbox). Это обычная конструкторная DI: она не добавляет
/// методов в ModuleManager, ModuleStorage или IsarService.
class ModuleBackupManager {
  ModuleBackupManager({
    required ModuleManager moduleManager,
    ModuleStateStore? stateStore,
    Future<Directory> Function(String moduleId)? assetsDirectoryResolver,
  })  : _moduleManager = moduleManager,
        _stateStore = stateStore,
        _assetsDirectoryResolver = assetsDirectoryResolver;

  final ModuleManager _moduleManager;
  final ModuleStateStore? _stateStore;
  final Future<Directory> Function(String moduleId)? _assetsDirectoryResolver;

  /// Создаёт .pmb-архив для установленного модуля.
  ///
  /// Бросает [BackupException], если модуль не зарегистрирован или
  /// не установлен.
  Future<ModuleBackupResult> createBackup({
    required String moduleId,
    required Directory outputDirectory,
    ModuleBackupOptions options = const ModuleBackupOptions(),
  }) async {
    final bytes = await ModuleBackupWriter(
      stateStore: _stateStore,
      assetsDirectoryResolver: _assetsDirectoryResolver,
    ).writeModuleBackup(
      manager: _moduleManager,
      moduleId: moduleId,
      options: options,
    );

    final file = File(path.join(
      outputDirectory.path,
      'module_${moduleId}_${DateTime.now().microsecondsSinceEpoch}.pmb',
    ));
    // temp → rename: оборванный процесс не оставит «наполовину
    // записанный» .pmb, который выглядел бы валидным файлом.
    await writeFileAtomically(file, bytes);

    return ModuleBackupResult(
      outputPath: file.path,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
      moduleId: moduleId,
      moduleVersion: ModuleRegistry.get(moduleId)!.manifest.version,
      options: options,
    );
  }

  /// Восстанавливает модуль из .pmb-архива.
  ///
  /// [targetModuleId] — модуль, в который восстанавливаем; обязан
  /// совпасть с `moduleId` из архива, иначе отказ без изменения
  /// данных. [options] задаёт partial restore: например
  /// `ModuleBackupOptions.dataOnly()` восстановит только ModuleStorage.
  ///
  /// Бросает [BackupException] при провале валидации и
  /// [ModuleRestoreException], если не удалось выполнить откат.
  Future<ModuleRestoreResult> restoreBackup({
    required List<int> archiveBytes,
    required String targetModuleId,
    ModuleBackupOptions options = const ModuleBackupOptions(),
  }) async {
    // Валидация архива: security → структура → manifest → checksum.
    // До этого момента не меняется НИЧЕГО.
    final backup = await ModuleBackupReader.readModuleBackup(archiveBytes);

    // Идентичность: backup.moduleId == target.moduleId.
    if (backup.moduleId != targetModuleId) {
      throw ModuleIdMismatchException(
        expected: targetModuleId,
        actual: backup.moduleId,
      );
    }

    // Модуль должен быть уже установлен — .pmb не устанавливает модуль.
    if (!ModuleRegistry.contains(targetModuleId)) {
      throw ModuleNotInstalledException(targetModuleId, 'модуль не зарегистрирован');
    }
    if (!_moduleManager.isInstalled(targetModuleId)) {
      throw ModuleNotInstalledException(targetModuleId, 'модуль не установлен');
    }

    return _serializeRestore(targetModuleId, () {
      return _restoreInternal(backup, targetModuleId, options);
    });
  }

  // -------------------------------------------------------------------
  // Restore internals
  // -------------------------------------------------------------------

  Future<ModuleRestoreResult> _restoreInternal(
    ModuleBackup backup,
    String moduleId,
    ModuleBackupOptions options,
  ) async {
    // Снимок ДО любых записей — единственная основа для отката.
    final snapshot = await _captureSnapshot(moduleId, options);

    // attempted — компоненты, которые НАЧАЛИ применяться; applied —
    // те, что успешно завершились (это попадает в отчёт).
    //
    // Откатывать нужно attempted, а не applied: компонент, упавший
    // ПОСЕРЕДИНЕ записи (например, рваная запись в ModuleStorage),
    // не попадает в applied, но уже изменил данные. Откат только по
    // applied молча оставил бы эти изменения в модуле.
    final applied = <String>[];
    final attempted = <String>[];
    try {
      if (options.includeState && backup.stateJson != null) {
        attempted.add('state');
        await _applyState(moduleId, backup.stateJson!);
        applied.add('state');
      }
      if (options.includeData && backup.dataJson != null) {
        attempted.add('data');
        await _applyData(moduleId, backup.dataJson!);
        applied.add('data');
      }
      if (options.includeAssets && backup.assets.isNotEmpty) {
        attempted.add('assets');
        await _applyAssets(moduleId, backup.assets);
        applied.add('assets');
      }

      return ModuleRestoreResult.success(
        moduleId: moduleId,
        appliedComponents: List.unmodifiable(applied),
      );
    } catch (error) {
      final rolledBack = await _rollback(snapshot, attempted);
      return ModuleRestoreResult.failure(
        moduleId: moduleId,
        error: error,
        appliedComponents: List.unmodifiable(applied),
        rolledBackComponents: rolledBack,
      );
    }
  }

  Future<_ModuleSnapshot> _captureSnapshot(
    String moduleId,
    ModuleBackupOptions options,
  ) async {
    final storage = <String, String>{};
    if (options.includeData) {
      final moduleStorage = _moduleManager.apiFor(moduleId).storage;
      for (final key in await moduleStorage.keys()) {
        final value = await moduleStorage.getString(key);
        if (value != null) storage[key] = value;
      }
    }

    final store = _stateStore;
    final state =
        (options.includeState && store != null) ? await store.load(moduleId) : null;

    final assets = <String, List<int>>{};
    var assetsDirExisted = false;
    if (options.includeAssets) {
      final dir = await _resolveAssetsDirectory(moduleId);
      assetsDirExisted = await dir.exists();
      if (assetsDirExisted) {
        for (final entity in await dir.list().toList()) {
          if (entity is File) {
            assets[path.basename(entity.path)] = await entity.readAsBytes();
          }
        }
      }
    }

    return _ModuleSnapshot(
      moduleId: moduleId,
      storage: storage,
      state: state,
      managerState: _moduleManager.stateOf(moduleId),
      assets: assets,
      assetsDirExisted: assetsDirExisted,
    );
  }

  Future<void> _applyState(String moduleId, String stateJson) async {
    final store = _stateStore;
    if (store == null) return;

    final decoded = jsonDecode(stateJson);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('state.json не является объектом');
    }
    // Идентичность внутри state.json обязана совпадать с целевым
    // модулем — иначе в модуль уедут чужое состояние и версия.
    final snapshotModuleId = decoded['moduleId'];
    if (snapshotModuleId != moduleId) {
      throw ModuleIdMismatchException(
        expected: moduleId,
        actual: '$snapshotModuleId',
      );
    }
    final snapshot = ModuleStateSnapshot.fromJson(decoded);

    // Сначала хранилище, потом ModuleManager. Порядок выбран из-за
    // асинхронности: adoptRestoredState() вызывает notifyListeners(),
    // на который ModuleStatePersistence отвечает собственной записью.
    // Если бы adopt шёл первым, его запись могла бы прийти в любой
    // момент относительно store.save() ниже, и итоговое значение
    // installedVersion зависел бы от того, кто завершился раньше.
    await store.save(snapshot);

    // Состояние в памяти обязано стать тем же, что и в архиве: иначе
    // ModuleManager остаётся источником старого состояния, и следующая
    // же синхронизация вернёт его обратно поверх restore (R-01).
    await _moduleManager.adoptRestoredState(snapshot);
  }

  Future<void> _applyData(String moduleId, String dataJson) async {
    await ModuleStorageSerializer.deserialize(
      jsonString: dataJson,
      storage: _moduleManager.apiFor(moduleId).storage,
      expectedModuleId: moduleId,
    );
  }

  Future<void> _applyAssets(String moduleId, Map<String, List<int>> assets) async {
    final dir = await _resolveAssetsDirectory(moduleId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Сначала пишем во временный каталог, затем переносим: если процесс
    // упадёт посередине, прежние файлы ещё целы.
    final staging = Directory('${dir.path}.pmb_restore_tmp');
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    try {
      for (final entry in assets.entries) {
        await File(path.join(staging.path, entry.key)).writeAsBytes(entry.value);
      }
      for (final entity in await dir.list().toList()) {
        if (entity is File) {
          await entity.delete();
        }
      }
      for (final entity in await staging.list().toList()) {
        if (entity is File) {
          await entity.rename(path.join(dir.path, path.basename(entity.path)));
        }
      }
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// Возвращает модуль к [_ModuleSnapshot].
  ///
  /// [attempted] — компоненты, которые начали применяться, включая
  /// упавшие посередине: их данные уже изменены, даже если этап не
  /// завершился. Откатывает ИХ ПРЕЖНИЕ значения, включая удалённые
  /// ключи и файлы. Если откат не удался, бросает
  /// [ModuleRestoreException]: наполовину откатанный модуль опаснее
  /// явно сообщённой ошибки.
  Future<List<String>> _rollback(
    _ModuleSnapshot snapshot,
    List<String> attempted,
  ) async {
    final rolledBack = <String>[];
    final failures = <Object>[];

    for (final component in attempted) {
      try {
        switch (component) {
          case 'state':
            final store = _stateStore;
            if (store != null) {
              final previous = snapshot.state;
              if (previous == null) {
                await store.delete(snapshot.moduleId);
              } else {
                await store.save(previous);
              }
            }
            await _rollbackManagerState(snapshot);
            rolledBack.add('state');
          case 'data':
            await _restoreStorage(snapshot.moduleId, snapshot.storage);
            rolledBack.add('data');
          case 'assets':
            await _restoreAssets(
              snapshot.moduleId,
              snapshot.assets,
              snapshot.assetsDirExisted,
            );
            rolledBack.add('assets');
        }
      } catch (error) {
        failures.add(error);
      }
    }

    if (failures.isNotEmpty) {
      throw ModuleRestoreException('откат не удался: ${failures.join("; ")}');
    }
    return rolledBack;
  }

  /// Возвращает ModuleManager к состоянию, которое было до restore.
  ///
  /// Идёт через тот же контракт adoptRestoredState, что и сам restore, —
  /// иначе откат состоял бы в прямой записи в приватную карту и не
  /// запускал бы нужные lifecycle-хуки (модуль, ставший неактивным
  /// из-за restore, должен снова отписаться от поиска, и наоборот).
  Future<void> _rollbackManagerState(_ModuleSnapshot snapshot) async {
    final prior = snapshot.managerState;
    if (prior == null || prior == ModuleState.uninstalled) return;

    final moduleId = snapshot.moduleId;
    if (_moduleManager.stateOf(moduleId) == prior) return;

    final previous = snapshot.state;
    await _moduleManager.adoptRestoredState(ModuleStateSnapshot(
      moduleId: moduleId,
      state: prior.name,
      installedVersion: previous?.installedVersion ?? '',
      enabled: prior == ModuleState.enabled,
      installedAt: previous?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _restoreStorage(
    String moduleId,
    Map<String, String> expected,
  ) async {
    final storage = _moduleManager.apiFor(moduleId).storage;

    // Убрать всё, чего не было до restore.
    for (final key in await storage.keys()) {
      if (!expected.containsKey(key)) {
        await storage.remove(key);
      }
    }
    // Вернуть прежние значения перезаписанных ключей.
    for (final entry in expected.entries) {
      await storage.setString(entry.key, entry.value);
    }
  }

  Future<void> _restoreAssets(
    String moduleId,
    Map<String, List<int>> expected,
    bool dirExisted,
  ) async {
    final dir = await _resolveAssetsDirectory(moduleId);

    if (await dir.exists()) {
      for (final entity in await dir.list().toList()) {
        if (entity is File) await entity.delete();
      }
    }
    if (expected.isEmpty) {
      if (!dirExisted && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (final entry in expected.entries) {
      await File(path.join(dir.path, entry.key)).writeAsBytes(entry.value);
    }
  }

  Future<Directory> _resolveAssetsDirectory(String moduleId) async {
    final resolver = _assetsDirectoryResolver;
    if (resolver != null) return resolver(moduleId);
    return ModuleSandbox.getAssetsDirectory(moduleId);
  }

  // -------------------------------------------------------------------
  // Concurrency
  // -------------------------------------------------------------------

  /// Очередь restore-задач на каждый moduleId: два параллельных restore
  /// одного модуля выполняются строго последовательно, поэтому откат
  /// одного не может уничтожить результат другого. Ключи разных
  /// модулей не конфликтуют и выполняются параллельно.
  static final Map<String, Future<void>> _restoreChains = {};

  Future<T> _serializeRestore<T>(
    String moduleId,
    Future<T> Function() body,
  ) async {
    final previous = _restoreChains[moduleId] ?? Future<void>.value();
    final gate = Completer<void>();

    // Ошибка в предыдущем restore не должна сломать очередь.
    final chain = previous.catchError((Object _) {}).then((_) => gate.future);
    _restoreChains[moduleId] = chain;

    try {
      await previous.catchError((Object _) {});
      return await body();
    } finally {
      gate.complete();
      // Снимаем цепочку, только если её не продолжил кто-то ещё.
      if (identical(_restoreChains[moduleId], chain)) {
        _restoreChains.remove(moduleId);
      }
    }
  }
}
