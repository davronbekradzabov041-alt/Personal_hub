/// Module backup writer.
///
/// Creates .pmb (Personal Hub Module Backup) archives from a single
/// installed module's user data.
///
/// Формат .pmb намеренно НЕ зависит от .phm: .phm — это пакет
/// реализации модуля (что устанавливать), .pmb — это данные
/// пользователя (что должно пережить замену реализации).
library module_backup_writer;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import '../modules/module_manager.dart';
import '../modules/module_registry.dart' show ModuleRegistry;
import '../modules/module_state_store.dart';
import '../modules/platform/module_storage_serializer.dart';
import '../modules/platform/module_sandbox.dart';
import 'module_backup_manifest.dart';
import 'backup_exceptions.dart';
import 'backup_security_guard.dart';

/// Пишет .pmb архив одного модуля.
///
/// Только публичный API модулей: ModuleManager.apiFor().storage,
/// ModuleStorageSerializer, ModuleStateStore. Никакого прямого
/// доступа к Isar.
class ModuleBackupWriter {
  ModuleBackupWriter({
    ModuleStateStore? stateStore,
    Future<Directory> Function(String moduleId)? assetsDirectoryResolver,
  })  : _stateStore = stateStore,
        _assetsDirectoryResolver = assetsDirectoryResolver;

  final ModuleStateStore? _stateStore;
  final Future<Directory> Function(String moduleId)? _assetsDirectoryResolver;

  /// Создаёт .pmb для установленного модуля [moduleId].
  ///
  /// Бросает [BackupException], если модуль не зарегистрирован или не
  /// установлен, либо если не удалось прочитать его данные.
  Future<List<int>> writeModuleBackup({
    required ModuleManager manager,
    required String moduleId,
    required ModuleBackupOptions options,
  }) async {
    if (!ModuleRegistry.contains(moduleId)) {
      throw BackupFormatException('модуль $moduleId не зарегистрирован');
    }
    if (!manager.isInstalled(moduleId)) {
      throw BackupFormatException('модуль $moduleId не установлен');
    }

    final module = ModuleRegistry.get(moduleId)!;
    final manifest = ModuleBackupManifest(
      backupFormatVersion: kCurrentModuleBackupFormatVersion,
      appVersion: '1.0.0',
      createdAt: DateTime.now(),
      moduleId: moduleId,
      moduleVersion: module.manifest.version,
      options: options,
    );

    final writer = _ModuleBackupZipWriter();

    // 1. manifest.json — идентификация backup и состав компонентов
    writer.addFile(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson())),
    );

    // 2. state.json — снимок состояния из постоянного хранилища
    if (options.includeState) {
      final store = _stateStore;
      if (store != null) {
        final snapshot = await store.load(moduleId);
        if (snapshot != null) {
          writer.addFile(
            'state.json',
            utf8.encode(
              const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
            ),
          );
        }
      }
    }

    // 3. data.json — данные ModuleStorage через существующий serializer
    if (options.includeData) {
      final storageJson = await ModuleStorageSerializer.serialize(
        storage: manager.apiFor(moduleId).storage,
        moduleId: moduleId,
      );
      writer.addFile('data.json', utf8.encode(storageJson));
    }

    // 4. assets/ — пользовательские файлы модуля (не runtime-каталог)
    if (options.includeAssets) {
      final assetsDir = await _resolveAssetsDirectory(moduleId);
      if (await assetsDir.exists()) {
        final entities = await assetsDir.list().toList();
        for (final entity in entities) {
          if (entity is! File) continue;

          // Только расширения из allowlist'а security guard: иначе мы
          // создадим .pmb, который наш же reader отвергнет. Файлы
          // неизвестных типов пропускаем молча — это пользовательские
          // данные, терять их из-за одного backup нельзя, а валить
          // экспорт тоже неправильно.
          final name = path.basename(entity.path);
          if (!BackupSecurityGuard.isAllowedModuleBackupAsset(name)) {
            continue;
          }
          writer.addFile('assets/$name', await entity.readAsBytes());
        }
      }
    }

    // 5. metadata/ — служебные метаданные архива
    writer.addFile(
      'metadata/backupFormatVersion',
      utf8.encode(kCurrentModuleBackupFormatVersion.toString()),
    );
    writer.addFile('metadata/appVersion', utf8.encode(manifest.appVersion));
    writer.addFile('metadata/createdAt', utf8.encode(manifest.createdAt.toIso8601String()));

    // Checksum считается по тем же байтам, что и в .pbk: все local file
    // headers + данные, КРОМЕ самой записи metadata/checksum.
    writer.addFile('metadata/checksum', utf8.encode(_computeChecksum(writer.rawData)));

    return writer.build();
  }

  Future<Directory> _resolveAssetsDirectory(String moduleId) async {
    final resolver = _assetsDirectoryResolver;
    if (resolver != null) return resolver(moduleId);
    return ModuleSandbox.getAssetsDirectory(moduleId);
  }

  static String _computeChecksum(List<int> data) => sha256.convert(data).toString();
}

/// Внутренний ZIP writer для .pmb (STORED, method 0) — тот же формат,
/// что и у .pbk, чтобы security-проверки и checksum совпадали.
class _ModuleBackupZipWriter {
  final List<int> _data = [];
  final List<_CentralDirEntry> _centralDir = [];
  int _offset = 0;

  /// Байты, по которым считается checksum (до добавления
  /// metadata/checksum). Отдаётся наружу только для вычисления
  /// контрольной суммы.
  List<int> get rawData => _data;

  void addFile(String name, List<int> bytes) {
    final localHeaderOffset = _offset;
    final crc32 = _computeCRC32(bytes);
    final compressedSize = bytes.length;
    final uncompressedSize = bytes.length;

    // Длина имени в ZIP — это длина в БАЙТАХ UTF-8, а String.length
    // считает UTF-16 code units. Для не-ASCII имён (кириллица в именах
    // пользовательских файлов) они расходятся, и весь архив после
    // такой записи смещается. Поэтому считаем байты явно.
    final nameBytes = utf8.encode(name);

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
    final centralDirStart = _offset;
    for (final entry in _centralDir) {
      final nameBytes = utf8.encode(entry.name);
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
      _writeUint16(nameBytes.length);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint16(0);
      _writeUint32(0);
      _writeUint32(entry.localHeaderOffset);
      _data.addAll(nameBytes);
    }
    final centralDirSize = _data.length - centralDirStart;

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
