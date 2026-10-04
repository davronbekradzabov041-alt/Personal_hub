import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/platform/package_reader.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/platform/package_exceptions.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('ModulePackageReader', () {
    late ModulePackageReader reader;

    setUp(() {
      reader = ModulePackageReader();
    });

    group('Valid packages', () {
      test('минимальный валидный .phm', () {
        final content = _createTestContent();
        final bytes = ModulePackageWriter.write(content);
        final readContent = reader.readBytes(bytes, existingModuleIds: const {});
        expect(readContent.manifest.id, 'test-module');
        expect(readContent.assets, isEmpty);
        expect(readContent.data, isNull);
        expect(readContent.readme, isNull);
      });

      test('пакет с README.md', () {
        final content = _createTestContent(readme: '# Test Module\n\nDescription here.');
        final bytes = ModulePackageWriter.write(content);
        final readContent = reader.readBytes(bytes, existingModuleIds: const {});
        expect(readContent.readme, '# Test Module\n\nDescription here.');
      });

      test('пакет с assets/icon.png', () {
        final assetBytes = List.filled(100, 0xFF);
        final content = _createTestContent(assets: {'assets/icon.png': assetBytes});
        final bytes = ModulePackageWriter.write(content);
        final readContent = reader.readBytes(bytes, existingModuleIds: const {});
        expect(readContent.assets.length, 1);
        expect(readContent.assets.first.path, 'assets/icon.png');
        expect(readContent.assets.first.bytes, assetBytes);
      });

      test('пакет с data/storage.json', () {
        final storage = {'note': 'test note', 'settings': {'theme': 'dark'}};
        final content = _createTestContent(storage: storage);
        final bytes = ModulePackageWriter.write(content);
        final readContent = reader.readBytes(bytes, existingModuleIds: const {});
        expect(readContent.data, isNotNull);
        expect(readContent.data!.storage['note'], 'test note');
        expect(readContent.data!.storage['settings']['theme'], 'dark');
      });

      test('комбинация всех компонентов', () {
        final content = _createTestContent(
          readme: '# Full Package',
          assets: {
            'assets/icon.png': List.filled(50, 0x00),
            'assets/data.json': utf8.encode('{"key": "value"}'),
          },
          storage: {'settings': {'theme': 'dark'}},
        );
        final bytes = ModulePackageWriter.write(content);
        final readContent = reader.readBytes(bytes, existingModuleIds: const {});
        expect(readContent.manifest.id, 'test-module');
        expect(readContent.readme, '# Full Package');
        expect(readContent.assets.length, 2);
        expect(readContent.data, isNotNull);
        expect(readContent.data!.storage['settings']['theme'], 'dark');
      });
    });

    group('Security validation errors', () {
      test('archive > 20 MB', () {
        final content = _createTestContent(
          assets: {'assets/large.bin': List.filled(21 * 1024 * 1024, 0xFF)},
        );
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<ArchiveTooLargeException>()),
        );
      });

      test('> 100 файлов', () {
        final assets = <String, List<int>>{};
        for (int i = 0; i < 101; i++) {
          assets['assets/file$i.txt'] = [0x00];
        }
        final content = _createTestContent(assets: assets);
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<TooManyFilesException>()),
        );
      });

      test('файл > 10 MB', () {
        final content = _createTestContent(
          assets: {'assets/large.bin': List.filled(11 * 1024 * 1024, 0xFF)},
        );
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<FileTooLargeException>()),
        );
      });

      test('путь с traversal', () {
        final bytes = _buildCorruptedPhmWithExtraFile('../evil.txt', [0x00]);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidPathException>()),
        );
      });

      test('неизвестное расширение', () {
        final bytes = _buildCorruptedPhmWithExtraFile('assets/evil.exe', [0x00]);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<UnsupportedFileException>()),
        );
      });

      test('запрещённый файл в data/', () {
        final bytes = _buildCorruptedPhmWithExtraFile('data/evil.txt', [0x00]);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidPackageStructureException>()),
        );
      });

      test('неизвестная директория', () {
        final bytes = _buildCorruptedPhmWithExtraFile('unknown/file.txt', [0x00]);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidPackageStructureException>()),
        );
      });

      test('скрытый файл', () {
        final bytes = _buildCorruptedPhmWithExtraFile('.hidden', [0x00]);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<HiddenFileException>()),
        );
      });

      test('повреждённый ZIP', () {
        final bytes = [0x00, 0x01, 0x02, 0x03];
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<CorruptedArchiveException>()),
        );
      });
    });

    group('Manifest validation', () {
      test('отсутствует manifest.json', () {
        final bytes = _buildPhmWithoutManifest();
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidPackageStructureException>()),
        );
      });

      test('невалидный manifest.json (JSON)', () {
        final bytes = _buildPhmWithManifest('{ not valid json }');
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidManifestException>()),
        );
      });

      test('невалидный manifest.json (отсутствует поле)', () {
        final manifest = _minimalManifest().replaceFirst('"version": "1.0.0"', '');
        final bytes = _buildPhmWithManifest(manifest);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidManifestException>()),
        );
      });

      test('дублирующийся moduleId', () {
        final content = _createTestContent();
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: {'test-module'}),
          throwsA(isA<InvalidManifestException>()),
        );
      });

      test('неподдерживаемая apiVersion', () {
        final manifest = _minimalManifest().replaceFirst('"apiVersion": 1', '"apiVersion": 99');
        final bytes = _buildPhmWithManifest(manifest);
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidManifestException>()),
        );
      });
    });

    group('Storage JSON validation', () {
      test('невалидный storage.json', () {
        final bytes = _buildPhmWithRawStorage(
          _minimalManifest(),
          '{ not valid json }',
        );
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidStorageJsonException>()),
        );
      });

      test('storage.json не объект', () {
        final bytes = _buildPhmWithRawStorage(
          _minimalManifest(),
          '[1, 2, 3]',
        );
        expect(
          () => reader.readBytes(bytes, existingModuleIds: const {}),
          throwsA(isA<InvalidStorageJsonException>()),
        );
      });
    });
  });

  group('ModulePackageWriter', () {
    test('Write → Read round-trip (минимальный)', () {
      final content = _createTestContent();
      final bytes = ModulePackageWriter.write(content);
      final reader = ModulePackageReader();
      final readContent = reader.readBytes(bytes, existingModuleIds: const {});

      expect(readContent.manifest.id, content.manifest.id);
      expect(readContent.manifest.name, content.manifest.name);
      expect(readContent.manifest.version, content.manifest.version);
      expect(readContent.readme, content.readme);
    });

    test('Write → Read round-trip (с assets и storage)', () {
      final content = _createTestContent(
        readme: '# Round Trip Test',
        assets: {
          'assets/icon.png': List.filled(100, 0xAA),
          'assets/data.json': utf8.encode('{"test": true}'),
        },
        storage: {'note': 'round trip', 'config': {'enabled': true}},
      );
      final bytes = ModulePackageWriter.write(content);
      final reader = ModulePackageReader();
      final readContent = reader.readBytes(bytes, existingModuleIds: const {});

      expect(readContent.readme, '# Round Trip Test');
      expect(readContent.assets.length, 2);
      expect(readContent.assets.first.path, 'assets/icon.png');
      expect(readContent.assets.first.bytes, List.filled(100, 0xAA));
      expect(readContent.data, isNotNull);
      expect(readContent.data!.storage['note'], 'round trip');
      expect(readContent.data!.storage['config']['enabled'], true);
    });

    test('Writer produces valid ZIP structure', () {
      final content = _createTestContent();
      final bytes = ModulePackageWriter.write(content);

      // Verify ZIP signatures
      expect(bytes[0], 0x50); // PK
      expect(bytes[1], 0x4b); // 

      // Find EOCD
      int eocdOffset = -1;
      for (int i = bytes.length - 22; i >= 0; i--) {
        if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
          eocdOffset = i;
          break;
        }
      }
      expect(eocdOffset, isNot(-1));
    });
  });

  // AUD-34: длина имени файла в ZIP-заголовках.
  //
  // Поля filename length обязаны содержать число БАЙТ. String.length в
  // Dart возвращает число UTF-16 code units, поэтому для кириллицы
  // (2 байта на букву в UTF-8) Writer записывал заниженную длину.
  // Central directory читался не с начала имени, и следующая запись
  // архива «съезжала»: .phm переставал читаться целиком, а не только
  // один файл получал битое имя.
  group('AUD-34: длина имени файла в ZIP-заголовках', () {
    /// Кириллическое имя: 20 code units, 40 байт в UTF-8.
    const cyrillicPath = 'assets/изображение.png';
    const emojiPath = 'assets/🚀/файл.txt';

    test('кириллическое имя: длина в локальном заголовке — в байтах', () {
      final bytes = ModulePackageWriter.write(
        _createTestContent(
          assets: {cyrillicPath: List.filled(64, 0x11)},
        ),
      );

      final entry = _findLocalHeader(bytes, utf8.encode(cyrillicPath));
      expect(entry, isNotNull, reason: 'запись с кириллическим именем не найдена');

      final declared = _readUint16(bytes, entry! + 26);
      expect(
        declared,
        utf8.encode(cyrillicPath).length,
        reason: 'в локальном заголовке объявлено $declared байт имени',
      );
      expect(
        declared,
        isNot(cyrillicPath.length),
        reason: 'String.length вернул бы ${cyrillicPath.length} — это и есть баг',
      );
    });

    test('кириллическое имя: длина в central directory — в байтах', () {
      final bytes = ModulePackageWriter.write(
        _createTestContent(
          assets: {cyrillicPath: List.filled(64, 0x11)},
        ),
      );

      final entry = _findCentralDirectoryEntry(bytes, cyrillicPath);
      expect(entry, isNotNull);

      final declared = _readUint16(bytes, entry! + 28);
      expect(
        declared,
        utf8.encode(cyrillicPath).length,
        reason: 'в central directory объявлено $declared байт имени',
      );
    });

    test('эмодзи и кириллица: длина в байтах, а не в code units', () {
      final bytes = ModulePackageWriter.write(
        _createTestContent(
          assets: {emojiPath: List.filled(32, 0x22)},
        ),
      );

      final entry = _findCentralDirectoryEntry(bytes, emojiPath);
      expect(entry, isNotNull);
      expect(_readUint16(bytes, entry! + 28), utf8.encode(emojiPath).length);

      final local = _findLocalHeader(bytes, utf8.encode(emojiPath));
      expect(local, isNotNull);
      expect(_readUint16(bytes, local! + 26), utf8.encode(emojiPath).length);
    });

    test('не-ASCII имя переживает round-trip write → read', () {
      final assetBytes = List.filled(48, 0x33);
      final bytes = ModulePackageWriter.write(
        _createTestContent(
          readme: '# Кириллица в README — содержимое не имя',
          assets: {cyrillicPath: assetBytes},
          storage: {'note': 'проверка'},
        ),
      );

      final readContent =
          ModulePackageReader().readBytes(bytes, existingModuleIds: const {});

      expect(readContent.assets.length, 1);
      expect(readContent.assets.first.path, cyrillicPath);
      expect(readContent.assets.first.bytes, assetBytes);
      expect(readContent.data!.storage['note'], 'проверка');
      expect(readContent.readme, '# Кириллица в README — содержимое не имя');
    });

    test('архив с не-ASCII именем остаётся структурно целым', () {
      // Несколько записей после кириллической: при заниженной длине
      // имени сдвигается всё последующее, включая central directory.
      final bytes = ModulePackageWriter.write(
        _createTestContent(
          assets: {
            cyrillicPath: List.filled(16, 0x11),
            'assets/second.png': List.filled(16, 0x22),
            'assets/third.png': List.filled(16, 0x33),
          },
        ),
      );

      // Central directory обязан начинаться ровно там, где его ждёт
      // EOCD: иначе архив нечитаем.
      final eocd = _findEocd(bytes);
      expect(eocd, isNotNull);
      final centralDirStart = _readUint32(bytes, eocd! + 16);
      // Central directory header signature 0x02014b50, little-endian.
      expect(bytes[centralDirStart], 0x50);
      expect(bytes[centralDirStart + 1], 0x4b);
      expect(bytes[centralDirStart + 2], 0x01);
      expect(bytes[centralDirStart + 3], 0x02);
    });
  });
}

