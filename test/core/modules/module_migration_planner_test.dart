/// Планировщик переноса данных: построение, отказы и детерминизм
/// (Этап 9.2).
///
/// ## Что здесь проверяется, а что — нет
///
/// Планировщик — чистая функция, поэтому проверяется поведением, а не
/// разбором исходников: на каждый вход есть ровно один ожидаемый
/// [ModuleMigrationPlan]. Статические утверждения о чистоте
/// (нет Isar, нет записи в хранилище, нет исполнения) — в
/// module_migration_planner_boundary_test.dart.
///
/// ## Почему отдельно проверяется детерминизм
///
/// План определяет, какие шаги и в каком порядке изменят данные
/// пользователя. Если бы результат зависел от порядка, в котором модуль
/// перечислил `dataMigrations`, то один и тот же модуль, собранный иначе,
/// переносил бы данные иначе — а это ровно тот класс дефектов, который
/// невозможно поймать на конкретном устройстве пользователя.
library module_migration_planner_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_data_migration.dart';
import 'package:personal_hub/core/modules/module_migration_plan.dart';
import 'package:personal_hub/core/modules/module_migration_planner.dart';
import 'package:personal_hub/core/modules/module_storage.dart';

/// Шаг, считающий запуски.
///
/// Отдельный класс верхнего уровня, а не локальный: в Dart нельзя
/// объявить класс внутри функции, а фикстура нужна десяткам проверок.
class _CountingMigration implements ModuleDataMigration {
  _CountingMigration(this.fromVersion, this.toVersion);

  @override
  final int fromVersion;

  @override
  final int toVersion;

  int runCount = 0;

  @override
  Future<void> run(ModuleStorage storage) async {
    runCount++;
  }
}

