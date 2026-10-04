/// Сторож архитектурных границ интеграции категорий (Этап 7.4).
///
/// Остальные тесты Этапа 7 проверяют, что категории работают. Этот —
/// что они не протекли туда, где им не место, потому что именно такие
/// протечки не ломают тесты и годами остаются незамеченными: Isar
/// открывается для всех сразу, а лишний импорт ничего не ломает, пока
/// что-то не сломается.
///
/// Проверки статические и по ИМПОРТАМ. Импорт разбирается до файловой
/// системы, а не ищется текстом: `lib/core/modules/...` — это платформа
/// модулей, законно используемая Schedule, и наивный поиск подстроки
/// 'modules/' поймал бы её как нарушение.
///
/// Упоминания в КОММЕНТАРИЯХ игнорируются: `app_typography.dart` законно
/// пишет «метки категорий» о типографике. Игнорирование не тихое — оно
/// само проверено тестом «фильтр комментариев действительно работает»,
/// иначе проверка «в ядре нет слова "категория"» проходила бы вхолостую.
library schedule_architecture_boundary_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Модуль, чьи границы проверяются.
const String _scheduleRoot = 'lib/modules/schedule';

/// Каталоги, которые проверяются на отсутствие знания о категориях.
const List<String> _categoryFreeRoots = <String>['lib/core', 'lib/ui'];

/// Единственный файл, где живёт правило «что показать пользователю».
const String _resolutionFile = 'lib/modules/schedule/ui/category_visuals.dart';

/// Схемы, которые Isar открывает на Этапе 7.
///
/// Список — не «на текущий момент», а утверждение архитектуры: категории
/// лежат в ModuleStorage и отдельной Isar-коллекции не имеют, поэтому
/// появление пятой схемы здесь означало бы, что кто-то завёл хранилище
/// в обход ModuleStorage — и backup/restore перестали бы видеть данные
/// модуля целиком.
const List<String> _expectedIsarSchemas = <String>[
  'CoreTestItemSchema',
  'AppSettingsSchema',
  'ModuleStateRecordSchema',
  'ModuleDataRowSchema',
];

/// Экраны и источники, которые обязаны брать категорию через
/// [CategoryResolver], а не решать по-своему.
///
/// Проверяется импорт, а не вызов: экран может и не показывать категорию
/// (например, пустой список), но обязан брать её из этого места.
const List<String> _categorySurfaces = <String>[
  'lib/modules/schedule/ui/today_tab.dart',
  'lib/modules/schedule/ui/calendar_tab.dart',
  'lib/modules/schedule/ui/event_form_screen.dart',
  'lib/modules/schedule/ui/home/schedule_home_section.dart',
  'lib/modules/schedule/schedule_search_provider.dart',
];

