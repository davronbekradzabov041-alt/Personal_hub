import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:meta/meta.dart';

import 'sandbox_exceptions.dart';

/// Manages persistent sandbox directories for external modules.
///
/// Each module gets an isolated directory under the app's support directory:
/// `<AppSupportDirectory>/modules/<moduleId>/assets/`
///
/// This class handles only filesystem operations — no module lifecycle,
/// registry, or storage interactions.
class ModuleSandbox {
  ModuleSandbox._();

  /// Validates a module ID for use in filesystem paths.
  ///
  /// Reuses the same validation logic as ManifestParser/ManifestValidator:
  /// - Non-empty string
  /// - No path traversal (`..`)
  /// - No relative path components (`.` and `..` on their own)
  /// - No absolute paths
  /// - No backslashes (Windows paths)
  /// - No control characters
  /// - Reasonable length
  static void validateModuleId(String moduleId) {
    if (moduleId.trim().isEmpty) {
      throw const InvalidModuleIdException(
        moduleId: '',
        reason: 'пустой moduleId',
      );
    }

    // "." и ".." — относительные компоненты пути, а не имена каталогов.
    //
    // ".." отсекается проверкой contains('..') ниже, а "." проходит
    // мимо неё: это единственная точка среди всех символов, где
    // path.join(родитель, '.') схлопывается в сам родительский каталог.
    // Для sandbox это означает delete(recursive: true) по каталогу,
    // содержащему ВСЕ песочницы модулей: недоверенный .phm с
    // id = "." в manifest.json удалял данные всех установленных
    // модулей разом.
    if (moduleId == '.') {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'относительный путь (.) не разрешён',
      );
    }

    // No path traversal
    if (moduleId.contains('..')) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'path traversal (..) не разрешен',
      );
    }

    // No absolute paths (Unix or Windows)
    if (moduleId.startsWith('/') ||
        moduleId.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(moduleId)) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'абсолютные пути не разрешены',
      );
    }

    // No backslashes
    if (moduleId.contains('\\')) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'обратные слэши не разрешены',
      );
    }

    // No control characters
    if (moduleId.runes.any((r) => r < 0x20 || r == 0x7F)) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'управляющие символы не разрешены',
      );
    }

    // No path separators (prevents subdirectories in moduleId)
    if (moduleId.contains('/') || moduleId.contains('\\')) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'разделители путей не разрешены',
      );
    }

    // Reasonable length limit
    if (moduleId.length > 100) {
      throw InvalidModuleIdException(
        moduleId: moduleId,
        reason: 'moduleId слишком длинный (макс. 100 символов)',
      );
    }
  }

  /// Gets the root sandbox directory for a module.
  ///
  /// Returns a Directory pointing to `<AppSupportDir>/modules/<moduleId>/`.
  /// Does NOT create the directory.
  static Future<Directory> getModuleRoot(String moduleId) async {
    validateModuleId(moduleId);
    final supportDir = await _getAppSupportDirectory();
    return Directory(path.join(supportDir.path, 'modules', moduleId));
  }

  /// Gets the assets directory for a module.
  ///
  /// Returns a Directory pointing to `<AppSupportDir>/modules/<moduleId>/assets/`.
  /// Does NOT create the directory.
  static Future<Directory> getAssetsDirectory(String moduleId) async {
    final root = await getModuleRoot(moduleId);
    return Directory(path.join(root.path, 'assets'));
  }

  /// Ensures the module's sandbox directories exist.
  ///
  /// Creates `<AppSupportDir>/modules/<moduleId>/` and
  /// `<AppSupportDir>/modules/<moduleId>/assets/` if they don't exist.
  /// Idempotent — safe to call multiple times.
  static Future<void> ensureModuleDirectories(String moduleId) async {
    validateModuleId(moduleId);
    final root = await getModuleRoot(moduleId);
    final assets = await getAssetsDirectory(moduleId);

    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    if (!await assets.exists()) {
      await assets.create(recursive: true);
    }
  }

  /// Checks if a module's sandbox exists.
  static Future<bool> exists(String moduleId) async {
    validateModuleId(moduleId);
    final root = await getModuleRoot(moduleId);
    return root.exists();
  }

  /// Deletes a module's sandbox completely.
  ///
  /// Removes `<AppSupportDir>/modules/<moduleId>/` and all contents.
  /// Idempotent — safe to call on non-existent sandbox.
  static Future<void> deleteModule(String moduleId) async {
    validateModuleId(moduleId);
    final root = await getModuleRoot(moduleId);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  /// Lists all module sandboxes in the app support directory.
  static Future<List<String>> listModuleIds() async {
    final supportDir = await _getAppSupportDirectory();
    final modulesDir = Directory(path.join(supportDir.path, 'modules'));
    if (!await modulesDir.exists()) {
      return const [];
    }
    final entities = await modulesDir.list().toList();
    return entities
        .whereType<Directory>()
        .map((d) => path.basename(d.path))
        .toList();
  }

  @visibleForTesting
  static Future<List<String>> listModuleIdsForTesting(Directory supportDir) async {
    final modulesDir = Directory(path.join(supportDir.path, 'modules'));
    if (!await modulesDir.exists()) {
      return const [];
    }
    final entities = await modulesDir.list().toList();
    return entities
        .whereType<Directory>()
        .map((d) => path.basename(d.path))
        .toList();
  }

  /// Gets the app's support directory (platform-independent).
  static Future<Directory> _getAppSupportDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    // Use a subdirectory to keep module data separate from other app data
    return Directory(path.join(appDocDir.path, 'personal_hub_modules'));
  }

  /// Internal method for testing - allows overriding the support directory.
  @visibleForTesting
  static Directory getModuleRootForTesting(String moduleId, Directory supportDir) {
    validateModuleId(moduleId);
    return Directory(path.join(supportDir.path, 'modules', moduleId));
  }

  @visibleForTesting
  static Directory getAssetsDirectoryForTesting(String moduleId, Directory supportDir) {
    final root = Directory(path.join(supportDir.path, 'modules', moduleId));
    return Directory(path.join(root.path, 'assets'));
  }

  @visibleForTesting
  static Future<Directory> getAssetsDirectoryForTestingAsync(String moduleId, Directory supportDir) async {
    validateModuleId(moduleId);
    final root = Directory(path.join(supportDir.path, 'modules', moduleId));
    return Directory(path.join(root.path, 'assets'));
  }

  @visibleForTesting
  static Future<Directory> getAppSupportDirectoryForTesting() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDocDir.path, 'personal_hub_modules'));
  }

  @visibleForTesting
  static Future<void> ensureModuleDirectoriesForTesting(String moduleId, Directory supportDir) async {
    validateModuleId(moduleId);
    final root = Directory(path.join(supportDir.path, 'modules', moduleId));
    final assets = Directory(path.join(root.path, 'assets'));

    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    if (!await assets.exists()) {
      await assets.create(recursive: true);
    }
  }

  @visibleForTesting
  static Future<bool> existsForTesting(String moduleId, Directory supportDir) async {
    validateModuleId(moduleId);
    final root = Directory(path.join(supportDir.path, 'modules', moduleId));
    return root.exists();
  }

  @visibleForTesting
  static Future<void> deleteModuleForTesting(String moduleId, Directory supportDir) async {
    validateModuleId(moduleId);
    final root = Directory(path.join(supportDir.path, 'modules', moduleId));
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}