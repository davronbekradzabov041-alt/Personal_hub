import 'dart:convert';
import 'dart:typed_data';

import 'package_content.dart';

/// Writes a .phm package (ZIP archive) from prepared content.
///
/// This class only handles serialization to ZIP format. It does NOT:
/// - Fetch data from ModuleManager or ModuleRegistry
/// - Read from ModuleStorage
/// - Execute export logic
/// - Validate the package (that's the caller's / reader's job)
///
/// The caller prepares [PackageContent] and passes it to [write].
/// This keeps the writer pure and testable.
class ModulePackageWriter {
  /// Writes a package to ZIP bytes.
  ///
  /// [content] must contain the manifest, assets, optional data, and optional readme.
  /// All paths in content are used as-is within the archive.
  ///
  /// Returns the complete ZIP archive as bytes.
  ///
  /// Uses STORED (no compression) method for simplicity and compatibility.
  static List<int> write(PackageContent content) {
    final writer = _ZipWriter();
    writer.writePackage(content);
    return writer.build();
  }
}

/// Internal ZIP writer using STORED compression (method 0).
class _ZipWriter {
  final List<int> _data = [];
  final List<_CentralDirEntry> _centralDir = [];
  int _offset = 0;

  void writePackage(PackageContent content) {
    // manifest.json (required)
    final manifestJson = content.manifest.toJson();
    // Ensure external manifest fields are always present (required by ManifestParser)
    manifestJson['permissions'] = manifestJson['permissions'] ?? [];
    manifestJson['dependencies'] = manifestJson['dependencies'] ?? [];
    manifestJson['description'] = manifestJson['description'] ?? '';
    manifestJson['icon'] = manifestJson['icon'] ?? '';
    _addFile(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifestJson)),
    );

    // README.md (optional)
    if (content.readme != null && content.readme!.isNotEmpty) {
      _addFile('README.md', utf8.encode(content.readme!));
    }

    // assets/
    for (final asset in content.assets) {
      _addFile(asset.path, asset.bytes);
    }

    // data/storage.json (optional)
    if (content.data != null) {
      final storageJson = const JsonEncoder.withIndent('  ').convert(content.data!.storage);
      _addFile('data/storage.json', utf8.encode(storageJson));
    }

    // Write central directory
    _writeCentralDirectory();
    // Write EOCD
    _writeEOCD();
  }

  void _addFile(String name, List<int> bytes) {
    final localHeaderOffset = _offset;
    final crc32 = _computeCRC32(bytes);
    final compressedSize = bytes.length;
    final uncompressedSize = bytes.length;

    // Имя файла пишется в заголовке ПОБАЙТОВОЙ длины: ZIP хранит
    // здесь число байт, а String.length в Dart — число UTF-16 code
    // units. Для не-ASCII имён (кириллица в именах пользовательских
    // файлов модуля) расхождение сдвигает весь архив после такой
    // записи, и .phm перестаёт читаться. Поэтому байты кодируются
    // явно, а длина берётся из них же — как в BackupWriter.
    final nameBytes = utf8.encode(name);

    // Local file header (30 bytes + name + extra)
    // Signature: 0x04034b50
    _writeUint32(0x04034b50);
    _writeUint16(20); // version needed to extract
    _writeUint16(0); // general purpose bit flag
    _writeUint16(0); // compression method (0 = stored)
    _writeUint16(0); // last mod time
    _writeUint16(0); // last mod date
    _writeUint32(crc32);
    _writeUint32(compressedSize);
    _writeUint32(uncompressedSize);
    _writeUint16(nameBytes.length);
    _writeUint16(0); // extra field length
    _data.addAll(nameBytes);
    _data.addAll(bytes);

    // Central directory entry
    _centralDir.add(_CentralDirEntry(
      name: name,
      nameByteLength: nameBytes.length,
      crc32: crc32,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      localHeaderOffset: localHeaderOffset,
    ));

    _offset = _data.length;
  }

  void _writeCentralDirectory() {
    final centralDirStart = _offset;

    for (final entry in _centralDir) {
      // Central directory file header (46 bytes + name + extra + comment)
      // Signature: 0x02014b50
      _writeUint32(0x02014b50);
      _writeUint16(45); // version made by
      _writeUint16(20); // version needed to extract
      _writeUint16(0); // general purpose bit flag
      _writeUint16(0); // compression method (0 = stored)
      _writeUint16(0); // last mod time
      _writeUint16(0); // last mod date
      _writeUint32(entry.crc32);
      _writeUint32(entry.compressedSize);
      _writeUint32(entry.uncompressedSize);
      _writeUint16(entry.nameByteLength);
      _writeUint16(0); // extra field length
      _writeUint16(0); // file comment length
      _writeUint16(0); // disk number start
      _writeUint16(0); // internal file attributes
      _writeUint32(0); // external file attributes
      _writeUint32(entry.localHeaderOffset);
      _data.addAll(utf8.encode(entry.name));
    }

    final centralDirEnd = _data.length;
    final centralDirSize = centralDirEnd - centralDirStart;

    // Store for EOCD
    _centralDirStart = centralDirStart;
    _centralDirSize = centralDirSize;
  }

  void _writeEOCD() {
    // End of central directory record (22 bytes + comment)
    // Signature: 0x06054b50
    _writeUint32(0x06054b50);
    _writeUint16(0); // number of this disk
    _writeUint16(0); // disk where central directory starts
    _writeUint16(_centralDir.length); // number of entries on this disk
    _writeUint16(_centralDir.length); // total number of entries
    _writeUint32(_centralDirSize); // size of central directory
    _writeUint32(_centralDirStart); // offset of central directory
    _writeUint16(0); // comment length
  }

  List<int> build() => Uint8List.fromList(_data);

  int _centralDirStart = 0;
  int _centralDirSize = 0;

  void _writeUint16(int v) {
    _data.add(v & 0xFF);
    _data.add((v >> 8) & 0xFF);
  }

  void _writeUint32(int v) {
    _data.add(v & 0xFF);
    _data.add((v >> 8) & 0xFF);
    _data.add((v >> 16) & 0xFF);
    _data.add((v >> 24) & 0xFF);
  }

  int _computeCRC32(List<int> data) {
    // Simple CRC32 implementation (IEEE 802.3 polynomial)
    // For production, consider using a dedicated package.
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
}

class _CentralDirEntry {
  final String name;

  /// Длина [name] В БАЙТАХ, а не в UTF-16 code units.
  ///
  /// Поле filename length в ZIP — это число байт; [String.length]
  /// для не-ASCII имён даёт меньшее число и ломает архив.
  final int nameByteLength;

  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  const _CentralDirEntry({
    required this.name,
    required this.nameByteLength,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}