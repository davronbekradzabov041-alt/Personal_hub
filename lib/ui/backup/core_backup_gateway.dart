/// Реализация [BackupGateway] поверх core-менеджеров Stage 6C/6D.
///
/// Адаптер намеренно тонкий: переводит вызовы UI в существующие API
/// core и оборачивает результаты в DTO. Бизнес-логики backup здесь
/// нет — она остаётся в core, чтобы 6E не стал второй реализацией
/// backup.
library core_backup_gateway;

import 'dart:io';
import 'package:path/path.dart' as path;

import '../../core/backup/backup_options.dart';
import '../../core/backup/backup_reader.dart';
import '../../core/backup/global_backup_manager.dart';
import '../../core/backup/module_backup_manager.dart';
import '../../core/backup/module_backup_options.dart';
import '../../core/backup/module_backup_reader.dart';
import '../../core/modules/module_manager.dart';
import '../../core/modules/module_registry.dart';
import 'backup_gateway.dart';

/// Адаптер core-менеджеров для UI.
class CoreBackupGateway implements BackupGateway {
  CoreBackupGateway({
    required GlobalBackupManager globalManager,
    required ModuleBackupManager moduleManager,
    required ModuleManager appModuleManager,
  })  : _global = globalManager,
        _module = moduleManager,
        _modules = appModuleManager;

  final GlobalBackupManager _global;
  final ModuleBackupManager _module;
  final ModuleManager _modules;

  @override
  Future<List<String>> installedModuleIds() async {
    return ModuleRegistry.modules
        .where((m) => _modules.isInstalled(m.id))
        .map((m) => m.id)
        .toList();
  }

  @override
  String displayNameOf(String moduleId) {
    final module = ModuleRegistry.get(moduleId);
    return module?.manifest.name ?? moduleId;
  }

  @override
  Future<BackupArtifact> createGlobalBackup(
    GlobalBackupSelection selection,
  ) async {
    // Файлы собираются во временную папку: core-менеджеры пишут на диск
    // сами, а конечное место выбирает файл-пикер. Поэтому UI получает
    // байты, а не путь.
    final staging = await Directory.systemTemp.createTemp('pbk_staging_');
    try {
      final options = BackupOptions(
        includeModuleData: selection.includeModuleData,
        includeAssets: selection.includeAssets,
        includeGlobalSettings: selection.includeGlobalSettings,
      );

      final GlobalBackupResult result;
      if (selection.allInstalled) {
        result = await _global.createGlobalBackup(
          options: options,
          outputDirectory: staging,
        );
      } else {
        result = await _global.createGlobalBackupWithSelection(
          options: options,
          moduleIdsToInclude: selection.moduleIds,
          outputDirectory: staging,
        );
      }

      return BackupArtifact(
        fileName: path.basename(result.outputPath),
        bytes: await File(result.outputPath).readAsBytes(),
      );
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  @override
  Future<BackupArtifact> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  ) async {
    final staging = await Directory.systemTemp.createTemp('pmb_staging_');
    try {
      final result = await _module.createBackup(
        moduleId: moduleId,
        outputDirectory: staging,
        options: options,
      );
      return BackupArtifact(
        fileName: path.basename(result.outputPath),
        bytes: await File(result.outputPath).readAsBytes(),
      );
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  @override
  Future<BackupPreview> inspectGlobalBackup(List<int> archiveBytes) async {
    final backup = await BackupReader.readGlobalBackup(
      archiveBytes,
      existingModuleIds: ModuleRegistry.modules.map((m) => m.id).toSet(),
    );

    return BackupPreview(
      title: 'Глобальный backup',
      // В BackupReader createdAt приходит строкой ISO-8601, а UI нужен
      // DateTime для форматирования.
      createdAt: DateTime.parse(backup.createdAt),
      appVersion: backup.appVersion,
      moduleIds: backup.modules.keys.toList()..sort(),
      includesSettings: backup.globalSettingsJson != null,
      includesData: backup.modules.values.any((m) => m.dataJson != null),
      includesAssets: backup.modules.values.any((m) => m.assets.isNotEmpty),
    );
  }

  @override
  Future<BackupPreview> inspectModuleBackup(List<int> archiveBytes) async {
    final backup = await ModuleBackupReader.readModuleBackup(archiveBytes);

    return BackupPreview(
      title: 'Backup модуля «${displayNameOf(backup.moduleId)}»',
      createdAt: DateTime.parse(backup.createdAt),
      appVersion: backup.appVersion,
      moduleIds: [backup.moduleId],
      includesSettings: false,
      includesData: backup.dataJson != null,
      includesAssets: backup.assets.isNotEmpty,
    );
  }

  @override
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  }) async {
    final result = await _module.restoreBackup(
      archiveBytes: archiveBytes,
      targetModuleId: moduleId,
      options: options,
    );

    if (result.isSuccess) {
      return RestoreOutcome(
        isSuccess: true,
        moduleId: result.moduleId,
        appliedComponents: result.appliedComponents,
      );
    }

    return RestoreOutcome(
      isSuccess: false,
      moduleId: result.moduleId,
      appliedComponents: result.appliedComponents,
      rolledBackComponents: result.rolledBackComponents,
      message: result.error?.toString(),
      // Объект, а не строка: UI переводит исключение в понятную фразу
      // через BackupErrorPresenter.
      error: result.error,
    );
  }
}
