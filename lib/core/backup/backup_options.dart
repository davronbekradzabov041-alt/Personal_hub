/// Backup options for configuring what to include in a backup.
library backup_options;

/// Options for configuring global backup content.
class BackupOptions {
  /// Whether to include module data (key-value storage) in the backup.
  final bool includeModuleData;

  /// Whether to include module assets (files in sandbox) in the backup.
  final bool includeAssets;

  /// Whether to include global application settings in the backup.
  final bool includeGlobalSettings;

  const BackupOptions({
    this.includeModuleData = true,
    this.includeAssets = true,
    this.includeGlobalSettings = true,
  });

  Map<String, dynamic> toJson() => {
    'includeModuleData': includeModuleData,
    'includeAssets': includeAssets,
    'includeGlobalSettings': includeGlobalSettings,
  };
}