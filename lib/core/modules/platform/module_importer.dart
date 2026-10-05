import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../external/external_module_adapter.dart';
import '../module.dart';
import '../module_manifest.dart';
import '../module_manager.dart';
import '../module_registry.dart';
import '../module_snapshot.dart';
import '../module_state.dart';
import '../module_state_store.dart';
import 'package_content.dart';
import 'package_reader.dart';
import 'module_sandbox.dart';
import 'module_sandbox_swap.dart';
import 'package_exceptions.dart';
import 'sandbox_exceptions.dart';
import 'module_storage_serializer.dart';
import 'importer_exceptions.dart';

// Global mutex to serialize concurrent imports across all ModuleImporter instances
bool _globalImportLockHeld = false;
final List<Completer<void>> _globalImportWaitQueue = <Completer<void>>[];

Future<void> _acquireGlobalImportLock() async {
  if (!_globalImportLockHeld) {
    _globalImportLockHeld = true;
    return;
  }
  final completer = Completer<void>();
  _globalImportWaitQueue.add(completer);
  await completer.future;
}

void _releaseGlobalImportLock() {
  if (_globalImportWaitQueue.isNotEmpty) {
    final next = _globalImportWaitQueue.removeAt(0);
    next.complete();
  } else {
    _globalImportLockHeld = false;
  }
}

/// Result of a module import operation.
class ModuleImportOutcome {
  final bool isSuccess;
  final String? moduleId;
  final String? error;
  final List<String> violations;

  /// Обновление, а не первая установка.
  ///
  /// Отдельный флаг, а не вывод из наличия moduleId: вызывающий
  /// показывает пользователю разное («установлен» / «обновлён»), а
  /// переписывать прежнее сообщение «успешно импортирован» после
  /// появления обновлений значило бы врать о том, что произошло.
  final bool isUpdate;

  const ModuleImportOutcome._({
    required this.isSuccess,
    this.moduleId,
    this.error,
    this.violations = const [],
    this.isUpdate = false,
  });

  const ModuleImportOutcome.success(String moduleId, {bool isUpdate = false})
      : this._(isSuccess: true, moduleId: moduleId, isUpdate: isUpdate);

  const ModuleImportOutcome.failure(String error,
      {List<String> violations = const [], bool isUpdate = false})
      : this._(
          isSuccess: false,
          error: error,
          violations: violations,
          isUpdate: isUpdate,
        );

  bool get isFailure => !isSuccess;
}

/// Orchestrates the import of external .phm modules with full transaction rollback.
///
/// The import pipeline:
/// 1. Read & validate .phm package (PackageReader + PackageSecurityGuard)
/// 2. Validate manifest (ManifestValidator + dependency checks)
/// 3. Check moduleId (not duplicate, not builtin)
/// 4. Prepare new version in a staging directory next to `modules/`
/// 5. Extract assets to that staging directory
/// 6. Create ExternalModuleAdapter & register in ModuleRegistry
/// 7. Seed ModuleStorage from data/storage.json
/// 8. Call ModuleManager.tryInstall()
/// 9. Atomic sandbox swap (staging -> permanent, previous version kept aside)
/// 10. Return success
///
/// On ANY failure after step 6, full rollback is performed:
/// 1. ModuleRegistry.unregister()
/// 2. ModuleStorage keys cleared
/// 3. Permanent sandbox removed / previous version returned
/// 4. Staging directory removed
/// 5. ModuleManager state restored
///
/// Обновление (Этап 8.1-Б) — отдельный путь [updateFromBytes] с тем же
/// набором механизмов, но другим смыслом каждого шага: он не имеет
/// права удалить пользовательские данные, поэтому здесь снимок и
/// возврат песочницы обязательны, а `uninstall + install` запрещён.
class ModuleImporter {
  final ModuleManager _moduleManager;
  final ModulePackageReader _packageReader;
  final ModuleSandboxSwap _sandboxSwap;
  final ModuleSnapshotService _snapshots;