void main() {
  const planner = ModuleMigrationPlanner();

  ModuleMigrationPlan plan(
    int current,
    int target, [
    List<ModuleDataMigration> migrations = const <ModuleDataMigration>[],
  ]) {
    return planner.plan(
      currentSchemaVersion: current,
      targetSchemaVersion: target,
      migrations: migrations,
    );
  }

  List<ModuleMigrationViolationCode> codesOf(ModuleMigrationPlan result) =>
      result.violations.map((v) => v.code).toList();

  /// Переходы плана одной строкой: `1→2, 2→3`.
  String chainOf(ModuleMigrationPlan result) =>
      result.steps.map((s) => '${s.fromVersion}→${s.toVersion}').join(', ');

  group('Успешные планы', () {
    test('одинаковые версии — no-op без шагов', () {
      // Перенос не нужен, и это НОРМАЛЬНЫЙ успех: модуль без миграций —
      // обычное дело, и его нельзя отличать от «план построен и пуст».
      final result = plan(1, 1);

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isFalse);
      expect(result.steps, isEmpty);
      expect(result.fromVersion, 1);
      expect(result.toVersion, 1);
      expect(result.violations, isEmpty);
      expect(result.reason, isNull);
    });

    test('no-op не считается переносом и при объявленных шагах', () {
      // Шаг `1 -> 2` объявлен, но данные уже в схеме 1, а новая версия
      // ждёт схему 1. Ничего выполнять нельзя: форма данных уже та.
      final result = plan(1, 1, <ModuleDataMigration>[
        _CountingMigration(1, 2),
      ]);

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isFalse);
      expect(result.steps, isEmpty);
    });

    test('один шаг', () {
      final step = _CountingMigration(1, 2);
      final result = plan(1, 2, <ModuleDataMigration>[step]);

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isTrue);
      expect(result.steps, <ModuleDataMigration>[step]);
      expect(result.fromVersion, 1);
      expect(result.toVersion, 2);
    });

    test('последовательная цепочка из трёх шагов', () {
      final first = _CountingMigration(1, 2);
      final second = _CountingMigration(2, 3);
      final third = _CountingMigration(3, 4);
      final result = plan(1, 4, <ModuleDataMigration>[
        first,
        second,
        third,
      ]);

      expect(result.isAccepted, isTrue);
      expect(result.steps, hasLength(3));
      // Порядок значим: исполнитель обязан идти ровно так.
      expect(result.steps, <ModuleDataMigration>[first, second, third]);
      expect(chainOf(result), '1→2, 2→3, 3→4');
    });

    test('пропущенные номера версий допустимы', () {
      // Номер версии — счётчик переносов, а не позиция в списке.
      // Требование «должны быть все промежуточные шаги» означало бы, что
      // модуль обязан дробить перенос на части без всякой причины.
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 3),
        _CountingMigration(3, 4),
      ]);

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isTrue);
      expect(chainOf(result), '1→3, 3→4');
    });

    test('один крупный шаг через все версии', () {
      final step = _CountingMigration(1, 4);
      final result = plan(1, 4, <ModuleDataMigration>[step]);

      expect(result.isAccepted, isTrue);
      expect(result.steps, <ModuleDataMigration>[step]);
    });

    test('цепочка начинается не с единицы', () {
      // Данные могут лежать в любой форме, а не только в первой: модуль,
      // поставленный поверх архива, начинает не с нуля.
      final result = plan(3, 5, <ModuleDataMigration>[
        _CountingMigration(3, 4),
        _CountingMigration(4, 5),
      ]);

      expect(result.isAccepted, isTrue);
      expect(chainOf(result), '3→4, 4→5');
    });

    test('объявленные шаги не в цепочке не мешают', () {
      // Модуль вправе объявить переходы для будущих версий. Планировщик
      // обязан их пережить молча, а не считать ошибкой: они не сломаны,
      // они просто не нужны сейчас.
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(3, 4),
      ]);

      expect(result.isAccepted, isTrue);
      expect(chainOf(result), '1→2');
    });
  });

  group('migrationMissing', () {
    test('цепочка обрывается на последней версии', () {
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
      ]);

      expect(result.isAccepted, isFalse);
      expect(result.isRequired, isFalse);
      expect(result.steps, isEmpty,
          reason: 'отклонённый план не должен содержать half-built цепочку');
      expect(codesOf(result),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
      // Версия, на которой цепочка оборвалась, названа прямо: из «нет
      // переноса» пользователю ничего понять нельзя.
      expect(result.violations.single.message, contains('схемы 3'));
    });

    test('нет ни одного перехода из текущей версии', () {
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(2, 3),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
      expect(result.violations.single.message, contains('схемы 1'));
    });

    test('переход мимо цели не используется', () {
      // `1 -> 5` при цели 4 — объявление само по себе законное, но после
      // него версия формы данных уже никогда не станет 4. План обязан
      // отказать, а не выполнить шаг «на всякий случай».
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 5),
      ]);

      expect(result.isAccepted, isFalse);
      expect(result.steps, isEmpty);
      expect(codesOf(result),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
      // Отдельного кода ради перескока не заводим, но назвать шаг,
      // который всё-таки объявлен, обязаны: иначе автор модуля будет
      // гадать, что именно он объявил не так.
      expect(result.violations.single.message, contains('1 → 5'));
    });

    test('переход мимо цели в середине цепочки', () {
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 9),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
      expect(result.violations.single.message, contains('схемы 2'));
    });

    test('шаг в тупик без продолжения', () {
      // Из 1 можно дойти до 3, но из 3 выхода нет. План не имеет права
      // остановиться на «уже куда-то пришли».
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 3),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
    });
  });

  group('dataSchemaIncompatible', () {
    test('данные впереди цели', () {
      final result = plan(3, 2);

      expect(result.isAccepted, isFalse);
      expect(result.steps, isEmpty);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.dataSchemaIncompatible,
      ]);
    });

    test('обратный шаг НЕ разрешается даже когда он объявлен', () {
      // Migration System forward-only. Наличие шага `3 -> 2` в списке не
      // превращает откат формы данных в перенос: такой шаг сначала
      // отвергся бы как некорректное объявление, а решение «данные
      // впереди кода» всё равно осталось бы в силе.
      final result = plan(3, 2, <ModuleDataMigration>[
        _CountingMigration(3, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.dataSchemaIncompatible,
      ]);
      // Приоритет именно такой: направление проверяется раньше
      // объявлений, потому что «система не умеет назад» не зависит от
      // того, что модуль наобъявлял.
      expect(result.violations.single.code,
          ModuleMigrationViolationCode.dataSchemaIncompatible);
    });

    test('назад на одну версию при длинной вперёд-цепочке', () {
      final result = plan(5, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.dataSchemaIncompatible,
      ]);
    });
  });

  group('invalidMigrationDefinition', () {
    test('переход в самого себя', () {
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 1),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
      expect(result.violations.single.message, contains('ничего не переносит'));
    });

    test('обратный переход в объявлении', () {
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(3, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
      expect(result.violations.single.message, contains('назад'));
    });

    test('сломано объявление, не нужное для цепочки', () {
      // Проверяются ВСЕ объявления, а не только попавшие в цепочку.
      // Молча проигнорировать сломанный шаг — значит узнать о нём уже
      // на середине переноса, когда откатываться поздно.
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(5, 5),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
    });

    test('нулевая версия в переходе', () {
      final result = plan(0, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidSchemaVersion,
      ]);
    });

    test('версия 0 внутри объявленного перехода', () {
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(0, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
      expect(result.violations.single.message,
          contains('не меньше 1'));
    });

    test('отрицательная версия внутри объявленного перехода', () {
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, -3),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
    });

    test('недопустимая версия на входе планировщика', () {
      for (final versions in <List<int>>[
        <int>[0, 1],
        <int>[1, 0],
        <int>[-1, 1],
        <int>[1, -5],
      ]) {
        final result = plan(versions[0], versions[1]);
        expect(result.isAccepted, isFalse,
            reason: 'версии ${versions.join(" → ")} недопустимы');
        expect(codesOf(result), <ModuleMigrationViolationCode>[
          ModuleMigrationViolationCode.invalidSchemaVersion,
        ]);
      }
    });

    test('недопустимая версия отвергается раньше направления', () {
      // current = 0, target = -1 формально «больше», но сравнивать
      // недопустимые номера бессмысленно: версия схемы не может быть
      // нулём, поэтому спорить о том, что в какую сторону, рано.
      final result = plan(0, -1);

      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidSchemaVersion,
      ]);
    });

    test('несколько сломанных объявлений собираются в один отказ', () {
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 1),
        _CountingMigration(3, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
      expect(result.violationsText, isNotEmpty);
    });

    test('один и тот же переход объявлен дважды', () {
      // Выбор шага из двух одинаковых зависел бы от порядка списка.
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(1, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
      expect(result.violations.single.message, contains('дважды'));
    });
  });

  group('ambiguousMigrations', () {
    test('два пути из одной версии в целевую', () {
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(1, 3),
        _CountingMigration(2, 4),
        _CountingMigration(3, 4),
      ]);

      expect(result.isAccepted, isFalse);
      expect(result.steps, isEmpty);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.ambiguousMigrations,
      ]);
      expect(result.violations.single.message, contains('схемы 1'));
    });

    test('неоднозначность в середине цепочки', () {
      // 1 → 2 однозначно, дальше из 2 два пути: сразу в 4 или через 3.
      // Оба заканчиваются в цели, поэтому выбрать можно было бы любой —
      // а нельзя именно это.
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(2, 4),
        _CountingMigration(3, 4),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.ambiguousMigrations,
      ]);
      expect(result.violations.single.message, contains('схемы 2'));
      expect(result.violations.single.message, contains('2 → 3, 2 → 4'),
          reason: 'перечисление должно быть в каноническом порядке, а не '
              'в том, в каком шаги заданы');
    });

    test('неоднозначность, не влияющая на выбор, выбор НЕ делает', () {
      // Из 1 объявлено и 1 → 2, и 1 → 3. Второй путь упирается в тупик,
      // поэтому до цели доходит только первый. Выбирать можно: путь
      // единственный, и порядок списка на него не влияет.
      final result = plan(1, 3, <ModuleDataMigration>[
        _CountingMigration(1, 3),
        _CountingMigration(1, 2),
      ]);

      expect(result.isAccepted, isTrue);
      expect(chainOf(result), '1→3');
    });

    test('переход мимо цели не создаёт неоднозначности', () {
      // 1 -> 5 не участвует в цепочке к 4, поэтому наличие второго
      // шага из 1 не делает выбор неоднозначным.
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(1, 5),
        _CountingMigration(2, 4),
      ]);

      expect(result.isAccepted, isTrue);
      expect(chainOf(result), '1→2, 2→4');
    });

    test('тупиковая ветка не мешает построению', () {
      // Из 1 идём в 2, из 2 — в 3 (цель) и в 9 (тупик). Неоднозначности
      // нет: до цели доходит только один путь.
      final result = plan(1, 3, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(2, 9),
      ]);

      expect(result.isAccepted, isTrue);
      expect(chainOf(result), '1→2, 2→3');
    });
  });

  group('Циклы', () {
    test('цикл из обратного ребра обрывается на проверке объявлений', () {
      // Отдельного обхода графа нет и не нужно: правило `to > from`
      // запрещает обратное ребро на проверке объявлений, а цикл из
      // одних возрастающих рёбер невозможен. Планировщик обязан
      // завершиться отказом, а не висеть.
      final result = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(3, 2),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
    });

    test('цикл не мешает no-op', () {
      final result = plan(2, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 1),
      ]);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.invalidMigrationDefinition,
      ]);
    });

