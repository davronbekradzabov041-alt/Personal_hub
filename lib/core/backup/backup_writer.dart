/// Global backup writer.
///
/// Creates .pbk (Personal Hub Backup) archives from application state.
library backup_writer;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import '../modules/module_manager.dart';
import '../modules/module_registry.dart';
import '../modules/module_storage_isar.dart';
import '../database/repositories/app_settings_repository.dart';
import '../database/repositories/module_state_repository.dart';
import '../modules/platform/module_storage_serializer.dart';
import '../modules/platform/module_sandbox.dart';
import 'backup_manifest.dart';
import 'backup_exceptions.dart';
import 'backup_security_guard.dart';

/// Writes a global backup (.pbk) archive.
class BackupWriter {
  /// Creates a global backup archive.
  ///
  /// [manager] - ModuleManager for accessing module state and storage
  /// [settingsRepository] - AppSettingsRepository for global settings
  /// [selection] - BackupSelection defining what to include
  /// [testSupportDir] - Optional test directory override
  ///
  /// Returns the complete .pbk archive as bytes.
  static Future<List<int>> writeGlobalBackup({
    required ModuleManager manager,
    required AppSettingsRepository settingsRepository,
    required BackupSelection selection,
    Directory? testSupportDir,
  }) async {
    final writer = _BackupZipWriter();
    final manifest = await _buildManifest(manager, selection);

    // 1. manifest.json
    _addFile(writer, 'manifest.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson())));

    // 2. global/settings.json (optional)
    if (selection.includeGlobalSettings) {
      final settings = await settingsRepository.load();
      _addFile(writer, 'global/settings.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(settings.toJson())));
    }

    // 3. global/metadata.json
    _addFile(writer, 'global/metadata.json', utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toIso8601String(),
    })));

    // 4. modules/<moduleId>/...
    for (final moduleId in selection.includedModules) {
      if (!ModuleRegistry.contains(moduleId)) {
        throw BackupWriteException('модуль $moduleId не зарегистрирован');
      }

      final module = ModuleRegistry.get(moduleId)!;
      if (!manager.isInstalled(moduleId)) {
        throw BackupWriteException('модуль $moduleId не установлен');
      }

      // manifest.json
      final moduleManifest = module.manifest;
      _addFile(writer, 'modules/$moduleId/manifest.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(moduleManifest.toJson())));

      // state.json
      final stateStore = ModuleStateRepository();
      final stateSnapshot = await stateStore.load(moduleId);
      if (stateSnapshot != null) {
        _addFile(writer, 'modules/$moduleId/state.json', utf8.encode(const JsonEncoder.withIndent('  ').convert(stateSnapshot.toJson())));
      }

      // data.json (optional)
      if (selection.includeModuleData) {
        final storage = ModuleStorageIsar(moduleId);
        final storageJson = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: moduleId,
        );
        _addFile(writer, 'modules/$moduleId/data.json', utf8.encode(storageJson));
      }

      // assets/ (optional)
      if (selection.includeAssets) {
        final assetsDir = await ModuleSandbox.getAssetsDirectory(moduleId);
        if (await assetsDir.exists()) {
          final entities = await assetsDir.list().toList();
          for (final entity in entities) {
            if (entity is! File) continue;

            // Фильтруем по тому же списку, что и security guard при
            // чтении: иначе создадим .pbk, который сам же не прочитаем.
            final fileName = path.basename(entity.path);
            if (!BackupSecurityGuard.isAllowedGlobalAsset(fileName)) {
              continue;
            }
            final bytes = await entity.readAsBytes();
            writer.addFile('modules/$moduleId/assets/$fileName', bytes);
          }
        }
      }
    }

    // metadata/
    _addFile(writer, 'metadata/backupFormatVersion', utf8.encode(kCurrentBackupFormatVersion.toString()));
    _addFile(writer, 'metadata/appVersion', utf8.encode(manifest.appVersion));
    _addFile(writer, 'metadata/createdAt', utf8.encode(DateTime.now().toIso8601String()));

    // Calculate checksum before finalizing
    final checksum = _computeChecksum(writer._data);
    _addFile(writer, 'metadata/checksum', utf8.encode(checksum));

    return writer.build();
  }

  static Future<BackupManifest> _buildManifest(ModuleManager manager, BackupSelection selection) async {
    final includedModules = <String>[];
    for (final moduleId in selection.includedModules) {
      if (ModuleRegistry.contains(moduleId) && manager.isInstalled(moduleId)) {
        includedModules.add(moduleId);
      }
    }

    return BackupManifest(
      backupFormatVersion: kCurrentBackupFormatVersion,
      appVersion: '1.0.0', // TODO: get from package info
      createdAt: DateTime.now(),
      type: BackupType.global,
      includedModules: includedModules,
      // Реально выбранные пользователем опции, а не константы: иначе
      // manifest архива утверждал бы, что в него вошли данные и ассеты
      // модулей, которых в нём нет. Читатель архива опирается на это
      // поле, поэтому подмена делала метаданные недостоверными.
      options: BackupOptions(
        includeModuleData: selection.includeModuleData,
        includeAssets: selection.includeAssets,
        includeGlobalSettings: selection.includeGlobalSettings,
      ),
    );
  }

  static void _addFile(_BackupZipWriter writer, String name, List<int> bytes) {
    writer.addFile(name, bytes);
  }

  static String _computeChecksum(List<int> data) {
    return sha256.convert(data).toString();
  }
}

/// Selection options for global backup.
class BackupSelection {
  final List<String> includedModules;
  final bool includeModuleData;
  final bool includeAssets;
  final bool includeGlobalSettings;

  const BackupSelection({
    required this.includedModules,
    this.includeModuleData = true,
    this.includeAssets = true,
    this.includeGlobalSettings = true,
  });
}

/// Internal ZIP writer using STORED compression (method 0).
class _BackupZipWriter {
  final List<int> _data = [];
  final List<_CentralDirEntry> _centralDir = [];
  int _offset = 0;

  void addFile(String name, List<int> bytes) {
    final localHeaderOffset = _offset;
    final crc32 = _computeCRC32(bytes);
    final compressedSize = bytes.length;
    final uncompressedSize = bytes.length;

    // Длина имени в ZIP — длина в БАЙТАХ UTF-8, а String.length
    // считает UTF-16 code units. Для не-ASCII имён (кириллица в именах
    // пользовательских файлов внутри .pbk) расхождение смещает весь
    // архив после такой записи, поэтому байты кодируются явно.
    final nameBytes = utf8.encode(name);

    // Local file header
    _writeUint32(0x04034b50);
    _writeUint16(20);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint32(crc32);
    _writeUint32(compressedSize);
    _writeUint32(uncompressedSize);
    _writeUint16(nameBytes.length);
    _writeUint16(0);
    _data.addAll(nameBytes);
    _data.addAll(bytes);

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

  List<int> build() {
    _writeCentralDirectory();
    _writeEOCD();
    return Uint8List.fromList(_data);
  }

  void _writeCentralDirectory() {
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
      _writeUint16(entry.nameByteLength);
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

    _centralDirStart = centralDirStart;
    _centralDirSize = centralDirSize;
  }

  void _writeEOCD() {
    _writeUint32(0x06054b50);
    _writeUint16(0);
    _writeUint16(0);
    _writeUint16(_centralDir.length);
    _writeUint16(_centralDir.length);
    _writeUint32(_centralDirSize);
    _writeUint32(_centralDirStart);
    _writeUint16(0);
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

  int _centralDirStart = 0;
  int _centralDirSize = 0;
}

class _CentralDirEntry {
  final String name;
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