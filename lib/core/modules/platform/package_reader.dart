import 'dart:convert';

import '../external/manifest_parser.dart';
import '../external/manifest_validator.dart';
import '../external/module_package.dart';
import '../module_manifest.dart';
import 'package_content.dart';
import 'package_exceptions.dart';
import 'package_security_guard.dart';

/// Reads and validates a .phm package from bytes.
///
/// This is the single entry point for reading external module packages.
/// It performs:
/// 1. Security guard validation (archive structure, sizes, paths)
/// 2. Extracts and parses manifest.json using existing ManifestParser
/// 3. Validates manifest using existing ManifestValidator
/// 4. Extracts assets and optional data/storage.json
/// 5. Returns a [PackageContent] ready for the Importer stage.
///
/// Does NOT:
/// - Register or install modules
/// - Modify ModuleRegistry or ModuleManager
/// - Write to ModuleStorage
/// - Run lifecycle hooks
class ModulePackageReader {
  final ManifestParser _parser;
  final ManifestValidator _validator;

  ModulePackageReader({
    ManifestParser? parser,
    ManifestValidator? validator,
  })  : _parser = parser ?? ManifestParser(),
        _validator = validator ?? ManifestValidator();

  /// Reads a package from raw ZIP bytes.
  ///
  /// [existingModuleIds] is required for manifest validation (duplicate id check).
  ///
  /// Returns [PackageContent] on success, throws [PackageException] on failure.
  PackageContent readBytes(
    List<int> archiveBytes, {
    required Set<String> existingModuleIds,
  }) {
    // 1. Security validation
    PackageSecurityGuard.validateArchive(archiveBytes);

    // 2. Extract entries
    final entries = _extractEntries(archiveBytes);

    // 3. Find and parse manifest.json
    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null) {
      throw const InvalidManifestException('manifest.json не найден в архиве');
    }
    final manifestJson = utf8.decode(manifestEntry);
    final ModuleManifest manifest;
    try {
      manifest = _parser.parse(manifestJson);
    } on ManifestParseException catch (e) {
      throw InvalidManifestException('невалидный manifest.json: ${e.message}');
    }

// 4. Validate manifest
    final violations = _validator.validate(manifest, existingModuleIds: existingModuleIds);
    if (violations.isNotEmpty) {
      throw InvalidManifestException('manifest не прошел валидацию', violations: violations);
    }

    // 5. Extract assets
    final assets = <PackageAsset>[];
    for (final entry in entries.entries) {
      if (entry.key.startsWith('assets/') && !entry.key.endsWith('/')) {
        assets.add(PackageAsset(path: entry.key, bytes: entry.value));
      }
    }

    // 6. Extract README if present
    String? readme;
    final readmeEntry = entries['README.md'];
    if (readmeEntry != null) {
      readme = utf8.decode(readmeEntry);
    }

    // 7. Extract data/storage.json if present
    PackageData? data;
    final storageEntry = entries['data/storage.json'];
    if (storageEntry != null) {
      final storageJson = utf8.decode(storageEntry);
      try {
        data = PackageData.fromJson(storageJson);
      } on FormatException catch (e) {
        throw InvalidStorageJsonException('невалидный data/storage.json: ${e.message}');
      }
    }

    // 7. Build result
    final pkg = ModulePackage(
      manifest: manifest,
      assetPaths: assets.map((a) => a.path).toList(),
      dataPaths: data != null ? ['data/storage.json'] : const [],
      readme: readme,
    );

