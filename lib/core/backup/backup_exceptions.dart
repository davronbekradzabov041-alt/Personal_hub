/// Exceptions for Backup operations.
///
/// These follow the existing typed-exception architecture pattern.
library backup_exceptions;

/// Base exception for all backup-related errors.
abstract class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The backup format is invalid or corrupted.
class BackupFormatException extends BackupException {
  final String reason;
  const BackupFormatException(this.reason) : super('некорректный формат backup: $reason');
}

/// The backup format version is not supported.
class UnsupportedBackupVersionException extends BackupException {
  final int version;
  final List<int> supportedVersions;

  UnsupportedBackupVersionException({
    required this.version,
    required this.supportedVersions,
  }) : super(
    'неподдерживаемая версия backup-формата: $version '
    '(поддерживаемые: ${supportedVersions.join(", ")})',
  );
}

/// The backup archive is corrupted or tampered with.
class CorruptedBackupException extends BackupException {
  final String reason;
  const CorruptedBackupException(this.reason) : super('backup повреждён: $reason');
}

/// Security violation in backup archive.
class BackupSecurityException extends BackupException {
  final String reason;
  const BackupSecurityException(this.reason) : super('нарушение безопасности backup: $reason');
}

/// Checksum verification failed.
class ChecksumMismatchException extends BackupException {
  const ChecksumMismatchException() : super('контрольная сумма не совпадает: backup повреждён или изменён');
}

/// Required entry missing from backup archive.
class MissingBackupEntryException extends BackupException {
  final String entryPath;
  const MissingBackupEntryException(this.entryPath)
      : super('обязательная запись отсутствует в backup: $entryPath');
}

/// Module ID validation failed.
class InvalidModuleIdInBackupException extends BackupException {
  final String moduleId;
  final String reason;
  const InvalidModuleIdInBackupException(this.moduleId, this.reason)
      : super('невалидный moduleId в backup: $moduleId ($reason)');
}

/// Duplicate module ID in backup.
class DuplicateModuleIdInBackupException extends BackupException {
  final String moduleId;
  const DuplicateModuleIdInBackupException(this.moduleId)
      : super('дублирующийся moduleId в backup: $moduleId');
}

/// Module not found in backup.
class ModuleNotInBackupException extends BackupException {
  final String moduleId;
  const ModuleNotInBackupException(this.moduleId)
      : super('модуль не найден в backup: $moduleId');
}

/// Backup manifest validation failed.
class InvalidBackupManifestException extends BackupException {
  final List<String> violations;
  InvalidBackupManifestException(this.violations)
      : super('manifest backup не прошел валидацию: ${violations.join("; ")}');
}

/// Backup writer error.
class BackupWriteException extends BackupException {
  final String reason;
  const BackupWriteException(this.reason) : super('ошибка записи backup: $reason');
}

/// Corrupted archive exception.
class CorruptedArchiveException extends BackupException {
  final String reason;
  const CorruptedArchiveException(this.reason) : super('архив повреждён: $reason');
}

/// Module ID mismatch between backup and target.
class ModuleIdMismatchException extends BackupException {
  final String expected;
  final String actual;
  const ModuleIdMismatchException({
    required this.expected,
    required this.actual,
  }) : super('moduleId не совпадает: ожидался "$expected", получен "$actual"');
}

/// Не удалось выполнить откат неудачного restore.
///
/// Отдельный тип от [BackupException] намеренно: «данные не восстановили»
/// и «данные восстановили, но не смогли вернуть как было» — разные
/// ситуации с разными последствиями, и молчать об этом нельзя.
class ModuleRestoreException extends BackupException {
  final Object cause;
  const ModuleRestoreException(this.cause)
      : super('откат восстановления не удался: $cause');
}

/// Целевой модуль не установлен, поэтому .pmb некуда восстанавливать.///
/// .pmb — это данные пользователя, а не пакет реализации: он не
/// устанавливает модуль. Восстановление возможно только в уже
/// установленный модуль с тем же moduleId.
class ModuleNotInstalledException extends BackupException {
  final String moduleId;
  final String reason;
  const ModuleNotInstalledException(this.moduleId, this.reason)
      : super('модуль $moduleId не установлен ($reason)');
}