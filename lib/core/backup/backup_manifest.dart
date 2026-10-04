/// Backup manifest model.
///
/// Represents the manifest.json inside a backup archive.
library backup_manifest;

import 'backup_options.dart';
export 'backup_options.dart';

/// Backup format version.
///
/// Starts at 1. Increment when making incompatible changes.
const int kCurrentBackupFormatVersion = 1;

/// Supported backup format versions.
const List<int> kSupportedBackupFormatVersions = [1];

/// Backup type.
enum BackupType {
  /// Global backup containing multiple modules and global settings.
  global,
  /// Single module backup (future).
  module,
}

/// Backup manifest model.
///
/// Contains all metadata about the backup archive.
class BackupManifest {
  final int backupFormatVersion;
  final String appVersion;
  final DateTime createdAt;
  final BackupType type;
  final List<String> includedModules;
  final BackupOptions options;

  const BackupManifest({
    required this.backupFormatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.type,
    required this.includedModules,
    required this.options,
  });

  /// Creates manifest from JSON.
  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    // Validate required fields
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

    if (!json.containsKey('type')) {
      violations.add('отсутствует type');
    } else if (json['type'] is! String) {
      violations.add('type должен быть строкой');
    }

    if (!json.containsKey('includedModules')) {
      violations.add('отсутствует includedModules');
    } else if (json['includedModules'] is! List) {
      violations.add('includedModules должен быть списком');
    } else {
      for (final item in json['includedModules']) {
        if (item is! String) {
          violations.add('все includedModules должны быть строками');
          break;
        }
      }
    }

    if (!json.containsKey('options')) {
      violations.add('отсутствует options');
    } else if (json['options'] is! Map) {
      violations.add('options должен быть объектом');
    }

    if (violations.isNotEmpty) {
      throw FormatException('невалидный backup manifest: ${violations.join("; ")}');
    }

    // Parse type
    BackupType type;
    switch (json['type']) {
      case 'global':
        type = BackupType.global;
        break;
      case 'module':
        type = BackupType.module;
        break;
      default:
        throw FormatException('неизвестный тип backup: ${json['type']}');
    }

    // Parse options
    final optionsJson = json['options'] as Map;
    final options = BackupOptions(
      includeModuleData: optionsJson['includeModuleData'] as bool? ?? true,
      includeAssets: optionsJson['includeAssets'] as bool? ?? true,
      includeGlobalSettings: optionsJson['includeGlobalSettings'] as bool? ?? true,
    );

    // Parse createdAt
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(json['createdAt'] as String);
    } catch (_) {
      throw FormatException('невалидный формат createdAt: ${json['createdAt']}');
    }

    // Parse includedModules
    final includedModules = (json['includedModules'] as List)
        .map((e) => e as String)
        .toList();

    // Validate module IDs are unique
    if (includedModules.toSet().length != includedModules.length) {
      throw const FormatException('дублирующиеся moduleId в includedModules');
    }

    return BackupManifest(
      backupFormatVersion: json['backupFormatVersion'] as int,
      appVersion: json['appVersion'] as String,
      createdAt: createdAt,
      type: type,
      includedModules: includedModules,
      options: options,
    );
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
    'backupFormatVersion': backupFormatVersion,
    'appVersion': appVersion,
    'createdAt': createdAt.toIso8601String(),
    'type': type.name,
    'includedModules': includedModules,
    'options': options.toJson(),
  };

  /// Validates the manifest for internal consistency.
  List<String> validate() {
    final violations = <String>[];

    if (!kSupportedBackupFormatVersions.contains(backupFormatVersion)) {
      violations.add('неподдерживаемая версия формата: $backupFormatVersion');
    }

    if (appVersion.isEmpty) {
      violations.add('appVersion не может быть пустым');
    }

    if (includedModules.isEmpty && !options.includeGlobalSettings) {
      // Backup без модулей допустим — только если в нём есть глобальные
      // настройки: тогда архив не пустой и его есть чем наполнить.
      // Раньше проверка была безусловной, из-за чего round-trip
      // «0 модулей + глобальные настройки» не проходил: GlobalBackupManager
      // такой backup создавал, а reader его отвергал как
      // некорректный манифест.
      violations.add(
        'backup без модулей допустим только вместе с global settings',
      );
    }

    for (final moduleId in includedModules) {
      if (moduleId.isEmpty) {
        violations.add('пустой moduleId в includedModules');
      }
      // Validate moduleId format (same as ModuleSandbox)
      if (moduleId.contains('..') ||
          moduleId.startsWith('/') ||
          moduleId.startsWith('\\') ||
          moduleId.contains('\\') ||
          moduleId.contains('/') ||
          moduleId.length > 100) {
        violations.add('невалидный moduleId: $moduleId');
      }
    }

    // Check for duplicates
    if (includedModules.toSet().length != includedModules.length) {
      violations.add('дублирующиеся moduleId в includedModules');
    }

    return violations;
  }
}