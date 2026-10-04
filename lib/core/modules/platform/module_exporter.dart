import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../external/external_module_adapter.dart';
import '../module_manager.dart';
import '../module_registry.dart';
import 'package_content.dart';
import 'package_writer.dart';
import 'module_sandbox.dart';
import 'module_storage_serializer.dart';
import 'package_security_guard.dart';

/// Result of a module export operation.
class ModuleExportOutcome {
  final bool isSuccess;
  final String? moduleId;
  final List<int>? phmBytes;
  final String? error;

  const ModuleExportOutcome._({
    required this.isSuccess,
    this.moduleId,
    this.phmBytes,
    this.error,
  });

  factory ModuleExportOutcome.success({
    required String moduleId,
    required List<int> phmBytes,
  }) = _ModuleExportSuccess;

  factory ModuleExportOutcome.failure(String error) = _ModuleExportFailure;

  bool get isFailure => !isSuccess;
}

class _ModuleExportSuccess extends ModuleExportOutcome {
  final String moduleId;
  final List<int> phmBytes;

  const _ModuleExportSuccess({
    required this.moduleId,
    required this.phmBytes,
  }) : super._(isSuccess: true, moduleId: moduleId, phmBytes: phmBytes);

  @override
  final bool isSuccess = true;
}

class _ModuleExportFailure extends ModuleExportOutcome {
  final String error;

  const _ModuleExportFailure(this.error)
      : super._(isSuccess: false, error: error);

  @override
  final bool isSuccess = false;
}

/// Export mode: whether to include user data (ModuleStorage) in the export.
enum ModuleExportMode {
  /// Export only the module package (manifest, README, assets) without user data.
  withoutData,

  /// Export the module package with current ModuleStorage data included.
  withData,
}

/// Resolves the directory a module's assets are exported from.
///
/// Продакшн по умолчанию читает собственную песочницу модуля. Тесты
/// подставляют собственную функцию, поэтому production-код не обязан
/// вызывать `@visibleForTesting`-API песочницы.
typedef ModuleAssetsDirectoryResolver = Future<Directory> Function(
  String moduleId,
);

/// Exports an installed external module to a .phm package.
///
/// Uses only public APIs: ModuleRegistry, ModuleManager, ModuleSandbox,
/// ModuleStorageSerializer, and PackageWriter. Does NOT access internal
/// state or Isar directly.
class ModuleExporter {
  final ModuleManager _moduleManager;
  final ModuleAssetsDirectoryResolver _assetsDirectoryResolver;

  ModuleExporter({
    required ModuleManager moduleManager,
    ModuleAssetsDirectoryResolver? assetsDirectoryResolver,
  })  : _moduleManager = moduleManager,
        _assetsDirectoryResolver =
            assetsDirectoryResolver ?? ModuleSandbox.getAssetsDirectory;

  /// Exports an installed external module to a .phm package.
  ///
  /// [moduleId] must be an installed external module (not a builtin module).
  /// [mode] determines whether to include ModuleStorage data in the export.
  ///
  /// Returns [ModuleExportOutcome] with the .phm bytes on success.
  Future<ModuleExportOutcome> export({
    required String moduleId,
    ModuleExportMode mode = ModuleExportMode.withoutData,
  }) async {
    // 1. Validate module exists and is registered
    final module = ModuleRegistry.get(moduleId);
    if (module == null) {
      return ModuleExportOutcome.failure(
        'модуль "$moduleId" не зарегистрирован в ModuleRegistry',
      );
    }

    // 2. Check if module is installed
    if (!_moduleManager.isInstalled(moduleId)) {
      return ModuleExportOutcome.failure(
        'модуль "$moduleId" не установлен',
      );
    }

    // 3. Ensure module is external (ExternalModuleAdapter), not builtin
    if (module is! ExternalModuleAdapter) {
      return ModuleExportOutcome.failure(
        'экспорт поддерживается только для внешних модулей; '
        '"$moduleId" — встроенный модуль',
      );
    }

    try {
      // 4. Get manifest
      final manifest = module.manifest;

      // 5. Get README if exists (from ExternalModuleAdapter - it doesn't have one currently)
      String? readme;
      // Note: ExternalModuleAdapter doesn't store README separately

      // 6. Get assets from persistent sandbox
      final assets = await _readAssetsFromSandbox(moduleId);

      // 7. Get storage data if mode is withData
      PackageData? packageData;
      if (mode == ModuleExportMode.withData) {
        final storage = _moduleManager.apiFor(moduleId).storage;
        final storageJson = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: moduleId,
        );
        // Parse the JSON to extract entries for PackageData
        final json = jsonDecode(storageJson);
        final entries = json['entries'] as Map<String, dynamic>? ?? {};
        final entriesMap = <String, String>{};
        entries.forEach((k, v) {
          entriesMap[k] = v.toString();
        });
        packageData = PackageData(entriesMap);
      }

      // 8. Create PackageContent
      final content = PackageContent(
        manifest: manifest,
        assets: assets,
        data: packageData,
        readme: readme,
      );

      // 9. Write .phm using PackageWriter
      final phmBytes = ModulePackageWriter.write(content);

      // 10. Validate the exported package passes security guard
      PackageSecurityGuard.validateArchive(phmBytes);

      return ModuleExportOutcome.success(
        moduleId: moduleId,
        phmBytes: phmBytes,
      );
    } catch (e) {
      return ModuleExportOutcome.failure(
        'ошибка экспорта: ${e.toString()}',
      );
    }
  }

  /// Reads assets from the module's persistent sandbox.
  Future<List<PackageAsset>> _readAssetsFromSandbox(String moduleId) async {
    final assetsDir = await _assetsDirectoryResolver(moduleId);
    final assets = <PackageAsset>[];

    if (await assetsDir.exists()) {
      final entities = await assetsDir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          final fileName = path.basename(entity.path);
          assets.add(PackageAsset(
            path: 'assets/$fileName',
            bytes: bytes,
          ));
        }
      }
    }

    return assets;
  }
}