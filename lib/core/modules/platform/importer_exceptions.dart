/// Exceptions for Module Platform import operations.
library importer_exceptions;

/// Base exception for all import errors.
abstract class ImporterException implements Exception {
  final String message;
  const ImporterException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Module ID already exists in registry or as builtin.
class DuplicateModuleIdException extends ImporterException {
  final String moduleId;

  const DuplicateModuleIdException(this.moduleId)
      : super('moduleId "$moduleId" уже зарегистрирован');
}

/// Module ID is a builtin module that cannot be replaced.
class BuiltinModuleIdException extends ImporterException {
  final String moduleId;

  const BuiltinModuleIdException(this.moduleId)
      : super('moduleId "$moduleId" является встроенным модулем и не может быть заменен');
}

/// Module ID is not registered in the registry.
class ModuleNotRegisteredException extends ImporterException {
  final String moduleId;

  const ModuleNotRegisteredException(this.moduleId)
      : super('модуль "$moduleId" не зарегистрирован в ModuleRegistry');
}

/// Module is in a state that prevents the requested operation.
class InvalidModuleStateException extends ImporterException {
  final String moduleId;
  final String currentState;
  final String requiredState;

  const InvalidModuleStateException({
    required this.moduleId,
    required this.currentState,
    required this.requiredState,
  }) : super(
      'модуль "$moduleId" в состоянии "$currentState", требуется "$requiredState"',
    );
}

/// Dependency resolution failed.
class DependencyResolutionException extends ImporterException {
  final String moduleId;
  final List<String> missingDependencies;

  DependencyResolutionException({
    required this.moduleId,
    required this.missingDependencies,
  }) : super(
      'модуль "$moduleId": не выполнены зависимости: ${missingDependencies.join(", ")}',
    );
}

/// Permission validation failed.
class PermissionValidationException extends ImporterException {
  final String moduleId;
  final String permission;

  const PermissionValidationException({
    required this.moduleId,
    required this.permission,
  }) : super('модуль "$moduleId" требует разрешение "$permission", но оно не объявлено в манифесте');
}

/// Sandbox operation failed.
class ImporterSandboxException extends ImporterException {
  final String operation;
  final String path;
  final String reason;

  const ImporterSandboxException({
    required this.operation,
    required this.path,
    required this.reason,
  }) : super('sandbox $operation failed for "$path": $reason');
}

/// Storage operation failed during import.
class ImporterStorageException extends ImporterException {
  final String operation;
  final String key;
  final String reason;

  const ImporterStorageException({
    required this.operation,
    required this.key,
    required this.reason,
  }) : super('storage $operation failed for key "$key": $reason');
}

/// ModuleManager operation failed during import.
class ImporterModuleManagerException extends ImporterException {
  final String operation;
  final String reason;

  const ImporterModuleManagerException({
    required this.operation,
    required this.reason,
  }) : super('ModuleManager $operation failed: $reason');
}