/// Module backup manifest model.
///
/// Represents the manifest.json inside a .pmb (Personal Hub Module Backup) archive.
library module_backup_manifest;

import 'module_backup_options.dart';
export 'module_backup_options.dart';

/// Module backup format version.
///
/// Starts at 1. Increment when making incompatible changes to .pmb format.
const int kCurrentModuleBackupFormatVersion = 1;

/// Supported module backup format versions.
const List<int> kSupportedModuleBackupFormatVersions = [1];

/// Module backup manifest model.
///
/// Contains all metadata about the module backup archive.
class ModuleBackupManifest {
  final int backupFormatVersion;
  final String appVersion;
  final DateTime createdAt;
  final String moduleId;
  final String moduleVersion;
  final ModuleBackupOptions options;

  const ModuleBackupManifest({
    required this.backupFormatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.moduleId,
    required this.moduleVersion,
    required this.options,
  });

  /// Creates manifest from JSON.
  factory ModuleBackupManifest.fromJson(Map<String, dynamic> json) {
    final violations = <String>[];

    if (!json.containsKey('backupFormatVersion')) {
      violations.add('отсутствует backupFormatVersion');
    } else if (json['backupFormatVersion'] is! int) {
      violations.add('backupFormatVersion должен быть целым числом');
    }

    if (!json.containsKey('appVersion')) {
      violations.add('отсутствует appVersion');
    } else if (json['appVersion'] is! String) {
      violations.add('appVersion должен быть строкой');
    }

    if (!json.containsKey('createdAt')) {
      violations.add('отсутствует createdAt');
    } else if (json['createdAt'] is! String) {
      violations.add('createdAt должен быть строкой');
    }

    if (!json.containsKey('moduleId')) {
      violations.add('отсутствует moduleId');
    } else if (json['moduleId'] is! String) {
      violations.add('moduleId должен быть строкой');
    }

    if (!json.containsKey('moduleVersion')) {
      violations.add('отсутствует moduleVersion');
    } else if (json['moduleVersion'] is! String) {
      violations.add('moduleVersion должен быть строкой');
    }

    if (!json.containsKey('options')) {
      violations.add('отсутствует options');
    } else if (json['options'] is! Map) {
      violations.add('options должен быть объектом');
    }

    if (violations.isNotEmpty) {
      throw FormatException('невалидный module backup manifest: ${violations.join("; ")}');
    }

    // Parse createdAt
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(json['createdAt'] as String);
    } catch (_) {
      throw FormatException('невалидный формат createdAt: ${json['createdAt']}');
    }

    // Parse options
    final optionsJson = json['options'] as Map;
    final options = ModuleBackupOptions(
      includeState: optionsJson['includeState'] as bool? ?? true,
      includeData: optionsJson['includeData'] as bool? ?? true,
      includeAssets: optionsJson['includeAssets'] as bool? ?? true,
    );

    return ModuleBackupManifest(
      backupFormatVersion: json['backupFormatVersion'] as int,
      appVersion: json['appVersion'] as String,
      createdAt: createdAt,
      moduleId: json['moduleId'] as String,
      moduleVersion: json['moduleVersion'] as String,
      options: options,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    'backupFormatVersion': backupFormatVersion,
    'appVersion': appVersion,
    'createdAt': createdAt.toIso8601String(),
    'moduleId': moduleId,
    'moduleVersion': moduleVersion,
    'options': options.toJson(),
  };

  /// Validates the manifest for internal consistency.
  List<String> validate() {
    final violations = <String>[];

    if (!kSupportedModuleBackupFormatVersions.contains(backupFormatVersion)) {
      violations.add('неподдерживаемая версия формата: $backupFormatVersion');
    }

    if (appVersion.isEmpty) {
      violations.add('appVersion не может быть пустым');
    }

    if (moduleId.isEmpty) {
      violations.add('moduleId не может быть пустым');
    }

    // Validate moduleId format
    if (moduleId.contains('..') ||
        moduleId.startsWith('/') ||
        moduleId.startsWith('\\') ||
        moduleId.contains('\\') ||
        moduleId.contains('/') ||
        moduleId.length > 100) {
      violations.add('невалидный moduleId: $moduleId');
    }

    if (moduleVersion.isEmpty) {
      violations.add('moduleVersion не может быть пустым');
    }

    return violations;
  }
}