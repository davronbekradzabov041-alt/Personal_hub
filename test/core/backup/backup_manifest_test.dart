import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/backup/backup_manifest.dart';

void main() {
  group('BackupManifest', () {
    group('valid global manifest', () {
      test('parses valid global manifest', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': '2026-09-25T14:30:00Z',
          'type': 'global',
          'includedModules': ['schedule', 'example'],
          'options': {
            'includeModuleData': true,
            'includeAssets': true,
            'includeGlobalSettings': true,
          },
        };

        final manifest = BackupManifest.fromJson(json);
        expect(manifest.backupFormatVersion, 1);
        expect(manifest.appVersion, '1.0.0');
        expect(manifest.type, BackupType.global);
        expect(manifest.includedModules, ['schedule', 'example']);
        expect(manifest.options.includeModuleData, true);
        expect(manifest.options.includeAssets, true);
        expect(manifest.options.includeGlobalSettings, true);
      });

      test('serializes to JSON correctly', () {
        final manifest = BackupManifest(
          backupFormatVersion: 1,
          appVersion: '1.0.0',
          createdAt: DateTime.parse('2026-09-25T14:30:00Z'),
          type: BackupType.global,
          includedModules: ['schedule', 'example'],
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: false,
            includeGlobalSettings: true,
          ),
        );

        final json = manifest.toJson();
        expect(json['backupFormatVersion'], 1);
        expect(json['appVersion'], '1.0.0');
        expect(json['type'], 'global');
        expect(json['includedModules'], ['schedule', 'example']);
        expect(json['options']['includeModuleData'], true);
        expect(json['options']['includeAssets'], false);
        expect(json['options']['includeGlobalSettings'], true);
      });

      test('validates successfully', () {
        final manifest = BackupManifest(
          backupFormatVersion: 1,
          appVersion: '1.0.0',
          createdAt: DateTime.now(),
          type: BackupType.global,
          includedModules: ['schedule'],
          options: const BackupOptions(),
        );

        final violations = manifest.validate();
        expect(violations, isEmpty);
      });
    });

    group('invalid manifest', () {
      test('missing required field', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          // missing createdAt
          'type': 'global',
          'includedModules': ['schedule'],
          'options': {},
        };

        expect(
          () => BackupManifest.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('invalid backupFormatVersion type', () {
        final json = {
          'backupFormatVersion': '1', // string instead of int
          'appVersion': '1.0.0',
          'createdAt': '2026-09-25T14:30:00Z',
          'type': 'global',
          'includedModules': ['schedule'],
          'options': {},
        };

        expect(
          () => BackupManifest.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('invalid timestamp format', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': 'not-a-timestamp',
          'type': 'global',
          'includedModules': ['schedule'],
          'options': {},
        };

        expect(
          () => BackupManifest.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('invalid type', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': '2026-09-25T14:30:00Z',
          'type': 'invalid',
          'includedModules': ['schedule'],
          'options': {},
        };

        expect(
          () => BackupManifest.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('duplicate module IDs', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': '2026-09-25T14:30:00Z',
          'type': 'global',
          'includedModules': ['schedule', 'schedule'],
          'options': {},
        };

        expect(
          () => BackupManifest.fromJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('invalid module ID format', () {
        final json = {
          'backupFormatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': '2026-09-25T14:30:00Z',
          'type': 'global',
          'includedModules': ['../invalid'],
          'options': {},
        };

        final manifest = BackupManifest.fromJson(json);
        final violations = manifest.validate();
        expect(violations, contains('невалидный moduleId: ../invalid'));
      });

      test('unsupported backup format version', () {
        final manifest = BackupManifest(
          backupFormatVersion: 99,
          appVersion: '1.0.0',
          createdAt: DateTime.now(),
          type: BackupType.global,
          includedModules: ['schedule'],
          options: const BackupOptions(),
        );

        final violations = manifest.validate();
        expect(violations, contains('неподдерживаемая версия формата: 99'));
      });
    });

    group('toJson/toString', () {
      test('toJson produces valid JSON', () {
        final manifest = BackupManifest(
          backupFormatVersion: 1,
          appVersion: '1.0.0',
          createdAt: DateTime.parse('2026-09-25T14:30:00Z'),
          type: BackupType.global,
          includedModules: ['schedule'],
          options: const BackupOptions(
            includeModuleData: true,
            includeAssets: true,
            includeGlobalSettings: false,
          ),
        );

        final json = manifest.toJson();
        expect(json['backupFormatVersion'], 1);
        expect(json['type'], 'global');
        expect(json['options']['includeGlobalSettings'], false);
      });
    });
  });
}