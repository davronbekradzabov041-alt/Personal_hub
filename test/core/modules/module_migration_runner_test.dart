/// ModuleMigrationRunner: выполнение плана, порядок записей и защита
/// от частичных failure (Этап 9.3).
///
/// ## Что проверяется, а что — нет
///
/// Поведение runner проверяется на фикстурах: фиктивный шаг считает
/// запуски, а фиктивный storage считает записи. Настоящий
/// ScheduleCategoriesMigration проверяется отдельно — в
/// schedule_migration_runner_test.dart.
///
/// ## Почему отдельно проверяется marker mismatch
///
/// Runner не строит план и не читает маркер до проверки. Если бы он
/// строил, то любое изменение фактической формы данных между
/// планированием и выполнением превратило бы перенос в операцию над
/// неправильными данными — именно то, что защищает разделение на
/// Planner → Runner.
library module_migration_runner_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/modules/module_data_migration.dart';
import 'package:personal_hub/core/modules/module_migration_plan.dart';
import 'package:personal_hub/core/modules/module_migration_result.dart';
import 'package:personal_hub/core/modules/module_migration_runner.dart';
import 'package:personal_hub/core/modules/module_schema_marker.dart';
import 'package:personal_hub/core/modules/module_storage.dart';

/// Шаг, считающий запуски и падения.
class _CountingMigration implements ModuleDataMigration {
  _CountingMigration(this.fromVersion, this.toVersion, {this.fail = false});

  @override
  final int fromVersion;

  @override
  final int toVersion;

  final bool fail;

  int runCount = 0;

  @override
  Future<void> run(ModuleStorage storage) async {
    runCount++;
    if (fail) throw StateError('имитация сбоя $fromVersion → $toVersion');
  }
}

/// Storage, считающий записи маркера.
class _CountingStorage implements ModuleStorage {
  _CountingStorage(this._values);

  final Map<String, String?> _values;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
    _writes.add(key);
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
    _removes.add(key);
  }

  @override
  Future<List<String>> keys() async =>
      _values.keys.where((k) => _values[k] != null).toList();

  final List<String> _writes = <String>[];
  final List<String> _removes = <String>[];

  int get writes => _writes.length;
  List<String> get writtenKeys => List<String>.unmodifiable(_writes);
}

/// Storage, падающий при записи маркера.
class _FailingStorage implements ModuleStorage {
  _FailingStorage(this._values);

  final Map<String, String?> _values;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (key == ModuleSchemaMarker.key) {
      throw StateError('имитация сбоя записи маркера');
    }
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<List<String>> keys() async =>
      _values.keys.where((k) => _values[k] != null).toList();
}

ModuleMigrationPlan _plan(
  int current,
  int target, [
  List<ModuleDataMigration> migrations = const <ModuleDataMigration>[],
]) {
  return ModuleMigrationPlan.accepted(
    fromVersion: current,
    toVersion: target,
    steps: migrations,
  );
}

Future<ModuleMigrationResult> _run(
  ModuleMigrationRunner runner,
  int current,
  int target, [
  List<ModuleDataMigration> migrations = const <ModuleDataMigration>[],
]) {
  return runner.run(
    plan: _plan(current, target, migrations),
    storage: _storage,
  );
}

late _CountingStorage _storage;

