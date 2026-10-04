/// Сторож архитектурной границы Core → Modules (QUAL-03).
///
/// Ядро (`lib/core/**`) и общий UI (`lib/ui/**`) не имеют права
/// знать о конкретных функциональных модулях (`lib/modules/**`).
/// Единственное исключение — composition root: файлы, которые
/// СОБИРАЮТ приложение и по определению связывают ядро с модулями.
///
/// Проверка статическая и по ИМПОРТАМ, а не по вхождению строки
/// 'schedule': `lib/core/design/app_colors.dart` законно содержит
/// ключ 'schedule' в общей таблице акцентов модулей, и это не
/// зависимость от модуля.
///
/// Импорт разбирается до файловой системы, а не ищется текстом:
/// `lib/core/database/repositories/module_state_repository.dart`
/// импортирует `../../modules/module_state_store.dart`, и это
/// `lib/core/modules/...` — платформа модулей, а вовсе не
/// `lib/modules/...`. Наивный поиск подстроки 'modules/' поймал бы
/// этот законный импорт как нарушение.
library home_architecture_boundary_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Каталог функциональных модулей, на который Core смотрит не должен.
const String _modulesRoot = 'lib/modules';

/// Каталоги, которые проверяются на отсутствие зависимости.
const List<String> _checkedRoots = <String>['lib/core', 'lib/ui'];

/// Composition root: файлы, которым знать о модулях положено —
/// они подключают модули и строят маршруты/оболочку.
const Set<String> _compositionRoot = <String>{
  'lib/core/modules/module_bootstrap.dart',
  'lib/core/navigation/app_routes.dart',
  'lib/core/navigation/app_shell.dart',
};

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

  /// Импорты/экспорты файла, уже разрешённые до путей относительно
  /// корня пакета.
  ///
  /// `package:personal_hub/x` → `lib/x`; относительный путь
  /// разрешается от каталога файла и нормализуется (`..`/`.`).
  List<String> resolvedImportsOf(String packageRelativePath) {
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      '${packageRelativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    final pathSegments = packageRelativePath.split('/');
    final fileDir = (pathSegments.sublist(0, pathSegments.length - 1)).join('/');
    final resolved = <String>[];

    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      final match = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''').firstMatch(line);
      if (match == null) continue;

      final spec = match.group(1)!;
      if (spec.startsWith('package:personal_hub/')) {
        resolved.add('lib/${spec.substring('package:personal_hub/'.length)}');
        continue;
      }
      if (spec.startsWith('dart:')) continue;
      if (!spec.startsWith('.')) continue;

      resolved.add(_normalize('$fileDir/$spec'));
    }
    return resolved;
  }

  group('QUAL-03: Core и общий UI не зависят от функциональных модулей', () {
    test('ни один файл lib/core и lib/ui не импортирует lib/modules', () {
      final violations = <String>[];

      for (final dir in _checkedRoots) {
        for (final path in dartFilesUnder(dir)) {
          if (_compositionRoot.contains(path)) continue;
          for (final target in resolvedImportsOf(path)) {
            if (target.startsWith('$_modulesRoot/')) {
              violations.add('$path → $target');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Core/UI не должны знать о конкретных модулях.\n'
            'Допустимы только composition root: ${_compositionRoot.join(', ')}.\n'
            'Найдено:\n  ${violations.join('\n  ')}',
      );
    });

    test('исключения не выветрились: composition root действительно их использует', () {
      // Смысл проверки в обратную сторону: если завтра кто-то вынесет
      // подключение модулей из composition root куда-то ещё, список
      // исключений станет пустым и тест молча перестанет что-либо
      // разрешать. Здесь он падает.
      for (final path in _compositionRoot) {
        final importsModules = resolvedImportsOf(path)
            .any((target) => target.startsWith('$_modulesRoot/'));
        expect(
          importsModules,
          isTrue,
          reason: '$path объявлен composition root, но не импортирует '
              'ничего из $_modulesRoot — либо он больше не composition root '
              '(уберите его из списка исключений), либо связь потеряна',
        );
      }
    });

    test('главный экран и его виджеты не содержат упоминаний модулей', () {
      // Точечная проверка того, ради чего QUAL-03 и проводился:
      // Home не знает о Schedule.
      const List<String> mustBeClean = <String>[
        'lib/ui/screens/home_screen.dart',
        'lib/core/modules/home_section.dart',
        'lib/core/modules/module.dart',
        'lib/ui/widgets/home/active_modules_canvas.dart',
      ];

      for (final path in mustBeClean) {
        for (final target in resolvedImportsOf(path)) {
          expect(
            target.startsWith('$_modulesRoot/'),
            isFalse,
            reason: '$path импортирует модуль: $target',
          );
        }
      }
    });

    test('Schedule-виджеты главного экрана живут в модуле, а не в ui/', () {
      // Виджеты Home переехали в модуль именно поэтому: пока они
      // лежали в lib/ui/, они тащили ScheduleEvent в общий UI.
      const List<String> movedIntoModule = <String>[
        'lib/modules/schedule/ui/home/today_hero.dart',
        'lib/modules/schedule/ui/home/timeline_strip.dart',
        'lib/modules/schedule/ui/home/upcoming_agenda.dart',
        'lib/modules/schedule/ui/home/schedule_home_section.dart',
      ];

      for (final path in movedIntoModule) {
        expect(
          File('${root.path}${Platform.pathSeparator}'
                  '${path.replaceAll('/', Platform.pathSeparator)}')
              .existsSync(),
          isTrue,
          reason: '$path должен существовать в модуле',
        );
      }

      // В lib/ui/widgets/home их больше нет.
      for (final name in const <String>['today_hero.dart', 'timeline_strip.dart', 'upcoming_agenda.dart']) {
        final stale = File('${root.path}${Platform.pathSeparator}'
            'lib${Platform.pathSeparator}ui${Platform.pathSeparator}widgets'
            '${Platform.pathSeparator}home${Platform.pathSeparator}$name');
        expect(
          stale.existsSync(),
          isFalse,
          reason: '$name не должен оставаться в общем UI: он принадлежит модулю',
        );
      }
    });
  });
}

/// Нормализует относительный путь, разбирая `.` и `..` вручную.
///
/// Пакет `path` здесь не используется намеренно: тест не должен
/// зависеть от того, объявлен ли `path` в pubspec, — иначе его
/// прохождение зависело бы от состава зависимостей.
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
