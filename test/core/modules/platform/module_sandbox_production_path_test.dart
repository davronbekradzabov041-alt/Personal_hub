/// TEST-01: покрытие production-path песочницы модуля.
///
/// `module_sandbox_test.dart` проверяет только `*ForTesting`-обёртки: они
/// получают `supportDir` параметром и строят путь сами. Production-методы
/// (`ModuleSandbox.getModuleRoot`, `ensureModuleDirectories`, `exists`,
/// `deleteModule`, `listModuleIds`, `getAssetsDirectory`) в этом файле не
/// вызывались ни разу — а именно их использует приложение. Расхождение
/// между двумя наборами путей оставалось незамеченным.
///
/// Здесь подменяется ТОЛЬКО платформенный канал `path_provider` (тот же
/// приём, что и в production-тестах импорта/бэкапа). Всё остальное —
/// настоящий ModuleSandbox: production-код сам вызывает
/// `getApplicationDocumentsDirectory()` и сам собирает путь.
///
/// Отдельная группа сверяет production-пути с `*ForTesting`-обёртками:
/// именно это сравнение ломается, если production-разметка песочницы
/// разойдётся с тестовой.
library module_sandbox_production_path_test;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_hub/core/modules/platform/module_sandbox.dart';
import 'package:personal_hub/core/modules/platform/sandbox_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDocuments;
  late Directory personalHubRoot;

  setUp(() async {
    appDocuments = await Directory.systemTemp.createTemp('sandbox_prod_docs_');
    personalHubRoot = Directory(path.join(appDocuments.path, 'personal_hub_modules'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => appDocuments.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (appDocuments.existsSync()) {
      appDocuments.deleteSync(recursive: true);
    }
  });

  group('TEST-01: production-путь песочницы', () {
    test('getModuleRoot/getAssetsDirectory не создают каталоги', () async {
      final root = await ModuleSandbox.getModuleRoot('alpha');
      final assets = await ModuleSandbox.getAssetsDirectory('alpha');

      // Реальный персистентный путь приложения:
      // <Documents>/personal_hub_modules/modules/<moduleId>/assets
      expect(root.path,
          path.join(personalHubRoot.path, 'modules', 'alpha'));
      expect(assets.path, path.join(root.path, 'assets'));

      // Оба метода только вычисляют путь — ничего не создано.
      expect(await root.exists(), isFalse);
      expect(await assets.exists(), isFalse);
    });

    test('ensureModuleDirectories создаёт layout и он реально на диске',
        () async {
      expect(await ModuleSandbox.exists('alpha'), isFalse);

      await ModuleSandbox.ensureModuleDirectories('alpha');

      expect(await ModuleSandbox.exists('alpha'), isTrue);

      final root = await ModuleSandbox.getModuleRoot('alpha');
      final assets = await ModuleSandbox.getAssetsDirectory('alpha');

      // Проверяем настоящую файловую систему, а не только объект Directory.
      expect(Directory(root.path).existsSync(), isTrue,
          reason: 'production-путь обязан существовать на диске');
      expect(Directory(assets.path).existsSync(), isTrue);
      expect(
        root.path,
        path.join(appDocuments.path, 'personal_hub_modules', 'modules', 'alpha'),
        reason: 'песочница лежит под Documents, а не во временной папке теста',
      );
    });

    test('ensureModuleDirectories идемпотентна и сохраняет содержимое',
        () async {
      await ModuleSandbox.ensureModuleDirectories('alpha');
      final assets = await ModuleSandbox.getAssetsDirectory('alpha');
      await File(path.join(assets.path, 'note.txt')).writeAsString('payload');

      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.ensureModuleDirectories('alpha');

      expect(
        File(path.join(assets.path, 'note.txt')).readAsStringSync(),
        'payload',
        reason: 'повторный вызов не должен затирать файлы модуля',
      );
    });

    test('песочницы модулей изолированы друг от друга', () async {
      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.ensureModuleDirectories('beta');

      final alphaAssets = await ModuleSandbox.getAssetsDirectory('alpha');
      final betaAssets = await ModuleSandbox.getAssetsDirectory('beta');

      expect(alphaAssets.path == betaAssets.path, isFalse);
      expect(
        alphaAssets.path,
        path.join(personalHubRoot.path, 'modules', 'alpha', 'assets'),
      );
      expect(
        betaAssets.path,
        path.join(personalHubRoot.path, 'modules', 'beta', 'assets'),
      );
    });

    test('listModuleIds возвращает созданные песочницы', () async {
      expect(await ModuleSandbox.listModuleIds(), isEmpty,
          reason: 'до создания песочниц каталога modules нет');

      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.ensureModuleDirectories('beta');

      final ids = (await ModuleSandbox.listModuleIds())..sort();
      expect(ids, ['alpha', 'beta']);
    });

    test('deleteModule удаляет песочницу целиком и не трогает соседей',
        () async {
      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.ensureModuleDirectories('beta');
      final alphaAssets = await ModuleSandbox.getAssetsDirectory('alpha');
      await File(path.join(alphaAssets.path, 'gone.txt')).writeAsString('x');

      await ModuleSandbox.deleteModule('alpha');

      expect(await ModuleSandbox.exists('alpha'), isFalse);
      expect(
        Directory(alphaAssets.path).existsSync(),
        isFalse,
        reason: 'рекурсивное удаление должно унести вложенные файлы',
      );
      expect(await ModuleSandbox.exists('beta'), isTrue,
          reason: 'удаление одного модуля не затрагивает другой');
    });

    test('deleteModule идемпотентна для несуществующей песочницы', () async {
      await expectLater(ModuleSandbox.deleteModule('ghost'), completes);
      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.deleteModule('alpha');
      await expectLater(ModuleSandbox.deleteModule('alpha'), completes);
    });
  });

  group('TEST-01: ограничения на реальном production-пути', () {
    // Валидация — единственное, что не даёт модулю выйти за пределы
    // своей песочницы. Проверяем её НА НАСТОЯЩИХ методах: каждый из них
    // обязан отказать ДО касания файловой системы.
    const hostileIds = <String, String>{
      '': 'пустой id',
      '   ': 'только пробелы',
      '.': 'относительный путь, схлопывающийся в родителя',
      '..': 'path traversal',
      '../evil': 'path traversal вверх',
      'a/b': 'разделитель путей',
      'a\\b': 'обратный слэш',
      'C:\\Windows': 'абсолютный путь Windows',
      '/etc': 'абсолютный путь Unix',
      'a\u0001b': 'управляющий символ',
    };

    test('все production-методы отказывают на небезопасном moduleId', () async {
      for (final entry in hostileIds.entries) {
        final id = entry.key;
        final why = entry.value;

        await expectLater(
          ModuleSandbox.getModuleRoot(id),
          throwsA(isA<InvalidModuleIdException>()),
          reason: 'getModuleRoot должен отказать: $why',
        );
        await expectLater(
          ModuleSandbox.getAssetsDirectory(id),
          throwsA(isA<InvalidModuleIdException>()),
          reason: 'getAssetsDirectory должен отказать: $why',
        );
        await expectLater(
          ModuleSandbox.ensureModuleDirectories(id),
          throwsA(isA<InvalidModuleIdException>()),
          reason: 'ensureModuleDirectories должен отказать: $why',
        );
        await expectLater(
          ModuleSandbox.exists(id),
          throwsA(isA<InvalidModuleIdException>()),
          reason: 'exists должен отказать: $why',
        );
        await expectLater(
          ModuleSandbox.deleteModule(id),
          throwsA(isA<InvalidModuleIdException>()),
          reason: 'deleteModule должен отказать: $why',
        );
      }
    });

    test('слишком длинный moduleId отвергается', () async {
      await expectLater(
        ModuleSandbox.getModuleRoot('x' * 101),
        throwsA(isA<InvalidModuleIdException>()),
      );
      // Граница включительно — 100 символов допустимы.
      await expectLater(
        ModuleSandbox.getModuleRoot('x' * 100),
        completes,
      );
    });

    test('id "." не стирает песочницы соседних модулей', () async {
      // Регрессия: path.join(parent, '.') схлопывается в parent, поэтому
      // deleteModule('.') удалил бы каталог со ВСЕМИ песочницами.
      await ModuleSandbox.ensureModuleDirectories('alpha');

      await expectLater(
        ModuleSandbox.deleteModule('.'),
        throwsA(isA<InvalidModuleIdException>()),
      );

      expect(await ModuleSandbox.exists('alpha'), isTrue);
      expect(
        Directory(path.join(personalHubRoot.path, 'modules')).existsSync(),
        isTrue,
      );
    });
  });

  group('TEST-01: production-разметка совпадает с *ForTesting-обёртками', () {
    // Главная проверка TEST-01. Тесты, живущие на *ForTesting, зелёные
    // сами по себе: они сверяются с собственной копией разметки. Если
    // production-путь изменится (другая папка, другой уровень вложенности,
    // другое имя каталога), сломается только этот тест.
    test('getModuleRoot/getAssetsDirectory совпадают с ForTesting-вариантами',
        () async {
      final supportDir = await ModuleSandbox.getAppSupportDirectoryForTesting();

      expect(
        (await ModuleSandbox.getModuleRoot('alpha')).path,
        ModuleSandbox.getModuleRootForTesting('alpha', supportDir).path,
      );
      expect(
        (await ModuleSandbox.getAssetsDirectory('alpha')).path,
        ModuleSandbox.getAssetsDirectoryForTesting('alpha', supportDir).path,
      );
      expect(
        (await ModuleSandbox.getAssetsDirectory('alpha')).path,
        (await ModuleSandbox.getAssetsDirectoryForTestingAsync('alpha', supportDir)).path,
      );
      expect(
        supportDir.path,
        personalHubRoot.path,
        reason: 'production-корень песочниц обязан совпадать с тем, что видят тесты',
      );
    });

    test('ensure/exists/delete совпадают с ForTesting-вариантами', () async {
      final supportDir = await ModuleSandbox.getAppSupportDirectoryForTesting();

      await ModuleSandbox.ensureModuleDirectories('alpha');
      await ModuleSandbox.ensureModuleDirectoriesForTesting('beta', supportDir);

      expect(
        await ModuleSandbox.exists('alpha'),
        await ModuleSandbox.existsForTesting('alpha', supportDir),
      );
      expect(
        await ModuleSandbox.existsForTesting('beta', supportDir),
        isTrue,
      );

      expect(
        (await ModuleSandbox.listModuleIds())..sort(),
        (await ModuleSandbox.listModuleIdsForTesting(supportDir))..sort(),
      );

      await ModuleSandbox.deleteModule('alpha');
      expect(
        await ModuleSandbox.existsForTesting('alpha', supportDir),
        isFalse,
        reason: 'production-удаление обязано быть видно тестовым обёрткам',
      );

      await ModuleSandbox.ensureModuleDirectoriesForTesting('gamma', supportDir);
      await ModuleSandbox.deleteModuleForTesting('gamma', supportDir);
      expect(
        await ModuleSandbox.exists('gamma'),
        isFalse,
        reason: 'тестовое удаление обязано быть видно production-проверке',
      );
    });
  });
}
