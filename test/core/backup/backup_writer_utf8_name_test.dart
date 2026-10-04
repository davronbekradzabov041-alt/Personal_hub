/// Регрессия AUD-04: длина имени файла в ZIP-заголовках должна считаться
/// в байтах UTF-8, а не в UTF-16 code units (`String.length`).
///
/// Для ASCII имён оба значения совпадают, поэтому баг был незаметен;
/// для кириллицы (реальные имена пользовательских файлов внутри
/// assets/) архив после такой записи разъезжался и .pbk не читался.
library backup_writer_utf8_name_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/backup/backup_reader.dart';
import 'package:personal_hub/core/backup/backup_writer.dart';
import 'package:personal_hub/core/database/isar_service.dart';
import 'package:personal_hub/core/database/repositories/app_settings_repository.dart';
import 'package:personal_hub/core/database/repositories/module_state_repository.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/module_state_store.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/search/global_search_service.dart';

import '../../support/isar_test_init.dart';

class _InMemoryModuleStorage implements ModuleStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList();
}

String _manifestJson(String id) => jsonEncode({
      'id': id,
      'name': 'Module $id',
      'version': '1.0.0',
      'apiVersion': 1,
      'author': 'Test',
      'description': 'UTF-8 name regression module',
      'permissions': <String>[],
      'dependencies': <String>[],
      'icon': 'assets/icon.png',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory _docDir;
  late ModuleManager _manager;

  setUpAll(() async {
    // Нативная библиотека Isar подключается явно: isar_flutter_libs
    // — плагин, и в flutter test его бинарники не собираются.
    await ensureIsarCoreInitialized();

    // IsarService.init() сам ходит в path_provider, поэтому каталог
    // документов должен существовать до регистрации mock-обработчика.
    _docDir = await Directory.systemTemp.createTemp('phm_utf8_name_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return _docDir.path;
        }
        return null;
      },
    );
    await IsarService.init();
  });
  
  tearDownAll(() async {
    // Каталог с базой Isar намеренно не удаляется: файл держит открытый
    // Isar, удаление упало бы с errno 32 на Windows. Temp-каталог уберёт ОС.
  });

  setUp(() async {
    ModuleRegistry.clear();
    _manager = ModuleManager(
      searchService: GlobalSearchService(),
      storageFactory: (moduleId) => _InMemoryModuleStorage(),
    );
  });

  tearDown(() async {
    ModuleRegistry.clear();
    final stateStore = ModuleStateRepository();
    for (final moduleId in ['ascii-module', 'cyrillic-module']) {
      await stateStore.delete(moduleId);
    }
    final sandboxRoot = Directory(
      path.join(_docDir.path, 'personal_hub_modules', 'modules'),
    );
    if (await sandboxRoot.exists()) {
      await sandboxRoot.delete(recursive: true);
    }
  });

  Future<List<int>> _writeBackup(String moduleId) {
    return BackupWriter.writeGlobalBackup(
      manager: _manager,
      settingsRepository: AppSettingsRepository(),
      selection: BackupSelection(
        includedModules: [moduleId],
        includeModuleData: true,
        includeAssets: true,
        includeGlobalSettings: true,
      ),
    );
  }

  Future<void> _registerInstalled(String moduleId) async {
    ModuleRegistry.register(
      ExternalModuleAdapter(
        ModuleManifest.fromJson(jsonDecode(_manifestJson(moduleId))),
      ),
    );
    _manager.setStateForTesting(moduleId, ModuleState.installed);
    await ModuleStateRepository().save(
      ModuleStateSnapshot(
        moduleId: moduleId,
        state: 'enabled',
        installedVersion: '1.0.0',
        enabled: true,
        installedAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
  }

  Future<void> _writeAsset(
    String moduleId,
    String fileName,
    List<int> bytes,
  ) async {
    final assetsDir = await ModuleSandbox.getAssetsDirectory(moduleId);
    await assetsDir.create(recursive: true);
    await File(path.join(assetsDir.path, fileName)).writeAsBytes(bytes);
  }

  group('BackupWriter: UTF-8 filename length (AUD-04 regression)', () {
    test('ASCII name: write then read round-trip is unchanged', () async {
      await _registerInstalled('ascii-module');
      final payload = List<int>.generate(64, (i) => i % 256);
      await _writeAsset('ascii-module', 'icon.png', payload);

      final bytes = await _writeBackup('ascii-module');
      final backup = await BackupReader.readGlobalBackup(
        bytes,
        existingModuleIds: const {'ascii-module'},
      );

      final assets = backup.modules['ascii-module']!.assets;
      expect(assets.keys, contains('icon.png'));
      expect(assets['icon.png'], payload);
    });

    test('non-ASCII name: write then read round-trip keeps the file', () async {
      await _registerInstalled('cyrillic-module');
      final payload = List<int>.generate(128, (i) => (i * 7) % 256);
      await _writeAsset('cyrillic-module', 'скриншот.png', payload);
      await _writeAsset('cyrillic-module', 'фото.jpg', payload);

      final bytes = await _writeBackup('cyrillic-module');
      final backup = await BackupReader.readGlobalBackup(
        bytes,
        existingModuleIds: const {'cyrillic-module'},
      );

      final assets = backup.modules['cyrillic-module']!.assets;
      expect(
        assets.keys,
        containsAll(<String>['скриншот.png', 'фото.jpg']),
        reason: 'non-ASCII asset names must survive the round-trip',
      );
      expect(assets['скриншот.png'], payload);
      expect(assets['фото.jpg'], payload);
    });

    test('entries after a non-ASCII name are not lost', () async {
      // Смещение архива (баг) ломало не только сам файл, но и все записи,
      // следующие за ним: metadata/ пишется после assets/.
      await _registerInstalled('cyrillic-module');
      await _writeAsset('cyrillic-module', 'скриншот.png', List<int>.filled(32, 7));

      final bytes = await _writeBackup('cyrillic-module');
      final backup = await BackupReader.readGlobalBackup(
        bytes,
        existingModuleIds: const {'cyrillic-module'},
      );

      expect(backup.checksum, isNotEmpty);
      expect(backup.manifest.includedModules, contains('cyrillic-module'));
      expect(backup.modules['cyrillic-module']!.dataJson, isNotNull);
    });

    test('header name length equals UTF-8 byte length, not UTF-16', () async {
      await _registerInstalled('cyrillic-module');
      await _writeAsset('cyrillic-module', 'скриншот.png', List<int>.filled(8, 1));

      final bytes = await _writeBackup('cyrillic-module');
      const entryName = 'modules/cyrillic-module/assets/скриншот.png';
      final nameBytes = utf8.encode(entryName);

      var found = false;
      for (var i = 0; i < bytes.length - 30; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4b &&
            bytes[i + 2] == 0x03 &&
            bytes[i + 3] == 0x04) {
          final nameLength = bytes[i + 26] | (bytes[i + 27] << 8);
          if (nameLength == nameBytes.length &&
              _startsWith(bytes.sublist(i + 30, i + 30 + nameLength), nameBytes)) {
            found = true;
          }
        }
      }

      expect(nameBytes.length, isNot(entryName.length),
          reason: 'test is meaningless when both lengths are equal');
      expect(
        found,
        isTrue,
        reason: 'name length in the local header must be ${nameBytes.length} '
            'bytes (UTF-8), not ${entryName.length} (UTF-16)',
      );
    });
  });
}

bool _startsWith(List<int> data, List<int> prefix) {
  if (prefix.length > data.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}
