/// Безопасный обмен песочницы внешнего модуля (Этап 8.1-А).
///
/// Проверяется главное свойство: на любом шаге обмена старая версия
/// либо живёт на месте, либо лежит целым в восстанавливаемом каталоге.
/// Схема «удалить старое → перенести новое» этим свойством не
/// обладает, и именно её заменяет этот механизм.
library module_sandbox_swap_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/platform/module_sandbox_swap.dart';
import 'package:personal_hub/core/modules/platform/sandbox_exceptions.dart';

void main() {
  late Directory support;
  late ModuleSandboxSwap swap;

  ModuleSandboxSwap buildSwap() =>
      ModuleSandboxSwap(supportDirectoryResolver: () async => support);

  /// Песочница модуля: modules/<id>
  Directory sandbox(String moduleId) =>
      Directory('${support.path}/modules/$moduleId');

  Future<Directory> createSandbox(String moduleId, String fileName) async {
    final dir = sandbox(moduleId);
    await dir.create(recursive: true);
    File('${dir.path}/$fileName').writeAsStringSync('старое');
    return dir;
  }

  setUp(() {
    support = Directory.systemTemp.createTempSync('module_sandbox_swap_test');
    swap = buildSwap();
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  group('подготовка', () {
    test('staging создаётся рядом с modules, а не внутри', () async {
      final staging = await swap.createStaging(moduleId: 'notes');

      expect(staging.existsSync(), isTrue);
      // Сравнение по сегментам, а не по префиксу строки: 'modules_staging'
      // начинается с 'modules', и проверка startsWith сказала бы «внутри».
      expect(
        staging.parent.path,
        '${support.path}${Platform.pathSeparator}$kModuleStagingDirName',
      );
      expect(
        Directory('${support.path}/modules').existsSync(),
        isFalse,
        reason: 'подготовленный каталог внутри modules/ выдал бы себя за '
            'ещё один установленный модуль в ModuleSandbox.listModuleIds()',
      );
    });

    test('небезопасный moduleId отклоняется до файловых операций', () async {
      await expectLater(
        swap.createStaging(moduleId: '../escape'),
        throwsA(isA<InvalidModuleIdException>()),
      );
      expect(
        Directory('${support.path}/modules_staging').existsSync(),
        isFalse,
      );
    });
  });

  group('обмен', () {
    test('новая версия встаёт на место, старая сохраняется', () async {
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');

      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'новое');
      expect(result.previousDirectory, isNotNull,
          reason: 'прежняя версия обязана остаться восстанавливаемой');
      expect(File('${result.previousDirectory!.path}/logo.png')
          .readAsStringSync(), 'старое');
      expect(result.isFirstInstall, isFalse);
      expect(staging.existsSync(), isFalse);
    });

    test('первая установка: предыдущей версии нет', () async {
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('первое');

      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      expect(result.isFirstInstall, isTrue);
      expect(result.previousDirectory, isNull);
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'первое');
    });

    test('подготовленного каталога нет — отказ до перемещений', () async {
      await createSandbox('notes', 'logo.png');

      await expectLater(
        swap.commit(
          moduleId: 'notes',
          stagedDirectory: Directory('${support.path}/modules_staging/nope'),
        ),
        throwsA(isA<SandboxStagingMissingException>()),
      );

      // Старая версия не тронута ни на байт.
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'старое');
      expect(await swap.findPreviousDirectory('notes'), isNull);
    });

    test('прежняя версия не попадает в перечень модулей', () async {
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');

      await swap.commit(moduleId: 'notes', stagedDirectory: staging);

      final live = Directory('${support.path}/modules')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .toList();
      expect(live, ['notes']);
    });
  });

  group('откат', () {
    test('прежняя версия возвращается на место', () async {
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');

      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      final restored = await swap.restorePrevious(
        moduleId: 'notes',
        previousDirectory: result.previousDirectory,
      );

      expect(restored, isTrue);
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'старое');
      expect(result.previousDirectory!.existsSync(), isFalse);
    });

    test('новую версию откат УВОДИТ В СТОРОНУ, а не удаляет', () async {
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      await swap.restorePrevious(
        moduleId: 'notes',
        previousDirectory: result.previousDirectory,
      );

      // Обновление откатили, но то, что его спровоцировало, ещё может
      // понадобиться для разбора — значит, оно должно лежать, а не исчезнуть.
      final leftovers = Directory('${support.path}/$kModuleStagingDirName')
          .listSync()
          .whereType<Directory>()
          .toList();
      expect(leftovers, hasLength(1));
      expect(File('${leftovers.single.path}/logo.png').readAsStringSync(),
          'новое');
    });

    test('откатывать нечего — false, а не ошибка', () async {
      expect(await swap.restorePrevious(moduleId: 'never-installed'), isFalse);
    });
  });

  group('восстановление после сбоя процесса', () {
    test('нет песочницы, есть бэкап — вернуть на место', () async {
      // Именно это состояние остаётся, если процесс убит между
      // шагами commit: первый каталог уже уведён, второй ещё не встал.
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      sandbox('notes').deleteSync(recursive: true);

      final recovered = await swap.recoverInterrupted(moduleId: 'notes');

      expect(recovered, isTrue);
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'старое');
      expect(result.previousDirectory!.existsSync(), isFalse);
    });

    test('песочница на месте — ничего не трогаем', () async {
      // Новая версия уже встала: трогать её на старте было бы
      // «восстановлением», откатывающим успешное обновление.
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      await swap.commit(moduleId: 'notes', stagedDirectory: staging);

      expect(await swap.recoverInterrupted(moduleId: 'notes'), isFalse);
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'новое');
    });

    test('ни песочницы, ни бэкапа — нечего восстанавливать', () async {
      expect(await swap.recoverInterrupted(moduleId: 'ghost'), isFalse);
    });
  });

  group('восстановление всех модулей при старте', () {
    /// Создаёт состояние «обмен состоялся, процесс убит на уборке»: новый
    /// модуль на месте, каталог прежней версии остался.
    Future<Directory> commitWithoutCleanup(String moduleId) async {
      await createSandbox(moduleId, 'logo.png');
      final staging = await swap.createStaging(moduleId: moduleId);
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      final result =
          await swap.commit(moduleId: moduleId, stagedDirectory: staging);
      return result.previousDirectory!;
    }

    test('модуль без песочницы возвращается на место', () async {
      await commitWithoutCleanup('notes');
      sandbox('notes').deleteSync(recursive: true);

      final report = await swap.recoverAllInterrupted();

      expect(report.recovered, ['notes']);
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'старое');
      expect(await swap.findPreviousDirectory('notes'), isNull);
    });

    test('несколько пострадавших модулей восстанавливаются за один проход',
        () async {
      await commitWithoutCleanup('notes');
      await commitWithoutCleanup('calendar');
      sandbox('notes').deleteSync(recursive: true);
      sandbox('calendar').deleteSync(recursive: true);

      final report = await swap.recoverAllInterrupted();

      expect(report.recovered.toSet(), {'notes', 'calendar'});
      expect(sandbox('notes').existsSync(), isTrue);
      expect(sandbox('calendar').existsSync(), isTrue);
    });

    test('moduleId с подчёркиванием восстанавливается целиком', () async {
      await commitWithoutCleanup('my_notes');
      sandbox('my_notes').deleteSync(recursive: true);

      final report = await swap.recoverAllInterrupted();

      // Разрез по ПОСЛЕДНЕМУ подчёркиванию: по первому получился бы id
      // "my", и восстановление не сделало бы ничего.
      expect(report.recovered, ['my_notes']);
      expect(File('${sandbox('my_notes').path}/logo.png').existsSync(), isTrue);
    });

    test('модуль на месте: прежняя версия убирается как остаток уборки',
        () async {
      final leftover = await commitWithoutCleanup('notes');

      final report = await swap.recoverAllInterrupted();

      expect(report.recovered, isEmpty);
      expect(report.discarded, ['notes']);
      // Новая версия, уже вставшая на место, остаётся нетронутой.
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'новое');
      expect(leftover.existsSync(), isFalse);
    });

    test('мусор в каталоге прежних версий не роняет восстановление', () async {
      final junk = Directory('${support.path}/$kModulePreviousDirName/../');
      await Directory('${support.path}/$kModulePreviousDirName')
          .create(recursive: true);
      Directory('${support.path}/$kModulePreviousDirName/без_метки')
          .createSync(recursive: true);
      await commitWithoutCleanup('notes');
      sandbox('notes').deleteSync(recursive: true);
      expect(junk.existsSync(), isTrue);

      final report = await swap.recoverAllInterrupted();

      expect(report.recovered, ['notes']);
    });

    test('прерванных обновлений не было — пустой отчёт', () async {
      final report = await swap.recoverAllInterrupted();

      // Поля по отдельности: записи сравниваются по идентичности
      // списков, и expect(record, record) выглядел бы как успех при
      // непустом содержимом.
      expect(report.recovered, isEmpty);
      expect(report.discarded, isEmpty);
    });
  });

  group('уборка', () {
    test('discardPrevious убирает каталог прежней версии', () async {
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      final result = await swap.commit(
        moduleId: 'notes',
        stagedDirectory: staging,
      );

      await swap.discardPrevious(
        moduleId: 'notes',
        previousDirectory: result.previousDirectory!,
      );

      expect(result.previousDirectory!.existsSync(), isFalse);
      expect(await swap.findPreviousDirectory('notes'), isNull);
    });

    test('discardStaging убирает каталог подготовки', () async {
      final staging = await swap.createStaging(moduleId: 'notes');

      await swap.discardStaging(staging);

      expect(staging.existsSync(), isFalse);
    });

    test('discardStagedVersions убирает и подготовку, и уведённую в сторону '
        'версию', () async {
      // Именно это состояние остаётся после отката обновления: новый
      // модуль не встал, restorePrevious увёл его в сторону, и оба
      // каталога больше не нужны.
      await createSandbox('notes', 'logo.png');
      final staging = await swap.createStaging(moduleId: 'notes');
      File('${staging.path}/logo.png').writeAsStringSync('новое');
      final result =
          await swap.commit(moduleId: 'notes', stagedDirectory: staging);
      await swap.restorePrevious(
        moduleId: 'notes',
        previousDirectory: result.previousDirectory,
      );

      await swap.discardStagedVersions(moduleId: 'notes');

      final stagingRoot = Directory('${support.path}/$kModuleStagingDirName');
      expect(
        stagingRoot.existsSync() ? stagingRoot.listSync() : const <Object>[],
        isEmpty,
      );
      expect(File('${sandbox('notes').path}/logo.png').readAsStringSync(),
          'старое',
          reason: 'живой модуль уборка подготовки трогать не должна');
    });

    test('discardStagedVersions не трогает подготовку другого модуля',
        () async {
      final notes = await swap.createStaging(moduleId: 'notes');
      final notesLite = await swap.createStaging(moduleId: 'notes_lite');

      await swap.discardStagedVersions(moduleId: 'notes');

      // Префикс 'notes_' не должен съесть 'notes_lite_…': иначе откат
      // одного модуля уничтожил бы подготовку соседнего по имени.
      expect(notes.existsSync(), isFalse);
      expect(notesLite.existsSync(), isTrue);
    });
  });
}