/// Смещение локального заголовка записи с байтовым именем [nameBytes].
int? _findLocalHeader(List<int> bytes, List<int> nameBytes) {
  for (var i = 0; i + 30 + nameBytes.length <= bytes.length; i++) {
    if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b ||
        bytes[i + 2] != 0x03 || bytes[i + 3] != 0x04) {
      continue;
    }
    final declared = _readUint16(bytes, i + 26);
    if (declared != nameBytes.length) continue;
    final matches = _regionMatches(bytes, i + 30, nameBytes);
    if (matches) return i;
  }
  return null;
}

/// Смещение записи central directory по имени [name].
int? _findCentralDirectoryEntry(List<int> bytes, String name) {
  final nameBytes = utf8.encode(name);
  final eocd = _findEocd(bytes);
  if (eocd == null) return null;

  final entriesCount = _readUint16(bytes, eocd + 10);
  var offset = _readUint32(bytes, eocd + 16);

  for (var i = 0; i < entriesCount; i++) {
    if (_readUint32(bytes, offset) != 0x02014b50) return null;
    final declared = _readUint16(bytes, offset + 28);
    final extraLength = _readUint16(bytes, offset + 30);
    final commentLength = _readUint16(bytes, offset + 32);
    if (declared == nameBytes.length &&
        _regionMatches(bytes, offset + 46, nameBytes)) {
      return offset;
    }
    offset += 46 + declared + extraLength + commentLength;
  }
  return null;
}

