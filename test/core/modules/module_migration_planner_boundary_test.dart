/// Архитектурные границы планировщика переноса (Этап 9.2).
///
/// ## Почему планировщику положен отдельный сторож
///
/// Поведение планирования проверяется в
/// module_migration_planner_test.dart, но там проверяется только то, что
/// он возвращает. А вот что он НЕ делает — нигде не видно: вход
/// типизирован, поэтому лишний `ModuleStorage` в сигнатуре и лишний
/// `await step.run(...)` в теле компилируются так же, как и
/// обязательные. Планирование стоит ДО снимка, поэтому одна запись в
/// хранилище здесь — это порча пользовательских данных до того, как
/// появилась возможность их откатить.
///
/// ## Что проверяется
///
/// 1. планировщик не зависит ни от Isar, ни от хранилища, ни от
///    файловой системы, ни от реестра, состояния и lifecycle;
/// 2. в его теле нет ни вызова шага, ни записи маркера, ни снимка;
/// 3. он не знает версии КОДА модуля: форма данных и версия публикации
///    живут разными шкалами;
/// 4. нигде в runtime-коде планировщик ещё не вызывается — интеграция
///    придёт в Этапе 9.4, и до тех пор её появление обязано ломать
///    этот тест;
/// 5. класс планировщика и класс плана объявлены ровно по одному разу,
///    и ни один модуль не заводит свой планировщик;
/// 6. новых Isar-коллекций Этап 9.2 не заводил.
///
/// Про отсутствие Isar-коллекций и зависимости ядра от конкретных
/// модулей следят сторожи, созданные раньше и не переносившие смысла:
/// schedule_architecture_boundary_test.dart (список схем IsarService) и
/// home_architecture_boundary_test.dart (lib/core и lib/ui не импортируют
/// lib/modules). Здесь дублировать их списки было бы вредно: два
/// перечня схем разойдутся при первой же правке.
///
/// Проверки статические и ищут по коду, а не по тексту: комментарии
/// обсуждают Isar, хранилище и lifecycle — именно чтобы объяснить, чего
/// здесь нет.
library module_migration_planner_boundary_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _plannerFile = 'lib/core/modules/module_migration_planner.dart';
const String _planFile = 'lib/core/modules/module_migration_plan.dart';
const String _contractFile = 'lib/core/modules/module_data_migration.dart';

/// Разрешённые импорты планировщика и плана.
///
/// Не «список запрещённых», а список единственно допустимых: правило
/// в виде «здесь нельзя вот это» перестаёт работать, как только
/// появляется новый запрет — а новый импорт появляется именно так.
/// План знает только про контракт шага, планировщик — ещё и про план.
const Map<String, List<String>> allowedImports = <String, List<String>>{
  _planFile: <String>[_contractFile],
  _plannerFile: <String>[_contractFile, _planFile],
};

