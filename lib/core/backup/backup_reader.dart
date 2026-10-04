/// Global backup reader.
///
/// Reads and validates .pbk backup archives.
library backup_reader;

import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../modules/module_manifest.dart';
import 'backup_manifest.dart';
import 'backup_security_guard.dart';
import 'backup_exceptions.dart';

/// Result of reading a global backup.
class GlobalBackup {
  final BackupManifest manifest;
  final String? globalSettingsJson;
  final String? globalMetadataJson;
  final Map<String, GlobalBackupModule> modules;
  final String backupFormatVersion;
  final String appVersion;
  final String createdAt;
  final String checksum;

  const GlobalBackup({
    required this.manifest,
    this.globalSettingsJson,
    this.globalMetadataJson,
    required this.modules,
    required this.backupFormatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.checksum,
  });
}

/// Module data from backup.
class GlobalBackupModule {
  final String moduleId;
  final ModuleManifest manifest;
  final String? stateJson;
  final String? dataJson;
  final Map<String, List<int>> assets;

  const GlobalBackupModule({
    required this.moduleId,
    required this.manifest,
    this.stateJson,
    this.dataJson,
    this.assets = const {},
  });
}

/// Reads and validates a global backup (.pbk) archive.
class BackupReader {
  /// Reads a global backup from bytes.
  ///
  /// [archiveBytes] - complete .pbk archive bytes
  /// [existingModuleIds] - set of currently registered module IDs for validation
  ///
  /// Returns [GlobalBackup] on success, throws [BackupException] on failure.
  static Future<GlobalBackup> readGlobalBackup(
    List<int> archiveBytes, {
    required Set<String> existingModuleIds,
  }) async {
    // 1. Security validation
    BackupSecurityGuard.validateArchive(archiveBytes);

    // 2. Extract entries
    final entries = _extractEntries(archiveBytes);

    // 3. Validate required entries
    _validateRequiredEntries(entries);

    // 2. Parse manifest
    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null) {
      throw const MissingBackupEntryException('manifest.json');
    }
    final manifestJson = utf8.decode(manifestEntry);
    final BackupManifest manifest;
    try {
      manifest = BackupManifest.fromJson(jsonDecode(manifestJson));
    } on FormatException catch (e) {
      throw BackupFormatException('невалидный manifest.json: ${e.message}');
    }

    // Validate manifest
    final violations = manifest.validate();
    if (violations.isNotEmpty) {
      throw InvalidBackupManifestException(violations);
    }

    // Check version compatibility
    if (!kSupportedBackupFormatVersions.contains(manifest.backupFormatVersion)) {
      throw UnsupportedBackupVersionException(
        version: manifest.backupFormatVersion,
        supportedVersions: kSupportedBackupFormatVersions,
      );
    }

    // Verify checksum
    _verifyChecksum(archiveBytes, entries);

    // 3. Extract global settings
    String? globalSettingsJson;
    final settingsEntry = entries['global/settings.json'];
    if (settingsEntry != null) {
      globalSettingsJson = utf8.decode(settingsEntry);
    }

    // Extract global metadata
    String? globalMetadataJson;
    final metadataEntry = entries['global/metadata.json'];
    if (metadataEntry != null) {
      globalMetadataJson = utf8.decode(metadataEntry);
    }

    // 3. Extract modules
    final modules = <String, GlobalBackupModule>{};
    for (final moduleId in manifest.includedModules) {
      final module = _extractModule(entries, moduleId);
      if (module != null) {
        modules[moduleId] = module;
      }
    }

    // Extract metadata
    String? backupFormatVersion;
    String? appVersion;
    String? createdAt;
    String? checksum;

    for (final entry in entries.entries) {
      if (entry.key == 'metadata/backupFormatVersion') {
        backupFormatVersion = utf8.decode(entry.value);
      } else if (entry.key == 'metadata/appVersion') {
        appVersion = utf8.decode(entry.value);
      } else if (entry.key == 'metadata/createdAt') {
        createdAt = utf8.decode(entry.value);
      } else if (entry.key == 'metadata/checksum') {
        checksum = utf8.decode(entry.value);
      }
    }

