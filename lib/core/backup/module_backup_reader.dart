/// Module backup reader.
///
/// Reads and validates .pmb (Personal Hub Module Backup) archives.
///
/// Семантика checksum и разбора ZIP — ровно та же, что в BackupReader
/// для .pbk: writer и reader должны оставаться совместимыми, поэтому
/// алгоритм здесь намеренно дублирует, а не «улучшает».
library module_backup_reader;

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'module_backup_manifest.dart';
import 'backup_security_guard.dart';
import 'backup_exceptions.dart';

/// Прочитанный и провалидированный .pmb.
class ModuleBackup {
  final ModuleBackupManifest manifest;
  final String? stateJson;
  final String? dataJson;
  final Map<String, List<int>> assets;
  final String appVersion;
  final String createdAt;
  final String checksum;

  const ModuleBackup({
    required this.manifest,
    this.stateJson,
    this.dataJson,
    required this.assets,
    required this.appVersion,
    required this.createdAt,
    required this.checksum,
  });

  String get moduleId => manifest.moduleId;
  String get moduleVersion => manifest.moduleVersion;
  int get backupFormatVersion => manifest.backupFormatVersion;
}

/// Читает .pmb: security → структура → manifest → checksum.
class ModuleBackupReader {
  /// [archiveBytes] — полный архив .pmb.
  ///
  /// Бросает [BackupException] на любой провал валидации.
  static Future<ModuleBackup> readModuleBackup(List<int> archiveBytes) async {
    // 1. Security (общие для .pbk/.pmb лимиты + структура .pmb)
    BackupSecurityGuard.validateArchive(
      archiveBytes,
      kind: BackupArchiveKind.module,
    );

    // 2. Entries
    final entries = _extractEntries(archiveBytes);

    // 3. Обязательные записи
    _validateRequiredEntries(entries);

    // 4. manifest.json
    final ModuleBackupManifest manifest;
    try {
      manifest = ModuleBackupManifest.fromJson(
        jsonDecode(utf8.decode(entries['manifest.json']!)) as Map<String, dynamic>,
      );
    } on FormatException catch (e) {
      throw BackupFormatException('невалидный manifest.json: ${e.message}');
    }

    // 5. Внутренняя непротиворечивость манифеста
    final violations = manifest.validate();
    if (violations.isNotEmpty) {
      throw InvalidBackupManifestException(violations);
    }

    // 6. Версия формата (неизвестная — отказ)
    if (!kSupportedModuleBackupFormatVersions.contains(manifest.backupFormatVersion)) {
      throw UnsupportedBackupVersionException(
        version: manifest.backupFormatVersion,
        supportedVersions: kSupportedModuleBackupFormatVersions,
      );
    }

    // 7. Checksum — до любого использования содержимого
    final checksum = _verifyChecksum(archiveBytes, entries);

    // 8. Компоненты
    final stateJson = entries.containsKey('state.json')
        ? utf8.decode(entries['state.json']!)
        : null;
    final dataJson =
        entries.containsKey('data.json') ? utf8.decode(entries['data.json']!) : null;

    final assets = <String, List<int>>{};
    for (final entry in entries.entries) {
      if (entry.key.startsWith('assets/')) {
        assets[entry.key.substring('assets/'.length)] = entry.value;
      }
    }

    return ModuleBackup(
      manifest: manifest,
      stateJson: stateJson,
      dataJson: dataJson,
      assets: assets,
      appVersion: utf8.decode(entries['metadata/appVersion']!),
      createdAt: utf8.decode(entries['metadata/createdAt']!),
      checksum: checksum,
    );
  }

  /// Извлекает все файлы. Дубликаты имён — отказ: иначе «какой из двух
  /// data.json победит» зависит от порядка и это неоднозначный backup.
  static Map<String, List<int>> _extractEntries(List<int> archiveBytes) {
    final eocdOffset = _findEocd(archiveBytes);

    final totalRecords = _readUint16(archiveBytes, eocdOffset + 10);
    final centralDirOffset = _readUint32(archiveBytes, eocdOffset + 16);

    final result = <String, List<int>>{};
    int offset = centralDirOffset;

    for (var i = 0; i < totalRecords; i++) {
      if (offset + 46 > archiveBytes.length) {
        throw const CorruptedArchiveException('неполная запись центральной директории');
      }
      if (archiveBytes[offset] != 0x50 ||
          archiveBytes[offset + 1] != 0x4b ||
          archiveBytes[offset + 2] != 0x01 ||
          archiveBytes[offset + 3] != 0x02) {
        throw const CorruptedArchiveException('неверная сигнатура записи');
      }

      final compressedSize = _readUint32(archiveBytes, offset + 20);
      final uncompressedSize = _readUint32(archiveBytes, offset + 24);
      final fileNameLength = _readUint16(archiveBytes, offset + 28);
      final extraFieldLength = _readUint16(archiveBytes, offset + 30);
      final commentLength = _readUint16(archiveBytes, offset + 32);
      final localHeaderOffset = _readUint32(archiveBytes, offset + 42);

      final nameStart = offset + 46;
      if (nameStart + fileNameLength > archiveBytes.length) {
        throw const CorruptedArchiveException('имя файла выходит за границы архива');
      }

      final name = utf8.decode(archiveBytes.sublist(nameStart, nameStart + fileNameLength));
      offset = nameStart + fileNameLength + extraFieldLength + commentLength;

      if (name.endsWith('/')) continue;

      if (result.containsKey(name)) {
        throw BackupFormatException('дублирующаяся запись в архиве: $name');
      }

      final localOffset = localHeaderOffset;
      if (localOffset + 30 > archiveBytes.length) {
        throw const CorruptedArchiveException('неполный локальный заголовок');
      }
      if (archiveBytes[localOffset] != 0x50 ||
          archiveBytes[localOffset + 1] != 0x4b ||
          archiveBytes[localOffset + 2] != 0x03 ||
          archiveBytes[localOffset + 3] != 0x04) {
        throw CorruptedBackupException('неверная сигнатура локального заголовка для $name');
      }

      final compressionMethod = _readUint16(archiveBytes, localOffset + 8);
      if (compressionMethod != 0) {
        throw BackupFormatException('неподдерживаемый метод сжатия: $compressionMethod для $name');
      }

      // stored: compressedSize обязан совпадать с uncompressedSize
      if (compressedSize != uncompressedSize) {
        throw CorruptedBackupException('compressedSize != uncompressedSize для stored-метода: $name');
      }

      final dataStart =
          localOffset + 30 + _readUint16(archiveBytes, localOffset + 26) + _readUint16(archiveBytes, localOffset + 28);
      final dataEnd = dataStart + compressedSize;
      if (dataEnd > archiveBytes.length) {
        throw CorruptedBackupException('данные файла $name выходят за границы архива');
      }

      result[name] = archiveBytes.sublist(dataStart, dataEnd);
    }

    return result;
  }