  /// Песочница обмена и снимки создаются здесь, а не внутри операции:
  /// они держат состояние между шагами (каталог прежней версии, снимок
  /// для отката), и собирать их заново на каждом шаге означало бы
  /// потерять именно то, ради чего они нужны.
  ///
  /// [sandboxSwap] и [stateStore] внедряются, чтобы тест мог подменить
  /// файловую систему и хранилище состояния: боевые резолверы работают
  /// через path_provider, который в тесте недоступен.
  ModuleImporter({
    required ModuleManager moduleManager,
    ModulePackageReader? packageReader,
    Directory? testSupportDir,
    ModuleSandboxSwap? sandboxSwap,
    ModuleStateStore? stateStore,
  })  : _moduleManager = moduleManager,
        _packageReader = packageReader ?? ModulePackageReader(),
        _sandboxSwap = sandboxSwap ??
            ModuleSandboxSwap(
              supportDirectoryResolver: testSupportDir == null
                  ? null
                  : () async => testSupportDir,
            ),
        _snapshots = ModuleSnapshotService(
          moduleManager: moduleManager,
          stateStore: stateStore,
          // Тот же корень, что и у обмена песочницей: снимок ассетов
          // обязан снимать ИМЕННО те файлы, которые обмен потом заменит.
          assetsDirectoryResolver: testSupportDir == null
              ? null
              : (moduleId) async => Directory(path.join(
                    testSupportDir.path,
                    'modules',
                    moduleId,
                    'assets',
                  )),
        );

  /// Imports a .phm package from bytes.
  ///
  /// Returns [ModuleImportOutcome] with success/failure details.
  /// All exceptions are caught and converted to failure outcomes.
  /// Concurrent calls are serialized — second call waits for first to complete.
  Future<ModuleImportOutcome> importFromBytes(List<int> archiveBytes) async {
    await _acquireGlobalImportLock();
    try {
      return await _importFromBytesInternal(archiveBytes);
    } finally {
      _releaseGlobalImportLock();
    }
  }

