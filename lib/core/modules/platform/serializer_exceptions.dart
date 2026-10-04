/// Serializer exceptions for Module Platform.
library serializer_exceptions;

/// Base exception for all serializer errors.
abstract class SerializerException implements Exception {
  final String message;
  const SerializerException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// JSON is not valid.
class InvalidSerializerJsonException extends SerializerException {
  final String reason;

  const InvalidSerializerJsonException(this.reason) : super(reason);
}

/// JSON is not an object.
class NotJsonObjectException extends SerializerException {
  const NotJsonObjectException() : super('JSON должен быть объектом');
}

/// Required field is missing.
class MissingSerializerFieldException extends SerializerException {
  final String field;

  const MissingSerializerFieldException(this.field)
      : super('отсутствует обязательное поле: $field');
}

/// Version is missing or unsupported.
class UnsupportedSerializerVersionException extends SerializerException {
  final int version;
  final List<int> supportedVersions;

  UnsupportedSerializerVersionException({
    required this.version,
    required this.supportedVersions,
  }) : super(
          'неподдерживаемая версия формата: $version '
          '(поддерживаемые: ${supportedVersions.join(", ")})',
        );
}

/// Module ID mismatch.
class ModuleIdMismatchException extends SerializerException {
  final String expected;
  final String actual;

  const ModuleIdMismatchException({
    required this.expected,
    required this.actual,
  }) : super(
          'moduleId не совпадает: ожидался "$expected", получен "$actual"',
        );
}

/// Entries field is missing or not an object.
class InvalidEntriesException extends SerializerException {
  final String reason;

  const InvalidEntriesException(this.reason) : super(reason);
}

/// Entry key is not a string.
class NonStringKeyException extends SerializerException {
  final dynamic key;

  const NonStringKeyException(this.key)
      : super('ключ записи не является строкой: $key');
}

/// Entry value is not a string.
class NonStringValueException extends SerializerException {
  final String key;
  final dynamic value;

  const NonStringValueException({
    required this.key,
    required this.value,
  }) : super('значение записи "$key" не является строкой: $value');
}

/// Data size exceeds reasonable limit.
class SerializerDataTooLargeException extends SerializerException {
  final int sizeBytes;
  final int maxBytes;

  SerializerDataTooLargeException({
    required this.sizeBytes,
    required this.maxBytes,
  }) : super(
          'размер данных ${_format(sizeBytes)} превышает максимум ${_format(maxBytes)}',
        );

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}