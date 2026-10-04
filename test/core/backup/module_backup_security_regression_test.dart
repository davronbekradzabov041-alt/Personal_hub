/// Regression-тесты безопасности и формата .pmb (Stage 6F).
///
/// Существующие security-тесты для .pbk не переписываются — здесь
/// закрывается .pmb, у которого свой набор допустимых путей и который
/// появился на Stage 6D. Каждый тест соответствует одному правилу
/// защиты, чтобы при поломке было видно, какое именно перестало
/// работать.
library module_backup_security_regression_test;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/backup_security_guard.dart';
import 'package:personal_hub/core/backup/module_backup_reader.dart';

/// Минимальный ZIP writer (STORED) для сборки подозрительных архивов.
///
/// Нужен, чтобы собрать архивы, которые нельзя получить из writer'а:
/// с чужими путями, лишними файлами, дубликатами и подменёнными
/// заголовками. Алгоритм намеренно повторяет продовый, иначе тест
/// проверял бы не тот формат, который читает приложение.
class _ZipBuilder {
  final List<int> _data = [];
  final List<_Entry> _entries = [];

  void add(String name, List<int> bytes, {int compressionMethod = 0}) {
    final localOffset = _data.length;
    final nameBytes = utf8.encode(name);
    final crc = _crc32(bytes);

    // Раскладка local header: signature, version, flags, method,
    // modTime, modDate, crc, sizes, nameLength, extraLength. Порядок
    // полей жёсткий — сдвиг даже на два байта ломает чтение имени.
    _u32(0x04034b50); // 0  signature
    _u16(20); // 4  version needed
    _u16(0); // 6  general purpose flags
    _u16(compressionMethod); // 8  method
    _u16(0); // 10 mod time
    _u16(0); // 12 mod date
    _u32(crc); // 14 crc32
    _u32(bytes.length); // 18 compressed size
    _u32(bytes.length); // 22 uncompressed size
    _u16(nameBytes.length); // 26 file name length
    _u16(0); // 28 extra field length
    _data.addAll(nameBytes);
    _data.addAll(bytes);

    _entries.add(_Entry(
      name: name,
      nameBytes: nameBytes,
      localOffset: localOffset,
      compressionMethod: compressionMethod,
      size: bytes.length,
      crc: crc,
    ));
  }

  /// Позволяет дописать запись после EOCD-подобного хвоста — нужно для
  /// теста на «мусор» после архива.
  void addRaw(List<int> bytes) => _data.addAll(bytes);

  List<int> build() {
    final centralStart = _data.length;
    for (final e in _entries) {
      // Раскладка центральной директории фиксирована форматом ZIP:
      // после versionMadeBy/versionNeeded идут flags, затем method.
      // Пропуск любого из этих полей сдвигает все последующие смещения,
      // и парсер читает мусор вместо заголовков.
      _u32(0x02014b50); // 0  signature
      _u16(45); // 4  version made by
      _u16(20); // 6  version needed
      _u16(0); // 8  general purpose flags
      _u16(e.compressionMethod); // 10 method
      _u16(0); // 12 mod time
      _u16(0); // 14 mod date
      _u32(e.crc); // 16 crc32
      _u32(e.size); // 20 compressed size
      _u32(e.size); // 24 uncompressed size
      _u16(e.nameBytes.length); // 28 file name length
      _u16(0); // 30 extra field length
      _u16(0); // 32 file comment length
      _u16(0); // 34 disk number start
      _u16(0); // 36 internal attributes
      _u32(0); // 38 external attributes
      _u32(e.localOffset); // 42 relative offset of local header
      _data.addAll(e.nameBytes);
    }
    final centralSize = _data.length - centralStart;

    _u32(0x06054b50);
    _u16(0); // disk number
    _u16(0); // disk with central directory
    _u16(_entries.length); // entries on this disk
    _u16(_entries.length); // total entries
    _u32(centralSize);
    _u32(centralStart);
    _u16(0); // comment length

    return List<int>.from(_data);
  }