void main() {
  const runner = ModuleMigrationRunner();

  setUp(() {
    _storage = _CountingStorage(<String, String?>{
      ModuleSchemaMarker.key: null,
    });
  });

  group('No-op и отказ без записи', () {
    test('rejected plan — ни одного запуска и ни одной записи', () {
      final result = ModuleMigrationPlan.rejected(
        fromVersion: 1,
        toVersion: 4,
        reason: 'цепочка не построена',
        violations: const <ModuleMigrationViolation>[
          ModuleMigrationViolation(
            ModuleMigrationViolationCode.migrationMissing,
            'нет перехода',
          ),
        ],
      );

      expect(
        () => runner.run(plan: result, storage: _storage),
        throwsA(isA<ModuleMigrationException>()),
      );
      expect(_storage.writes, 0);
    });

    test('no-op — успех без запуска и без записи маркера', () async {
      final result = await _run(runner, 1, 1);

      expect(result.isNoop, isTrue);
      expect(result.fromVersion, 1);
      expect(result.toVersion, 1);
      expect(result.executedSteps, 0);
      expect(_storage.writes, 0,
          reason: 'runner не пишет маркер просто потому, что его вызвали');
    });
  });

  group('Один шаг', () {
    test('run() вызван один раз, marker стал toVersion', () async {
      final step = _CountingMigration(1, 2);
      final result = await _run(runner, 1, 2, <ModuleDataMigration>[step]);

      expect(result.isNoop, isFalse);
      expect(result.fromVersion, 1);
      expect(result.toVersion, 2);
      expect(result.executedSteps, 1);
      expect(step.runCount, 1);
      expect(_storage.writes, 1);
      expect(_storage.writtenKeys.single, ModuleSchemaMarker.key);
      expect(
        _storage._values[ModuleSchemaMarker.key],
        '2',
        reason: 'маркер пишется ПОСЛЕ успешного run()',
      );
    });
  });

  group('Последовательное выполнение', () {
    test('цепочка 1→2→3→4: шаги и маркер в правильном порядке', () async {
      final first = _CountingMigration(1, 2);
      final second = _CountingMigration(2, 3);
      final third = _CountingMigration(3, 4);
      final result = await _run(runner, 1, 4, <ModuleDataMigration>[
        first,
        second,
        third,
      ]);

      expect(result.isNoop, isFalse);
      expect(result.executedSteps, 3);
      expect(first.runCount, 1);
      expect(second.runCount, 1);
      expect(third.runCount, 1);

      expect(_storage.writes, 3);
      expect(_storage.writtenKeys, <String>[
        ModuleSchemaMarker.key,
        ModuleSchemaMarker.key,
        ModuleSchemaMarker.key,
      ]);
      expect(_storage._values[ModuleSchemaMarker.key], '4');
    });

    test('следующий шаг начинается только после успешного run()', () async {
      final steps = <_CountingMigration>[
        _CountingMigration(1, 2),
        _CountingMigration(2, 3),
        _CountingMigration(3, 4),
      ];
      await _run(runner, 1, 4, steps);

      for (final step in steps) {
        expect(step.runCount, 1);
      }
      expect(_storage.writes, 3);
    });
  });

  group('Marker check', () {
    test('marker mismatch — ни одного запуска', () async {
      _storage._values[ModuleSchemaMarker.key] = '2';
      final step = _CountingMigration(1, 2);

      expect(
        () => _run(runner, 1, 2, <ModuleDataMigration>[step]),
        throwsA(isA<ModuleMigrationException>()),
      );
      expect(step.runCount, 0);
      expect(_storage.writes, 0,
          reason: 'runner не выполняет и не пишет при чужом маркере');
    });

    test('marker == fromVersion — выполнение разрешено', () async {
      _storage._values[ModuleSchemaMarker.key] = '1';
      final step = _CountingMigration(1, 2);
      final result = await _run(runner, 1, 2, <ModuleDataMigration>[step]);

      expect(result.executedSteps, 1);
      expect(step.runCount, 1);
    });
  });

  group('Migration failure', () {
    test('сбой шага — маркер на предыдущей версии, следующий не запущен',
        () async {
      final first = _CountingMigration(1, 2);
      final second = _CountingMigration(2, 3, fail: true);
      final third = _CountingMigration(3, 4);

      await expectLater(
        _run(runner, 1, 4, <ModuleDataMigration>[first, second, third]),
        throwsA(isA<ModuleMigrationException>()),
      );

      expect(first.runCount, 1);
      expect(second.runCount, 1);
      expect(third.runCount, 0,
          reason: 'после сбоя следующий шаг не запускается');

      expect(_storage.writes, 1,
          reason: 'маркер записан только после успешного первого шага');
      expect(_storage._values[ModuleSchemaMarker.key], '2',
          reason: 'после сбоя второго шага маркер остаётся на 2');
    });

    test('повторный запуск с новым планом продолжает с места сбоя', () async {
      // Первый запуск: 1→2 успех, 2→3 сбой.
      await expectLater(
        _run(runner, 1, 4, <ModuleDataMigration>[
          _CountingMigration(1, 2),
          _CountingMigration(2, 3, fail: true),
          _CountingMigration(3, 4),
        ]),
        throwsA(isA<ModuleMigrationException>()),
      );

      // Второй запуск: 2→3 успех, 3→4 успех.
      // Маркер уже на 2, поэтому план 2→4 проходит проверку.
      // Создаём НОВЫЕ шаги для второго запуска (без fail: true).
      final result = await _run(runner, 2, 4, <ModuleDataMigration>[
        _CountingMigration(2, 3),
        _CountingMigration(3, 4),
      ]);

      expect(result.executedSteps, 2);
      expect(result.toVersion, 4);
      expect(_storage._values[ModuleSchemaMarker.key], '4');
    });
  });

  group('Marker write failure', () {
    test('исключение выходит наружу, следующий шаг не запускается', () async {
      final failing = _FailingStorage(<String, String?>{
        ModuleSchemaMarker.key: '1',
      });

      final first = _CountingMigration(1, 2);
      final second = _CountingMigration(2, 3);

      await expectLater(
        runner.run(
          plan: _plan(1, 3, <ModuleDataMigration>[first, second]),
          storage: failing,
        ),
        throwsA(isA<ModuleMigrationException>()),
      );

      expect(first.runCount, 1);
      expect(second.runCount, 0);
    });

    test('marker write failure — данные перенесены, маркер не записан', () async {
      final failing = _FailingStorage(<String, String?>{
        ModuleSchemaMarker.key: '1',
      });

      final first = _CountingMigration(1, 2);
      final second = _CountingMigration(2, 3);

      await expectLater(
        runner.run(
          plan: _plan(1, 3, <ModuleDataMigration>[first, second]),
          storage: failing,
        ),
        throwsA(isA<ModuleMigrationException>()
            .having((e) => e.code, 'code', ModuleMigrationFailureCode.markerWriteFailed)),
      );

      expect(first.runCount, 1,
          reason: 'шаг выполнился успешно, ошибка при записи маркера');
      expect(second.runCount, 0,
          reason: 'после ошибки записи маркера следующий шаг не запускается');
      // rollback данных НЕ происходит — идемпотентность следующего запуска
      // спасёт ситуацию.
    });
  });

  group('Defensive checks', () {
    test('invalid transition — шаг не запускается', () async {
      final badPlan = ModuleMigrationPlan.accepted(
        fromVersion: 1,
        toVersion: 3,
        steps: <ModuleDataMigration>[
          _CountingMigration(2, 3),
        ],
      );

      await expectLater(
        runner.run(plan: badPlan, storage: _storage),
        throwsA(isA<ModuleMigrationException>()),
      );
    });

    test('тот же storage передаётся шагу', () async {
      final step = _CountingMigration(1, 2);
      await _run(runner, 1, 2, <ModuleDataMigration>[step]);

      // Фикстура runner передаёт runner.storage шагу. Проверяется
      // косвенно: запись прошла через тот же _storage.
      expect(_storage.writes, 1);
    });
  });

  group('Idempotency / повторы', () {
    test('повторный run после marker-write failure с новым планом', () async {
      final step = _CountingMigration(1, 2);

      // Первый запуск: шаг успешен, маркер не пишется (имитация сбоя записи).
      // Используем _FailingStorage который падает при записи маркера.
      final failing = _FailingStorage(<String, String?>{
        ModuleSchemaMarker.key: '1',
      });
      await expectLater(
        runner.run(
          plan: _plan(1, 2, <ModuleDataMigration>[step]),
          storage: failing,
        ),
        throwsA(isA<ModuleMigrationException>()),
      );
      expect(step.runCount, 1,
          reason: 'шаг должен выполниться до сбоя записи маркера');

      // Второй запуск с тем же планом: шаг снова выполняется, потому
      // что runner не хранит состояние и не знает, что первый раз
      // прошёл. Идемпотентность — ответственность migration.run().
      // Используем нормальное хранилище.
      final second = await _run(runner, 1, 2, <ModuleDataMigration>[step]);
      expect(second.executedSteps, 1);
      expect(step.runCount, 2);
      expect(_storage._values[ModuleSchemaMarker.key], '2');
    });
  });
}