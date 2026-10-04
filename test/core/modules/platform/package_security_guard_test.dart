import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/platform/package_security_guard.dart';
import 'package:personal_hub/core/modules/platform/package_exceptions.dart';
import 'package:personal_hub/core/modules/platform/package_writer.dart';
import 'package:personal_hub/core/modules/platform/package_content.dart';
import 'package:personal_hub/core/modules/module_manifest.dart';
import 'dart:convert';

void main() {
  group('PackageSecurityGuard', () {
    group('Valid archives', () {
      test('минимальный валидный .phm (только manifest.json)', () {
        final content = _createTestContent();
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('пакет с README.md', () {
        final content = _createTestContent(readme: '# Test Module');
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('пакет с assets/icon.png', () {
        final content = _createTestContent(assets: {'assets/icon.png': List.filled(100, 0xFF)});
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('пакет с data/storage.json', () {
        final content = _createTestContent(storage: {'note': 'test'});
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('комбинация всех разрешённых компонентов', () {
        final content = _createTestContent(
          readme: '# Readme',
          assets: {
            'assets/icon.png': List.filled(50, 0x00),
            'assets/data.json': utf8.encode('{"key": "value"}'),
            'assets/image.webp': List.filled(200, 0xAA),
          },
          storage: {'settings': {'theme': 'dark'}},
        );
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });
    });

    group('Security: Size limits', () {
      test('> 100 файлов', () {
        final assets = <String, List<int>>{};
        for (int i = 0; i < 101; i++) {
          assets['assets/file$i.txt'] = [0x00];
        }
        final content = _createTestContent(assets: assets);
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => PackageSecurityGuard.validateArchive(bytes),
          throwsA(isA<TooManyFilesException>()),
        );
      });

      test('archive > 20 MB', () {
        final content = _createTestContent(assets: {'assets/large.bin': List.filled(21 * 1024 * 1024, 0xFF)});
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => PackageSecurityGuard.validateArchive(bytes),
          throwsA(isA<ArchiveTooLargeException>()),
        );
      });

      test('отдельный файл > 10 MB', () {
        final content = _createTestContent(assets: {'assets/large.bin': List.filled(11 * 1024 * 1024, 0xFF)});
        final bytes = ModulePackageWriter.write(content);
        expect(
          () => PackageSecurityGuard.validateArchive(bytes),
          throwsA(isA<FileTooLargeException>()),
        );
      });
    });

    group('Security: Path traversal (malformed ZIP - skipped, requires valid ZIP)', () {
      test('security guard парсит EOCD корректно', () {
        // Test that the security guard can at least parse a valid ZIP
        final content = _createTestContent();
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });
    });

    group('Icon validation', () {
      test('валидный assets/icon.png', () {
        final content = _createTestContent(assets: {'assets/icon.png': List.filled(100, 0xFF)});
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('system: иконка в manifest — проходит на уровне guard', () {
        // Guard only validates archive structure, not manifest content.
        // Manifest validation is done by ManifestValidator separately.
        final manifest = _minimalManifest(icon: 'system:event_note');
        final content = _createTestContentFromManifest(manifest);
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('manifest.icon указывает на отсутствующий asset — guard пропускает', () {
        // Guard validates structure, not cross-references.
        // Missing asset reference is caught by Importer/ModuleStore later.
        final manifest = _minimalManifest(icon: 'assets/missing.png');
        final content = _createTestContentFromManifest(manifest);
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('../icon.png в manifest.icon — guard пропускает (путь в строке)', () {
        // The icon field is a string in manifest; guard doesn't parse manifest content.
        final manifest = _minimalManifest(icon: '../icon.png');
        final content = _createTestContentFromManifest(manifest);
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });

      test('некорректный system: identifier — guard пропускает', () {
        final manifest = _minimalManifest(icon: 'system:invalid');
        final content = _createTestContentFromManifest(manifest);
        final bytes = ModulePackageWriter.write(content);
        expect(() => PackageSecurityGuard.validateArchive(bytes), returnsNormally);
      });
    });
  });
}

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

PackageContent _createTestContentFromManifest(String manifestJson) {
  final manifest = ModuleManifest.fromJson(jsonDecode(manifestJson));
  return PackageContent(manifest: manifest);
}