  /// Internal import implementation (called with lock held).
  Future<ModuleImportOutcome> _importFromBytesInternal(List<int> archiveBytes) async {
    String? moduleId;
    bool moduleRegistered = false;
    Directory? stagedDirectory;
    ModuleSandboxSwapResult? swapResult;
    bool installAttempted = false;

    try {
      // ============================================================
      // STEP 1: Read & validate package
      // ============================================================
      final existingIds = ModuleRegistry.modules.map((m) => m.id).toSet();
      final content = _packageReader.readBytes(
        archiveBytes,
        existingModuleIds: existingIds,
      );

      moduleId = content.manifest.id;

      // ============================================================
      // STEP 1.5: Validate moduleId format BEFORE any filesystem use
      // ============================================================
      // moduleId приходит из недоверенного .phm и подставляется в
      // filesystem path (staging, permanent sandbox). Валидация
      // обязана предшествовать любой операции с ФС, иначе id вида
      // "../../Documents" уводит создание/удаление каталога за пределы
      // personal_hub_modules. Правила — те же, что у ModuleSandbox.
      try {
        ModuleSandbox.validateModuleId(moduleId);
      } on InvalidModuleIdException catch (e) {
        return ModuleImportOutcome.failure(
          'невалидный moduleId: ${e.reason}',
          violations: const ['invalid_module_id'],
        );
      }

      // ============================================================
      // STEP 2: Check for duplicate/builtin moduleId
      // ============================================================
      if (ModuleRegistry.contains(moduleId)) {
        final existing = ModuleRegistry.get(moduleId);
        if (existing != null && existing is! ExternalModuleAdapter) {
          return ModuleImportOutcome.failure(
            'moduleId "$moduleId" уже зарегистрирован',
            violations: ['duplicate_module_id'],
          );
        }
      }

      // Check if it's a builtin module (from module_bootstrap)
      if (_isBuiltinModule(moduleId)) {
        return ModuleImportOutcome.failure(
          'moduleId "$moduleId" является встроенным модулем и не может быть заменен',
          violations: ['builtin_module_id'],
        );
      }

      // ============================================================
      // STEP 3: Prepare staging directory for the new version
      // ============================================================
      // Раньше здесь был каталог в `modules_tmp/`, который перед
      // переносом УДАЛЯЛСЯ вместе с прежней песочницей: между этими
      // двумя действиями модуля не было вообще ничего. Теперь новую
      // версию собирают рядом с `modules/`, а на место она встаёт
      // переносом (ModuleSandboxSwap) — см. комментарий в этом файле
      // про «delete → rename».
      stagedDirectory = await _sandboxSwap.createStaging(moduleId: moduleId);

      // ============================================================
      // STEP 4: Extract assets to the staging directory
      // ============================================================
      await _extractAssetsToSandbox(content, stagedDirectory);

      // ============================================================
      // STEP 5: Create ExternalModuleAdapter & register
      // ============================================================
      final adapter = ExternalModuleAdapter(content.manifest);
      ModuleRegistry.register(adapter);
      moduleRegistered = true;

      // ============================================================
      // STEP 6: Seed ModuleStorage
      // ============================================================
      if (content.data != null) {
        final storage = _moduleManager.apiFor(moduleId).storage;
        // Construct full JSON structure expected by ModuleStorageSerializer
        final storageJson = jsonEncode({
          'version': ModuleStorageSerializer.currentVersion,
          'moduleId': moduleId,
          'entries': content.data!.storage,
        });
        await ModuleStorageSerializer.deserialize(
          jsonString: storageJson,
          storage: storage,
          expectedModuleId: moduleId,
        );
      }

      // ============================================================
      // STEP 7: Install via ModuleManager
      // ============================================================
      installAttempted = true;
      final installResult = await _moduleManager.tryInstall(moduleId);
      if (!installResult.isSuccess) {
        throw ImporterModuleManagerException(
          operation: 'tryInstall',
          reason: installResult.reason ?? 'unknown',
        );
      }

      // ============================================================
      // STEP 8: Atomic sandbox swap (staging -> permanent)
      // ============================================================
      swapResult = await _sandboxSwap.commit(
        moduleId: moduleId,
        stagedDirectory: stagedDirectory,
      );

      // Прежняя версия при установке не должна существовать (дубликат
      // id отбит выше), но если каталог-остаток всё же есть — он не
      // нужен и обязан исчезнуть вместе с успешной установкой.
      final previousDirectory = swapResult.previousDirectory;
      if (previousDirectory != null) {
        await _sandboxSwap.discardPrevious(
          moduleId: moduleId,
          previousDirectory: previousDirectory,
        );
      }

      return ModuleImportOutcome.success(moduleId);
    } catch (e) {
      // ============================================================
      // ROLLBACK on any failure
      // ============================================================
      await _rollback(
        moduleId: moduleId,
        moduleRegistered: moduleRegistered,
        stagedDirectory: stagedDirectory,
        swapResult: swapResult,
        installAttempted: installAttempted,
        originalError: e,
      );

      return ModuleImportOutcome.failure(
        e is ImporterException ? e.message : e.toString(),
        violations: [],
      );
    }
  }

  /// Checks if a moduleId belongs to a builtin module.
  bool _isBuiltinModule(String moduleId) {
    // Builtin modules are registered in ModuleRegistry at startup
    // via module_bootstrap.dart. We check if the registered module
    // is NOT an ExternalModuleAdapter (which would be an imported one).
    final module = ModuleRegistry.get(moduleId);
    if (module == null) return false;
    return module is! ExternalModuleAdapter;
  }

