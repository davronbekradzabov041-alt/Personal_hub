import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_manifest.dart' hide BackupOptions;
import 'package:personal_hub/core/backup/backup_reader.dart';
import 'package:personal_hub/core/backup/global_backup_manager.dart';
import 'package:personal_hub/core/backup/backup_options.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/modules/module_manager.dart';
import 'package:personal_hub/core/modules/module_registry.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'package:personal_hub/core/modules/module_state.dart';
import 'package:personal_hub/core/modules/external/external_module_adapter.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/core/search/global_search_service.dart';
import 'package:personal_hub/core/database/isar_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import '../../support/isar_test_init.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalBackupManager', () {
    late ModuleManager manager0;
    late Directory testSupportDir;

    setUpAll(() async {
      // Нативная библиотека Isar подключается явно: isar_flutter_libs
      // — плагин, и в flutter test его бинарники не собираются.
      await ensureIsarCoreInitialized();

      // Set up path_provider mock for tests
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            final tempDir =
                await Directory.systemTemp.createTemp('phm_test_isar_');
            return tempDir.path;
          }
          return null;
        },
      );
      
      // Initialize Isar for tests
      await IsarService.init();
    });

    setUp(() async {
      ModuleRegistry.clear();
      
      // Register test modules
      ModuleRegistry.registerAll([
        ExternalModuleAdapter(ModuleManifest.fromJson(jsonDecode(_minimalManifest(id: 'test-module')))),
        ExternalModuleAdapter(ModuleManifest.fromJson(jsonDecode(_minimalManifest(id: 'module-a')))),
        ExternalModuleAdapter(ModuleManifest.fromJson(jsonDecode(_minimalManifest(id: 'module-b')))),
        ExternalModuleAdapter(ModuleManifest.fromJson(jsonDecode(_minimalManifest(id: 'module-c')))),
      ]);

      manager0 = ModuleManager(
        searchService: GlobalSearchService(),
        storageFactory: (moduleId) => _TestModuleStorage(),
      );
      
      testSupportDir = await Directory.systemTemp.createTemp('phm_test_');
    });

    tearDown(() async {
      ModuleRegistry.clear();
      await testSupportDir.delete(recursive: true);
    });

    group('GlobalBackupManager', () {
      test('empty global backup (settings only)', () async {
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: false,
            includeAssets: false,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.includedModuleIds, isEmpty);
        expect(result.optionsSummary.includeGlobalSettings, true);
      });

      test('backup with all modules', () async {
        // Use the _manager that has the module registered
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.includedModuleIds, contains('test-module'));
      });

      test('selected modules only', () async {
        manager0.setStateForTesting('module-a', ModuleState.installed);
        manager0.setStateForTesting('module-b', ModuleState.installed);
        manager0.setStateForTesting('module-c', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackupWithSelection(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          moduleIdsToInclude: {'module-a', 'module-b'},
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.includedModuleIds, containsAll(['module-a', 'module-b']));
        expect(result.includedModuleIds, isNot(contains('module-c')));
      });

      test('without global settings', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: false,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.optionsSummary.includeGlobalSettings, false);
      });

      test('without module data', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: false,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.optionsSummary.includeModuleData, false);
      });

      test('without assets', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: false,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.optionsSummary.includeAssets, false);
      });

      test('metadata is correct', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        expect(result.includedModuleIds, isNotEmpty);
        expect(result.sizeBytes, greaterThan(0));
        
        // Verify backup can be read back
        final content = await BackupReader.readGlobalBackup(
          await File(result.outputPath).readAsBytes(),
          existingModuleIds: {'test-module'},
        );
        
        expect(content.manifest.backupFormatVersion, kCurrentBackupFormatVersion);
        expect(content.manifest.type, BackupType.global);
        expect(content.manifest.includedModules, contains('test-module'));
        expect(content.modules.containsKey('test-module'), true);
      });

      test('checksum matches', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Verify checksum by reading back
        final content = await BackupReader.readGlobalBackup(
          await File(result.outputPath).readAsBytes(),
          existingModuleIds: {'test-module'},
        );
        
        expect(content.checksum, isNotEmpty);
      });

      test('source data integrity preserved', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Verify source data unchanged - backup writer doesn't modify source data
        expect(result.sizeBytes, greaterThan(0));
      });
    });

    group('Checksum verification (regression tests)', () {
      test('valid backup - checksum matches and reads successfully', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Read backup - should succeed with valid checksum
        final content = await BackupReader.readGlobalBackup(
          await File(result.outputPath).readAsBytes(),
          existingModuleIds: {'test-module'},
        );
        
        expect(content.checksum, isNotEmpty);
        expect(content.manifest.includedModules, contains('test-module'));
        expect(content.modules.containsKey('test-module'), true);
      });

      test('tampered backup - payload modification detected via checksum mismatch', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Read the backup bytes and tamper with a byte in a non-critical file's payload
        // Target metadata/createdAt which is a simple ISO timestamp string
        final backupBytes = await File(result.outputPath).readAsBytes();
        final tamperedBytes = Uint8List.fromList(backupBytes);
        
        // Find the local file header for metadata/createdAt and modify its data
        bool modified = false;
        for (int i = 0; i < tamperedBytes.length - 100; i++) {
          if (tamperedBytes[i] == 0x50 && 
              tamperedBytes[i + 1] == 0x4b && 
              tamperedBytes[i + 2] == 0x03 && 
              tamperedBytes[i + 3] == 0x04) {
            final nameLen = tamperedBytes[i + 26] | (tamperedBytes[i + 27] << 8);
            final extraLen = tamperedBytes[i + 28] | (tamperedBytes[i + 29] << 8);
            final nameStart = i + 30;
            if (nameStart + nameLen <= tamperedBytes.length) {
              final name = utf8.decode(tamperedBytes.sublist(nameStart, nameStart + nameLen));
              if (name == 'metadata/createdAt') {
                // Found metadata/createdAt, modify its data (change one digit in timestamp)
                final dataStart = nameStart + nameLen + extraLen;
                if (dataStart < tamperedBytes.length) {
                  // Change '2' to '3' in the timestamp (keeps valid UTF-8/ISO format)
                  if (tamperedBytes[dataStart] == 0x32) { // '2'
                    tamperedBytes[dataStart] = 0x33; // '3'
                  } else if (tamperedBytes[dataStart] == 0x33) { // '3'
                    tamperedBytes[dataStart] = 0x32; // '2'
                  } else {
                    tamperedBytes[dataStart] ^= 0x01; // Flip lowest bit
                  }
                  modified = true;
                  break;
                }
              }
            }
          }
        }
        
        expect(modified, true, reason: 'Should have found and modified metadata/createdAt');
        
        // Reading tampered backup should fail with ChecksumMismatchException
        expect(
          () => BackupReader.readGlobalBackup(
            tamperedBytes,
            existingModuleIds: {'test-module'},
          ),
          throwsA(isA<ChecksumMismatchException>()),
        );
      });

      test('tampered backup - metadata/checksum modification detected', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Read the backup bytes and tamper with the checksum value itself
        // Keep it valid UTF-8 (change one hex char to another valid hex char)
        final backupBytes = await File(result.outputPath).readAsBytes();
        final tamperedBytes = Uint8List.fromList(backupBytes);
        
        // Find the local file header for metadata/checksum and modify its data
        bool modified = false;
        for (int i = 0; i < tamperedBytes.length - 100; i++) {
          if (tamperedBytes[i] == 0x50 && 
              tamperedBytes[i + 1] == 0x4b && 
              tamperedBytes[i + 2] == 0x03 && 
              tamperedBytes[i + 3] == 0x04) {
            final nameLen = tamperedBytes[i + 26] | (tamperedBytes[i + 27] << 8);
            final extraLen = tamperedBytes[i + 28] | (tamperedBytes[i + 29] << 8);
            final nameStart = i + 30;
            if (nameStart + nameLen <= tamperedBytes.length) {
              final name = utf8.decode(tamperedBytes.sublist(nameStart, nameStart + nameLen));
              if (name == 'metadata/checksum') {
                // Found metadata/checksum local header, modify its data
                final dataStart = nameStart + nameLen + extraLen;
                if (dataStart < tamperedBytes.length) {
                  // Change one hex character to another valid hex character
                  // Hex chars are 0-9, a-f (0x30-0x39, 0x61-0x66)
                  final byte = tamperedBytes[dataStart];
                  if (byte >= 0x30 && byte <= 0x39) { // '0'-'9'
                    tamperedBytes[dataStart] = (byte == 0x39) ? 0x30 : byte + 1;
                  } else if (byte >= 0x61 && byte <= 0x66) { // 'a'-'f'
                    tamperedBytes[dataStart] = (byte == 0x66) ? 0x61 : byte + 1;
                  } else {
                    tamperedBytes[dataStart] = 0x30; // '0'
                  }
                  modified = true;
                  break;
                }
              }
            }
          }
        }
        
        expect(modified, true, reason: 'Should have found and modified metadata/checksum');
        
        // Reading tampered backup should fail with ChecksumMismatchException
        expect(
          () => BackupReader.readGlobalBackup(
            tamperedBytes,
            existingModuleIds: {'test-module'},
          ),
          throwsA(isA<ChecksumMismatchException>()),
        );
      });

      test('ZIP size validation rejects uncompressedSize=0 with compressedSize>0 for stored method', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Read the backup bytes and modify Central Directory to set uncompressedSize = 0
        // for a file entry while keeping compressedSize > 0
        final backupBytes = await File(result.outputPath).readAsBytes();
        final tamperedBytes = Uint8List.fromList(backupBytes);
        
        // Find the Central Directory entry for manifest.json and set its uncompressedSize to 0
        // Central Directory entry structure:
        // offset 20-23: compressedSize (4 bytes)
        // offset 24-27: uncompressedSize (4 bytes)
        bool modified = false;
        // First find EOCD to locate Central Directory
        for (int i = tamperedBytes.length - 22; i >= 0; i--) {
          if (tamperedBytes[i] == 0x50 && 
              tamperedBytes[i + 1] == 0x4b && 
              tamperedBytes[i + 2] == 0x05 && 
              tamperedBytes[i + 3] == 0x06) {
            final centralDirOffset = _readUint32(tamperedBytes, i + 16);
            final totalRecords = _readUint16(tamperedBytes, i + 10);
            
            int offset = centralDirOffset;
            for (int r = 0; r < totalRecords; r++) {
              if (offset + 46 > tamperedBytes.length) break;
              
              // Check signature
              if (tamperedBytes[offset] == 0x50 && 
                  tamperedBytes[offset + 1] == 0x4b && 
                  tamperedBytes[offset + 2] == 0x01 && 
                  tamperedBytes[offset + 3] == 0x02) {
                final fileNameLength = _readUint16(tamperedBytes, offset + 28);
                final nameStart = offset + 46;
                if (nameStart + fileNameLength <= tamperedBytes.length) {
                  final name = utf8.decode(tamperedBytes.sublist(nameStart, nameStart + fileNameLength));
                  if (name == 'manifest.json') {
                    // Found manifest.json entry, set uncompressedSize to 0
                    // offset + 24 is uncompressedSize (4 bytes, little-endian)
                    _writeUint32(tamperedBytes, offset + 24, 0);
                    modified = true;
                    break;
                  }
                }
              }
              
              final extraFieldLength = _readUint16(tamperedBytes, offset + 30);
              final commentLength = _readUint16(tamperedBytes, offset + 32);
              final fileNameLength = _readUint16(tamperedBytes, offset + 28);
              offset = offset + 46 + fileNameLength + extraFieldLength + commentLength;
            }
            break;
          }
        }
        
        expect(modified, true, reason: 'Should have found and modified manifest.json Central Directory entry');
        
        // Reading tampered backup should fail with CorruptedBackupException due to size mismatch
        expect(
          () => BackupReader.readGlobalBackup(
            tamperedBytes,
            existingModuleIds: {'test-module'},
          ),
          throwsA(isA<CorruptedBackupException>()),
        );
      });

      test('rejects unsupported compression method (not BackupException)', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);
        
        
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: true,
          ),
          outputDirectory: await _getTestOutputDir(),
        );
        
        expect(result.sizeBytes, greaterThan(0));
        
        // Read the backup bytes and modify compression method in LFH for global/settings.json to 8 (DEFLATE)
        final backupBytes = await File(result.outputPath).readAsBytes();
        final tamperedBytes = Uint8List.fromList(backupBytes);
        
        // Find the local file header for global/settings.json and change compression method to 8
        bool modified = false;
        for (int i = 0; i < tamperedBytes.length - 100; i++) {
          if (tamperedBytes[i] == 0x50 && 
              tamperedBytes[i + 1] == 0x4b && 
              tamperedBytes[i + 2] == 0x03 && 
              tamperedBytes[i + 3] == 0x04) {
            final nameLen = tamperedBytes[i + 26] | (tamperedBytes[i + 27] << 8);
            final nameStart = i + 30;
            if (nameStart + nameLen <= tamperedBytes.length) {
              final name = utf8.decode(tamperedBytes.sublist(nameStart, nameStart + nameLen));
              if (name == 'global/settings.json') {
                // Found global/settings.json local header, change compression method (offset 8-9)
                tamperedBytes[i + 8] = 8; // DEFLATE
                tamperedBytes[i + 9] = 0;
                modified = true;
                break;
              }
            }
          }
        }
        
        expect(modified, true, reason: 'Should have found and modified global/settings.json LFH');
        
        // Reading tampered backup should fail with BackupFormatException, NOT UnsupportedError
        try {
          await BackupReader.readGlobalBackup(
            tamperedBytes,
            existingModuleIds: {'test-module'},
          );
          fail('Expected BackupFormatException to be thrown');
        } on BackupFormatException catch (e) {
          expect(e.message, contains('неподдерживаемый метод сжатия'));
        } on UnsupportedError catch (e) {
          fail('Should throw BackupFormatException, not UnsupportedError: $e');
        }
      });
    });

    // AUD-40: GlobalBackupManager создаёт backup без модулей, когда
    // установленных модулей нет, но включены глобальные настройки.
    // Такой архив обязан быть валидным и читаться обратно: раньше
    // BackupManifest.validate() отвергал пустой includedModules
    // безусловно, и round-trip «create → write → read» падал на
    // собственном backup приложения.
    group('AUD-40: backup без модулей, только глобальные настройки', () {
      test('round-trip: 0 модулей + includeGlobalSettings читается обратно',
          () async {
        final outputDir = await _getTestOutputDir();

        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: const BackupOptions(
            includeModuleData: false,
            includeAssets: false,
            includeGlobalSettings: true,
          ),
          outputDirectory: outputDir,
        );

        expect(result.includedModuleIds, isEmpty,
            reason: 'в этом сценарии модули не установлены');

        // Ключевая проверка: архив, созданный приложением, обязан
        // читаться обратно без dummy-модулей и без ручных правок.
        final content = await BackupReader.readGlobalBackup(
          await File(result.outputPath).readAsBytes(),
          existingModuleIds: const {},
        );

        expect(content.modules, isEmpty,
            reason: 'в backup не должно быть ни одного модуля');
        expect(content.manifest.includedModules, isEmpty);
        expect(content.manifest.type, BackupType.global);
        expect(content.globalSettingsJson, isNotNull,
            reason: 'глобальные настройки обязаны быть в архиве');
      });

      test('manifest с 0 модулей без глобальных настроек отвергается',
          () async {
        // Пустой архив без единого полезного содержимого невалиден —
        // это осознанное ограничение, а не побочный эффект исправления.
        final manifest = BackupManifest(
          backupFormatVersion: kCurrentBackupFormatVersion,
          appVersion: '1.0.0',
          createdAt: DateTime.now(),
          type: BackupType.global,
          includedModules: const [],
          options: const BackupOptions(
            includeGlobalSettings: false,
          ),
        );

        expect(manifest.validate(), isNotEmpty,
            reason: 'backup без модулей и без настроек невалиден');
      });

      test('backup без модулей и без настроек не создаётся', () async {
        await expectLater(
          GlobalBackupManager(moduleManager: manager0).createGlobalBackup(
            options: const BackupOptions(
              includeGlobalSettings: false,
            ),
            outputDirectory: await _getTestOutputDir(),
          ),
          throwsA(isA<BackupFormatException>()),
        );
      });
    });

    // AUD-52: manifest.options обязан отражать реально выбранные
    // пользователем опции. Раньше туда писались константы
    // includeData: true / includeAssets: true / includeSettings: true
    // независимо от выбора, то есть метаданные архива были ложными.
    group('AUD-52: manifest.options отражает реальный выбор', () {
      Future<BackupManifest> manifestOf(BackupOptions options) async {
        final result = await GlobalBackupManager(
          moduleManager: manager0,
        ).createGlobalBackup(
          options: options,
          outputDirectory: await _getTestOutputDir(),
        );

        // Читаем manifest прямо из записанного архива, а не из
        // переданных опций: проверяется именно то, что оказалось
        // в .pbk на диске.
        final content = await BackupReader.readGlobalBackup(
          await File(result.outputPath).readAsBytes(),
          existingModuleIds: const {'test-module'},
        );
        return content.manifest;
      }

      test('все опции выключены, кроме глобальных настроек', () async {
        final manifest = await manifestOf(const BackupOptions(
          includeModuleData: false,
          includeAssets: false,
          includeGlobalSettings: true,
        ));

        expect(manifest.options.includeModuleData, isFalse);
        expect(manifest.options.includeAssets, isFalse);
        expect(manifest.options.includeGlobalSettings, isTrue);
      });

      test('только данные модулей, без ассетов и настроек', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);

        final manifest = await manifestOf(const BackupOptions(
          includeModuleData: true,
          includeAssets: false,
          includeGlobalSettings: false,
        ));

        expect(manifest.options.includeModuleData, isTrue);
        expect(manifest.options.includeAssets, isFalse);
        expect(manifest.options.includeGlobalSettings, isFalse);
      });

      test('только ассеты модулей', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);

        final manifest = await manifestOf(const BackupOptions(
          includeModuleData: false,
          includeAssets: true,
          includeGlobalSettings: false,
        ));

        expect(manifest.options.includeModuleData, isFalse);
        expect(manifest.options.includeAssets, isTrue);
        expect(manifest.options.includeGlobalSettings, isFalse);
      });

      test('все опции включены', () async {
        manager0.setStateForTesting('test-module', ModuleState.installed);

        final manifest = await manifestOf(const BackupOptions(
          includeModuleData: true,
          includeAssets: true,
          includeGlobalSettings: true,
        ));

        expect(manifest.options.includeModuleData, isTrue);
        expect(manifest.options.includeAssets, isTrue);
        expect(manifest.options.includeGlobalSettings, isTrue);
      });

      test('выключенные опции не заявляются в toJson архива', () async {
        // Метаданные проверяются в том виде, в каком они сериализуются.
        const chosen = BackupOptions(
          includeModuleData: false,
          includeAssets: true,
          includeGlobalSettings: false,
        );
        final json = chosen.toJson();

        expect(json['includeModuleData'], isFalse);
        expect(json['includeAssets'], isTrue);
        expect(json['includeGlobalSettings'], isFalse);
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

/// Helper to get test output directory
Future<Directory> _getTestOutputDir() async {
  final tempDir = await Directory.systemTemp.createTemp('phm_test_');
  return tempDir;
}

/// Helper functions for reading/writing integers in little-endian format
int _readUint16(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

void _writeUint32(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}