  static void _validateRequiredEntries(Map<String, List<int>> entries) {
    const required = [
      'manifest.json',
      'metadata/backupFormatVersion',
      'metadata/appVersion',
      'metadata/createdAt',
      'metadata/checksum',
    ];
    for (final entry in required) {
      if (!entries.containsKey(entry)) {
        throw MissingBackupEntryException(entry);
      }
    }
  }

  /// Восстанавливает ровно те байты, которые writer скормил в SHA-256:
  /// local file header + данные для каждой записи в порядке центральной
  /// директории, кроме самой metadata/checksum. Возвращает сохранённую
  /// строку checksum.
  static String _verifyChecksum(List<int> archiveBytes, Map<String, List<int>> entries) {
    final storedChecksum = utf8.decode(entries['metadata/checksum']!);

    final reconstructed = <int>[];
    for (final record in _centralDirectory(archiveBytes)) {
      if (record.name == 'metadata/checksum') continue;

      final data = entries[record.name];
      if (data == null) {
        throw CorruptedBackupException('запись найдена в манифесте архива, но отсутствует: ${record.name}');
      }

      final nameBytes = utf8.encode(record.name);
      _writeUint32(reconstructed, 0x04034b50);
      _writeUint16(reconstructed, 20);
      _writeUint16(reconstructed, 0);
      _writeUint16(reconstructed, 0);
      _writeUint16(reconstructed, 0);
      _writeUint16(reconstructed, 0);
      _writeUint32(reconstructed, _computeCRC32(data));
      _writeUint32(reconstructed, data.length);
      _writeUint32(reconstructed, data.length);
      _writeUint16(reconstructed, nameBytes.length);
      _writeUint16(reconstructed, 0);
      reconstructed.addAll(nameBytes);
      reconstructed.addAll(data);
    }

    if (sha256.convert(reconstructed).toString() != storedChecksum) {
      throw const ChecksumMismatchException();
    }
    return storedChecksum;
  }

  static List<({String name, int localHeaderOffset})> _centralDirectory(List<int> archiveBytes) {
    final eocdOffset = _findEocd(archiveBytes);
    final totalRecords = _readUint16(archiveBytes, eocdOffset + 10);
    int offset = _readUint32(archiveBytes, eocdOffset + 16);

    final records = <({String name, int localHeaderOffset})>[];
    for (var i = 0; i < totalRecords; i++) {
      if (offset + 46 > archiveBytes.length) {
        throw const CorruptedArchiveException('неполная запись центральной директории');
      }
      final fileNameLength = _readUint16(archiveBytes, offset + 28);
      final extraFieldLength = _readUint16(archiveBytes, offset + 30);
      final commentLength = _readUint16(archiveBytes, offset + 32);
      final nameStart = offset + 46;
      if (nameStart + fileNameLength > archiveBytes.length) {
        throw const CorruptedArchiveException('имя файла выходит за границы архива');
      }

      final name = utf8.decode(archiveBytes.sublist(nameStart, nameStart + fileNameLength));
      if (!name.endsWith('/')) {
        records.add((name: name, localHeaderOffset: _readUint32(archiveBytes, offset + 42)));
      }
      offset = nameStart + fileNameLength + extraFieldLength + commentLength;
    }
    return records;
  }

  static int _findEocd(List<int> bytes) {
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    throw const CorruptedBackupException('не найдена EOCD');
  }

  static int _computeCRC32(List<int> data) {
    const int polynomial = 0xEDB88320;
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ ((crc & 1) * polynomial);
      }
    }
    return ~crc & 0xFFFFFFFF;
  }

  static void _writeUint16(List<int> list, int v) {
    list.add(v & 0xFF);
    list.add((v >> 8) & 0xFF);
  }

  static void _writeUint32(List<int> list, int v) {
    list.add(v & 0xFF);
    list.add((v >> 8) & 0xFF);
    list.add((v >> 16) & 0xFF);
    list.add((v >> 24) & 0xFF);
  }

  static int _readUint16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _readUint32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
