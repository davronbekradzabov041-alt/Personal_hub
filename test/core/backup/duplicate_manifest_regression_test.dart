/// SEC-01: differential parsing — дублирующийся `manifest.json` в .pbk.
///
/// Продовые парсеры выбирали РАЗНЫЕ записи с одинаковым именем:
/// `BackupSecurityGuard._extractFileBytes` линейным сканом берёт ПЕРВЫЙ
/// локальный заголовок, а `BackupReader._extractEntries` строит map из
/// центральной директории и перезаписывает — побеждает ПОСЛЕДНИЙ.
///
/// Итог: guard валидировал один манифест, а reader восстанавливал данные по
/// другому. Проверка checksum это не спасает — `_verifyChecksum` тоже
/// пересобирает данные через map, поэтому последний дубликат проходит и там.
///
/// Контракт после фикса: любой дубликат `manifest.json` отклоняется
/// независимо от порядка и содержимого записей.
library duplicate_manifest_regression_test;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_exceptions.dart';
import 'package:personal_hub/core/backup/backup_reader.dart';
import 'package:personal_hub/core/backup/backup_security_guard.dart';

/// Валидный манифест с произвольным списком модулей.
String _manifestJson(List<String> modules) => jsonEncode({
      'backupFormatVersion': 1,
      'appVersion': '1.0.0',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'type': 'global',
      'includedModules': modules,
      'options': {
        'includeModuleData': true,
        'includeAssets': true,
        'includeGlobalSettings': true,
      },
    });

/// Обрезанный JSON — не проходит `jsonDecode`.
const String _malformedManifest = '{"includedModules": ["alpha"';

/// Минимальный ZIP writer (STORED) с намеренной возможностью дописать
/// вторую запись с тем же именем.
///
/// Раскладка полей повторяет продовый writer: иначе тест проверял бы не тот
/// формат, который читает приложение.
class _PbkBuilder {
  final List<int> _data = [];
  final List<_Entry> _entries = [];

  void add(String name, List<int> bytes) {
    final localOffset = _data.length;
    final nameBytes = utf8.encode(name);
    final crc = _crc32(bytes);

    _u32(0x04034b50); // 0  signature
    _u16(20); // 4  version needed
    _u16(0); // 6  general purpose flags
    _u16(0); // 8  method (stored)
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
      size: bytes.length,
      crc: crc,
      data: bytes,
    ));
  }

  void addText(String name, String content) => add(name, utf8.encode(content));

  /// Собирает архив целиком, дописывая `metadata/checksum`.
  ///
  /// Контрольная сумма считается ровно так, как её пересобирает
  /// `BackupReader._verifyChecksum`: по центральной директории, с
  /// last-wins выбором данных и без самой записи checksum. Благодаря этому
  /// архив с дубликатом проходит проверку целостности — то есть ошибка
  /// действительно в выборе манифеста, а не в checksum.
  List<int> build() {
    _addChecksumPlaceholder();
    final checksum = _computeChecksum();

    // Пересобираем архив с настоящей суммой на месте placeholder'а.
    final entriesWithoutChecksum = _entries
        .where((e) => e.name != 'metadata/checksum')
        .toList();
    return _writeArchive(entriesWithoutChecksum, checksum);
  }

  void _addChecksumPlaceholder() {
    addText('metadata/checksum', '');
  }

  String _computeChecksum() {
    final lastWins = <String, _Entry>{};
    for (final e in _entries) {
      if (e.name == 'metadata/checksum') continue;
      lastWins[e.name] = e; // last-wins, как в BackupReader
    }

    final reconstructed = <int>[];
    for (final e in _entries) {
      if (e.name == 'metadata/checksum') continue;
      final data = lastWins[e.name]!;
      _u32To(reconstructed, 0x04034b50);
      _u16To(reconstructed, 20);
      _u16To(reconstructed, 0);
      _u16To(reconstructed, 0);
      _u16To(reconstructed, 0);
      _u16To(reconstructed, 0);
      _u32To(reconstructed, data.crc);
      _u32To(reconstructed, data.size);
      _u32To(reconstructed, data.size);
      _u16To(reconstructed, data.nameBytes.length);
      _u16To(reconstructed, 0);
      reconstructed.addAll(data.nameBytes);
      reconstructed.addAll(data.data);
    }
    return sha256.convert(reconstructed).toString();
  }

  List<int> _writeArchive(List<_Entry> entries, String checksum) {
    final out = <int>[];
    final offsets = <String, int>{};

    void u16(int v) {
      out.add(v & 0xff);
      out.add((v >> 8) & 0xff);
    }

    void u32(int v) {
      out.add(v & 0xff);
      out.add((v >> 8) & 0xff);
      out.add((v >> 16) & 0xff);
      out.add((v >> 24) & 0xff);
    }

    for (final e in entries) {
      offsets[e.name] = out.length;
      final data = e.name == 'metadata/checksum'
          ? utf8.encode(checksum)
          : e.data;
      u32(0x04034b50);
      u16(20);
      u16(0);
      u16(0);
      u16(0);
      u16(0);
      u32(_crc32(data));
      u32(data.length);
      u32(data.length);
      u16(e.nameBytes.length);
      u16(0);
      out.addAll(e.nameBytes);
      out.addAll(data);
    }

    final centralStart = out.length;
    for (final e in entries) {
      final data = e.name == 'metadata/checksum'
          ? utf8.encode(checksum)
          : e.data;
      u32(0x02014b50);
      u16(45); // version made by
      u16(20); // version needed
      u16(0); // flags
      u16(0); // method
      u16(0); // mod time
      u16(0); // mod date
      u32(_crc32(data));
      u32(data.length);
      u32(data.length);
      u16(e.nameBytes.length);
      u16(0); // extra
      u16(0); // comment
      u16(0); // disk
      u16(0); // internal attrs
      u32(0); // external attrs
      u32(offsets[e.name]!);
      out.addAll(e.nameBytes);
    }
    final centralSize = out.length - centralStart;

    u32(0x06054b50);
    u16(0); // disk
    u16(0); // central dir disk
    u16(entries.length); // records on disk
    u16(entries.length); // total records
    u32(centralSize);
    u32(centralStart);
    u16(0); // comment length

    return out;
  }

  // ── low-level ────────────────────────────────────────────────────────────

  void _u16(int v) {
    _data.add(v & 0xff);
    _data.add((v >> 8) & 0xff);
  }

  void _u32(int v) {
    _data.add(v & 0xff);
    _data.add((v >> 8) & 0xff);
    _data.add((v >> 16) & 0xff);
    _data.add((v >> 24) & 0xff);
  }

  static void _u16To(List<int> out, int v) {
    out.add(v & 0xff);
    out.add((v >> 8) & 0xff);
  }

  static void _u32To(List<int> out, int v) {
    out.add(v & 0xff);
    out.add((v >> 8) & 0xff);
    out.add((v >> 16) & 0xff);
    out.add((v >> 24) & 0xff);
  }

  /// Базовая карта CRC-32 (IEEE 802.3), полином 0xEDB88320.
  static int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _Entry {
  _Entry({
    required this.name,
    required this.nameBytes,
    required this.localOffset,
    required this.size,
    required this.crc,
    required this.data,
  });

  final String name;
  final List<int> nameBytes;
  final int localOffset;
  final int size;
  final int crc;
  final List<int> data;
}

