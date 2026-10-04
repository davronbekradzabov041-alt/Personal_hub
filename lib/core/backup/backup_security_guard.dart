/// Security guard for backup archives.
///
/// Validates backup archive structure, paths, and size limits before extraction.
library backup_security_guard;

import 'dart:convert';
import 'backup_exceptions.dart';

/// Тип проверяемого архива.
///
/// Определяет, какая структура путей допустима: .pbk (global) или
/// .pmb (module backup). Все остальные проверки — лимиты, пути,
/// подсчёт файлов — общие для обоих форматов.
enum BackupArchiveKind {
  /// Глобальный backup приложения (.pbk).
  global,

  /// Backup одного модуля (.pmb).
  module,
}

/// ZIP entry info from central directory.
class _ZipEntry {
  final String name;
  final int size; // uncompressed
  final int compressedSize;

  const _ZipEntry({
    required this.name,
    required this.size,
    required this.compressedSize,
  });
}

/// Security guard for backup archives.
///
/// Validates archive structure, paths, and size limits before any extraction.
/// This is the first line of defense against malicious or malformed backups.
class BackupSecurityGuard {
  BackupSecurityGuard._();

  // =========================================================================
  // Limits (Stage 6B constants)
  // =========================================================================

  static const int maxArchiveSizeBytes = 100 * 1024 * 1024; // 100 MB
  static const int maxExtractedSizeBytes = 500 * 1024 * 1024; // 500 MB
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB
  static const int maxFileCount = 1000;

  // =========================================================================
  // Allowed structure
  // =========================================================================

  static const Set<String> _allowedTopLevelDirs = {'assets', 'data', 'global', 'modules', 'metadata'};

  static const Set<String> _allowedRootEntries = {
    'manifest.json',
    'global/',
    'modules/',
    'metadata/',
  };
  static const Set<String> _allowedGlobalEntries = {
    'global/settings.json',
    'global/metadata.json',
  };

  // Структура .pmb (Personal Hub Module Backup). Отличается от .pbk
  // только корнем и набором файлов модуля: state.json / data.json /
  // assets/ лежат прямо в корне, без обёртки modules/<moduleId>/.
  static const Set<String> _allowedModuleBackupRootEntries = {
    'manifest.json',
    'state.json',
    'data.json',
    'assets/',
    'metadata/',
  };