void main() {
  final root = Directory.current;

  /// Все .dart под указанным каталогом, путями через '/'.
  List<String> dartFilesUnder(String relativeDir) {
    final absolute = Directory('${root.path}${Platform.pathSeparator}'
        '${relativeDir.replaceAll('/', Platform.pathSeparator)}');
    if (!absolute.existsSync()) {
      fail('каталог не найден: $relativeDir');
    }
    return absolute
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path.substring(root.path.length + 1).replaceAll('\\', '/'))
        .toList()
      ..sort();
  }

  String readFile(String packageRelativePath) => File(
        '${root.path}${Platform.pathSeparator}'
        '${packageRelativePath.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();

  /// Импорты/экспорты файла, разрешённые до путей относительно корня.
  List<String> resolvedImportsOf(String packageRelativePath) {
    final pathSegments = packageRelativePath.split('/');
    final fileDir = pathSegments.sublist(0, pathSegments.length - 1).join('/');
    final resolved = <String>[];

    for (final rawLine in readFile(packageRelativePath).split('\n')) {
      final line = rawLine.trim();
      final match =
          RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''').firstMatch(line);
      if (match == null) continue;

      final spec = match.group(1)!;
      if (spec.startsWith('package:personal_hub/')) {
        resolved.add('lib/${spec.substring('package:personal_hub/'.length)}');
        continue;
      }
      if (spec.startsWith('dart:')) continue;

      // Внешний пакет другой схемы (`package:isar/isar.dart`,
      // `package:flutter/material.dart`) остаётся как есть: у него нет
      // файла внутри пакета, но проверка «модуль не импортирует Isar»
      // обязана его видеть, поэтому молча выбрасывать его нельзя.
      if (spec.contains(':')) {
        resolved.add(spec);
        continue;
      }

      // Всё остальное — относительный путь. Без ведущей точки тоже:
      // `import 'category_visuals.dart';` — законная форма, и пропустив
      // её, проверка молча разошлась бы с кодом.
      resolved.add(_normalize('$fileDir/$spec'));
    }
    return resolved;
  }

  /// Строки файла, где слово встречается В КОДЕ, а не в комментарии.
  List<String> codeLinesContaining(
    String packageRelativePath,
    String pattern, {
    bool caseSensitive = true,
  }) {
    final regex = RegExp(
      pattern,
      caseSensitive: caseSensitive,
      multiLine: true,
    );
    return _stripComments(readFile(packageRelativePath))
        .split('\n')
        .where(regex.hasMatch)
        .toList();
  }

  group('Этап 7.4: Schedule не ходит в базу напрямую', () {
    test('ни один файл модуля не импортирует Isar и core/database', () {
      final violations = <String>[];

      for (final path in dartFilesUnder(_scheduleRoot)) {
        for (final target in resolvedImportsOf(path)) {
          final isIsar = target.startsWith('package:isar');
          final isCoreDb = target.startsWith('lib/core/database/');
          if (isIsar || isCoreDb) violations.add('$path → $target');
        }
        // Прямой вызов IsarService без импорта невозможен в Dart, но
        // проверка ловит и частичный обход: getApplicationDocumentsDirectory
        // и Isar.open, написанные вручную с полным путём.
        final manual = RegExp(r'IsarService|Isar\.open|getApplicationDocumentsDirectory');
        if (manual.hasMatch(readFile(path))) violations.add('$path → $manual');
      }

      expect(
        violations,
        isEmpty,
        reason: 'Модуль работает с данными через ModuleStorage. Прямой доступ '
            'к Isar сделал бы его данные невидимыми для backup, restore и '
            'очистки при uninstall — они проходят по всем ключам хранилища.\n'
            'Найдено:\n  ${violations.join('\n  ')}',
      );
    });

    test('исключение не выветрилось: модуль реально ходит в данные', () {
      // Смысл проверки в обратную сторону: если бы модуль не касался
      // данных вовсе, запрет выше был бы пустым. Здесь он падает.
      for (final path in const <String>[
        'lib/modules/schedule/schedule_repository.dart',
        'lib/modules/schedule/schedule_category_repository.dart',
      ]) {
        expect(
          resolvedImportsOf(path).contains('lib/core/modules/module_storage.dart'),
          isTrue,
          reason: '$path обязан брать хранилище от платформы модулей',
        );
      }
    });
  });

  group('Этап 7.4: Schedule не зависит от чужих модулей', () {
    test('ни один файл модуля не импортирует другой функциональный модуль', () {
      final violations = <String>[];

      for (final path in dartFilesUnder(_scheduleRoot)) {
        for (final target in resolvedImportsOf(path)) {
          if (!target.startsWith('lib/modules/')) continue;
          if (target.startsWith('$_scheduleRoot/')) continue;
          violations.add('$path → $target');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Модули не должны знать друг о друге: обмен идёт через '
            'Module Platform, а не через прямые импорты.\n'
            'Найдено:\n  ${violations.join('\n  ')}',
      );
    });

    test('исключение не выветрилось: модуль использует платформу модулей', () {
      expect(
        resolvedImportsOf('lib/modules/schedule/schedule_module.dart')
            .contains('lib/core/modules/module.dart'),
        isTrue,
        reason: 'ScheduleModule обязан реализовывать контракт платформы',
      );
    });
  });

  group('Этап 7.4: ядро и общий UI не знают о категориях', () {
    test('в коде lib/core и lib/ui нет ни слова о категориях', () {
      final violations = <String>[];

      for (final dir in _categoryFreeRoots) {
        for (final path in dartFilesUnder(dir)) {
          final latin = codeLinesContaining(path, 'Categor');
          final cyrillic =
              codeLinesContaining(path, 'категор', caseSensitive: false);
          for (final line in <String>[...latin, ...cyrillic]) {
            violations.add('$path: ${line.trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Категория — понятие модуля Schedule. Появление её в ядре '
            'означало бы, что архитектура перестала быть модульной.\n'
            'Найдено:\n  ${violations.join('\n  ')}',
      );
    });

    test('фильтр комментариев действительно работает', () {
      // Слово «категорий» есть в ДОКУМЕНТАЦИИ типографики — и это
      // законно: там оно о надписях, а не о сущности Schedule. Если бы
      // фильтр перестал вырезать комментарии, проверка выше начала бы
      // падать на этом файле. Значит, она не выродилась в «ищем
      // подстроку в тексте».
      const String typography = 'lib/core/design/app_typography.dart';

      expect(readFile(typography).contains('категорий'), isTrue,
          reason: 'фикстура изменилась: слово убрали из документации');
      expect(codeLinesContaining(typography, 'категор', caseSensitive: false),
          isEmpty);
    });
  });

  group('Этап 7.4: ни одной новой Isar-коллекции', () {
    test('в функциональных модулях нет ни Isar, ни аннотаций коллекций', () {
      final violations = <String>[];

      for (final path in dartFilesUnder('lib/modules')) {
        final hits = codeLinesContaining(
          path,
          r'@collection|CollectionSchema|package:isar|IsarService',
        );
        for (final line in hits) {
          violations.add('$path: ${line.trim()}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Данные модулей лежат в ModuleDataRow через ModuleStorage. '
            'Своя Isar-коллекция у модуля означала бы данные, о которых '
            'backup не знает.\nНайдено:\n  ${violations.join('\n  ')}',
      );
    });

    test('список схем в IsarService не изменился', () {
      const String service = 'lib/core/database/isar_service.dart';
      final body = _stripComments(readFile(service));
      final call = RegExp(r'Isar\.open\((.*?)\]\s*,', dotAll: true)
          .firstMatch(body);
      expect(call, isNotNull, reason: 'не разобран список схем в $service');

      final schemas = RegExp(r'(\w+Schema)')
          .allMatches(call!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();

      expect(
        schemas,
        _expectedIsarSchemas,
        reason: 'Коллекции добавляются только вместе с платформенным '
            'решением. Категории Schedule живут в ModuleStorage — отдельной '
            'схемы у них быть не должно.',
      );
    });
  });

  group('Этап 7.4: правило разрешения категории одно', () {
    test('подпись «Без категории» в коде встречается ровно в одном файле', () {
      final owners = <String>[];

      for (final path in dartFilesUnder('lib/modules/schedule')) {
        if (codeLinesContaining(path, 'Без категории').isNotEmpty) {
          owners.add(path);
        }
      }

      expect(
        owners,
        <String>[_resolutionFile],
        reason: 'Вторая копия подписи означала бы, что у приложения две '
            'разные подписи для одного и того же состояния события.',
      );
    });

    test('ResolvedCategory и CategoryResolver определены в одном файле', () {
      final definitions = <String>[];

      for (final path in dartFilesUnder('lib/modules/schedule')) {
        final hits = codeLinesContaining(
          path,
          r'^\s*(?:abstract\s+)?class\s+(?:ResolvedCategory|CategoryResolver)\b',
        );
        if (hits.isNotEmpty) definitions.add(path);
      }

      expect(definitions, <String>[_resolutionFile]);
    });

    test('все экраны и поиск берут категорию из этого файла', () {
      for (final path in _categorySurfaces) {
        expect(
          resolvedImportsOf(path).contains(_resolutionFile),
          isTrue,
          reason: '$path обязан разрешать категорию через CategoryResolver. '
              'Своё решение здесь означало бы, что на одном экране категория '
              'есть, а на другом — «Без категории» для того же события.',
        );
      }
    });

    test('список экранов не устарел: ни один экран не остался без него', () {
      // Обратная проверка: если появится новый экран с категориями, этот
      // тест о нём не узнает — узнает следующий. Пока новых нет, список
      // обязан совпадать с тем, кто реально строит разрешитель.
      final resolvers = <String>[];
      for (final path in dartFilesUnder('lib/modules/schedule')) {
        // Сам файл-определение из списка убирается: `CategoryResolver.of`
        // в нём — это фабрика, а не потребитель правила.
        if (path == _resolutionFile) continue;
        if (codeLinesContaining(path, 'CategoryResolver.of').isNotEmpty) {
          resolvers.add(path);
        }
      }

      expect(resolvers.toList()..sort(), <String>[
        ..._categorySurfaces,
      ]..sort());
    });
  });

  group('Этап 7.4: backup и очистка остались в неведении', () {
    test('в ядре нет ни префикса category:, ни слов о категориях', () {
      // Поведение (архив .pmb уносит категории и rollback их возвращает)
      // проверяется в schedule_backup_categories_test.dart. Здесь — что
      // оно не выросло из правок ядра: ключи хранилища ядро не знает.
      final violations = <String>[];

      for (final path in dartFilesUnder('lib/core')) {
        for (final line in codeLinesContaining(path, 'category:')) {
          violations.add('$path: ${line.trim()}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Ядро переносит все ключи модуля вслепую. Знание префикса '
            '«category:» означало бы, что backup начал понимать содержимое '
            'модуля — и перестал быть общим.\n'
            'Найдено:\n  ${violations.join('\n  ')}',
      );
    });
  });
}

/// Нормализует относительный путь, разбирая `.` и `..` вручную.
String _normalize(String rawPath) {
  final parts = <String>[];
  for (final segment in rawPath.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

/// Убирает комментарии, оставляя код.
///
/// Грубый, но достаточный сканер: строковые литералы он понимает, чтобы
/// не съесть `//` внутри `'https://…'`, raw-строки — чтобы не сломать
/// `r'\'`. Ложные срабатывания возможны только на экзотике вида
/// `"а // б"` внутри строки, чего в проверяемых файлах нет.
String _stripComments(String source) {
  final out = StringBuffer();
  var index = 0;
  var quote = '';
  var rawString = false;
  var inBlockComment = false;

  while (index < source.length) {
    final char = source[index];

    if (inBlockComment) {
      if (char == '*' &&
          index + 1 < source.length &&
          source[index + 1] == '/') {
        inBlockComment = false;
        index += 2;
        continue;
      }
      if (char == '\n') out.write('\n');
      index++;
      continue;
    }

    if (quote.isNotEmpty) {
      out.write(char);
      if (char == r'\' && !rawString && index + 1 < source.length) {
        out.write(source[index + 1]);
        index += 2;
        continue;
      }
      if (char == quote) quote = '';
      index++;
      continue;
    }

    if (char == '/' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '/') {
        while (index < source.length && source[index] != '\n') {
          index++;
        }
        continue;
      }
      if (next == '*') {
        inBlockComment = true;
        index += 2;
        continue;
      }
    }

    if (char == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"')) {
      rawString = true;
      quote = source[index + 1];
      out.write(char);
      out.write(quote);
      index += 2;
      continue;
    }

    if (char == "'" || char == '"') {
      quote = char;
      rawString = false;
      out.write(char);
      index++;
      continue;
    }

    out.write(char);
    index++;
  }

  return out.toString();
}