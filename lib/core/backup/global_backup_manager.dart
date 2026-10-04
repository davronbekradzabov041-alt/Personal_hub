/// Global backup manager.
///
/// Orchestrates creation of global backup (.pbk) archives by coordinating
/// data collection from various application components and delegating
/// archive creation to [BackupWriter].
library global_backup_manager;

import 'dart:io';
import 'package:path/path.dart' as path;

import '../modules/module_manager.dart';
import '../modules/module_registry.dart';
import '../database/repositories/app_settings_repository.dart';
import 'backup_manifest.dart';
import 'backup_writer.dart';
import 'atomic_file_writer.dart';
import 'backup_exceptions.dart';
import 'backup_options.dart';

/// Result of a global backup operation.
class GlobalBackupResult {
  final String outputPath;
  final int sizeBytes;
  final DateTime createdAt;
  final List<String> includedModuleIds;
  final BackupOptions optionsSummary;

  const GlobalBackupResult({
    required this.outputPath,
    required this.sizeBytes,
    required this.createdAt,
    required this.includedModuleIds,
    required this.optionsSummary,
  });

  bool get isSuccess => true;

  @override
  String toString() {
    return 'GlobalBackupResult('
        'outputPath: $outputPath, '
        'sizeBytes: $sizeBytes, '
        'createdAt: $createdAt, '
        'includedModuleIds: $includedModuleIds, '
        'optionsSummary: $optionsSummary)';
  }
}

/// Orchestrates creation of global backup (.pbk) archives.
///
/// Coordinates data collection from application components and delegates
/// archive creation to [BackupWriter].
class GlobalBackupManager {
  GlobalBackupManager({
    required ModuleManager moduleManager,
  }) : _moduleManager = moduleManager;

  final ModuleManager _moduleManager;

  /// Creates a global backup archive.
  ///
  /// [options] configures what data to include in the backup.
  /// [outputDirectory] specifies where to save the .pbk file.
  ///
  /// Returns [GlobalBackupResult] with output path and metadata.
  /// Throws [BackupException] on failure.
  Future<GlobalBackupResult> createGlobalBackup({
    required BackupOptions options,
    required Directory outputDirectory,
  }) async {
    // Determine which modules to include
    final includedModuleIds = _getIncludedModuleIds();

    if (includedModuleIds.isEmpty && !options.includeGlobalSettings) {
      throw const BackupFormatException('нет модулей для включения в backup');
    }

    // Create backup using BackupWriter
    final bytes = await BackupWriter.writeGlobalBackup(
      manager: _moduleManager,
      settingsRepository: AppSettingsRepository(),
      selection: BackupSelection(
        includedModules: includedModuleIds.toList(),
        includeModuleData: options.includeModuleData,
        includeAssets: options.includeAssets,
        includeGlobalSettings: options.includeGlobalSettings,
      ),
    );

    // Write to file
    final fileName = 'personal_hub_backup_${DateTime.now().millisecondsSinceEpoch}.pbk';
    final outputFile = File(path.join(outputDirectory.path, fileName));

    await writeFileAtomically(outputFile, bytes);

    return GlobalBackupResult(
      outputPath: outputFile.path,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
      includedModuleIds: _getIncludedModuleIds().toList(),
      optionsSummary: options,
    );
  }

  /// Creates a global backup archive with custom module selection.
  Future<GlobalBackupResult> createGlobalBackupWithSelection({
    required BackupOptions options,
    required Set<String> moduleIdsToInclude,
    required Directory outputDirectory,
  }) async {
    // Validate module IDs
    for (final moduleId in moduleIdsToInclude) {
      if (!ModuleRegistry.contains(moduleId)) {
        throw BackupFormatException('модуль $moduleId не зарегистрирован');
      }
      if (!_moduleManager.isInstalled(moduleId)) {
        throw BackupFormatException('модуль $moduleId не установлен');
      }
    }

    final bytes = await BackupWriter.writeGlobalBackup(
      manager: _moduleManager,
      settingsRepository: AppSettingsRepository(),
      selection: BackupSelection(
        includedModules: moduleIdsToInclude.toList(),
        includeModuleData: options.includeModuleData,
        includeAssets: options.includeAssets,
        includeGlobalSettings: options.includeGlobalSettings,
      ),
    );

    final outputFile = File(path.join(
      outputDirectory.path,
      'personal_hub_backup_${DateTime.now().millisecondsSinceEpoch}.pbk',
    ));

    await writeFileAtomically(outputFile, bytes);

    return GlobalBackupResult(
      outputPath: outputFile.path,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
      includedModuleIds: moduleIdsToInclude.toList(),
      optionsSummary: options,
    );
  }

  Set<String> _getIncludedModuleIds() {
    final installedModules = ModuleRegistry.modules
        .where((m) => _moduleManager.isInstalled(m.id))
        .map((m) => m.id)
        .toSet();
    return installedModules;
  }
}