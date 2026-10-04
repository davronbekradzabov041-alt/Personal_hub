/// SEC-01 (часть .phm): дублирующийся `manifest.json` в пакете.
///
/// `PackageReader._extractEntries` собирает записи в map, где последняя
/// побеждает, тогда как `PackageSecurityGuard` лишь отмечал факт наличия
/// манифеста. Два `manifest.json` означали, что проверялся один файл, а
/// импортировался другой. Теперь любой дубликат отклоняется до разбора.
library duplicate_manifest_package_test;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/platform/package_exceptions.dart';
import 'package:personal_hub/core/modules/platform/package_security_guard.dart';

/// Минимальный ZIP writer (STORED), допускающий две записи одного имени.
class _ZipBuilder {
  final List<int> _data = [];
  final List<_Entry> _entries = [];

  void addFile(String name, String content) {
    final nameBytes = utf8.encode(name);
    final data = utf8.encode(content);

    _u32(0x04034b50);
    _u16(20);
    _u16(0);
    _u16(0);
    _u16(0);
    _u16(0);
    _u32(_crc32(data));
    _u32(data.length);
    _u32(data.length);
    _u16(nameBytes.length);
    _u16(0);
    _data.addAll(nameBytes);
    _data.addAll(data);

    _entries.add(_Entry(name: name, nameBytes: nameBytes, data: data));
  }

  List<int> build() {
    final offsets = <String, int>{};
    for (final e in _entries) {
      offsets[e.name] = _data.length;
      _u32(0x04034b50);
      _u16(20);
      _u16(0);
      _u16(0);
      _u16(0);
      _u16(0);
      _u32(_crc32(e.data));
      _u32(e.data.length);
      _u32(e.data.length);
      _u16(e.nameBytes.length);
      _u16(0);
      _data.addAll(e.nameBytes);
      _data.addAll(e.data);
    }

    final centralStart = _data.length;
    for (final e in _entries) {
      _u32(0x02014b50);
      _u16(45);
      _u16(20);
      _u16(0);
      _u16(0);
      _u16(0);
      _u16(0);
      _u32(_crc32(e.data));
      _u32(e.data.length);
      _u32(e.data.length);
      _u16(e.nameBytes.length);
      _u16(0);
      _u16(0);
      _u16(0);
      _u16(0);
      _u32(0);
      _u32(offsets[e.name]!);
      _data.addAll(e.nameBytes);
    }
    final centralSize = _data.length - centralStart;

    _u32(0x06054b50);
    _u16(0);
    _u16(0);
    _u16(_entries.length);
    _u16(_entries.length);
    _u32(centralSize);
    _u32(centralStart);
    _u16(0);

    return _data;
  }

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
    required this.data,
  });

  final String name;
  final List<int> nameBytes;
  final List<int> data;
}

void main() {
  group('SEC-01 (.phm): дублирующийся manifest.json отклоняется', () {
    test('два манифеста с разным содержимым', () {
      final z = _ZipBuilder();
      z.addFile('manifest.json', '{"moduleId":"alpha"}');
      z.addFile('manifest.json', '{"moduleId":"beta"}');

      expect(
        () => PackageSecurityGuard.validateArchive(z.build()),
        throwsA(isA<InvalidPackageStructureException>()),
      );
    });

    test('обратный порядок отклоняется так же', () {
      final z = _ZipBuilder();
      z.addFile('manifest.json', '{"moduleId":"beta"}');
      z.addFile('manifest.json', '{"moduleId":"alpha"}');

      expect(
        () => PackageSecurityGuard.validateArchive(z.build()),
        throwsA(isA<InvalidPackageStructureException>()),
      );
    });

    test('битый манифест перед валидным не парсится вообще', () {
      final z = _ZipBuilder();
      z.addFile('manifest.json', '{"moduleId":');
      z.addFile('manifest.json', '{"moduleId":"alpha"}');

      expect(
        () => PackageSecurityGuard.validateArchive(z.build()),
        throwsA(isA<InvalidPackageStructureException>()),
      );
    });

    test('пакет с одним манифестом проходит без изменений', () {
      final z = _ZipBuilder();
      z.addFile('manifest.json', '{"moduleId":"alpha"}');

      expect(
        () => PackageSecurityGuard.validateArchive(z.build()),
        returnsNormally,
      );
    });
  });
}