int? _findEocd(List<int> bytes) {
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
      return i;
    }
  }
  return null;
}

bool _regionMatches(List<int> bytes, int start, List<int> expected) {
  if (start + expected.length > bytes.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[start + i] != expected[i]) return false;
  }
  return true;
}

int _readUint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _readUint32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

// =========================================================================
// Test helpers
// =========================================================================

String _minimalManifest({String? icon}) {
  return '''
{
  "id": "test-module",
  "name": "Test Module",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Test Author",
  "description": "Test module for security guard",
  "permissions": [],
  "dependencies": [],
  "icon": "${icon ?? 'assets/icon.png'}"
}
''';
}

PackageContent _createTestContent({
  String? readme,
  Map<String, List<int>>? assets,
  Map<String, dynamic>? storage,
}) {
  final manifest = ModuleManifest.fromJson(jsonDecode(_minimalManifest()));
  final assetList = assets?.entries.map((e) => PackageAsset(path: e.key, bytes: e.value)).toList() ?? [];
  PackageData? data;
  if (storage != null) {
    data = PackageData(storage);
  }
  return PackageContent(
    manifest: manifest,
    assets: assetList,
    data: data,
    readme: readme,
  );
}

// Helper to build PHM with custom manifest (for invalid manifest tests)
List<int> _buildPhmWithManifest(String manifestJson) {
  final writer = _TestZipWriter();
  writer.addFile('manifest.json', utf8.encode(manifestJson));
  return writer.build();
}

