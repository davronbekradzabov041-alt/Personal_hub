/// Exceptions for Module Platform package I/O operations.
///
/// These are distinct from ModuleLifecycleError (which is for lifecycle
/// violations) and ManifestParseException (which is for JSON parsing).
/// These exceptions cover archive-level and package-structure issues.
library package_exceptions;

/// Base exception for all package I/O errors.
abstract class PackageException implements Exception {
  final String message;
  const PackageException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The ZIP archive is corrupted or not a valid ZIP file.
class CorruptedArchiveException extends PackageException {
  const CorruptedArchiveException([String message = 'повреждённый или невалидный ZIP-архив'])
      : super(message);
}

/// Archive size exceeds the maximum allowed (20 MB).
class ArchiveTooLargeException extends PackageException {
  final int sizeBytes;
  final int maxBytes;

  ArchiveTooLargeException({
    required this.sizeBytes,
    required this.maxBytes,
  }) : super(
          'размер архива ${_format(sizeBytes)} превышает максимум ${_format(maxBytes)}',
        );

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

/// Archive contains more files than the maximum allowed (100).
class TooManyFilesException extends PackageException {
  final int count;
  final int maxCount;

  const TooManyFilesException({
    required this.count,
    required this.maxCount,
  }) : super('количество файлов $count превышает максимум $maxCount');
}

/// Total extracted size exceeds the maximum allowed (50 MB).
class ExtractedSizeExceededException extends PackageException {
  final int extractedBytes;
  final int maxBytes;

  ExtractedSizeExceededException({
    required this.extractedBytes,
    required this.maxBytes,
  }) : super(
          'распакованный размер ${_format(extractedBytes)} превышает максимум ${_format(maxBytes)}',
        );

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

/// Individual file size exceeds the maximum allowed (10 MB).
class FileTooLargeException extends PackageException {
  final String path;
  final int sizeBytes;
  final int maxBytes;

  FileTooLargeException({
    required this.path,
    required this.sizeBytes,
    required this.maxBytes,
  }) : super(
          'файл "$path" (${_format(sizeBytes)}) превышает максимум ${_format(maxBytes)}',
        );

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

/// Path contains traversal attempts or is otherwise invalid.
class InvalidPathException extends PackageException {
  final String path;
  final String reason;

  const InvalidPathException({
    required this.path,
    required this.reason,
  }) : super('невалидный путь "$path": $reason');
}

/// File extension or type is not allowed in the package.
class UnsupportedFileException extends PackageException {
  final String path;
  final String reason;

  const UnsupportedFileException({
    required this.path,
    required this.reason,
  }) : super('неподдерживаемый файл "$path": $reason');
}

/// Package structure is invalid (wrong files in wrong places).
class InvalidPackageStructureException extends PackageException {
  final String reason;

  const InvalidPackageStructureException(this.reason) : super(reason);
}

/// manifest.json is missing, not valid JSON, or fails validation.
class InvalidManifestException extends PackageException {
  final String reason;
  final List<String>? violations;

  const InvalidManifestException(this.reason, {this.violations}) : super(reason);
}

/// data/storage.json is present but not valid JSON.
class InvalidStorageJsonException extends PackageException {
  final String reason;

  const InvalidStorageJsonException(this.reason) : super(reason);
}

/// Hidden or system files are not allowed.
class HiddenFileException extends PackageException {
  final String path;

  const HiddenFileException(this.path)
      : super('скрытые или системные файлы не разрешены: "$path"');
}