    return GlobalBackup(
      manifest: manifest,
      globalSettingsJson: globalSettingsJson,
      globalMetadataJson: globalMetadataJson,
      modules: modules,
      backupFormatVersion: backupFormatVersion ?? '',
      appVersion: appVersion ?? '',
      createdAt: createdAt ?? '',
      checksum: checksum ?? '',
    );
  }

  static Map<String, List<int>> _extractEntries(List<int> archiveBytes) {
    // Find EOCD
    int eocdOffset = -1;
    for (int i = archiveBytes.length - 22; i >= 0; i--) {
      if (archiveBytes[i] == 0x50 &&
          archiveBytes[i + 1] == 0x4b &&
          archiveBytes[i + 2] == 0x05 &&
          archiveBytes[i + 3] == 0x06) {
        eocdOffset = i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw const CorruptedBackupException('не найдена EOCD');
    }

    final totalRecords = _readUint16(archiveBytes, eocdOffset + 10);
    final centralDirOffset = _readUint32(archiveBytes, eocdOffset + 16);

    final result = <String, List<int>>{};
    int offset = centralDirOffset;

    for (int i = 0; i < totalRecords; i++) {
      if (offset + 46 > archiveBytes.length) {
        throw const CorruptedArchiveException('неполная запись центральной директории');
      }

      // Verify signature
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

      // Skip directory entries
      if (!name.endsWith('/')) {
        final localOffset = localHeaderOffset;
        if (localOffset + 30 > archiveBytes.length) {
          throw const CorruptedArchiveException('неполный локальный заголовок');
        }

        // Verify local header signature
        if (archiveBytes[localOffset] != 0x50 ||
            archiveBytes[localOffset + 1] != 0x4b ||
            archiveBytes[localOffset + 2] != 0x03 ||
            archiveBytes[localOffset + 3] != 0x04) {
          throw CorruptedBackupException('неверная сигнатура локального заголовка для $name');
        }

        final localNameLength = _readUint16(archiveBytes, localOffset + 26);
        final localExtraLength = _readUint16(archiveBytes, localOffset + 28);
        final dataStart = localOffset + 30 + localNameLength + localExtraLength;
        final dataEnd = dataStart + compressedSize;

        if (dataEnd > archiveBytes.length) {
          throw CorruptedBackupException('данные файла $name выходят за границы архива');
        }

        final compressedData = archiveBytes.sublist(dataStart, dataEnd);

        // Decompress if needed
        final compressionMethod = _readUint16(archiveBytes, localOffset + 8);
        if (compressionMethod != 0) {
          throw BackupFormatException('неподдерживаемый метод сжатия: $compressionMethod для $name');
        }
        final data = compressedData;

        // For stored (method 0), compressedSize must equal uncompressedSize
        if (compressionMethod == 0 && compressedSize != uncompressedSize) {
          throw CorruptedBackupException('compressedSize != uncompressedSize для stored-метода: $name');
        }

        if (data.length != uncompressedSize) {
          throw CorruptedBackupException('размер распакованных данных не совпадает для $name');
        }

        result[name] = data;
      }

      offset = nameStart + fileNameLength + extraFieldLength + commentLength;
    }

    return result;
  }

  static GlobalBackupModule? _extractModule(Map<String, List<int>> entries, String moduleId) {
    final manifestEntry = entries['modules/$moduleId/manifest.json'];
    if (manifestEntry == null) {
      return null;
    }

    final manifestJson = utf8.decode(manifestEntry);
    // Результат не нужен: fromJson здесь валидирует манифест модуля и
    // бросает BackupFormatException на некорректных данных.
    ModuleManifest.fromJson(jsonDecode(manifestJson));

    String? stateJson;
    final stateEntry = entries['modules/$moduleId/state.json'];
    if (stateEntry != null) {
      stateJson = utf8.decode(stateEntry);
    }

    String? dataJson;
    final dataEntry = entries['modules/$moduleId/data.json'];
    if (dataEntry != null) {
      dataJson = utf8.decode(dataEntry);
    }

    final assets = <String, List<int>>{};
    for (final entry in entries.entries) {
      if (entry.key.startsWith('modules/$moduleId/assets/') && !entry.key.endsWith('/')) {
        final fileName = entry.key.split('/').last;
        assets[fileName] = entry.value;
      }
    }

    return GlobalBackupModule(
      moduleId: moduleId,
      manifest: ModuleManifest.fromJson(jsonDecode(utf8.decode(manifestEntry))),
      stateJson: stateJson,
      dataJson: dataJson,
      assets: assets,
    );
  }

  static void _validateRequiredEntries(Map<String, List<int>> entries) {
    if (!entries.containsKey('manifest.json')) {
      throw const MissingBackupEntryException('manifest.json');
    }
    if (!entries.containsKey('metadata/backupFormatVersion')) {
      throw const MissingBackupEntryException('metadata/backupFormatVersion');
    }
    if (!entries.containsKey('metadata/appVersion')) {
      throw const MissingBackupEntryException('metadata/appVersion');
    }
    if (!entries.containsKey('metadata/createdAt')) {
      throw const MissingBackupEntryException('metadata/createdAt');
    }
    if (!entries.containsKey('metadata/checksum')) {
      throw const MissingBackupEntryException('metadata/checksum');
    }
  }

  static void _verifyChecksum(List<int> archiveBytes, Map<String, List<int>> entries) {
    // Get the stored checksum
    final checksumEntry = entries['metadata/checksum'];
    if (checksumEntry == null) {
      throw const MissingBackupEntryException('metadata/checksum');
    }
    final storedChecksum = utf8.decode(checksumEntry);

    // Reconstruct the exact byte sequence that was checksummed by BackupWriter:
    // All local file headers + file data, in central directory order,
    // EXCEPT the metadata/checksum entry itself.

    // First, parse the central directory to get entries in order
    final centralDirEntries = _parseCentralDirectory(archiveBytes);

    // Reconstruct the data that was checksummed
    final reconstructedData = <int>[];
    for (final entry in centralDirEntries) {
      if (entry.name == 'metadata/checksum') {
        continue; // Skip the checksum entry itself
      }

      // Reconstruct local file header + data for this entry
      final data = entries[entry.name];
      if (data == null) {
        throw CorruptedBackupException('entry data not found: ${entry.name}');
      }

      final crc32 = _computeCRC32(data);
      final nameBytes = utf8.encode(entry.name);
      final compressedSize = data.length;
      final uncompressedSize = data.length;

      // Local file header
      _writeUint32ToList(reconstructedData, 0x04034b50);
      _writeUint16ToList(reconstructedData, 20); // version needed to extract
      _writeUint16ToList(reconstructedData, 0); // general purpose bit flag
      _writeUint16ToList(reconstructedData, 0); // compression method (stored)
      _writeUint16ToList(reconstructedData, 0); // last mod file time
      _writeUint16ToList(reconstructedData, 0); // last mod file date
      _writeUint32ToList(reconstructedData, crc32);
      _writeUint32ToList(reconstructedData, compressedSize);
      _writeUint32ToList(reconstructedData, uncompressedSize);
      _writeUint16ToList(reconstructedData, nameBytes.length);
      _writeUint16ToList(reconstructedData, 0); // extra field length
      reconstructedData.addAll(nameBytes);

      // File data
      reconstructedData.addAll(data);
    }

    // Compute checksum of reconstructed data
    final computedChecksum = sha256.convert(reconstructedData).toString();

    if (computedChecksum != storedChecksum) {
      throw const ChecksumMismatchException();
    }
  }

  /// Parses the central directory and returns entries in order.
  static List<_CentralDirEntryInfo> _parseCentralDirectory(List<int> archiveBytes) {
    // Find EOCD
    int eocdOffset = -1;
    for (int i = archiveBytes.length - 22; i >= 0; i--) {
      if (archiveBytes[i] == 0x50 &&
          archiveBytes[i + 1] == 0x4b &&
          archiveBytes[i + 2] == 0x05 &&
          archiveBytes[i + 3] == 0x06) {
        eocdOffset = i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw const CorruptedBackupException('не найдена EOCD');
    }

    final totalRecords = _readUint16(archiveBytes, eocdOffset + 10);
    final centralDirOffset = _readUint32(archiveBytes, eocdOffset + 16);

    final entries = <_CentralDirEntryInfo>[];
    int offset = centralDirOffset;

    for (int i = 0; i < totalRecords; i++) {
      if (offset + 46 > archiveBytes.length) {
        throw const CorruptedArchiveException('неполная запись центральной директории');
      }

      // Verify signature
      if (archiveBytes[offset] != 0x50 ||
          archiveBytes[offset + 1] != 0x4b ||
          archiveBytes[offset + 2] != 0x01 ||
          archiveBytes[offset + 3] != 0x02) {
        throw const CorruptedArchiveException('неверная сигнатура записи');
      }

      final compressedSize = _readUint32(archiveBytes, offset + 20);
      final fileNameLength = _readUint16(archiveBytes, offset + 28);
      final extraFieldLength = _readUint16(archiveBytes, offset + 30);
      final commentLength = _readUint16(archiveBytes, offset + 32);
      final localHeaderOffset = _readUint32(archiveBytes, offset + 42);

      final nameStart = offset + 46;
      if (nameStart + fileNameLength > archiveBytes.length) {
        throw const CorruptedArchiveException('имя файла выходит за границы архива');
      }

      final name = utf8.decode(archiveBytes.sublist(nameStart, nameStart + fileNameLength));

      if (!name.endsWith('/')) {
        entries.add(_CentralDirEntryInfo(
          name: name,
          localHeaderOffset: localHeaderOffset,
          compressedSize: compressedSize,
        ));
      }

      offset = nameStart + fileNameLength + extraFieldLength + commentLength;
    }

    return entries;
  }

  static int _computeCRC32(List<int> data) {
    const int polynomial = 0xEDB88320;
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ ((crc & 1) * polynomial);
      }
    }
    return ~crc & 0xFFFFFFFF;
  }

  static void _writeUint16ToList(List<int> list, int v) {
    list.add(v & 0xFF);
    list.add((v >> 8) & 0xFF);
  }

  static void _writeUint32ToList(List<int> list, int v) {
    list.add(v & 0xFF);
    list.add((v >> 8) & 0xFF);
    list.add((v >> 16) & 0xFF);
    list.add((v >> 24) & 0xFF);
  }

  static int _readUint16(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32(List<int> bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

class _CentralDirEntryInfo {
  final String name;
  final int localHeaderOffset;
  final int compressedSize;

  const _CentralDirEntryInfo({
    required this.name,
    required this.localHeaderOffset,
    required this.compressedSize,
  });
}