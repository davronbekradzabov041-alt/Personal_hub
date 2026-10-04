import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/platform/module_importer.dart';
import 'package:personal_hub/core/modules/platform/module_exporter.dart';
import 'package:personal_hub/core/modules/platform/package_security_guard.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/modules/platform/package_reader.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModuleExporter', () {
    late ModuleManager _manager;
    late _TestModuleStorage _testStorage;
    late Directory _testSupportDir;

    setUp(() async {
      ModuleRegistry.clear();
      
      _testStorage = _TestModuleStorage();
      _manager = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (moduleId) => _testStorage,
      );
      
      _testSupportDir = await Directory.systemTemp.createTemp('phm_test_');
    });

    tearDown(() async {
      ModuleRegistry.clear();
      _testStorage.clear();
      await _testSupportDir.delete(recursive: true);
    });

    group('Export without user data', () {
      test('minimal module', () async {
        // First install a module
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Now export without data
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        expect(result.moduleId, 'test-module');
        expect(result.phmBytes, isNotNull);
        expect(result.phmBytes!.isNotEmpty, true);
      });

      test('module with README', () async {
        final bytes1 = _createTestPhm(
          manifestJson: _minimalManifest(),
          readme: '# Test Module\n\nDescription.',
        );
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        
        // Verify the exported package can be read
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.manifest.id, 'test-module');
        // README is not stored by ExternalModuleAdapter, so it will be null
        expect(content.readme, isNull);
      });

      test('module with assets', () async {
        final bytes1 = _createTestPhm(
          manifestJson: _minimalManifest(),
          assets: {'assets/icon.png': List.filled(100, 0xFF)},
        );
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        
        // Verify the exported package can be read
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.manifest.id, 'test-module');
        expect(content.assets.length, 1);
        expect(content.assets.first.path, 'assets/icon.png');
      });
    });

    group('Export with user data', () {
      test('module with storage', () async {
        // First install a module
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Add some storage data
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('note', 'test note');
        await storage.setString('config', jsonEncode({'theme': 'dark'}));
        
        // Export with data
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        expect(result.isSuccess, true);
        expect(result.moduleId, 'test-module');
        
        // Verify the exported package contains storage
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.data, isNotNull);
        expect(content.data!.storage['note'], 'test note');
        expect(content.data!.storage['config'], '{"theme":"dark"}');
      });

      test('empty storage', () async {
        // First install a module
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Export with data (empty storage)
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        expect(result.isSuccess, true);
        
        // Verify the exported package contains empty storage
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.data, isNotNull);
        expect(content.data!.storage, isEmpty);
      });

      test('multiple storage entries', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Add multiple storage entries
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('key1', 'value1');
        await storage.setString('key2', 'value2');
        await storage.setString('key3', 'value3');
        
        // Export with data
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        expect(result.isSuccess, true);
        
        // Verify the exported package contains all entries
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.data!.storage.length, 3);
        expect(content.data!.storage['key1'], 'value1');
        expect(content.data!.storage['key2'], 'value2');
        expect(content.data!.storage['key3'], 'value3');
      });

      test('unicode storage', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('ключ', 'значение 🎉');
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        expect(result.isSuccess, true);
        
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.data!.storage['ключ'], 'значение 🎉');
      });
    });

    group('Round-trip tests', () {
      test('export without data -> import -> storage is empty', () async {
        // Install original module
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Add some storage data
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('note', 'test note');
        
        // Export WITHOUT data
        final exportResult = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(exportResult.isSuccess, true);
        
        // Create clean environment with captured storage instance
        ModuleRegistry.clear();
        _testStorage.clear();
        _TestModuleStorage? capturedStorage;
        _manager = ModuleManager(
          searchService: GlobalSearchService(),
          storageFactory: (moduleId) {
            final instance = _TestModuleStorage();
            capturedStorage = instance;
            return instance;
          },
        );
        
        // Import the exported package
        final importResult = await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(exportResult.phmBytes!);
        
        expect(importResult.isSuccess, true);
        
        // Verify storage is empty
        expect(capturedStorage != null, true);
        expect((await capturedStorage!.keys()).length, 0);
      });

      test('export with data -> import -> storage exactly restored', () async {
        // Install original module
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Add storage data
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('note', 'test note');
        await storage.setString('config', jsonEncode({'theme': 'dark'}));
        
        // Export WITH data
        final exportResult = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        expect(exportResult.isSuccess, true);
        
        // Create clean environment with captured storage instance
        ModuleRegistry.clear();
        _testStorage.clear();
        _TestModuleStorage? capturedStorage;
        _manager = ModuleManager(
          searchService: GlobalSearchService(),
          storageFactory: (moduleId) {
            final instance = _TestModuleStorage();
            capturedStorage = instance;
            return instance;
          },
        );
        
        // Import the exported package
        final importResult = await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(exportResult.phmBytes!);
        
        expect(importResult.isSuccess, true);
        
        // Verify storage exactly restored
        expect(capturedStorage != null, true);
        expect((await capturedStorage!.keys()).length, 2);
        expect(await capturedStorage!.getString('note'), 'test note');
        expect(await capturedStorage!.getString('config'), '{"theme":"dark"}');
      });

      test('export with assets -> import -> assets restored', () async {
        final bytes1 = _createTestPhm(
          manifestJson: _minimalManifest(),
          assets: {'assets/icon.png': List.filled(100, 0xFF)},
        );
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Export without data
        final exportResult = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(exportResult.isSuccess, true);
        
        // Create clean environment with a fresh storage instance
        ModuleRegistry.clear();
        _testStorage.clear();
        _manager = ModuleManager(
          searchService: GlobalSearchService(),
          storageFactory: (moduleId) => _TestModuleStorage(),
        );
        
        // Import the exported package
        final importResult = await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(exportResult.phmBytes!);
        
        expect(importResult.isSuccess, true);
        
        // Verify assets restored
        final reader = ModulePackageReader();
        final content = reader.readBytes(exportResult.phmBytes!, existingModuleIds: const {});
        expect(content.assets.length, 1);
        expect(content.assets.first.path, 'assets/icon.png');
      });
    });

    group('Error cases', () {
      test('export non-existent module', () async {
        final result = await ModuleExporter(
          moduleManager: _manager,
        ).export(moduleId: 'non-existent');
        
        expect(result.isFailure, true);
        expect(result.error, contains('не зарегистрирован'));
      });

      test('export uninstalled module', () async {
        // Register module but don't install
        final manifest = ModuleManifest.fromJson(jsonDecode(_minimalManifest(id: 'uninstalled-module')));
        ModuleRegistry.register(ExternalModuleAdapter(manifest));
        
        final result = await ModuleExporter(
          moduleManager: _manager,
        ).export(moduleId: 'uninstalled-module');
        
        expect(result.isFailure, true);
        expect(result.error, contains('не установлен'));
      });

      test('export builtin module rejected', () async {
        // Register a builtin module (not ExternalModuleAdapter)
        final builtinManifest = _minimalManifest(id: 'builtin-module');
        final builtinModule = _FakeBuiltinModule(ModuleManifest.fromJson(jsonDecode(builtinManifest)));
        ModuleRegistry.register(builtinModule);
        
        // Install the builtin module first
        await _manager.tryInstall('builtin-module');
        
        // Try to export external with same id
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'builtin-module');
        
        expect(result.isFailure, true);
        expect(result.error, contains('встроенный модуль'));
      });

      test('export does not modify source ModuleStorage', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Add storage data
        final storage = _manager.apiFor('test-module').storage;
        await storage.setString('note', 'original note');
        
        // Export with data
        await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withData);
        
        // Verify original storage unchanged
        expect(await storage.getString('note'), 'original note');
      });

      test('export does not modify source sandbox', () async {
        final bytes1 = _createTestPhm(
          manifestJson: _minimalManifest(),
          assets: {'assets/icon.png': List.filled(100, 0xFF)},
        );
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        // Export without data
        await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        // Verify sandbox still exists
        final modulesDir = Directory(path.join(_testSupportDir.path, 'modules', 'test-module', 'assets'));
        expect(await modulesDir.exists(), true);
        
        // Verify asset file still exists
        final assetFile = File(path.join(modulesDir.path, 'icon.png'));
        expect(await assetFile.exists(), true);
      });
    });

    group('Exported package validation', () {
      test('exported package passes PackageSecurityGuard', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        
        // Should not throw
        PackageSecurityGuard.validateArchive(result.phmBytes!);
      });

      test('exported package can be read by PackageReader', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        
        final reader = ModulePackageReader();
        final content = reader.readBytes(result.phmBytes!, existingModuleIds: const {});
        expect(content.manifest.id, 'test-module');
      });

      test('exported package can be imported by ModuleImporter', () async {
        final bytes1 = _createTestPhm(manifestJson: _minimalManifest());
        await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(bytes1);
        
        final result = await ModuleExporter(
          moduleManager: _manager,
          assetsDirectoryResolver: (id) =>
              ModuleSandbox.getAssetsDirectoryForTestingAsync(id, _testSupportDir),
        ).export(moduleId: 'test-module', mode: ModuleExportMode.withoutData);
        
        expect(result.isSuccess, true);
        
        // Create clean environment
        ModuleRegistry.clear();
        _testStorage.clear();
        _manager = ModuleManager(
          searchService: GlobalSearchService(),
          storageFactory: (moduleId) => _TestModuleStorage(),
        );
        
        // Import the exported package
        final importResult = await ModuleImporter(
          moduleManager: _manager,
          testSupportDir: _testSupportDir,
        ).importFromBytes(result.phmBytes!);
        
        expect(importResult.isSuccess, true);
        expect(ModuleRegistry.contains('test-module'), true);
      });
    });
  });
}

// =========================================================================
// Test helpers
// =========================================================================

/// In-memory ModuleStorage for testing
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
}

/// Minimal valid manifest
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

/// Creates a minimal valid .phm package bytes for testing
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

/// Fake builtin module (not ExternalModuleAdapter) for testing builtin module rejection
class _FakeBuiltinModule extends Module {
  _FakeBuiltinModule(ModuleManifest manifest) : _manifest = manifest;

  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension;

  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}