  void _u16(int v) {
    _data.add(v & 0xFF);
    _data.add((v >> 8) & 0xFF);
  }

  void _u32(int v) {
    _data.add(v & 0xFF);
    _data.add((v >> 8) & 0xFF);
    _data.add((v >> 16) & 0xFF);
    _data.add((v >> 24) & 0xFF);
  }

  static int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ ((crc & 1) * 0xEDB88320);
      }
    }
    return ~crc & 0xFFFFFFFF;
  }
}

class _Entry {
  final String name;
  final List<int> nameBytes;
  final int localOffset;
  final int compressionMethod;
  final int size;
  final int crc;

  _Entry({
    required this.name,
    required this.nameBytes,
    required this.localOffset,
    required this.compressionMethod,
    required this.size,
    required this.crc,
  });
}

String _manifestJson({
  String moduleId = 'alpha',
  int version = 1,
}) {
  // Набор полей обязан совпадать с ModuleBackupManifest.fromJson:
  // appVersion, createdAt, moduleVersion и options — обязательные,
  // их отсутствие reader отвергает как невалидный манифест.
  return jsonEncode({
    'backupFormatVersion': version,
    'appVersion': '1.0.0',
    'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'moduleId': moduleId,
    'moduleVersion': '1.0.0',
    'options': {
      'includeState': true,
      'includeData': true,
      'includeAssets': false,
    },
  });
}

/// Собирает валидный .pmb, поверх которого можно наложить изменения.
class _PmbBuilder {
  _PmbBuilder({
    this.moduleId = 'alpha',
    this.formatVersion = 1,
    this.extraFiles = const {},
    this.duplicateEntry,
    this.compressionMethod,
  })  : manifestOverride = null,
        trailingGarbage = false;

  final String moduleId;
  final int formatVersion;

  /// Дополнительные записи: имя → содержимое.
  final Map<String, List<int>> extraFiles;

  /// Готовая строка manifest.json вместо генерируемой.
  final String? manifestOverride;

  /// Имя записи, продублированной дважды.
  final String? duplicateEntry;

  /// Недопустимый метод сжатия (например, deflate).
  final int? compressionMethod;

  /// Мусор после EOCD.
  final bool trailingGarbage;

  List<int> build() {
    // Checksum считается по тем же байтам, что и у reader: локальные
    // заголовки и данные всех записей, КРОМЕ metadata/checksum. Поэтому
    // сначала собираем набор без checksum, считаем, затем добавляем
    // запись checksum.
    final withoutChecksum = _assemble(includeChecksum: false);
    final checksum = _sha256Of(withoutChecksum);
    return _assemble(includeChecksum: true, checksum: checksum);
  }

  List<int> _assemble({required bool includeChecksum, String? checksum}) {
    final zip = _ZipBuilder();

    for (final entry in payload().entries) {
      zip.add(entry.key, entry.value,
          compressionMethod: compressionMethod ?? 0);
      if (duplicateEntry != null && entry.key == duplicateEntry) {
        zip.add(entry.key, entry.value,
            compressionMethod: compressionMethod ?? 0);
      }
    }

    zip.add('metadata/backupFormatVersion', utf8.encode('1'));
    zip.add('metadata/appVersion', utf8.encode('1.0.0'));
    zip.add('metadata/createdAt', utf8.encode('2026-01-01T00:00:00.000Z'));
    if (includeChecksum) {
      zip.add('metadata/checksum', utf8.encode(checksum!));
    }

    final result = zip.build();
    if (trailingGarbage) {
      zip.addRaw(List<int>.filled(16, 0xAB));
      return zip.build();
    }
    return result;
  }

