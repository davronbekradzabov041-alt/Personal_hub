/// Планирование переноса данных Schedule (Этап 9.2).
///
/// ## Почему этот файл живёт у модуля, а не в ядре
///
/// Проверяется одно: платформенный планировщик умеет построить цепочку
/// для РЕАЛЬНОГО модуля. Само планирование проверяется в
/// test/core/modules/module_migration_planner_test.dart и о Schedule не
/// знает; здесь наоборот — ядро проверяется на настоящем
/// `dataMigrations`, который объявляет Schedule. Смешивать эти две
/// проверки в одном файле означало бы либо связать ядро с Schedule, либо
/// лишить тест настоящего входа.
///
/// ## Чего здесь нет
///
/// Ни одного вызова `ScheduleMigrator.run()`: планирование не переносит
/// данные, оно только решает, возможно ли их перенести. Исполнитель
/// переноса у Schedule по-прежнему живёт в ScheduleMigrator и вызывается
/// из onInstall (Этапы 9.3–9.4 переведут его на платформенный
/// исполнитель).
library schedule_migration_planner_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_migration_plan.dart';
import 'package:personal_hub/core/modules/module_migration_planner.dart';
import 'package:personal_hub/core/modules/module_storage.dart';
import 'package:personal_hub/modules/schedule/schedule_migrator.dart';
import 'package:personal_hub/modules/schedule/schedule_module.dart';

/// Шаг Schedule, который считает, а не переносит.
///
/// Наследник, а не отдельная фикстура: нужны настоящие номера версий из
/// ScheduleCategoriesMigration, иначе тест проверял бы не тот вход,
/// которым пользуется модуль.
class _CountingCategoriesMigration extends ScheduleCategoriesMigration {
  int runCount = 0;

  @override
  Future<void> run(ModuleStorage storage) async {
    runCount++;
  }
}

/// Тот же шаг, но объявляющий перенос выше целевой версии.
class _OvershootingCategoriesMigration extends ScheduleCategoriesMigration {
  @override
  int get toVersion => 5;
}

void main() {
  const planner = ModuleMigrationPlanner();
  final module = ScheduleModule();

  group('Schedule объявляет перенос, который планируется', () {
    test('номера версий шага совпадают с манифестом модуля', () {
      // Расхождение здесь означало бы, что планировщик построит цепочку
      // к версии, которой модуль не ждёт, — и данные переедут «не туда».
      expect(module.manifest.schemaVersion,
          ScheduleMigrator.currentSchemaVersion);
      expect(module.dataMigrations, hasLength(1));

      final step = module.dataMigrations.single;
      expect(step, isA<ScheduleCategoriesMigration>());
      expect(step.fromVersion, 1);
      expect(step.toVersion, ScheduleMigrator.currentSchemaVersion);
      expect(step.toVersion, module.manifest.schemaVersion);
    });

    test('из схемы 1 в схему 2 строится один шаг', () {
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: module.manifest.schemaVersion,
        migrations: module.dataMigrations,
      );

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isTrue);
      expect(result.fromVersion, 1);
      expect(result.toVersion, 2);
      expect(result.steps, hasLength(1));
      expect(result.steps.single, isA<ScheduleCategoriesMigration>());
      expect(result.toString(), contains('1→2'));
    });

    test('из схемы 2 в схему 2 — no-op', () {
      // Данные Schedule уже перенесены. Планирование обязано это увидеть
      // и не требовать переноса, хотя модуль шаг объявляет.
      final result = planner.plan(
        currentSchemaVersion: 2,
        targetSchemaVersion: module.manifest.schemaVersion,
        migrations: module.dataMigrations,
      );

      expect(result.isAccepted, isTrue);
      expect(result.isRequired, isFalse);
      expect(result.steps, isEmpty);
    });

    test('шаг Schedule не запускается при планировании', () {
      // Ключевая проверка именно здесь: настоящий шаг Schedule пишет
      // категории и ссылки в ModuleStorage. Если бы планировщик его
      // запускал, тест создавал бы и менял данные, а планирование стоит
      // ДО снимка — там, где любая запись недопустима.
      final step = _CountingCategoriesMigration();
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: <ScheduleCategoriesMigration>[step],
      );

      expect(result.isAccepted, isTrue);
      expect(result.steps, <Object>[step]);
      expect(step.runCount, 0);
    });

    test('маркер версии после планирования не появляется', () {
      // Планировщик не получает хранилища и потому не может записать
      // `schema:version`. Проверяется через то, что единственный путь
      // записи — ModuleSchemaMarker.write, и он требует ModuleStorage:
      // раз планирование синхронно и без аргументов, записи быть не
      // могло. Здесь фиксируется, что шаг остался невыполненным.
      final step = _CountingCategoriesMigration();
      planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: <ScheduleCategoriesMigration>[step],
      );

      expect(step.runCount, 0);
    });

    test('без объявленных шагов перенос невозможен', () {
      // Гипотетический Schedule без dataMigrations: обновить его до
      // схемы 2 нельзя, и планировщик обязан сказать это машинным кодом,
      // а не молча согласиться.
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
      );

      expect(result.isAccepted, isFalse);
      expect(
        result.violations.map((v) => v.code),
        <ModuleMigrationViolationCode>[
          ModuleMigrationViolationCode.migrationMissing,
        ],
      );
    });

    test('из схемы 3 назад в схему 2 — dataSchemaIncompatible', () {
      // Направление проверяется прежде объявлений: система forward-only,
      // и наличие шага `1 → 2` не делает откат возможным.
      final result = planner.plan(
        currentSchemaVersion: 3,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: module.dataMigrations,
      );

      expect(result.isAccepted, isFalse);
      expect(
        result.violations.map((v) => v.code),
        <ModuleMigrationViolationCode>[
          ModuleMigrationViolationCode.dataSchemaIncompatible,
        ],
      );
    });

    test('перенос в схему выше объявленной — migrationMissing', () {
      // Модуль не ждёт схему 5, а шаг в неё ведёт. Такой шаг не
      // годится: после него версия формы данных уже не станет 2, и
      // новый код прочитает данные не той формы, которую сам же обещал.
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: <ScheduleCategoriesMigration>[
          _OvershootingCategoriesMigration(),
        ],
      );

      expect(result.isAccepted, isFalse);
      expect(result.steps, isEmpty);
      expect(result.violations.map((v) => v.code),
          <ModuleMigrationViolationCode>[
            ModuleMigrationViolationCode.migrationMissing,
          ]);
      expect(result.violations.single.message, contains('1 → 5'),
          reason: 'объявленный шаг назван: иначе автор модуля гадает');
    });
  });

  group('Планировщик ничего не пишет и не запускает', () {
    test('вызов планирования не требует хранилища', () {
      // Формулировка проверки: plan() не принимает и не создаёт
      // ModuleStorage. Если бы это изменилось, подпись планировщика
      // начала бы зависеть от данных — и планирование перестало бы быть
      // безопасным ДО снимка.
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: module.dataMigrations,
      );

      expect(result, isA<ModuleMigrationPlan>());
    });

    test('список шагов неизменяем', () {
      final result = planner.plan(
        currentSchemaVersion: 1,
        targetSchemaVersion: ScheduleMigrator.currentSchemaVersion,
        migrations: module.dataMigrations,
      );

      expect(() => result.steps.clear(), throwsUnsupportedError);
    });
  });
}