  /// Extracts all assets from package content to sandbox.
  Future<void> _extractAssetsToSandbox(PackageContent content, Directory sandboxDir) async {
    final assetsDir = Directory(path.join(sandboxDir.path, 'assets'));
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }

    for (final asset in content.assets) {
      final assetFile = File(path.join(assetsDir.path, path.basename(asset.path)));
      await assetFile.writeAsBytes(asset.bytes);
    }

    // Also write README if present
    if (content.readme != null && content.readme!.isNotEmpty) {
      final readmeFile = File(path.join(sandboxDir.path, 'README.md'));
      await readmeFile.writeAsString(content.readme!);
    }
  }

  /// Performs full rollback on import failure.
  Future<void> _rollback({
    required String? moduleId,
    required bool moduleRegistered,
    required Directory? stagedDirectory,
    required ModuleSandboxSwapResult? swapResult,
    required bool installAttempted,
    required Object originalError,
  }) async {
    if (moduleId == null) return;

    // 1. Clear ModuleStorage FIRST (while module is still registered)
    if (moduleRegistered) {
      try {
        final storage = _moduleManager.apiFor(moduleId).storage;
        final keys = await storage.keys();
        for (final key in keys) {
          await storage.remove(key);
        }
      } catch (_) {
        // Best effort
      }
    }

    // 2. Unregister module from registry
    if (moduleRegistered) {
      try {
        ModuleRegistry.unregister(moduleId);
      } catch (_) {
        // Best effort
      }
    }

    // 3. Вернуть песочницу в прежнее состояние.
    //
    // Если обмен уже состоялся, но прежней версии не было (первая
    // установка), возвращать нечего — тогда на месте модуля стоит
    // версия, которой до сбоя не существовало, и её надлежит убрать.
    // Если прежняя версия была, она лежит целым в previousDirectory.
    if (swapResult != null) {
      try {
        final previousDirectory = swapResult.previousDirectory;
        if (previousDirectory != null) {
          await _sandboxSwap.restorePrevious(
            moduleId: moduleId,
            previousDirectory: previousDirectory,
          );
        } else {
          final permanent = await _sandboxSwap.permanentDirectory(moduleId);
          if (await permanent.exists()) {
            await permanent.delete(recursive: true);
          }
        }
      } catch (_) {
        // Best effort
      }
    }

    // 4. Delete staging directory
    if (stagedDirectory != null) {
      try {
        await _sandboxSwap.discardStaging(stagedDirectory);
      } catch (_) {
        // Best effort
      }
    }

    // 5. Restore ModuleManager state if install was attempted
    // moduleId к этому моменту уже присвоен из манифеста пакета:
    // installAttempted ставится в true только на шаге установки.
    if (installAttempted) {
      try {
        // ModuleManager.tryInstall already handles rollback internally,
        // but we ensure clean state here too
        final state = _moduleManager.stateOf(moduleId);
        if (state != null && state != ModuleState.uninstalled) {
          // ModuleManager's internal rollback should have handled this,
          // but we don't have direct access to _states. The public API
          // doesn't expose a way to clear state, so we rely on tryInstall's
          // internal rollback which runs before this.
        }
      } catch (_) {
        // Best effort
      }
    }
  }

  // ================================================================
  // ОБНОВЛЕНИЕ (Этап 8.1-Б)
  // ================================================================

  /// Обновляет уже установленный внешний модуль пакетом [archiveBytes].
  ///
  /// Отдельный метод, а не ветка внутри [importFromBytes]: импорт
  /// отказывает уже установленному moduleId (см. контракт модуля),
  /// и «молча превращать отказ в обновление» означало бы отменять
  /// чужое правило без нужды. Обновление — осознанное действие
  /// вызывающего, и целевой [moduleId] он знает заранее: подмена id в
  /// пакете отбивается проверкой, а не молчаливой установкой чужого
  /// модуля вместо запрошенного.
  ///
  /// Порядок шагов — тот же, что в требованиях Этапа 8:
  /// `проверки → снимок → подготовка → обмен песочницы → обмен
  /// реестра → успех`, и он выбран так, чтобы подготовленное никогда
  /// не стояло раньше проверенного, а снимок снимался до первой
  /// записи.
  ///
  /// Хранилище при обновлении НЕ переписывается. `data/storage.json`
  /// новой версии — это данные для ЧИСТОЙ установки; переносить их
  /// поверх пользовательских значило бы затереть их, а удалять ключи,
  /// которых в новом пакете нет, — потерять данные пользователя. Свои
  /// данные модуля переживают обновление как есть.
  ///
  /// Конкурентный вызов ждёт в общей с импортом очереди: обмен
  /// песочницы и реестра одного модуля не должен выполняться
  /// одновременно с установкой или обновлением того же модуля.
  Future<ModuleImportOutcome> updateFromBytes({
    required String moduleId,
    required List<int> archiveBytes,
  }) async {
    await _acquireGlobalImportLock();
    try {
      return await _updateFromBytesInternal(moduleId, archiveBytes);
    } finally {
      _releaseGlobalImportLock();
    }
  }

  /// Обновляет модуль пакетом [archiveBytes], определяя модуль по
  /// манифесту самого пакета.
  ///
  /// Для сценария «пользователь выбрал файл» (UI не знает, какой
  /// модуль в файле): идентичность берётся из manifest.json, и если
  /// модуль с таким id не установлен — обновлять нечего, поэтому
  /// возвращается отказ с кодом `module_not_installed` и указанием на
  /// импорт. Молча установить или установить ЧУЖОЙ модуль здесь было бы
  /// тем же, чем «найти модуль по имени файла».
  ///
  /// Всё, что определяет поведение обновления, живёт в
  /// [updateFromBytes]: этот метод только спрашивает у пакета, кто он,
  /// и передаёт управление.
  Future<ModuleImportOutcome> updateFromPackageBytes(
    List<int> archiveBytes,
  ) async {
    final ModuleManifest manifest;
    try {
      manifest = _packageReader.readManifest(archiveBytes);
    } on PackageException catch (e) {
      return ModuleImportOutcome.failure(
        'пакет не прочитан: ${e.message}',
        isUpdate: true,
      );
    }

    return updateFromBytes(
      moduleId: manifest.id,
      archiveBytes: archiveBytes,
    );
  }

  Future<ModuleImportOutcome> _updateFromBytesInternal(
    String moduleId,
    List<int> archiveBytes,
  ) async {
    Module? previousModule;
    ModuleSnapshot? snapshot;
    Directory? stagedDirectory;
    ModuleSandboxSwapResult? swapResult;

    try {
      // moduleId приходит от вызывающего, а не из пакета, но он всё
      // равно попадает в путь песочницы — значит, проверяется так же,
      // как в импорте (Этап 8, AUD-01).
      ModuleSandbox.validateModuleId(moduleId);

      // --- Проверки: обновлять есть что? ---
      //
      // Встроенный модуль сюда попасть не может: его реализация
      // поставляется с приложением, и «обновление» внешним пакетом
      // просто подменило бы код, собранный вместе с ядром.
      previousModule = ModuleRegistry.get(moduleId);
      if (previousModule == null) {
        return ModuleImportOutcome.failure(
          'модуль "$moduleId" не установлен',
          violations: const ['module_not_installed'],
        );
      }
      if (previousModule is! ExternalModuleAdapter) {
        return ModuleImportOutcome.failure(
          'модуль "$moduleId" является встроенным и не может быть обновлён '
          'из внешнего пакета',
          violations: const ['builtin_module_id'],
        );
      }

      // --- Чтение пакета ---
      //
      // Свой id исключён из списка занятых: он занят обновляемым
      // модулем — им же. ManifestValidator считает такой случай
      // конфликтом, и без исключения каждое обновление отказывалось
      // бы с «id уже занят».
      final content = _packageReader.readBytes(
        archiveBytes,
        existingModuleIds: {
          for (final module in ModuleRegistry.modules)
            if (module.id != moduleId) module.id,
        },
      );

      if (content.manifest.id != moduleId) {
        return ModuleImportOutcome.failure(
          'в пакете модуль "${content.manifest.id}", а обновлялся "$moduleId"',
          violations: const ['module_id_mismatch'],
        );
      }

      // --- Проверки совместимости обновления ---
      //
      // Тот же ModuleUpdateValidator, что у ModuleManager.update:
      // правило одно на оба пути, иначе «можно обновить» означало бы
      // разное в зависимости от того, откуда вызвали.
      final plan = _moduleManager.updateValidator.validate(
        newManifest: content.manifest,
        currentManifest: previousModule.manifest,
        currentState: _moduleManager.stateOf(moduleId),
        installedManifests: [
          for (final module in ModuleRegistry.modules) module.manifest,
        ],
      );
      if (!plan.isAccepted) {
        return ModuleImportOutcome.failure(
          plan.violationsText.isEmpty
              ? (plan.reason ?? 'обновление отклонено')
              : '${plan.reason ?? "обновление отклонено"}: '
                  '${plan.violationsText}',
          // Коды, а не тексты: UI обязан решать по коду, а не разбирать
          // русские строки (см. ModuleUpdatePlan).
          violations: [
            for (final violation in plan.violations) violation.code.name,
          ],
        );
      }

      // --- Снимок ДО первой записи ---
      //
      // Ассеты в него входят не «на всякий случай»: снимок ассетов —
      // это страховка от случая, когда обмен песочницы не состоялся,
      // но файлы уже начали меняться. Если обмен состоялся, прежние
      // ассеты возвращаются вместе с прежним каталогом целиком.
      snapshot = await _snapshots.capture(moduleId: moduleId);

      // --- Подготовка новой версии ---
      stagedDirectory = await _sandboxSwap.createStaging(moduleId: moduleId);
      await _extractAssetsToSandbox(content, stagedDirectory);

      // --- Обмен песочницы ---
      swapResult = await _sandboxSwap.commit(
        moduleId: moduleId,
        stagedDirectory: stagedDirectory,
      );

      // --- Обмен реестра ---
      //
      // Через ModuleManager.update, а не через ModuleRegistry.swap
      // напрямую: он же сохраняет состояние installed/enabled/disabled
      // (обновление не включает и не выключает модуль) и уведомляет
      // подписчиков ChangeNotifier. Состояние и хранилище при этом не
      // трогаются — это гарантия того, что обновление не выглядит как
      // uninstall + install.
      await _moduleManager.update(ExternalModuleAdapter(content.manifest));

      // --- Успех ---
      //
      // Обмен уже состоялся и модуль в реестре уже новый. Уборка
      // прежней версии — ДЕЙСТВИЕ ПОСЛЕ УСПЕХА, и её провал не должен
      // отменять обновление: иначе неудачное удаление каталога
      // (занятый файл вирусом, антивирусом, другим процессом) превращало
      // бы в отказ операцию, которая уже применена и о которой уже
      // сообщено. Остаток убирает восстановление при старте
      // (ModuleSandboxSwap.recoverAllInterrupted).
      final previousDirectory = swapResult.previousDirectory;
      if (previousDirectory != null) {
        try {
          await _sandboxSwap.discardPrevious(
            moduleId: moduleId,
            previousDirectory: previousDirectory,
          );
        } on Object {
          // Остаток прежней версии — мусор, а не часть результата.
        }
      }
      try {
        await _sandboxSwap.discardStaging(stagedDirectory);
      } on Object {
        // То же: staging уже не участвует в работе модуля.
      }

      return ModuleImportOutcome.success(moduleId, isUpdate: true);
    } catch (e) {
      final rollbackFailures = await _rollbackUpdate(
        moduleId: moduleId,
        previousModule: previousModule,
        snapshot: snapshot,
        swapResult: swapResult,
      );

      if (rollbackFailures.isNotEmpty) {
        // Наполовину откатанный модуль опаснее явно сообщённой ошибки:
        // результат обязан это показать, а не выглядеть как обычный
        // отказ проверок.
        return ModuleImportOutcome.failure(
          'откат обновления не удался: ${rollbackFailures.join("; ")} '
          '(исходная ошибка: $e)',
          violations: const ['rollback_failed'],
          isUpdate: true,
        );
      }

      return ModuleImportOutcome.failure(
        e is ImporterException ? e.message : e.toString(),
        isUpdate: true,
      );
    }
  }

  /// Возвращает модуль к состоянию ДО обновления.
  ///
  /// Порядок отката — обратный порядку шагов, и это не формальность:
  /// 1. реестр — прежний объект модуля (код приложения должен
  ///    соответствовать песочнице, а не наоборот);
  /// 2. файловая система — прежняя песочница целиком;
  /// 3. снимок — хранилище и состояние.
  ///
  /// Каждый шаг ловит свою ошибку и продолжает следующие: первый же
  /// упавший откат не должен мешать вернуть остальное. Возвращает
  /// список неудавшихся шагов — вызывающий обязан сообщить о нём, а не
  /// замолчать (см. ModuleSnapshotRollbackException).
  Future<List<Object>> _rollbackUpdate({
    required String moduleId,
    required Module? previousModule,
    required ModuleSnapshot? snapshot,
    required ModuleSandboxSwapResult? swapResult,
  }) async {
    final failures = <Object>[];

    // 1. Реестр.
    //
    // Сверка по идентичности, а не по версии: подменить модуль мог и
    // не обновление (например, сработавший слушатель), и молча
    // оставить чужой код на месте было бы хуже, чем вернуть прежний.
    final registered = ModuleRegistry.get(moduleId);
    if (previousModule != null &&
        registered != null &&
        !identical(registered, previousModule)) {
      try {
        ModuleRegistry.swap(previousModule);
      } catch (error) {
        failures.add(error);
      }
    }

    // 2. Файловая система.
    //
    // Каталог прежней версии ищется заново, а не берётся из
    // [swapResult]: commit может бросить ПОСЛЕ того, как он уже всё
    // переместил, и тогда результата у вызывающего просто не будет.
    // Если прежней версии нет, restorePrevious вернёт false и ничего не
    // сделает — то есть вызов безопасен и когда обмена не было вовсе.
    try {
      await _sandboxSwap.restorePrevious(
        moduleId: moduleId,
        previousDirectory: swapResult?.previousDirectory,
      );
    } catch (error) {
      failures.add(error);
    }

    // 3. Снимок: хранилище и состояние.
    //
    // Ассеты здесь не перечисляются намеренно: если обмен состоялся,
    // прежние ассеты вернулись вместе с прежним каталогом (шаг 2), а
    // если не состоялся — их никто не трогал. Повторная запись тех же
    // байт была бы пустой работой, которая вдобавок может затереть
    // изменения, сделанные уже после провала обновления.
    if (snapshot != null) {
      try {
        await _snapshots.rollback(
          snapshot,
          attemptedComponents: const [
            ModuleSnapshotComponent.storage,
            ModuleSnapshotComponent.state,
          ],
        );
      } catch (error) {
        failures.add(error);
      }
    }

    // 4. Подготовка: и каталог новой версии, который не встал на место, и
    // версия, которую restorePrevious увёл в сторону. Обновление на этом
    // закончено — оставлять оба было бы мусором на каждой неудаче.
    try {
      await _sandboxSwap.discardStagedVersions(moduleId: moduleId);
    } catch (error) {
      failures.add(error);
    }

    return failures;
  }
}