    return PackageContent.fromPackage(
      pkg,
      assets: assets,
      data: data,
      readme: readme,
    );
  }

  /// Reads only the manifest from the package.
  ///
  /// Нужна вызывающему, который должен ПЕРВОЙ узнать, о каком модуле
  /// пакет, до того как решит, что с ним делать (ModuleImporter.
  /// updateFromPackageBytes: «модуль с таким id установлен?»). Для
  /// обновляемого модуля полная проверка [readBytes] не годится:
  /// ManifestValidator счёл бы его id занятым — им же.
  ///
  /// Поэтому здесь НЕТ проверки «id уже занят», но ЕСТЬ всё, что
  /// касается недоверенного архива: security-guard и разбор
  /// manifest.json. Отсутствующая проверка занятости защиту не обходит
  /// — её делает вызывающий, у которого есть ModuleRegistry.
  ///
  /// Бросает [CorruptedArchiveException], [ArchiveTooLargeException],
  /// [TooManyFilesException], [ExtractedSizeExceededException] или
  /// [InvalidManifestException].
  ModuleManifest readManifest(List<int> archiveBytes) {
    // Порядок как в readBytes: недоверенные байты не разбираются до
    // того, как пережили проверку архива.
    PackageSecurityGuard.validateArchive(archiveBytes);
    final entries = _extractEntries(archiveBytes);

    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null) {
      throw const InvalidManifestException('manifest.json не найден в архиве');
    }

    try {
      return _parser.parse(utf8.decode(manifestEntry));
    } on ManifestParseException catch (e) {
      throw InvalidManifestException('невалидный manifest.json: ${e.message}');
    }
  }

  /// Extracts all files from ZIP into a map of path -> bytes.
  Map<String, List<int>> _extractEntries(List<int> archiveBytes) {
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
      throw const CorruptedArchiveException('не найдена EOCD');
    }

    // EOCD format (ZIP spec):
    // Offset 0-3: Signature (0x06054b50)
    // Offset 4-5: Number of this disk (2 bytes)
    // Offset 6-7: Disk where central directory starts (2 bytes)
    // Offset 8-9: Number of central directory records on this disk (2 bytes)
    // Offset 10-11: Total number of central directory records (2 bytes)
    // Offset 12-15: Size of central directory (4 bytes)
    // Offset 16-19: Offset of start of central directory (4 bytes)
    // Offset 20-21: Comment length (2 bytes)

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

      // Central directory entry (ZIP spec):
      // Offset 0-3: Signature (0x02014b50)
      // Offset 4-5: Version made by
      // Offset 6-7: Version needed to extract
      // Offset 8-9: General purpose bit flag
      // Offset 10-11: Compression method
      // Offset 12-13: Last mod file time
      // Offset 14-15: Last mod file date
      // Offset 16-19: CRC-32
      // Offset 20-23: Compressed size
      // Offset 24-27: Uncompressed size
      // Offset 28-29: File name length
      // Offset 30-31: Extra field length
      // Offset 32-33: File comment length
      // Offset 34-35: Disk number start
      // Offset 36-37: Internal file attributes
      // Offset 38-41: External file attributes
      // Offset 42-45: Relative offset of local header
      // Offset 46+: File name...

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
        // Read from local file header
        final localOffset = localHeaderOffset;
        if (localOffset + 30 > archiveBytes.length) {
          throw const CorruptedArchiveException('неполный локальный заголовок');
        }

        // Verify local header signature (0x04034b50)
        if (archiveBytes[localOffset] != 0x50 ||
            archiveBytes[localOffset + 1] != 0x4b ||
            archiveBytes[localOffset + 2] != 0x03 ||
            archiveBytes[localOffset + 3] != 0x04) {
          throw CorruptedArchiveException('неверная сигнатура локального заголовка для $name');
        }

        // Local file header (ZIP spec):
        // Offset 0-3: Signature (0x04034b50)
        // Offset 4-5: Version needed to extract
        // Offset 6-7: General purpose bit flag
        // Offset 8-9: Compression method
        // Offset 10-11: Last mod file time
        // Offset 12-13: Last mod file date
        // Offset 14-17: CRC-32
        // Offset 18-21: Compressed size
        // Offset 22-25: Uncompressed size
        // Offset 26-27: File name length
        // Offset 28-29: Extra field length
        // Offset 30+: File name...

        final localNameLength = _readUint16(archiveBytes, localOffset + 26);
        final localExtraLength = _readUint16(archiveBytes, localOffset + 28);
        final dataStart = localOffset + 30 + localNameLength + localExtraLength;
        final dataEnd = dataStart + compressedSize;

        if (dataEnd > archiveBytes.length) {
          throw CorruptedArchiveException(
            'данные файла $name выходят за границы архива',
          );
        }

        final compressedData = archiveBytes.sublist(dataStart, dataEnd);

        // Decompress if needed (compression method at offset 8 in local header)
        final compressionMethod = _readUint16(archiveBytes, localOffset + 8);
        final data = compressionMethod == 0
            ? compressedData
            : _decompressDeflate(compressedData);

        if (data.length != uncompressedSize && uncompressedSize != 0) {
          throw CorruptedArchiveException(
            'размер распакованных данных не совпадает для $name (ожидалось $uncompressedSize, получено ${data.length})',
          );
        }

        result[name] = data;
      }

      offset = nameStart + fileNameLength + extraFieldLength + commentLength;
    }

    return result;
  }

  /// Simple DEFLATE decompression using Dart's built-in zlib.
  /// For production, this should use a proper zip library.
  List<int> _decompressDeflate(List<int> compressedData) {
    // Use ZLibDecoder from dart:io - but we can't import dart:io in pure Dart
    // For now, assume stored (method 0) only. DEFLATE would require archive package.
    // This is a minimal implementation - in production, add `archive` package.
    throw UnsupportedError('DEFLATE compression not supported in minimal reader; use stored (method 0) only');
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