  /// Расширения файлов, разрешённые в assets/ внутри .pmb.
  ///
  /// Публичная константа, а не приватная: writer обязан использовать
  /// ровно этот список, иначе он создаст .pmb, который его же reader
  /// затем отвергнет (backup проходит, restore падает — худший вид
  /// расхождения).
  static const Set<String> moduleBackupAssetsExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.svg', '.json', '.txt', '.md',
  };

  /// Validates a ZIP archive represented as bytes.
  ///
  /// Performs all security checks and throws a [BackupException] on
  /// any violation. Returns normally if the archive passes all checks.
  ///
  /// The [archiveBytes] must be the complete ZIP file content.
  ///
  /// [kind] определяет допустимую структуру путей: .pbk (global) или
  /// .pmb (module backup). По умолчанию — global, поэтому существующие
  /// вызовы .pbk не меняют поведения.
  static void validateArchive(
    List<int> archiveBytes, {
    BackupArchiveKind kind = BackupArchiveKind.global,
  }) {
    // Size check
    if (archiveBytes.length > maxArchiveSizeBytes) {
      throw const BackupFormatException('размер архива превышает максимум');
    }

    // Parse ZIP structure
    final entries = _parseZipEntries(archiveBytes);

    // SEC-01: guard и reader обязаны видеть один и тот же manifest.json.
    // Reader собирает записи в map (последняя побеждает), а этот guard
    // читал манифест линейным сканом и брал ПЕРВУЮ запись. При двух
    // manifest.json проверялся один файл, а восстановление шло по другому —
    // и checksum это не спасал, он пересобирает данные через тот же map.
    // Проверка выполняется до разбора содержимого: дубликат отклоняется
    // независимо от порядка и содержимого записей, поэтому jsonDecode
    // никогда не встречает битый манифест.
    var manifestEntryCount = 0;
    for (final entry in entries) {
      if (entry.name == 'manifest.json') manifestEntryCount++;
    }
    if (manifestEntryCount > 1) {
      throw const BackupFormatException('дублирующийся manifest.json в архиве');
    }

    // File count check
    if (entries.length > maxFileCount) {
      throw const BackupFormatException('превышено максимальное количество файлов');
    }

    // Validate each entry
    int totalExtractedSize = 0;
    bool hasManifest = false;
    final moduleIds = <String>{};

    for (final entry in entries) {
      final path = entry.name;

      // Skip directory entries
      if (path.endsWith('/')) continue;

      // Size checks
      if (entry.size > maxFileSizeBytes) {
        throw const BackupSecurityException('файл превышает максимальный размер');
      }
      totalExtractedSize += entry.size;
      if (totalExtractedSize > maxExtractedSizeBytes) {
        throw const BackupSecurityException('превышен максимальный суммарный размер распакованных данных');
      }

      // Check for manifest.json and parse it
      if (path == 'manifest.json') {
        final manifestBytes = _extractFileBytes(archiveBytes, path);
        final manifestJson = utf8.decode(manifestBytes);
        final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
        final includedModules = manifest['includedModules'];
        if (includedModules is List) {
          for (final moduleId in includedModules) {
            if (moduleId is String) {
              moduleIds.add(moduleId);
            }
          }
        }
        hasManifest = true;
      }

      // Path validation
      _validatePath(path);

      // Structure validation
      if (kind == BackupArchiveKind.module) {
        _validateModuleBackupStructure(path);
      } else {
        _validateStructure(path, moduleIds);
      }
    }

    // Required files
    if (!hasManifest) {
      throw const BackupFormatException('manifest.json отсутствует в backup');
    }

    // Validate module IDs are unique
    if (moduleIds.length != moduleIds.toSet().length) {
      throw const BackupFormatException('дублирующиеся moduleId в backup');
    }
  }

  /// Структурные правила для .pmb — отдельный набор путей, но та же
  /// логика «сначала форма, потом содержимое», что и для .pbk.
  static void _validateModuleBackupStructure(String path) {
    final segments = path.split('/');

    // Корень: manifest.json / state.json / data.json
    if (segments.length == 1) {
      if (!_allowedModuleBackupRootEntries.contains(path)) {
        throw BackupSecurityException('неизвестный файл в корне module backup: $path');
      }
      return;
    }

    final topDir = segments.first;

    if (topDir == 'metadata') {
      _validateMetadataEntry(path);
      return;
    }

    if (topDir == 'assets') {
      // assets/ — только файлы с разрешённым расширением, без поддиректорий
      if (segments.length != 2) {
        throw BackupSecurityException('поддиректории в assets/ не разрешены: $path');
      }
      final ext = _getExtension(path).toLowerCase();
      if (!moduleBackupAssetsExtensions.contains(ext)) {
        throw BackupSecurityException('расширение "$ext" не разрешено для assets/');
      }
      return;
    }

    throw BackupSecurityException('неизвестная директория верхнего уровня: $topDir');
  }

  /// Проверяет, что имя файла можно положить в assets/ .pmb.
  ///
  /// Writer использует это ДО создания архива, guard — при чтении.
  /// Один список, одно правило: backup всегда читается тем же кодом,
  /// который его создал.
  static bool isAllowedModuleBackupAsset(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return moduleBackupAssetsExtensions.contains(fileName.substring(dot).toLowerCase());
  }

  /// Расширения файлов, разрешённые в assets/ внутри .pbk.
  ///
  /// Публичная константа: writer обязан фильтровать по этому же
  /// списку, иначе он создаст .pbk, который его же reader отвергнет —
  /// backup проходит создание, но не проходит даже чтение.
  static const Set<String> globalAssetsExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.svg', '.json', '.txt', '.md',
  };

  /// Проверяет, что имя файла можно положить в assets/ глобального .pbk.
  static bool isAllowedGlobalAsset(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return globalAssetsExtensions.contains(fileName.substring(dot).toLowerCase());
  }

  /// Извлекает file bytes из ZIP-архива по локальному заголовку.
  static List<int> _extractFileBytes(List<int> archiveBytes, String fileName) {
    // If the archive is too small to contain a valid ZIP entry, return empty list immediately
    if (archiveBytes.length < 30) {
      return <int>[];
    }
    
    List<int> result = <int>[];
    for (int i = 0; i < archiveBytes.length - 30; i++) {
      if (archiveBytes[i] == 0x50 && archiveBytes[i + 1] == 0x4b && 
          archiveBytes[i + 2] == 0x03 && archiveBytes[i + 3] == 0x04) {
        // Found local file header signature
        final fileNameLength = _readUint16(archiveBytes, i + 26);
        final nameStart = i + 30;
        
        if (nameStart + fileNameLength > archiveBytes.length) continue;
        
        final name = utf8.decode(archiveBytes.sublist(nameStart, nameStart + fileNameLength));
        
        if (name == fileName) {
          // Found the file, extract its content
          final compressedSize = _readUint32(archiveBytes, i + 18);
          final extraFieldLength = _readUint16(archiveBytes, i + 28);
          final dataStart = i + 30 + fileNameLength + extraFieldLength;
          final dataEnd = dataStart + compressedSize;

          if (dataEnd <= archiveBytes.length) {
            result = archiveBytes.sublist(dataStart, dataEnd);
            return result;
          }
        }
      }
    }
    
    // If we get here, the file was not found or couldn't be extracted
    return <int>[];
  }

  /// Parses ZIP entries from bytes without full extraction.
  static List<_ZipEntry> _parseZipEntries(List<int> bytes) {
    // Find EOCD signature (0x06054b50 little-endian)
    int eocdOffset = -1;
    for (int i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
        eocdOffset = i;
        break;
      }
    }

    if (eocdOffset == -1) {
      throw const BackupFormatException('не найдена сигнатура конца центральной директории (EOCD)');
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
      throw const BackupFormatException('центральная директория выходит за границы архива');
    }

    // Parse central directory entries
    final entries = <_ZipEntry>[];
    int offset = centralDirOffset;

    for (int i = 0; i < totalRecords; i++) {
      if (offset + 46 > bytes.length) {
        throw const BackupFormatException('неполная запись центральной директории');
      }

      // Check signature (0x02014b50)
      if (bytes[offset] != 0x50 || bytes[offset + 1] != 0x4b || bytes[offset + 2] != 0x01 || bytes[offset + 3] != 0x02) {
        throw const BackupFormatException('неверная сигнатура записи центральной директории');
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
        throw const BackupFormatException('имя файла выходит за границы архива');
      }

      final name = utf8.decode(bytes.sublist(nameStart, nameStart + fileNameLength));

      entries.add(_ZipEntry(
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

  static void _validatePath(String path) {
    // Empty path
    if (path.isEmpty) {
      throw const BackupSecurityException('пустой путь в backup');
    }

    // No leading slash or backslash
    if (path.startsWith('/') || path.startsWith('\\')) {
      throw const BackupSecurityException('абсолютные пути не разрешены');
    }

    // No path traversal
    if (path.contains('..')) {
      throw const BackupSecurityException('path traversal (..) не разрешен');
    }

    // No backslashes (Windows paths)
    if (path.contains('\\')) {
      throw const BackupSecurityException('обратные слэши не разрешены');
    }

    // No control characters
    if (path.runes.any((r) => r < 0x20 || r == 0x7F)) {
      throw const BackupSecurityException('управляющие символы не разрешены');
    }

    // No hidden files (starting with .)
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.startsWith('.') && segment != '..') {
        throw const BackupSecurityException('скрытые файлы не разрешены');
      }
    }

    // No absolute Windows paths like C:\...
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      throw const BackupSecurityException('абсолютные Windows-пути не разрешены');
    }
  }

  static void _validateStructure(String path, Set<String> moduleIds) {
    final segments = path.split('/');

    // Root level entries
    if (segments.length == 1) {
      if (!_allowedRootEntries.contains(path)) {
        throw BackupSecurityException('неизвестный файл в корне backup: $path');
      }
      return;
    }

    // Check top-level directory
    final topDir = segments.first;
    if (!_allowedTopLevelDirs.contains(topDir)) {
      throw BackupSecurityException('неизвестная директория верхнего уровня: $topDir');
    }

    if (topDir == 'global') {
      _validateGlobalEntry(path);
    } else if (topDir == 'modules') {
      _validateModuleEntry(path, moduleIds);
    } else if (topDir == 'metadata') {
      _validateMetadataEntry(path);
    }
  }

  static void _validateGlobalEntry(String path) {
    final segments = path.split('/');
    if (segments.length < 2) return;

    if (segments.length == 2) {
      if (!_allowedGlobalEntries.contains(path)) {
        throw BackupSecurityException('неизвестный файл в global/: $path');
      }
      return;
    }

    // global/ subdirectories not allowed
    throw const BackupSecurityException('поддиректории в global/ не разрешены');
  }

  static void _validateModuleEntry(String path, Set<String> moduleIds) {
    final segments = path.split('/');
    // modules/<moduleId>/...
    if (segments.length < 2) {
      throw BackupSecurityException('некорректный путь модуля: $path');
    }

    final moduleId = segments[1];
    if (!moduleIds.contains(moduleId)) {
      throw BackupSecurityException('moduleId в backup не объявлен в манифесте: $moduleId');
    }

    if (segments.length == 2) {
      // modules/<moduleId>/ directory entry
      return;
    }

    if (segments.length == 3) {
      final fileName = segments[2];
      final allowed = {'manifest.json', 'state.json', 'data.json'};
      if (!allowed.contains(fileName) && !fileName.startsWith('assets/')) {
        throw BackupSecurityException('неизвестный файл в modules/$moduleId/: $fileName');
      }
      return;
    }

    // assets/ files
    if (segments[2] == 'assets' && segments.length >= 4) {
      final ext = _getExtension(path).toLowerCase();
      if (!globalAssetsExtensions.contains(ext)) {
        throw BackupSecurityException('расширение "$ext" не разрешено для assets/: $ext');
      }
      return;
    }

    throw BackupSecurityException('неизвестная структура в модуле: $path');
  }

  static void _validateMetadataEntry(String path) {
    final segments = path.split('/');
    if (segments.length != 2) {
      throw BackupSecurityException('некорректный путь в metadata/: $path');
    }

    final fileName = segments[1];
    final allowed = {'backupFormatVersion', 'appVersion', 'createdAt', 'checksum'};
    if (!allowed.contains(fileName)) {
      throw BackupSecurityException('неизвестный файл в metadata/: $fileName');
    }
  }

  static String _getExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot) : '';
  }
}