/// Базовая валидная структура .pbk без дубликатов.
_PbkBuilder _validArchive() {
  final b = _PbkBuilder();
  b.addText('manifest.json', _manifestJson(['alpha']));
  b.addText('metadata/backupFormatVersion', '1');
  b.addText('metadata/appVersion', '1.0.0');
  b.addText('metadata/createdAt', '2026-01-01T00:00:00.000Z');
  return b;
}

void main() {
  group('SEC-01: дублирующийся manifest.json отклоняется guard\'ом', () {
    test('порядок валидный → битый', () {
      final b = _validArchive();
      b.addText('manifest.json', _malformedManifest);

      expect(
        () => BackupSecurityGuard.validateArchive(b.build()),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('порядок битый → валидный', () {
      final b = _PbkBuilder();
      b.addText('manifest.json', _malformedManifest);
      b.addText('metadata/backupFormatVersion', '1');
      b.addText('metadata/appVersion', '1.0.0');
      b.addText('metadata/createdAt', '2026-01-01T00:00:00.000Z');
      b.addText('manifest.json', _manifestJson(['alpha']));

      expect(
        () => BackupSecurityGuard.validateArchive(b.build()),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('два валидных манифеста с разным содержимым', () {
      final b = _validArchive();
      b.addText('manifest.json', _manifestJson(['beta']));

      expect(
        () => BackupSecurityGuard.validateArchive(b.build()),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('SEC-01: сквозной путь чтения .pbk', () {
    test('дубликат манифеста с разным содержимым не восстанавливается', () async {
      final b = _validArchive();
      b.addText('manifest.json', _manifestJson(['beta']));

      await expectLater(
        BackupReader.readGlobalBackup(b.build(), existingModuleIds: {}),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('дубликат манифеста не проходит и при обратном порядке', () async {
      final b = _PbkBuilder();
      b.addText('manifest.json', _manifestJson(['beta']));
      b.addText('metadata/backupFormatVersion', '1');
      b.addText('metadata/appVersion', '1.0.0');
      b.addText('metadata/createdAt', '2026-01-01T00:00:00.000Z');
      b.addText('manifest.json', _manifestJson(['alpha']));

      await expectLater(
        BackupReader.readGlobalBackup(b.build(), existingModuleIds: {}),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('SEC-01: специфичность — дубликатов нет', () {
    test('архив с одним манифестом проходит guard', () {
      expect(
        () => BackupSecurityGuard.validateArchive(_validArchive().build()),
        returnsNormally,
      );
    });

    test('архив без manifest.json отклоняется как раньше', () {
      final b = _PbkBuilder();
      b.addText('metadata/backupFormatVersion', '1');
      b.addText('metadata/appVersion', '1.0.0');
      b.addText('metadata/createdAt', '2026-01-01T00:00:00.000Z');

      expect(
        () => BackupSecurityGuard.validateArchive(b.build()),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });
}
