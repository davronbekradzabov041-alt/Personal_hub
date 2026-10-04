import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:personal_hub/core/modules/platform/module_storage_serializer.dart';
import 'package:personal_hub/core/modules/platform/serializer_exceptions.dart';
import 'package:personal_hub/core/modules/module_storage.dart';

/// In-memory implementation of ModuleStorage for testing.
class _TestModuleStorage implements ModuleStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<List<String>> keys() async => _data.keys.toList();

  // Test helper
  void clear() => _data.clear();
  void setAll(Map<String, String> data) => _data.addAll(data);
}

void main() {
  group('ModuleStorageSerializer', () {
    late _TestModuleStorage storage;

    setUp(() {
      storage = _TestModuleStorage();
    });

    group('serialize', () {
      test('empty storage', () async {
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('"version": 1'));
        expect(json, contains('"moduleId": "test-module"'));
        expect(json, contains('"entries": {}'));
      });

      test('one entry', () async {
        await storage.setString('key1', 'value1');
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('"key1": "value1"'));
      });

      test('multiple entries', () async {
        storage.setAll({'key1': 'value1', 'key2': 'value2', 'key3': 'value3'});
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('"key1": "value1"'));
        expect(json, contains('"key2": "value2"'));
        expect(json, contains('"key3": "value3"'));
      });

      test('unicode', () async {
        await storage.setString('ключ', 'значение 🎉');
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('ключ'));
        expect(json, contains('значение'));
        expect(json, contains('🎉'));
      });

      test('empty string value', () async {
        await storage.setString('empty', '');
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('"empty": ""'));
      });

      test('special characters', () async {
        await storage.setString('special', 'line1\nline2\ttab\r\ncr');
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );
        expect(json, contains('line1'));
        expect(json, contains('line2'));
      });

      test('version и moduleId в JSON', () async {
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'my-module',
        );
        final parsed = jsonDecode(json);
        expect(parsed['version'], 1);
        expect(parsed['moduleId'], 'my-module');
        expect(parsed['entries'], isA<Map>());
      });
    });

    group('deserialize', () {
      test('empty storage', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {}
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        expect(await storage.keys(), isEmpty);
      });

      test('one entry', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "key1": "value1"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        expect(await storage.getString('key1'), 'value1');
      });

      test('multiple entries', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "key1": "value1",
    "key2": "value2",
    "key3": "value3"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        expect(await storage.getString('key1'), 'value1');
        expect(await storage.getString('key2'), 'value2');
        expect(await storage.getString('key3'), 'value3');
      });

      test('unicode', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "ключ": "значение 🎉"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        expect(await storage.getString('ключ'), 'значение 🎉');
      });

      test('empty string value', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "empty": ""
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        expect(await storage.getString('empty'), '');
      });

      test('special characters', () async {
        const json = r'''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "special": "line1\nline2\ttab\r\ncr"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );
        // JSON decode converts \r\n to actual CRLF, \n to LF, \t to tab
        expect(await storage.getString('special'), 'line1\nline2\ttab\r\ncr');
      });

      test('removes keys not in new data', () async {
        // Pre-populate with extra keys
        storage.setAll({'key1': 'old1', 'key2': 'old2', 'key3': 'old3'});

        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "key1": "new1",
    "key2": "new2"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );

        expect(await storage.getString('key1'), 'new1');
        expect(await storage.getString('key2'), 'new2');
        expect(await storage.getString('key3'), isNull); // removed
      });

      test('preserves existing keys not in new data if not mentioned - actually removes them', () async {
        // This test confirms the behavior: deserialize replaces entire storage
        storage.setAll({'keep': 'value', 'remove': 'value'});

        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "keep": "value"
  }
}
''';
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );

        expect(await storage.getString('keep'), 'value');
        expect(await storage.getString('remove'), isNull);
      });
    });

    group('round-trip', () {
      test('serialize → deserialize preserves data', () async {
        storage.setAll({
          'key1': 'value1',
          'key2': 'value2',
          'key3': 'value3',
        });

        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );

        // Clear and deserialize
        storage.clear();
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );

        expect(await storage.getString('key1'), 'value1');
        expect(await storage.getString('key2'), 'value2');
        expect(await storage.getString('key3'), 'value3');
        expect(await storage.keys(), unorderedEquals(['key1', 'key2', 'key3']));
      });

      test('round-trip with unicode', () async {
        await storage.setString('ключ', 'значение 🎉');

        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );

        storage.clear();
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );

        expect(await storage.getString('ключ'), 'значение 🎉');
      });

      test('round-trip with empty storage', () async {
        final json = await ModuleStorageSerializer.serialize(
          storage: storage,
          moduleId: 'test-module',
        );

        storage.clear();
        await ModuleStorageSerializer.deserialize(
          jsonString: json,
          storage: storage,
          expectedModuleId: 'test-module',
        );

        expect(await storage.keys(), isEmpty);
      });
    });

    group('validation errors', () {
      test('invalid JSON', () async {
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: '{ not valid json }',
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<InvalidSerializerJsonException>()),
        );
      });

      test('JSON not object', () async {
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: '[1, 2, 3]',
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<NotJsonObjectException>()),
        );
      });

      test('missing version', () async {
        const json = '''
{
  "moduleId": "test-module",
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<MissingSerializerFieldException>()),
        );
      });

      test('unsupported version', () async {
        const json = '''
{
  "version": 99,
  "moduleId": "test-module",
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<UnsupportedSerializerVersionException>()),
        );
      });

      test('version not integer', () async {
        const json = '''
{
  "version": "1",
  "moduleId": "test-module",
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<InvalidSerializerJsonException>()),
        );
      });

      test('missing moduleId', () async {
        const json = '''
{
  "version": 1,
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<MissingSerializerFieldException>()),
        );
      });

      test('moduleId not string', () async {
        const json = '''
{
  "version": 1,
  "moduleId": 123,
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<InvalidSerializerJsonException>()),
        );
      });

      test('wrong moduleId', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "other-module",
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<ModuleIdMismatchException>()),
        );
      });

      test('missing entries', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module"
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<MissingSerializerFieldException>()),
        );
      });

      test('entries not object', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": ["key1", "key2"]
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<InvalidEntriesException>()),
        );
      });

      test('non-string key', () async {
        // JSON doesn't allow non-string keys, so the JSON parser fails first
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    123: "value"
  }
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<InvalidSerializerJsonException>()),
        );
      });

      test('non-string value', () async {
        const json = '''
{
  "version": 1,
  "moduleId": "test-module",
  "entries": {
    "key": 123
  }
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<NonStringValueException>()),
        );
      });

      test('unsupported version 0', () async {
        const json = '''
{
  "version": 0,
  "moduleId": "test-module",
  "entries": {}
}
''';
        expect(
          () => ModuleStorageSerializer.deserialize(
            jsonString: json,
            storage: storage,
            expectedModuleId: 'test-module',
          ),
          throwsA(isA<UnsupportedSerializerVersionException>()),
        );
      });
    });
  });
}