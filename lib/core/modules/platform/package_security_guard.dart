import 'dart:convert';
import 'package_exceptions.dart';

/// Security guard for .phm package archives.
///
/// Performs all structural and size validation on a ZIP archive
/// before any content is extracted or processed. This is the first
/// line of defense against malicious or malformed packages.
///
/// All checks are performed on the archive level (without full
/// extraction where possible) to minimize attack surface.
class PackageSecurityGuard {
  PackageSecurityGuard._();

  // =========================================================================
  // Limits (Stage 1 constants)
  // =========================================================================

  static const int maxArchiveSizeBytes = 20 * 1024 * 1024; // 20 MB
  static const int maxExtractedSizeBytes = 50 * 1024 * 1024; // 50 MB
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxFileCount = 100;

  // =========================================================================
  // Allowed structure
  // =========================================================================

  static const Set<String> _allowedRootFiles = {'manifest.json', 'README.md'};
  static const Set<String> _allowedAssetExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.svg', '.json'
  };
  static const Set<String> _allowedTopLevelDirs = {'assets', 'data'};

  /// Validates a ZIP archive represented as bytes.
  ///
  /// Performs all security checks and throws a [PackageException] on
  /// any violation. Returns normally if the archive passes all checks.
  ///
  /// The [archiveBytes] must be the complete ZIP file content.
  static void validateArchive(List<int> archiveBytes) {
    // Size check
    if (archiveBytes.length > maxArchiveSizeBytes) {
      throw ArchiveTooLargeException(
        sizeBytes: archiveBytes.length,
        maxBytes: maxArchiveSizeBytes,
      );
    }

    // Parse ZIP structure
    final entries = _parseZipEntries(archiveBytes);

    // SEC-01: PackageReader собирает записи в map (последняя побеждает),
    // поэтому два manifest.json в архиве означают, что проверяемый здесь
    // манифест и реально прочитанный могут различаться. Отклоняем любой
    // дубликат — выбор становится однозначным независимо от порядка.
    var manifestEntryCount = 0;
    for (final entry in entries) {
      if (entry.name == 'manifest.json') manifestEntryCount++;
    }
    if (manifestEntryCount > 1) {
      throw const InvalidPackageStructureException(
        'дублирующийся manifest.json в пакете',
      );
    }

    // File count check
    if (entries.length > maxFileCount) {
      throw TooManyFilesException(
        count: entries.length,
        maxCount: maxFileCount,
      );
    }

    // Validate each entry
    int totalExtractedSize = 0;
    bool hasManifest = false;
    bool hasDataDir = false;

    for (final entry in entries) {
      final path = entry.name;

      // Skip directory entries (they end with / in zip)
      if (path.endsWith('/')) continue;

      // Size checks
      if (entry.size > maxFileSizeBytes) {
        throw FileTooLargeException(
          path: path,
          sizeBytes: entry.size,
          maxBytes: maxFileSizeBytes,
        );
      }
      totalExtractedSize += entry.size;
      if (totalExtractedSize > maxExtractedSizeBytes) {
        throw ExtractedSizeExceededException(
          extractedBytes: totalExtractedSize,
          maxBytes: maxExtractedSizeBytes,
        );
      }

      // Path validation
      _validatePath(path);

      // Structure validation
      _validateStructure(path, entry, (p) {
        if (p == 'manifest.json') hasManifest = true;
        if (p.startsWith('data/')) hasDataDir = true;
      });
    }

    // Required files
    if (!hasManifest) {
      throw const InvalidPackageStructureException(
        'manifest.json отсутствует в пакете',
      );
    }

    // If data/ exists, it must contain only storage.json
    if (hasDataDir) {
      // Additional check: ensure no other files under data/
      for (final entry in entries) {
        final path = entry.name;
        if (path.startsWith('data/') && !path.endsWith('/') && path != 'data/storage.json') {
          throw InvalidPackageStructureException(
            'директория data/ может содержать только storage.json, найдено: $path',
          );
        }
      }
    }
  }

  /// Validates a single path for security issues.
  static void _validatePath(String path) {
    // Empty path
    if (path.isEmpty) {
      throw const InvalidPathException(path: '', reason: 'пустой путь');
    }

    // No leading slash or backslash
    if (path.startsWith('/') || path.startsWith('\\')) {
      throw InvalidPathException(
        path: path,
        reason: 'абсолютные пути не разрешены',
      );
    }

    // No path traversal
    if (path.contains('..')) {
      throw InvalidPathException(
        path: path,
        reason: 'path traversal (..) не разрешен',
      );
    }

    // No backslashes (Windows paths)
    if (path.contains('\\')) {
      throw InvalidPathException(
        path: path,
        reason: 'обратные слэши не разрешены',
      );
    }

    // No control characters
    if (path.runes.any((r) => r < 0x20 || r == 0x7F)) {
      throw InvalidPathException(
        path: path,
        reason: 'управляющие символы не разрешены',
      );
    }

    // No hidden files (starting with .)
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.startsWith('.') && segment != '..') {
        throw HiddenFileException(path);
      }
    }

    // No absolute Windows paths like C:\...
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      throw InvalidPathException(
        path: path,
        reason: 'абсолютные Windows-пути не разрешены',
      );
    }
  }

  /// Validates that the path follows the allowed package structure.
  static void _validateStructure(
    String path,
    ZipEntry entry,
    void Function(String) onSpecialFile,
  ) {
    final segments = path.split('/');

    // Root level files
    if (segments.length == 1) {
      if (!_allowedRootFiles.contains(path)) {
        throw InvalidPackageStructureException(
          'файл "$path" в корне пакета не разрешен (разрешены: manifest.json, README.md)',
        );
      }
      onSpecialFile(path);
      return;
    }

    // Subdirectories
    final topDir = segments.first;
    if (!_allowedTopLevelDirs.contains(topDir)) {
      throw InvalidPackageStructureException(
        'неизвестная директория верхнего уровня: "$topDir" (разрешены: assets/, data/)',
      );
    }

    if (topDir == 'assets') {
      // assets/ files - check extension
      final ext = _getExtension(path).toLowerCase();
      if (!_allowedAssetExtensions.contains(ext)) {
        throw UnsupportedFileException(
          path: path,
          reason: 'расширение "$ext" не разрешено для assets/ (разрешены: ${_allowedAssetExtensions.join(', ')})',
        );
      }
      onSpecialFile(path);
    } else if (topDir == 'data') {
      // data/ files - only storage.json allowed
      if (path != 'data/storage.json') {
        throw InvalidPackageStructureException(
          'директория data/ может содержать только storage.json, найдено: $path',
        );
      }
      onSpecialFile(path);
    }
  }

  static String _getExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot) : '';
  }

  // =========================================================================
  // ZIP parsing (minimal, for validation only)
  // =========================================================================

  /// Parses ZIP entries from bytes without full extraction.
  /// Returns list of entries with name, size, and compressed size.
  static List<ZipEntry> _parseZipEntries(List<int> bytes) {
    // Use a simple ZIP parser for central directory
    // We look for the End of Central Directory Record (EOCD)
    // and parse backwards.

    if (bytes.length < 22) {
      throw const CorruptedArchiveException('архив слишком мал для ZIP');
    }

    // Find EOCD signature (0x06054b50 little-endian)
    int eocdOffset = -1;
    for (int i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
        eocdOffset = i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw const CorruptedArchiveException('не найдена сигнатура конца центральной директории (EOCD)');
    }

    // Parse EOCD (ZIP spec):
    // Offset 0-3: Signature (0x06054b50)
    // Offset 4-5: Number of this disk (2 bytes)
    // Offset 6-7: Disk where central directory starts (2 bytes)
    // Offset 8-9: Number of central directory records on this disk (2 bytes)
    // Offset 10-11: Total number of central directory records (2 bytes)
    // Offset 12-15: Size of central directory (4 bytes)
    // Offset 16-19: Offset of start of central directory (4 bytes)
    // Offset 20-21: Comment length (2 bytes)

    final totalRecords = _readUint16(bytes, eocdOffset + 10);
    final centralDirSize = _readUint32(bytes, eocdOffset + 12);
    final centralDirOffset = _readUint32(bytes, eocdOffset + 16);

    if (centralDirOffset + centralDirSize > bytes.length) {
      throw const CorruptedArchiveException('центральная директория выходит за границы архива');
    }

    // Parse central directory entries
    final entries = <ZipEntry>[];
    int offset = centralDirOffset;

    for (int i = 0; i < totalRecords; i++) {
      if (offset + 46 > bytes.length) {
        throw const CorruptedArchiveException('неполная запись центральной директории');
      }

      // Check signature (0x02014b50)
      if (bytes[offset] != 0x50 || bytes[offset + 1] != 0x4b || bytes[offset + 2] != 0x01 || bytes[offset + 3] != 0x02) {
        throw const CorruptedArchiveException('неверная сигнатура записи центральной директории');
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

      final compressedSize = _readUint32(bytes, offset + 20);
      final uncompressedSize = _readUint32(bytes, offset + 24);
      final fileNameLength = _readUint16(bytes, offset + 28);
      final extraFieldLength = _readUint16(bytes, offset + 30);
      final commentLength = _readUint16(bytes, offset + 32);

      final nameStart = offset + 46;
      if (nameStart + fileNameLength > bytes.length) {
        throw const CorruptedArchiveException('имя файла выходит за границы архива');
      }

      final name = utf8.decode(bytes.sublist(nameStart, nameStart + fileNameLength));

      entries.add(ZipEntry(
        name: name,
        size: uncompressedSize,
        compressedSize: compressedSize,
      ));

      offset = nameStart + fileNameLength + extraFieldLength + commentLength;
    }

    return entries;
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

/// ZIP entry info from central directory.
class ZipEntry {
  final String name;
  final int size; // uncompressed
  final int compressedSize;

  const ZipEntry({
    required this.name,
    required this.size,
    required this.compressedSize,
  });
}