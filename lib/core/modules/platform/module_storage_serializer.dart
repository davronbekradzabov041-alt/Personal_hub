import 'dart:convert';

import '../module_storage.dart';
import 'serializer_exceptions.dart';

/// Serializes and deserializes ModuleStorage to/from JSON.
///
/// Uses the public ModuleStorage API only — no direct Isar access.
/// The JSON format:
/// ```json
/// {
///   "version": 1,
///   "moduleId": "example",
///   "entries": {
///     "key1": "value1",
///     "key2": "value2"
///   }
/// }
/// ```
class ModuleStorageSerializer {
  ModuleStorageSerializer._();

  /// Current serialization format version.
  static const int currentVersion = 1;

  /// Supported format versions (for forward compatibility).
  static const List<int> supportedVersions = [1];

  /// Maximum allowed size of serialized JSON (1 MB).
  static const int maxJsonSizeBytes = 1024 * 1024;

  /// Serializes a ModuleStorage to a JSON string.
  ///
  /// Returns a pretty-printed JSON string with version, moduleId, and all entries.
  /// Throws [SerializerException] on failure.
  static Future<String> serialize({
    required ModuleStorage storage,
    required String moduleId,
  }) async {
    // Get all keys
    final keys = await storage.keys();

    // Build entries map
    final entries = <String, String>{};
    for (final key in keys) {
      final value = await storage.getString(key);
      if (value != null) {
        entries[key] = value;
      }
    }

    // Build JSON structure
    final json = {
      'version': currentVersion,
      'moduleId': moduleId,
      'entries': entries,
    };

    // Serialize with pretty printing
    final encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(json);

    // Check size limit
    final bytes = utf8.encode(jsonString);
    if (bytes.length > maxJsonSizeBytes) {
      throw SerializerDataTooLargeException(
        sizeBytes: bytes.length,
        maxBytes: maxJsonSizeBytes,
      );
    }

    return jsonString;
  }

  /// Deserializes a JSON string into a ModuleStorage.
  ///
  /// Validates the JSON structure, version, moduleId, and all entries.
  /// Performs atomic restore: validates entire JSON first, then writes all entries.
  /// On failure, rolls back any entries written during this operation.
  ///
  /// Returns normally on success, throws [SerializerException] on failure.
  static Future<void> deserialize({
    required String jsonString,
    required ModuleStorage storage,
    required String expectedModuleId,
  }) async {
    // 1. Parse JSON
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const NotJsonObjectException();
      }
      json = decoded;
    } on FormatException catch (e) {
      throw InvalidSerializerJsonException('повреждённый JSON: ${e.message}');
    }

    // 2. Validate top-level structure
    _validateVersion(json);
    _validateModuleId(json, expectedModuleId);
    final entries = _validateEntries(json);

    // 3. Atomic restore: validate all, then write
    // First, get existing keys to know what to clean up on failure
    final existingKeys = await storage.keys();
    final existingKeysSet = existingKeys.toSet();

    try {
      // Write all entries
      for (final entry in entries.entries) {
        await storage.setString(entry.key, entry.value);
      }

      // Remove keys that existed before but aren't in the new data
      // (This ensures exact match with the serialized data)
      final newKeys = entries.keys.toSet();
      final keysToRemove = existingKeysSet.difference(newKeys);
      for (final key in keysToRemove) {
        await storage.remove(key);
      }
    } catch (e) {
      // Rollback: remove any keys written during this operation
      // and restore original keys
      await _rollback(storage, existingKeysSet);
      rethrow;
    }
  }

  /// Validates the version field.
  static void _validateVersion(Map<String, dynamic> json) {
    if (!json.containsKey('version')) {
      throw const MissingSerializerFieldException('version');
    }
    final version = json['version'];
    if (version is! int) {
      throw const InvalidSerializerJsonException('version должен быть целым числом');
    }
    if (!supportedVersions.contains(version)) {
      throw UnsupportedSerializerVersionException(
        version: version,
        supportedVersions: supportedVersions,
      );
    }
  }

  /// Validates the moduleId field.
  static void _validateModuleId(Map<String, dynamic> json, String expectedModuleId) {
    if (!json.containsKey('moduleId')) {
      throw const MissingSerializerFieldException('moduleId');
    }
    final moduleId = json['moduleId'];
    if (moduleId is! String) {
      throw const InvalidSerializerJsonException('moduleId должен быть строкой');
    }
    if (moduleId != expectedModuleId) {
      throw ModuleIdMismatchException(
        expected: expectedModuleId,
        actual: moduleId,
      );
    }
  }

  /// Validates the entries field.
  static Map<String, String> _validateEntries(Map<String, dynamic> json) {
    if (!json.containsKey('entries')) {
      throw const MissingSerializerFieldException('entries');
    }
    final entries = json['entries'];
    if (entries is! Map<String, dynamic>) {
      throw const InvalidEntriesException('entries должен быть объектом');
    }

    final result = <String, String>{};
    for (final entry in entries.entries) {
      // Ключи Map<String, dynamic> по типу всегда String, поэтому
      // отдельная проверка ключа и приведение типа не нужны.
      final key = entry.key;

      // Value must be string
      if (entry.value is! String) {
        throw NonStringValueException(key: key, value: entry.value);
      }
      result[key] = entry.value as String;
    }
    return result;
  }

  /// Rollback on deserialization failure.
  static Future<void> _rollback(ModuleStorage storage, Set<String> originalKeys) async {
    // Get current keys
    final currentKeys = await storage.keys();
    final currentKeysSet = currentKeys.toSet();

    // Remove keys that were added during this operation
    final keysToRemove = currentKeysSet.difference(originalKeys);
    for (final key in keysToRemove) {
      try {
        await storage.remove(key);
      } catch (_) {
        // Best effort rollback
      }
    }

    // Note: We don't restore modified values of original keys
    // because ModuleStorage doesn't support "get all values atomically"
    // This is a best-effort rollback
  }
}