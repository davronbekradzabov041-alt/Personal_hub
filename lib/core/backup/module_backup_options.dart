/// Module backup options for configuring what to include in a module backup.
library module_backup_options;

/// Options for configuring module backup content.
class ModuleBackupOptions {
  /// Whether to include module state (installed/enabled/disabled) in the backup.
  final bool includeState;

  /// Whether to include module data (key-value storage) in the backup.
  final bool includeData;

  /// Whether to include module assets (files in sandbox) in the backup.
  final bool includeAssets;

  const ModuleBackupOptions({
    this.includeState = true,
    this.includeData = true,
    this.includeAssets = true,
  });

  /// Creates options for full backup (all components).
  const ModuleBackupOptions.full()
      : includeState = true,
        includeData = true,
        includeAssets = true;

  /// Creates options for data-only backup.
  const ModuleBackupOptions.dataOnly()
      : includeState = false,
        includeData = true,
        includeAssets = false;

  /// Creates options for state-only backup.
  const ModuleBackupOptions.stateOnly()
      : includeState = true,
        includeData = false,
        includeAssets = false;

  /// Creates options for assets-only backup.
  const ModuleBackupOptions.assetsOnly()
      : includeState = false,
        includeData = false,
        includeAssets = true;

  /// Creates options for data + assets backup (no state).
  const ModuleBackupOptions.dataAndAssets()
      : includeState = false,
        includeData = true,
        includeAssets = true;

  Map<String, dynamic> toJson() => {
    'includeState': includeState,
    'includeData': includeData,
    'includeAssets': includeAssets,
  };

  @override
  String toString() {
    return 'ModuleBackupOptions(includeState: $includeState, includeData: $includeData, includeAssets: $includeAssets)';
  }
}