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
import '../modules/module_snapshot.dart';
import '../modules/module_state_store.dart';
import '../modules/platform/module_storage_serializer.dart';
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

/// Создаёт и восстанавливает .pmb для одного установленного модуля.
///
/// [stateStore] и [assetsDirectoryResolver] — внедряемые зависимости.
/// Без них используется боевая реализация (Isar-репозиторий и
/// ModuleSandbox). Это обычная конструкторная DI: она не добавляет
/// методов в ModuleManager, ModuleStorage или IsarService.
///
/// Съём снимка и откат делегированы ModuleSnapshotService — общему
/// механизму, который с Этапа 8 использует и обновление модуля. Здесь
/// он остаётся с теми же компонентами и в том же порядке, что были до
/// вынесения, поэтому поведение restore не меняется.
class ModuleBackupManager {
  ModuleBackupManager({
    required ModuleManager moduleManager,
    ModuleStateStore? stateStore,
    Future<Directory> Function(String moduleId)? assetsDirectoryResolver,
  })  : _moduleManager = moduleManager,
        _stateStore = stateStore,
        _assetsDirectoryResolver = assetsDirectoryResolver {
    _snapshots = ModuleSnapshotService(
      moduleManager: moduleManager,
      stateStore: stateStore,
      assetsDirectoryResolver: assetsDirectoryResolver,
    );
  }

  final ModuleManager _moduleManager;
  final ModuleStateStore? _stateStore;

  /// Остаётся и после вынесения снимка: тем же резолвером
  /// пользуется writer при создании .pmb — иначе экспорт и откат
  /// смотрели бы в разные каталоги ассетов.
  final Future<Directory> Function(String moduleId)? _assetsDirectoryResolver;
  late final ModuleSnapshotService _snapshots;

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
    final snapshot = await _snapshots.capture(
      moduleId: moduleId,
      components: _componentsFor(options),
    );

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
      final List<String> rolledBack;
      try {
        rolledBack = await _snapshots.rollback(
          snapshot,
          attemptedComponents: attempted,
        );
      } on ModuleSnapshotRollbackException catch (rollbackError) {
        // Наружу выходит тот же тип, что и до вынесения механизма:
        // ModuleSnapshotService не знает про слой backup и не может
        // бросать его исключения, поэтому перевод здесь.
        throw ModuleRestoreException(rollbackError.message);
      }
      return ModuleRestoreResult.failure(
        moduleId: moduleId,
        error: error,
        appliedComponents: List.unmodifiable(applied),
        rolledBackComponents: rolledBack,
      );
    }
  }

  /// Компоненты снимка по опциям restore.
  ///
  /// Ровно те же условия, по которым снимок снимался раньше: если
  /// опция выключена, её данные не снимались и откат их не трогает.
  Set<ModuleSnapshotComponent> _componentsFor(
    ModuleBackupOptions options,
  ) {
    return <ModuleSnapshotComponent>{
      if (options.includeData) ModuleSnapshotComponent.storage,
      if (options.includeState) ModuleSnapshotComponent.state,
      if (options.includeAssets) ModuleSnapshotComponent.assets,
    };
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

    // Версия в state.json описывает АРХИВ, а установленная версия — это
    // то, что сейчас в ModuleRegistry (manifest.version). Поэтому в
    // хранилище уходит снимок с версией реестра: иначе после restore в
    // приложении появился бы второй источник истины о версии, и любое
    // решение по версии (например, какую миграцию данных запускать в
    // Этапе 9) опиралось бы на версию из архива вместо реально
    // установленной. Тот же принцип держит ModuleStatePersistence._sync.
    final currentVersion = ModuleRegistry.get(moduleId)?.manifest.version;
    final effective = currentVersion == null || currentVersion == snapshot.installedVersion
        ? snapshot
        : ModuleStateSnapshot(
            moduleId: snapshot.moduleId,
            state: snapshot.state,
            installedVersion: currentVersion,
            enabled: snapshot.enabled,
            installedAt: snapshot.installedAt,
            updatedAt: snapshot.updatedAt,
          );

    // Сначала хранилище, потом ModuleManager. Порядок выбран из-за
    // асинхронности: adoptRestoredState() вызывает notifyListeners(),
    // на который ModuleStatePersistence отвечает собственной записью.
    // Если бы adopt шёл первым, его запись могла бы прийти в любой
    // момент относительно store.save() ниже, и итоговое значение
    // installedVersion зависел бы от того, кто завершился раньше.
    await store.save(effective);

    // Состояние в памяти обязано стать тем же, что и в архиве: иначе
    // ModuleManager остаётся источником старого состояния, и следующая
    // же синхронизация вернёт его обратно поверх restore (R-01).
    await _moduleManager.adoptRestoredState(effective);
  }

  Future<void> _applyData(String moduleId, String dataJson) async {
    await ModuleStorageSerializer.deserialize(
      jsonString: dataJson,
      storage: _moduleManager.apiFor(moduleId).storage,
      expectedModuleId: moduleId,
    );
  }

  Future<void> _applyAssets(String moduleId, Map<String, List<int>> assets) async {
    final dir = await _snapshots.resolveAssetsDirectory(moduleId);
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
