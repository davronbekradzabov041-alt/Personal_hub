import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/platform/module_importer.dart';
import 'package:personal_hub/core/modules/platform/module_exporter.dart';
import 'package:personal_hub/core/modules/platform/module_storage_serializer.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/modules/platform/package_reader.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModuleImporter: десериализация storage в .phm', () {
    late ModuleManager _manager;
    late _TestModuleStorage _testStorage;
    late Directory _testSupportDir;

    setUp(() async {
      ModuleRegistry.clear();

      _testStorage = _TestModuleStorage();
      _manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (moduleId) => _TestModuleStorage(),
      );

      _testSupportDir = await Directory.systemTemp.createTemp('phm_test_');
    });

    tearDown(() async {
      ModuleRegistry.clear();
      _testStorage.clear();
      await _testSupportDir.delete(recursive: true);
    });

    test('экспортированное хранилище десериализуется обратно', () async {
      // Устанавливаем модуль и наполняем его хранилище.
      final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
      await ModuleImporter(
        moduleManager: _manager,
        testSupportDir: _testSupportDir,
      ).importFromBytes(bytes1);

      final storage = _manager.apiFor('test-module').storage;
      await storage.setString('note', 'test note');
      await storage.setString('config', jsonEncode({'theme': 'dark'}));

      final exportResult = await ModuleExporter(
        moduleManager: _manager,
        assetsDirectoryResolver: (id) =>
            ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
      ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);

      expect(exportResult.isSuccess, true);

      // Читаем экспортированный пакет и десериализуем его содержимое
      // тем же путём, которым пользуется импортёр.
      final content = ModulePackageReader()
          .readBytes(exportResult.phmBytes!, existingModuleIds: const {});

      expect(content.data, isNotNull,
          reason: 'экспорт с данными обязан включать data/storage.json');
      expect(content.data!.storage.keys,
          unorderedEquals(<String>['note', 'config']));

      final storageJson = jsonEncode({
        'version': ModuleStorageSerializer.currentVersion,
        'moduleId': 'test-module',
        'entries': content.data!.storage,
      });

      await ModuleStorageSerializer.deserialize(
        jsonString: storageJson,
        storage: _testStorage,
        expectedModuleId: 'test-module',
      );

      expect(await _testStorage.keys(), unorderedEquals(<String>['note', 'config']));
      expect(await _testStorage.getString('note'), 'test note');
      expect(await _testStorage.getString('config'), '{"theme":"dark"}');
    });
  });
}

// =========================================================================
// Test helpers
// =========================================================================

class _TestModuleStorage implements ModuleStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();

  void clear() => _data.clear();
  void setAll(Map<String, String> data) => _data.addAll(data);
  
  @override
  String toString() => '_TestModuleStorage($_data)';
}

String _minimalManifest({String id = 'test-module', String version = '1.0.0'}) {
  return '''
{
  "id": "$id",
  "name": "Test Module",
  "version": "$version",
  "apiVersion": 1,
  "author": "Test Author",
  "description": "Test module",
  "permissions": [],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';
}

List<int> _createTestPhm({
  required String manifestJson,
  String? readme,
  Map<String, List<int>>? assets,
  Map<String, dynamic>? storage,
}) {
  final writer = _TestZipWriter();
  writer.addFile('manifest.json', utf8.encode(manifestJson));
  if (readme != null) writer.addFile('README.md', utf8.encode(readme));
  if (assets != null) assets.forEach((path, bytes) => writer.addFile(path, bytes));
  if (storage != null) writer.addFile('data/storage.json', utf8.encode(jsonEncode(storage)));
  return writer.build();
}

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

    _writeUint32(0x06054b50);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(_centralDir.length);
    _writeUint16(_centralDir.length);
    _writeUint32(centralDirSize);
    _writeUint32(centralDirStart);
    _writeUint16(0);

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