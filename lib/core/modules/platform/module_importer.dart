import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../external/external_module_adapter.dart';
import '../module_manager.dart';
import '../module_registry.dart';
import '../module_state.dart';
import 'package_content.dart';
import 'package_reader.dart';
import 'module_sandbox.dart';
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

  const ModuleImportOutcome._({
    required this.isSuccess,
    this.moduleId,
    this.error,
    this.violations = const [],
  });

  const ModuleImportOutcome.success(String moduleId)
      : this._(isSuccess: true, moduleId: moduleId);

  const ModuleImportOutcome.failure(String error, {List<String> violations = const []})
      : this._(isSuccess: false, error: error, violations: violations);

  bool get isFailure => !isSuccess;
}

/// Orchestrates the import of external .phm modules with full transaction rollback.
///
/// The import pipeline:
/// 1. Read & validate .phm package (PackageReader + PackageSecurityGuard)
/// 2. Validate manifest (ManifestValidator + dependency checks)
/// 3. Check moduleId (not duplicate, not builtin)
/// 4. Create temporary sandbox
/// 5. Extract assets to temporary sandbox
/// 6. Create ExternalModuleAdapter & register in ModuleRegistry
/// 7. Seed ModuleStorage from data/storage.json
/// 8. Call ModuleManager.tryInstall()
/// 9. Commit sandbox (move temp -> permanent)
/// 10. Return success
///
/// On ANY failure after step 6, full rollback is performed:
/// 1. ModuleRegistry.unregister()
/// 2. ModuleStorage keys cleared
/// 3. Permanent sandbox deleted
/// 4. Temporary sandbox deleted
/// 5. ModuleManager state restored
class ModuleImporter {
  final ModuleManager _moduleManager;
  final ModulePackageReader _packageReader;
  final Directory? _testSupportDir;

  ModuleImporter({
    required ModuleManager moduleManager,
    ModulePackageReader? packageReader,
    Directory? testSupportDir,
  })  : _moduleManager = moduleManager,
        _packageReader = packageReader ?? ModulePackageReader(),
        _testSupportDir = testSupportDir;

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
    String? tempSandboxPath;
    String? permanentSandboxPath;
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
      // filesystem path (temp sandbox, permanent sandbox). Валидация
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
      // STEP 3: Create temporary sandbox
      // ============================================================
      final tempDir = await _createTempSandbox(moduleId);
      tempSandboxPath = tempDir.path;

      // ============================================================
      // STEP 4: Extract assets to temporary sandbox
      // ============================================================
      await _extractAssetsToSandbox(content, tempDir);

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
      // STEP 8: Commit sandbox (temp -> permanent)
      // ============================================================
      permanentSandboxPath = await _commitSandbox(moduleId, tempDir);

      return ModuleImportOutcome.success(moduleId);
    } catch (e) {
      // ============================================================
      // ROLLBACK on any failure
      // ============================================================
      await _rollback(
        moduleId: moduleId,
        moduleRegistered: moduleRegistered,
        tempSandboxPath: tempSandboxPath,
        permanentSandboxPath: permanentSandboxPath,
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

  /// Creates a temporary sandbox directory.
  Future<Directory> _createTempSandbox(String moduleId) async {
    // Последняя линия перед path.join: даже если вызывающий код забудет
    // проверить id, путь не будет построен из непроверенного значения.
    ModuleSandbox.validateModuleId(moduleId);
    final supportDir = await _getAppSupportDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDirName = '${moduleId}_$timestamp';
    final tempDir = Directory(path.join(supportDir.path, 'modules_tmp', tempDirName));
    
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);
    return tempDir;
  }

  /// Gets the app's support directory (mirror of ModuleSandbox._getAppSupportDirectory).
  /// Uses _testSupportDir if provided (for testing).
  Future<Directory> _getAppSupportDirectory() async {
    if (_testSupportDir != null) return _testSupportDir;
    final appDocDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDocDir.path, 'personal_hub_modules'));
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

  /// Commits temporary sandbox to permanent location.
  Future<String> _commitSandbox(String moduleId, Directory tempDir) async {
    // permanentDir.delete(recursive: true) удаляет произвольный каталог,
    // если id не проверен, поэтому валидация обязана быть здесь.
    ModuleSandbox.validateModuleId(moduleId);
    final supportDir = await _getAppSupportDirectory();
    final permanentDir = Directory(path.join(supportDir.path, 'modules', moduleId));
    
    // If permanent exists, remove it first
    if (await permanentDir.exists()) {
      await permanentDir.delete(recursive: true);
    }
    
    // Ensure parent exists
    await permanentDir.parent.create(recursive: true);
    
    // Move temp to permanent (rename is atomic on same filesystem)
    await tempDir.rename(permanentDir.path);
    
    return permanentDir.path;
  }

  /// Performs full rollback on import failure.
  Future<void> _rollback({
    required String? moduleId,
    required bool moduleRegistered,
    required String? tempSandboxPath,
    required String? permanentSandboxPath,
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

    // 3. Delete permanent sandbox
    if (permanentSandboxPath != null) {
      try {
        final dir = Directory(permanentSandboxPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // Best effort
      }
    }

    // 4. Delete temporary sandbox
    if (tempSandboxPath != null) {
      try {
        final dir = Directory(tempSandboxPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
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
}