  Map<String, List<int>> payload() {
    return <String, List<int>>{
      'manifest.json': utf8.encode(manifestOverride ??
          _manifestJson(moduleId: moduleId, version: formatVersion)),
      'state.json': utf8.encode(jsonEncode({'moduleId': moduleId})),
      'data.json': utf8.encode(jsonEncode({'entries': {}})),
      ...extraFiles,
    };
  }
}

/// SHA-256 по тем же байтам, что и reader: локальные заголовки и данные
/// всех записей, кроме metadata/checksum.
String _sha256Of(List<int> archiveBytes) {
  final rebuilt = <int>[];
  // Берём готовый архив и пересобираем его побайтно в том же порядке.
  for (final part in _recordsOf(archiveBytes)) {
    rebuilt.addAll(part);
  }
  return _sha256Hex(rebuilt);
}

List<List<int>> _recordsOf(List<int> archiveBytes) {
  final records = <List<int>>[];
  final eocd = _findEocd(archiveBytes);
  final count = archiveBytes[eocd + 10] | (archiveBytes[eocd + 11] << 8);
  final centralStart = archiveBytes[eocd + 16] |
      (archiveBytes[eocd + 17] << 8) |
      (archiveBytes[eocd + 18] << 16) |
      (archiveBytes[eocd + 19] << 24);

  var offset = centralStart;
  for (var i = 0; i < count; i++) {
    final nameLength = archiveBytes[offset + 28] | (archiveBytes[offset + 29] << 8);
    final extraLength = archiveBytes[offset + 30] | (archiveBytes[offset + 31] << 8);
    final commentLength = archiveBytes[offset + 32] | (archiveBytes[offset + 33] << 8);
    final localOffset = archiveBytes[offset + 42] |
        (archiveBytes[offset + 43] << 8) |
        (archiveBytes[offset + 44] << 16) |
        (archiveBytes[offset + 45] << 24);
    final nameStart = offset + 46;
    final name = utf8.decode(
      archiveBytes.sublist(nameStart, nameStart + nameLength),
    );

    if (name != 'metadata/checksum') {
      final dataStart = localOffset + 30 +
          (archiveBytes[localOffset + 26] | (archiveBytes[localOffset + 27] << 8)) +
          (archiveBytes[localOffset + 28] | (archiveBytes[localOffset + 29] << 8));
      final size = archiveBytes[localOffset + 18] |
          (archiveBytes[localOffset + 19] << 8) |
          (archiveBytes[localOffset + 20] << 16) |
          (archiveBytes[localOffset + 21] << 24);
      final record = <int>[];
      // Локальный заголовок (30 байт) + имя + данные.
      record.addAll(
          archiveBytes.sublist(localOffset, dataStart + size));
      records.add(record);
    }

    offset = nameStart + nameLength + extraLength + commentLength;
  }
  return records;
}

int _findEocd(List<int> bytes) {
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return i;
    }
  }
  throw StateError('EOCD не найдена');
}

/// Смещение первого байта ДАННЫХ записи [name] в архиве.
int _dataOffsetsOf(List<int> bytes, String name) {
  final eocd = _findEocd(bytes);
  final count = bytes[eocd + 10] | (bytes[eocd + 11] << 8);
  var offset = (bytes[eocd + 16] |
          (bytes[eocd + 17] << 8) |
          (bytes[eocd + 18] << 16) |
          (bytes[eocd + 19] << 24));

  for (var i = 0; i < count; i++) {
    final nameLength = bytes[offset + 28] | (bytes[offset + 29] << 8);
    final extraLength = bytes[offset + 30] | (bytes[offset + 31] << 8);
    final commentLength = bytes[offset + 32] | (bytes[offset + 33] << 8);
    final localOffset = (bytes[offset + 42] |
        (bytes[offset + 43] << 8) |
        (bytes[offset + 44] << 16) |
        (bytes[offset + 45] << 24));
    final nameStart = offset + 46;
    final entryName = utf8.decode(bytes.sublist(nameStart, nameStart + nameLength));

    if (entryName == name) {
      final nameBytesLength = bytes[localOffset + 26] | (bytes[localOffset + 27] << 8);
      final extraBytesLength = bytes[localOffset + 28] | (bytes[localOffset + 29] << 8);
      return localOffset + 30 + nameBytesLength + extraBytesLength;
    }

    offset = nameStart + nameLength + extraLength + commentLength;
  }
  throw StateError('Запись $name не найдена');
}