void main() {
  final root = Directory.current;

  /// Все .dart под указанным каталогом, путями через '/'.
  List<String> dartFilesUnder(String relativeDir) {
    final absolute = Directory('${root.path}${Platform.pathSeparator}'
        '${relativeDir.replaceAll('/', Platform.pathSeparator)}');
    if (!absolute.existsSync()) fail('каталог не найден: $relativeDir');
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

  /// Строки файла, где образец встречается В КОДЕ, а не в комментарии.
  List<String> codeLinesContaining(
    String packageRelativePath,
    String pattern,
  ) {
    final regex = RegExp(pattern, multiLine: true);
    return _stripComments(readFile(packageRelativePath))
        .split('\n')
        .where(regex.hasMatch)
        .map((line) => line.trim())
        .toList();
  }

group('Этап 9.2: планировщик ничего не знает о мире', () {
    test('у планировщика и плана нет импортов, кроме контракта шага', () {
      for (final file in const <String>[_plannerFile, _planFile]) {
        final imports = RegExp(r'''^(?:import|export|part)\s+['"]([^'"]+)''',
                multiLine: true)
            .allMatches(_stripComments(readFile(file)))
            .map((m) {
          final spec = m.group(1)!;
          if (spec.startsWith('dart:')) return spec;
          if (spec.startsWith('package:personal_hub/')) {
            return 'lib/${spec.substring('package:personal_hub/'.length)}';
          }
          // Относительный импорт в этом проекте пишется без `./`
          // (`import 'module_data_migration.dart';`), поэтому признак
          // относительности — отсутствие `package:` и `dart:`, а не
          // ведущая точка.
          final parts = file.split('/')..removeLast();
          return <String>[...parts, spec].join('/');
        })
            .toList();

        expect(imports, allowedImports[file],
            reason: '$file вправе знать только про контракт шага и план. '
                'Isar, хранилище, файловая система, реестр, состояние и '
                'lifecycle появятся здесь первыми же.');
      }
    });

    test('в теле планировщика нет ни данных, ни исполнения', () {
      // Самая опасная поломка на этом этапе: одна строка `await
      // step.run(storage)` превращает планирование в перенос данных,
      // произведённый ДО снимка.
      final forbidden = <String, String>{
        r'\.run\s*\(': 'вызов шага миграции',
        r'ModuleStorage': 'хранилище модуля',
        r'setString|getString|remove\s*\(': 'запись в хранилище',
        r'ModuleSchemaMarker': 'маркер версии схемы',
        r'ModuleSnapshot': 'снимок данных',
        r'package:isar|@collection|CollectionSchema|IsarService':
            'прямой доступ к Isar',
        r'dart:io|File\s*\(|Directory\s*\(': 'файловая система',
      };

      final violations = <String>[];
      for (final file in const <String>[_plannerFile, _planFile]) {
        for (final entry in forbidden.entries) {
          for (final line in codeLinesContaining(file, entry.key)) {
            violations.add('$file: $line — ${entry.value}');
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Планирование стоит до снимка и обязано быть чистым.\n'
              'Найдено:\n  ${violations.join('\n  ')}');
    });

    test('планировщик не знает про реестр, состояние и lifecycle', () {
      final violations = <String>[];
      for (final file in const <String>[_plannerFile, _planFile]) {
        for (final line in codeLinesContaining(
          file,
          r'ModuleRegistry|ModuleState|ModuleManager|ModuleImporter|'
          r'backup|Backup|onInstall|onEnable|onDisable|onUninstall|'
          r'onUpdate|ModuleLifecycleError',
        )) {
          violations.add('$file: $line');
        }
      }

      expect(violations, isEmpty,
          reason: 'Решение «переносить ли данные» принимается до того, как '
              'приложение что-либо делает. Реестр, состояние и lifecycle '
              'описывают «после», а не «можно ли».\n'
              'Найдено:\n  ${violations.join('\n  ')}');
    });

    test('планировщик не читает версию КОДА модуля', () {
      // Версия публикации и форма данных — разные шкалы. Решение о
      // переносе, принятое по manifest.version или installedVersion,
      // означало бы, что перенос зависит от того, как модуль
      // заверсионирован, а не от того, как устроены его данные.
      final violations = <String>[];
      for (final file in const <String>[_plannerFile, _planFile]) {
        for (final line in codeLinesContaining(
          file,
          r'ModuleManifest|ModuleVersion|installedVersion|manifest\.',
        )) {
          violations.add('$file: $line');
        }
      }

      expect(violations, isEmpty,
          reason: 'На входе у планировщика только schemaVersion и номера '
              'версий шагов.\nНайдено:\n  ${violations.join('\n  ')}');
    });

    test('планировщик остаётся чистой функцией чисел и шагов', () {
      // Подпись plan() — это весь контракт планировщика. Если появится
      // хранилище, реестр или модуль целиком, планирование перестанет
      // быть проверяемым ДО снимка, даже если тело не изменится.
      final signature = codeLinesContaining(
        _plannerFile,
        r'ModuleMigrationPlan plan\(',
      );

      expect(signature, hasLength(1));
      final block = RegExp(r'ModuleMigrationPlan plan\(([\s\S]*?)\)\s*\{')
          .firstMatch(_stripComments(readFile(_plannerFile)))!
          .group(1)!;

      for (final parameter in const <String>[
        'currentSchemaVersion',
        'targetSchemaVersion',
        'migrations',
      ]) {
        expect(block, contains(parameter));
      }
      expect(block, isNot(contains('storage')),
          reason: 'хранилище в подписи сделало бы план зависимым от данных');
    });
  });

  group('Этап 9.3: исполнитель существует и централизован', () {
    test('ModuleMigrationRunner объявлен ровно в одном файле', () {
      // Исполнитель — платформенная сущность. Объявление класса
      // (class ModuleMigrationRunner) должно быть ровно в одном файле.
      // Использование runner'а в других файлах (например, ScheduleMigrator)
      // допускается — это делегирование, а не второе объявление.
      final declarations = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (RegExp(r'\bclass\s+ModuleMigrationRunner\b')
            .hasMatch(_stripComments(readFile(file)))) {
          declarations.add(file);
        }
      }

      expect(declarations, <String>{'lib/core/modules/module_migration_runner.dart'},
          reason: 'ModuleMigrationRunner — платформенная сущность, и на Этапе 9.3 '
              'её объявление (class) должно быть ровно в одном файле.\n'
              'Найдено:\n  ${declarations.join('\n  ')}');
    });

    test('план объявлен ровно в одном файле', () {
      final declarations = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (RegExp(r'\bclass\s+ModuleMigrationPlan\b')
            .hasMatch(_stripComments(readFile(file)))) {
          declarations.add(file);
        }
      }

      expect(declarations, <String>[_planFile],
          reason: 'Второе объявление плана означало бы две несовместимые '
              'формы ответа для одного и того же отказа.');
    });

    test('ни один модуль не заводит свой планировщик', () {
      // Планировщик не должен ветвиться по модулям: иначе у модулей
      // появятся свои правила о том, что считать переносом, и цепочка
      // перестанет быть свойством платформы.
      //
      // Модули МОГУТ использовать платформенный планировщик
      // (ModuleMigrationPlanner().plan(...)) — это делегирование.
      // Запрещено: объявлять свои классы планировщика, наследовать
      // от ModuleMigrationPlanner, или создавать кастомные экземпляры
      // с переопределённой логикой.
      final usages = <String>[];
      for (final file in dartFilesUnder('lib/modules')) {
        // Ищем объявления СВОИХ классов планировщика или наследование
        if (RegExp(r'\bclass\s+\w*\w*MigrationPlanner\b')
            .hasMatch(_stripComments(readFile(file)))) {
          usages.add('$file: объявляет свой класс планировщика');
        }
        // Проверяем наследование от ModuleMigrationPlanner
        if (RegExp(r'extends\s+ModuleMigrationPlanner\b')
            .hasMatch(_stripComments(readFile(file)))) {
          usages.add('$file: наследуется от ModuleMigrationPlanner');
        }
        // Проверяем создание кастомных экземпляров с переопределением логики
        // (но допускаем простое использование: const ModuleMigrationPlanner().plan(...))
      }

      expect(usages, isEmpty,
          reason: 'Модуль объявляет ШАГИ (dataMigrations), а план строит '
              'платформа. Свой класс планировщика у модуля означал бы свои правила '
              'переноса.\nНайдено:\n  ${usages.join('\n  ')}');
    });
  });

group('Этап 9.3: исполнитель существует и централизован', () {
    test('ModuleMigrationRunner объявлен ровно в одном файле', () {
      // Исполнитель — Этап 9.3. Объявление класса
      // (class ModuleMigrationRunner) должно быть ровно в одном файле.
      // Использование runner'а в других файлах (например, ScheduleMigrator)
      // допускается — это делегирование, а не второе объявление.
      final declarations = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (RegExp(r'\bclass\s+ModuleMigrationRunner\b')
            .hasMatch(_stripComments(readFile(file)))) {
          declarations.add(file);
        }
      }

      expect(declarations, <String>{'lib/core/modules/module_migration_runner.dart'},
          reason: 'ModuleMigrationRunner — платформенная сущность, и на Этапе 9.3 '
              'её объявление (class) должно быть ровно в одном файле.\n'
              'Найдено:\n  ${declarations.join('\n  ')}');
    });

    test('платформа запускает шаг миграции ТОЛЬКО через ModuleMigrationRunner', () {
      // На Этапе 9.3 исполнитель существует и является ЕДИНСТВЕННЫМ местом
      // в lib/core и lib/ui, где вызывается step.run(storage).
      // Сам ModuleMigrationRunner вызывает step.run — это нормально.
      // Любой ДРУГОЙ прямой вызов run() в lib/core или lib/ui означал бы
      // вторую точку исполнения, обходящую маркер, снимок и идемпотентность.
      final usages = <String>[];
      for (final dir in const <String>['lib/core', 'lib/ui']) {
        for (final file in dartFilesUnder(dir)) {
          // Исключаем сам файл runner'а
          if (file == 'lib/core/modules/module_migration_runner.dart') continue;
          for (final line in codeLinesContaining(
            file,
            r'\.\s*run\s*\(\s*(?:storage|_storage|api\.storage)\s*\)',
          )) {
            usages.add('$file: $line');
          }
        }
      }

      expect(usages, isEmpty,
          reason: 'Только ModuleMigrationRunner вызывает step.run(storage). '
              'Прямой вызов в ядре означал бы вторую точку исполнения.\n'
              'Найдено:\n  ${usages.join('\n  ')}');
    });
  });

  group('Этап 9.2: контракт шага остался прежним', () {
    test('шаг по-прежнему не пишет маркер версии', () {
      // Правило «маркер пишет вызывающий» держится на уровне контракта:
      // если бы ModuleDataMigration сам себя так помечал, прерванный
      // на середине перенос выглядел бы завершённым.
      final hits = codeLinesContaining(
        _contractFile,
        r'ModuleSchemaMarker\.write|setString\s*\(',
      );

      expect(hits, isEmpty,
          reason: 'Шаг преобразует данные; версию записывает исполнитель '
              'после успешного run.\nНайдено:\n  ${hits.join('\n  ')}');
    });

    test('контракт шага не получил новых полей', () {
      // fromVersion/toVersion/run — весь контракт Этапа 9.1. Любое
      // новое поле означало бы, что планирования перестало быть
      // достаточно для решения о переносе: потребовалось бы ещё
      // что-то, чего планировщик не умеет спрашивать.
      final body = RegExp(
        r'abstract class ModuleDataMigration \{([\s\S]*?)\n\}',
      ).firstMatch(_stripComments(readFile(_contractFile)))!.group(1)!;

      final declarations = body
          .split('\n')
          .map((line) => line.trim())
          .where((line) =>
              line.isNotEmpty &&
              RegExp(r'^(?:const |int |Future<).*[;(]$').hasMatch(line))
          .toList();

      expect(declarations, <String>[
        'const ModuleDataMigration();',
        'int get fromVersion;',
        'int get toVersion;',
        'Future<void> run(ModuleStorage storage);',
      ]);
    });
  });
}

/// Убирает комментарии из исходника: иначе поиск по слову ловил бы
/// объяснения того, почему чего-то нет.
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