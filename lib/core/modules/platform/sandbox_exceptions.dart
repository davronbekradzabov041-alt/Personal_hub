/// Sandbox exceptions for Module Platform.
///
/// These are distinct from PackageException (archive-level) and
/// ModuleLifecycleError (lifecycle-level).
library sandbox_exceptions;

/// Base exception for all sandbox errors.
abstract class SandboxException implements Exception {
  final String message;
  const SandboxException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Module ID contains path traversal or is otherwise invalid.
class InvalidModuleIdException extends SandboxException {
  final String moduleId;
  final String reason;

  const InvalidModuleIdException({
    required this.moduleId,
    required this.reason,
  }) : super('невалидный moduleId "$moduleId": $reason');
}

/// Sandbox directory operations failed.
class SandboxIOException extends SandboxException {
  final String operation;
  final String path;
  final String reason;

  const SandboxIOException({
    required this.operation,
    required this.path,
    required this.reason,
  }) : super('sandbox $operation failed for "$path": $reason');
}

/// Sandbox already exists when creation was expected to fail.
class SandboxAlreadyExistsException extends SandboxException {
  final String moduleId;

  const SandboxAlreadyExistsException(this.moduleId)
      : super('sandbox для модуля "$moduleId" уже существует');
}

/// Sandbox does not exist when operation expected it to.
class SandboxNotFoundException extends SandboxException {
  final String moduleId;

  const SandboxNotFoundException(this.moduleId)
      : super('sandbox для модуля "$moduleId" не найден');
}