test('длинная цепочка заканчивается отказом, а не зависает', () {
      // Страховка на случай, если правило возрастания однажды ослабят:
      // поиск всё равно обязан завершиться, потому что версия на каждом
      // шаге растёт и не может превысить цель.
      final migrations = <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(4, 5),
        _CountingMigration(5, 6),
        _CountingMigration(6, 7),
      ];
      final result = plan(1, 4, migrations);

      expect(result.isAccepted, isFalse);
      expect(codesOf(result), <ModuleMigrationViolationCode>[
        ModuleMigrationViolationCode.migrationMissing,
      ],
          reason: 'шаги выше цели не участвуют, а шага 3 → 4 нет');
      expect(result.violations.single.message, contains('схемы 3'));
    });
  });

  group('Детерминизм', () {
    /// Все 6 перестановок одного и того же графа.
    const graph = <List<int>>[
      <int>[1, 2, 2, 3, 3, 4],
      <int>[1, 2, 3, 4, 2, 3],
      <int>[2, 3, 1, 2, 3, 4],
      <int>[2, 3, 3, 4, 1, 2],
      <int>[3, 4, 1, 2, 2, 3],
      <int>[3, 4, 2, 3, 1, 2],
    ];

    test('порядок объявлений не влияет на цепочку', () {
      const expected = '1→2, 2→3, 3→4';
      for (final permutation in graph) {
        final migrations = <ModuleDataMigration>[
          for (var i = 0; i < permutation.length; i += 2)
            _CountingMigration(permutation[i], permutation[i + 1]),
        ];
        final result = plan(1, 4, migrations);
        expect(result.isAccepted, isTrue,
            reason: 'порядок ${permutation.join(", ")}');
        expect(chainOf(result), expected,
            reason: 'порядок ${permutation.join(", ")}');
      }
    });

    test('порядок объявлений не влияет на текст отказа', () {
      final messages = <String>{};
      for (final permutation in <List<int>>[
        <int>[1, 1, 3, 2, 5, 5],
        <int>[5, 5, 1, 1, 3, 2],
        <int>[3, 2, 5, 5, 1, 1],
      ]) {
        final migrations = <ModuleDataMigration>[
          for (var i = 0; i < permutation.length; i += 2)
            _CountingMigration(permutation[i], permutation[i + 1]),
        ];
        final result = plan(1, 4, migrations);
        expect(result.isAccepted, isFalse);
        messages.add(result.violationsText);
      }
      expect(messages, hasLength(1),
          reason: 'нарушения перечисляются в каноническом порядке, а не в '
              'том, в каком автор навёл их в списке');
    });

    test('неоднозначность не разрешается выбором «первого»', () {
      // Ключевая проверка: два года назад такой план строился «как
      // получится» и зависел от порядка. Теперь — явный отказ.
      final forward = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(1, 3),
        _CountingMigration(2, 4),
        _CountingMigration(3, 4),
      ]);
      final backward = plan(1, 4, <ModuleDataMigration>[
        _CountingMigration(3, 4),
        _CountingMigration(2, 4),
        _CountingMigration(1, 3),
        _CountingMigration(1, 2),
      ]);

      expect(codesOf(forward), codesOf(backward));
      expect(forward.violationsText, backward.violationsText);
    });
  });

  group('План ничего не выполняет', () {
    test('ни один шаг плана не запущен', () {
      final steps = <_CountingMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(3, 4),
      ];
      final result = plan(1, 4, steps.cast<ModuleDataMigration>());

      expect(result.steps, hasLength(3));
      for (final step in steps) {
        expect(step.runCount, 0,
            reason: 'планировщик строит план, а не выполняет его');
      }
    });

    test('шаги отказного плана тоже не запущены', () {
      // Особенно важно: планирование стоит ДО снимка, поэтому
      // «попробовать и посмотреть» здесь недопустимо в любом случае.
      final steps = <_CountingMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
      ];
      final result = plan(1, 4, steps.cast<ModuleDataMigration>());

      expect(result.isAccepted, isFalse);
      for (final step in steps) {
        expect(step.runCount, 0);
      }
    });

    test('повторные вызовы планирования не меняют план', () {
      // Планировщик не хранит состояния между вызовами: иначе один
      // вызов влиял бы на другой, а обновление вызывало бы его дважды.
      final migrations = <ModuleDataMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
      ];
      final first = plan(1, 3, migrations);
      final second = plan(1, 3, migrations);

      expect(first.toString(), second.toString());
      expect(identical(first, second), isFalse);
    });
  });

  group('План — значение, а не действие', () {
    test('список шагов нельзя изменить снаружи', () {
      final result = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
      ]);

      expect(() => result.steps.add(_CountingMigration(2, 3)),
          throwsUnsupportedError,
          reason: 'исполнитель не должен переставлять шаги: порядок и есть '
              'смысл плана');
    });

    test('isRequired различает «не нужно» и «невозможно»', () {
      final noop = plan(1, 1);
      final ready = plan(1, 2, <ModuleDataMigration>[
        _CountingMigration(1, 2),
      ]);
      final rejected = plan(1, 4);

      expect(noop.isRequired, isFalse);
      expect(ready.isRequired, isTrue);
      expect(rejected.isRequired, isFalse);
      // У отклонённого плана шагов тоже нет, поэтому флаг обязан
      // смотреть ещё и на isAccepted — иначе «невозможно» выглядело бы
      // как «не нужно».
      expect(rejected.steps, isEmpty);
      expect(noop.isAccepted, isTrue);
      expect(rejected.isAccepted, isFalse);
    });

    test('версии плана совпадают с запрошенными', () {
      final result = plan(2, 7, <ModuleDataMigration>[
        _CountingMigration(2, 7),
      ]);

      expect(result.fromVersion, 2);
      expect(result.toVersion, 7);
    });
  });
}