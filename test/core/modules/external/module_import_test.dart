import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/external/manifest_parser.dart';
import 'package:personal_hub/core/modules/external/manifest_validator.dart';
import 'package:personal_hub/core/modules/external/module_import_result.dart';

const _validManifestJson = '''
{
  "id": "notes-lite",
  "name": "Notes Lite",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Jane Doe",
  "description": "A simple external notes module (example).",
  "permissions": ["core.search"],
  "dependencies": [],
  "icon": "assets/icon.png"
}
''';

void main() {
  group('ManifestParser', () {
    final parser = ManifestParser();

    test('разбирает валидный manifest.json', () {
      final manifest = parser.parse(_validManifestJson);
      expect(manifest.id, 'notes-lite');
      expect(manifest.name, 'Notes Lite');
      expect(manifest.apiVersion, 1);
      expect(manifest.permissions.map((p) => p.id), ['core.search']);
    });

    test('повреждённый JSON', () {
      expect(
        () => parser.parse('{ not valid json'),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('JSON, но не объект верхнего уровня', () {
      expect(
        () => parser.parse('[1, 2, 3]'),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('отсутствующие поля перечисляются в сообщении', () {
      const json = '{"id": "x", "name": "X"}';
      try {
        parser.parse(json);
        fail('должно было бросить ManifestParseException');
      } on ManifestParseException catch (e) {
        expect(e.message, contains('version'));
        expect(e.message, contains('apiVersion'));
        expect(e.message, contains('permissions'));
      }
    });

    test('пустой id', () {
      final json = _validManifestJson.replaceFirst('"notes-lite"', '""');
      expect(
        () => parser.parse(json),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('неверная версия API — не число', () {
      final json =
          _validManifestJson.replaceFirst('"apiVersion": 1', '"apiVersion": "1"');
      expect(
        () => parser.parse(json),
        throwsA(isA<ManifestParseException>()),
      );
    });
  });

  group('ManifestValidator', () {
    final parser = ManifestParser();
    final validator = ManifestValidator();

    test('валидный манифест — список ошибок пуст', () {
      final manifest = parser.parse(_validManifestJson);
      final errors = validator.validate(manifest, existingModuleIds: const {});
      expect(errors, isEmpty);
    });

    test('дублирующийся moduleId', () {
      final manifest = parser.parse(_validManifestJson);
      final errors = validator.validate(
        manifest,
        existingModuleIds: const {'notes-lite'},
      );
      expect(errors.any((e) => e.contains('уже занят')), isTrue);
    });

    test('неподдерживаемая версия manifest — apiVersion вне диапазона', () {
      final json =
          _validManifestJson.replaceFirst('"apiVersion": 1', '"apiVersion": 99');
      final manifest = parser.parse(json);
      final errors = validator.validate(manifest, existingModuleIds: const {});
      expect(errors.any((e) => e.contains('неподдерживаемая версия')), isTrue);
    });

    test('циклические зависимости — простой цикл a→b→c→a', () {
      final cycles = validator.findDependencyCycles({
        'a': ['b'],
        'b': ['c'],
        'c': ['a'],
      });
      expect(cycles, isNotEmpty);
    });

    test('циклические зависимости — самоссылка', () {
      final cycles = validator.findDependencyCycles({
        'a': ['a'],
      });
      expect(cycles, isNotEmpty);
    });

    test('циклические зависимости — граф без циклов', () {
      final cycles = validator.findDependencyCycles({
        'a': ['b'],
        'b': ['c'],
        'c': [],
      });
      expect(cycles, isEmpty);
    });

    test('циклические зависимости — пустой граф (текущее состояние приложения)', () {
      final cycles = validator.findDependencyCycles(const {});
      expect(cycles, isEmpty);
    });
  });

  group('ModuleImportResult.from', () {
    test('успешный импорт', () {
      final result = ModuleImportResult.from(
        manifestJson: _validManifestJson,
        existingModuleIds: const {},
      );
      expect(result.isSuccess, isTrue);
      expect(result.package, isNotNull);
      expect(result.package!.manifest.id, 'notes-lite');
    });

    test('отказ при повреждённом JSON', () {
      final result = ModuleImportResult.from(
        manifestJson: '{ broken',
        existingModuleIds: const {},
      );
      expect(result.isSuccess, isFalse);
      expect(result.package, isNull);
      expect(result.errors, isNotEmpty);
    });

    test('отказ при дублирующемся id', () {
      final result = ModuleImportResult.from(
        manifestJson: _validManifestJson,
        existingModuleIds: const {'notes-lite'},
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors.any((e) => e.contains('уже занят')), isTrue);
    });
  });
}
