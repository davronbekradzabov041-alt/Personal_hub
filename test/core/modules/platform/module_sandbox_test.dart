import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/modules/platform/sandbox_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModuleSandbox', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('phm_sandbox_test_');
    });

    tearDownAll(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    group('Module ID validation', () {
      test('valid moduleId проходит', () {
        expect(() => ModuleSandbox.validateModuleId('example'), returnsNormally);
        expect(() => ModuleSandbox.validateModuleId('my-module'), returnsNormally);
        expect(() => ModuleSandbox.validateModuleId('module123'), returnsNormally);
        expect(() => ModuleSandbox.validateModuleId('a'), returnsNormally);
      });

      test('пустой moduleId отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId(''),
          throwsA(isA<InvalidModuleIdException>()),
        );
        expect(
          () => ModuleSandbox.validateModuleId('   '),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('path traversal отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('../evil'),
          throwsA(isA<InvalidModuleIdException>()),
        );
        expect(
          () => ModuleSandbox.validateModuleId('../../outside'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('absolute path отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('/absolute/path'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('Windows absolute path отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId(r'C:\outside'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('backslash отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('foo\bar'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('moduleId с / отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('foo/bar'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('control characters отклоняются', () {
        expect(
          () => ModuleSandbox.validateModuleId('module\x00'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('слишком длинный moduleId отклоняется', () {
        final longId = 'a' * 101;
        expect(
          () => ModuleSandbox.validateModuleId(longId),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      // AUD-37 + AUD-56: moduleId = "." проходил валидацию, потому что
      // не содержит "..", не является абсолютным путём и не имеет
      // разделителей. Но path.join(родитель, '.') схлопывается в сам
      // родительский каталог — то есть в каталог со ВСЕМИ песочницами
      // модулей. Для недоверенного .phm это превращалось в
      // delete(recursive: true) по данным всех установленных модулей.
      test('"." отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('.'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('".." отклоняется', () {
        expect(
          () => ModuleSandbox.validateModuleId('..'),
          throwsA(isA<InvalidModuleIdException>()),
        );
      });

      test('встроенная точка в имени модуля разрешена', () {
        // Точка сама по себе не запрещена — запрещены только
        // относительные компоненты пути целиком. Иначе сломались бы
        // валидные id вроде "ru.example.module".
        expect(() => ModuleSandbox.validateModuleId('ru.example.module'), returnsNormally);
        expect(() => ModuleSandbox.validateModuleId('a.b'), returnsNormally);
        expect(() => ModuleSandbox.validateModuleId('.hidden'), returnsNormally);
      });
    });

    // AUD-37 + AUD-56: проверяем последствие, а не только факт
    // исключения — тест создаёт реальные песочницы и убеждается, что
    // они физически уцелели.
    group('AUD-37/AUD-56: dot-id не уничтожает чужие песочницы', () {
      test('deleteModuleForTesting с "." отказывается и не трогает каталоги', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('alpha', tempDir);
        await ModuleSandbox.ensureModuleDirectoriesForTesting('beta', tempDir);
        await File('${tempDir.path}${Platform.pathSeparator}modules'
            '${Platform.pathSeparator}alpha'
            '${Platform.pathSeparator}marker.txt').writeAsString('данные alpha');

        await expectLater(
          ModuleSandbox.deleteModuleForTesting('.', tempDir),
          throwsA(isA<InvalidModuleIdException>()),
        );

        // Обе песочницы обязаны остаться на месте целиком.
        expect(
          await ModuleSandbox.existsForTesting('alpha', tempDir),
          isTrue,
          reason: 'песочница alpha не должна пострадать от отказа',
        );
        expect(
          await ModuleSandbox.existsForTesting('beta', tempDir),
          isTrue,
          reason: 'песочница beta не должна пострадать от отказа',
        );
        final marker = File('${tempDir.path}${Platform.pathSeparator}modules'
            '${Platform.pathSeparator}alpha'
            '${Platform.pathSeparator}marker.txt');
        expect(await marker.readAsString(), 'данные alpha',
            reason: 'содержимое песочницы обязано уцелеть побайтово');
      });

      test('".." отказывается и не поднимает удаление выше каталога модулей', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('gamma', tempDir);
        final sentinel = File('${tempDir.path}${Platform.pathSeparator}sentinel.txt');
        await sentinel.writeAsString('вне modules');

        await expectLater(
          ModuleSandbox.deleteModuleForTesting('..', tempDir),
          throwsA(isA<InvalidModuleIdException>()),
        );

        expect(await ModuleSandbox.existsForTesting('gamma', tempDir), isTrue);
        expect(await sentinel.exists(), isTrue,
            reason: 'файл вне каталога модулей не должен удаляться');
      });

      test('ensureModuleDirectories с "." не создаёт ничего вне ожидаемого', () async {
        await expectLater(
          ModuleSandbox.ensureModuleDirectoriesForTesting('.', tempDir),
          throwsA(isA<InvalidModuleIdException>()),
        );
        expect(await Directory(tempDir.path).exists(), isTrue);
      });
    });

    group('Path operations (with test override)', () {
      test('getModuleRootForTesting возвращает правильный путь', () async {
        final root = await ModuleSandbox.getModuleRootForTesting('test-module', tempDir);
        expect(root.path, contains('modules${Platform.pathSeparator}test-module'));
        expect(root.path, endsWith('test-module'));
      });

      test('getAssetsDirectoryForTesting возвращает правильный путь', () async {
        final assets = await ModuleSandbox.getAssetsDirectoryForTesting('test-module', tempDir);
        expect(assets.path, contains('modules${Platform.pathSeparator}test-module${Platform.pathSeparator}assets'));
        expect(assets.path, endsWith('assets'));
      });

      test('ensureModuleDirectoriesForTesting создает директории', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('new-module', tempDir);
        final root = await ModuleSandbox.getModuleRootForTesting('new-module', tempDir);
        final assets = await ModuleSandbox.getAssetsDirectoryForTesting('new-module', tempDir);
        expect(await root.exists(), true);
        expect(await assets.exists(), true);
      });

      test('повторный ensureModuleDirectoriesForTesting не ломает существующий sandbox', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('existing-module', tempDir);
        await ModuleSandbox.ensureModuleDirectoriesForTesting('existing-module', tempDir);
        final root = await ModuleSandbox.getModuleRootForTesting('existing-module', tempDir);
        expect(await root.exists(), true);
      });

      test('existsForTesting возвращает false для несуществующего', () async {
        final exists = await ModuleSandbox.existsForTesting('non-existent-module-xyz', tempDir);
        expect(exists, false);
      });

test('existsForTesting возвращает true после создания', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('exists-test', tempDir);
        final exists = await ModuleSandbox.existsForTesting('exists-test', tempDir);
        expect(exists, true);
      });

test('deleteModuleForTesting удаляет sandbox', () async {
        await ModuleSandbox.ensureModuleDirectoriesForTesting('to-delete', tempDir);
        await ModuleSandbox.deleteModuleForTesting('to-delete', tempDir);
        final exists = await ModuleSandbox.existsForTesting('to-delete', tempDir);
        expect(exists, false);
      });

      test('повторное deleteModuleForTesting не падает', () async {
        await ModuleSandbox.deleteModuleForTesting('non-existent', tempDir);
        expect(true, true); // no exception
      });

      test('listModuleIds работает', () async {
        // Just verify it doesn't crash and returns empty list for clean temp dir
        final list = await ModuleSandbox.listModuleIdsForTesting(tempDir);
        expect(list, isA<List<String>>());
      });
    });
  });
}