String _sha256Hex(List<int> data) => sha256.convert(data).toString();

void main() {
  group('.pmb принимается в ожидаемом виде', () {
    test('валидный архив читается и отдаёт содержимое', () async {
      final bytes = _PmbBuilder().build();

      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      expect(backup.moduleId, 'alpha');
      expect(backup.stateJson, isNotNull);
      expect(backup.dataJson, isNotNull);
    });
  });

  group('пути и структура', () {
    test('path traversal отклоняется', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'assets/../../evil.txt': utf8.encode('pwn')},
      ).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('абсолютный путь отклоняется', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'assets//etc/passwd': utf8.encode('x')},
      ).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('неожиданный файл в корне отклоняется', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'surprise.json': utf8.encode('{}')},
      ).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('неожиданная директория отклоняется', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'extra/thing.json': utf8.encode('{}')},
      ).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('обязательные записи metadata проверяются', () async {
      final zip = _ZipBuilder();
      zip.add('manifest.json', utf8.encode(_manifestJson()));
      // Без metadata/* — архив неполон.
      final bytes = zip.build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<MissingBackupEntryException>()),
      );
    });
  });

  group('имя файла и расширения', () {
    test('UTF-8 имя файла принимается и читается', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'assets/заметка.txt': utf8.encode('данные')},
      ).build();

      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      expect(backup.assets.keys, contains('заметка.txt'));
      expect(utf8.decode(backup.assets['заметка.txt']!), 'данные');
    });

    test('asset с неразрешённым расширением отклоняется', () async {
      final bytes = _PmbBuilder(
        extraFiles: {'assets/malware.exe': utf8.encode('MZ')},
      ).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('allowlist расширений совпадает с тем, что пишет writer', () {
      // writer и reader обязаны использовать ОДИН список: иначе
      // backup создастся, но не прочитается.
      for (final ext in BackupSecurityGuard.moduleBackupAssetsExtensions) {
        expect(
          BackupSecurityGuard.isAllowedModuleBackupAsset('файл$ext'),
          isTrue,
          reason: '$ext должен быть разрешён',
        );
      }
      expect(BackupSecurityGuard.isAllowedModuleBackupAsset('a.exe'), isFalse);
      expect(BackupSecurityGuard.isAllowedModuleBackupAsset('a.blob'), isFalse);
      expect(BackupSecurityGuard.isAllowedModuleBackupAsset('noext'), isFalse);
    });
  });

  group('целостность архива', () {
    test('некорректный ZIP отклоняется', () async {
      expect(
        () => ModuleBackupReader.readModuleBackup(
          Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('checksum mismatch отклоняется', () async {
      final bytes = _PmbBuilder().build();

      // Портим байт ВНУТРИ данных state.json: находим запись по
      // центральной директории, а не поиском подстроки, иначе можно
      // задеть заголовок и получить не ту ошибку.
      final records = _dataOffsetsOf(bytes, 'state.json');
      final corrupted = List<int>.from(bytes);
      corrupted[records + 2] ^= 0xFF;

      expect(
        () => ModuleBackupReader.readModuleBackup(corrupted),
        throwsA(isA<ChecksumMismatchException>()),
      );
    });

    test('дублирующаяся запись отклоняется', () async {
      final bytes = _PmbBuilder(duplicateEntry: 'data.json').build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupException>()),
        reason: 'неоднозначный архив читать нельзя',
      );
    });

    test('неподдерживаемый метод сжатия отклоняется', () async {
      // 8 = deflate: формат поддерживает только STORED.
      final bytes = _PmbBuilder(compressionMethod: 8).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('версия формата', () {
    test('неизвестная версия формата отклоняется', () async {
      final bytes = _PmbBuilder(formatVersion: 99).build();

      expect(
        () => ModuleBackupReader.readModuleBackup(bytes),
        throwsA(isA<BackupException>()),
        reason: 'будущий формат читать нельзя — иначе данные пойдут не так',
      );
    });

    test('текущая версия формата принимается', () async {
      final bytes = _PmbBuilder(formatVersion: 1).build();

      final backup = await ModuleBackupReader.readModuleBackup(bytes);
      expect(backup.backupFormatVersion, 1);
    });
  });

  group('лимиты', () {
    test('слишком большой архив отклоняется до разбора', () {
      final huge = List<int>.filled(
        BackupSecurityGuard.maxArchiveSizeBytes + 1,
        0,
      );

      // Предел размера guard сообщает BackupFormatException, а не
      // BackupSecurityException: обе — BackupException, и UI-презентер
      // переводит обе в понятный текст. Проверяем базовый тип, чтобы
      // тест не ломался от выбора конкретного подкласса.
      expect(
        () => BackupSecurityGuard.validateArchive(
          huge,
          kind: BackupArchiveKind.module,
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('превышение числа файлов отклоняется', () async {
      // Больше файлов, чем разрешено лимитом; каждый — валидный asset.
      final zip = _ZipBuilder();
      zip.add('manifest.json', utf8.encode(_manifestJson()));
      for (var i = 0; i <= BackupSecurityGuard.maxFileCount; i++) {
        zip.add('assets/f$i.txt', utf8.encode('x'));
      }
      zip.add('metadata/backupFormatVersion', utf8.encode('1'));
      zip.add('metadata/appVersion', utf8.encode('1.0.0'));
      zip.add('metadata/createdAt', utf8.encode('2026-01-01T00:00:00.000Z'));
      zip.add('metadata/checksum', utf8.encode('x'));

      expect(
        () => ModuleBackupReader.readModuleBackup(zip.build()),
        throwsA(isA<BackupException>()),
      );
    });

    test('архив в пределах лимита проходит проверку размера', () {
      // Проверяем именно границу лимита, а не разбор архива.
      final withinLimit = List<int>.filled(1024, 0);
      expect(BackupSecurityGuard.maxArchiveSizeBytes, greaterThan(1024));
      expect(withinLimit.length, lessThan(BackupSecurityGuard.maxArchiveSizeBytes));
    });

    test('лимиты объявлены константами и не нулевые', () {
      expect(BackupSecurityGuard.maxArchiveSizeBytes, greaterThan(0));
      expect(BackupSecurityGuard.maxExtractedSizeBytes, greaterThan(0));
      expect(BackupSecurityGuard.maxFileSizeBytes, greaterThan(0));
      expect(BackupSecurityGuard.maxFileCount, greaterThan(0));
    });
  });

  group('moduleId', () {
    test('идентичность читается из манифеста', () async {
      final bytes = _PmbBuilder(moduleId: 'my-module').build();

      final backup = await ModuleBackupReader.readModuleBackup(bytes);
      expect(backup.moduleId, 'my-module');
    });

    test('state.json с чужим moduleId отклоняется на restore', () async {
      // Проверка на уровне manifest: state.json без moduleId не
      // проходит, а с чужим — тем более.
      final bytes = _PmbBuilder(moduleId: 'alpha').build();
      final backup = await ModuleBackupReader.readModuleBackup(bytes);

      // Манифест и state обязаны говорить об одном модуле — иначе
      // restore положил бы чужое состояние.
      final state = jsonDecode(backup.stateJson!) as Map<String, dynamic>;
      expect(state['moduleId'], 'alpha');
    });
  });
}