// Helper to build PHM with raw storage.json (not jsonEncoded)
List<int> _buildPhmWithRawStorage(String manifestJson, String rawStorageJson) {
  final writer = _TestZipWriter();
  writer.addFile('manifest.json', utf8.encode(manifestJson));
  writer.addFile('data/storage.json', utf8.encode(rawStorageJson));
  return writer.build();
}

// Helper to build PHM without manifest
List<int> _buildPhmWithoutManifest() {
  final writer = _TestZipWriter();
  writer.addFile('README.md', utf8.encode('# Readme'));
  return writer.build();
}

// Helper to build PHM with extra file (for structure violation tests)
List<int> _buildCorruptedPhmWithExtraFile(String path, List<int> content) {
  final writer = _TestZipWriter();
  writer.addFile('manifest.json', utf8.encode(_minimalManifest()));
  writer.addFile(path, content);
  return writer.build();
}

// Minimal ZIP writer for test corruption cases
class _TestZipWriter {
  final List<int> _data = [];
  final List<_CentralDirEntry> _centralDir = [];
  int _offset = 0;

  void addFile(String name, List<int> bytes) {
    final localHeaderOffset = _offset;
    final crc32 = _computeCRC32(bytes);
    final compressedSize = bytes.length;
    final uncompressedSize = bytes.length;

    _writeUint32(0x04034b50);
    _writeUint16(20);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint32(crc32);
    _writeUint32(compressedSize);
    _writeUint32(uncompressedSize);
    _writeUint16(name.length);
    _writeUint16(0);
    _data.addAll(utf8.encode(name));
    _data.addAll(bytes);

    _centralDir.add(_CentralDirEntry(
      name: name,
      crc32: crc32,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      localHeaderOffset: localHeaderOffset,
    ));

    _offset = _data.length;
  }

  List<int> build() {
    final centralDirStart = _offset;
    for (final entry in _centralDir) {
      _writeUint32(0x02014b50);
      _writeUint16(45);
      _writeUint16(20);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint32(entry.crc32);
      _writeUint32(entry.compressedSize);
      _writeUint32(entry.uncompressedSize);
      _writeUint16(entry.name.length);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint32(0);
      _writeUint32(entry.localHeaderOffset);
      _data.addAll(utf8.encode(entry.name));
    }
    final centralDirEnd = _data.length;
    final centralDirSize = centralDirEnd - centralDirStart;

    // EOCD (ZIP spec):
    // Offset 0-3: Signature (0x06054b50)
    // Offset 4-5: Number of this disk (2 bytes)
    // Offset 6-7: Disk where central directory starts (2 bytes)
    // Offset 8-9: Number of central directory records on this disk (2 bytes)
    // Offset 10-11: Total number of central directory records (2 bytes)
    // Offset 12-15: Size of central directory (4 bytes)
    // Offset 16-19: Offset of start of central directory (4 bytes)
    // Offset 20-21: Comment length (2 bytes)

    _writeUint32(0x06054b50);
    _writeUint16(0); // number of this disk
    _writeUint16(0); // disk where central directory starts
    _writeUint16(_centralDir.length); // number of entries on this disk
    _writeUint16(_centralDir.length); // total number of entries
    _writeUint32(centralDirSize); // size of central directory
    _writeUint32(centralDirStart); // offset of central directory
    _writeUint16(0); // comment length

    return Uint8List.fromList(_data);
  }

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
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  const _CentralDirEntry({
    required this.name,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}