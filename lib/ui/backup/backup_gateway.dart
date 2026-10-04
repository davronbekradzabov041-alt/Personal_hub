/// Контракт операций backup, которые доступны UI.
///
/// Слой UI работает не с core-менеджерами напрямую, а с этим
/// интерфейсом. Причины именно интерфейс, а не прямые вызовы:
///
/// 1. core-менеджеры внутри обращаются к Isar (AppSettingsRepository,
///    ModuleStorageIsar), а UI-тесты должны работать без базы;
/// 2. UI не должен зависеть от способа хранения backup — при смене
///    реализации меняется одна реализация этого интерфейса;
/// 3. операции возвращают готовые байты, а не путь на диске: выбор
///    места сохранения делает file picker, а не core.
///
/// Интерфейс НЕ добавляет backend-возможностей: всё, что здесь
/// есть, уже поддержано Stage 6C/6D. В частности, глобального
/// restore (.pbk) в core нет — и здесь его тоже нет.
library backup_gateway;

import '../../core/backup/module_backup_options.dart';

/// Что включать в глобальный backup.
///
/// [includeModuleState] отсутствует не по недосмотру: в
/// `BackupSelection`/`BackupOptions` (Stage 6C) такого флага нет, а
/// state.json пишется всегда для каждого включённого модуля. Добавлять
/// флаг только ради переключателя в UI означало бы менять формат
/// глобального backup — этого 6E делать не должен.
class GlobalBackupSelection {
  /// Какие модули включать.
  final Set<String> moduleIds;

  /// «Все установленные модули» вместо ручного выбора.
  final bool allInstalled;

  final bool includeGlobalSettings;
  final bool includeModuleData;
  final bool includeAssets;

  const GlobalBackupSelection({
    required this.moduleIds,
    required this.allInstalled,
    this.includeGlobalSettings = true,
    this.includeModuleData = true,
    this.includeAssets = true,
  });
}

/// Что включать в backup одного модуля.
typedef ModuleBackupSelection = ModuleBackupOptions;

/// Режим восстановления модуля — 1:1 к поддерживаемым core режимам.
enum ModuleRestoreMode {
  full('Полный', 'State, данные и файлы модуля'),
  dataOnly('Только данные', 'Только хранилище модуля'),
  stateOnly('Только состояние', 'Только состояние установки'),
  assetsOnly('Только файлы', 'Только файлы модуля'),
  dataAndAssets('Данные и файлы', 'Хранилище и файлы модуля');

  const ModuleRestoreMode(this.label, this.description);

  final String label;
  final String description;

  /// Преобразует режим в параметры core.
  ModuleBackupOptions toOptions() {
    switch (this) {
      case ModuleRestoreMode.full:
        return const ModuleBackupOptions.full();
      case ModuleRestoreMode.dataOnly:
        return const ModuleBackupOptions.dataOnly();
      case ModuleRestoreMode.stateOnly:
        return const ModuleBackupOptions.stateOnly();
      case ModuleRestoreMode.assetsOnly:
        return const ModuleBackupOptions.assetsOnly();
      case ModuleRestoreMode.dataAndAssets:
        return const ModuleBackupOptions.dataAndAssets();
    }
  }
}

/// Готовый backup-файл: имя, которое предложит сохранить файл-пикер,
/// и сами байты.
class BackupArtifact {
  final String fileName;
  final List<int> bytes;

  const BackupArtifact({required this.fileName, required this.bytes});

  int get sizeBytes => bytes.length;
}

/// Краткое описание того, что внутри архива, — для показа до
/// подтверждения restore.
class BackupPreview {
  final String title;
  final DateTime createdAt;
  final String appVersion;
  final List<String> moduleIds;
  final bool includesSettings;
  final bool includesData;
  final bool includesAssets;

  const BackupPreview({
    required this.title,
    required this.createdAt,
    required this.appVersion,
    required this.moduleIds,
    required this.includesSettings,
    required this.includesData,
    required this.includesAssets,
  });
}

/// Результат восстановления модуля в терминах UI.
class RestoreOutcome {
  final bool isSuccess;
  final String moduleId;
  final List<String> appliedComponents;
  final List<String> rolledBackComponents;
  final String? message;

  const RestoreOutcome({
    required this.isSuccess,
    required this.moduleId,
    this.appliedComponents = const [],
    this.rolledBackComponents = const [],
    this.message,
    this.error,
  });

  /// Причина неудачи как объект-исключение.
  ///
  /// [message] — та же причина, но уже строкой; для показа пользователю
  /// нужен объект: [BackupErrorPresenter] умеет превращать известные
  /// исключения в понятные фразы и намеренно не показывает технический
  /// текст вслепую.
  final Object? error;
}

/// Проверенный файл, готовый к восстановлению.
class PickedBackup {
  final String fileName;
  final List<int> bytes;
  final BackupPreview preview;

  const PickedBackup({
    required this.fileName,
    required this.bytes,
    required this.preview,
  });
}

/// Операции backup, доступные UI.
abstract class BackupGateway {
  /// Идентификаторы установленных модулей — для выбора в UI.
  Future<List<String>> installedModuleIds();

  /// Название установленного модуля (для показа пользователю).
  String displayNameOf(String moduleId);

  Future<BackupArtifact> createGlobalBackup(GlobalBackupSelection selection);

  Future<BackupArtifact> createModuleBackup(
    String moduleId,
    ModuleBackupOptions options,
  );

  /// Читает и проверяет .pbk, ничего не изменяя.
  Future<BackupPreview> inspectGlobalBackup(List<int> archiveBytes);

  /// Читает и проверяет .pmb, ничего не изменяя.
  Future<BackupPreview> inspectModuleBackup(List<int> archiveBytes);

  /// Восстанавливает модуль из .pmb.
  Future<RestoreOutcome> restoreModuleBackup({
    required List<int> archiveBytes,
    required String moduleId,
    required ModuleBackupOptions options,
  });
}
