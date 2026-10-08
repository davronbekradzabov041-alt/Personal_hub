import 'module_data_migration.dart';
import 'module_migration_plan.dart';
import 'module_migration_result.dart';
import 'module_schema_marker.dart';
import 'module_storage.dart';

/// Выполняет построенный план переноса данных (Этап 9.3).
///
/// Runner получает готовый [ModuleMigrationPlan] и [ModuleStorage] и
/// ничего больше: он не строит план, не читает маркер до проверки,
/// не делает снимок и не откатывает данные. Все решения о том, что и
/// когда переносить, — за вызывающим.
///
/// ## Порядок выполнения
///
/// 1. rejected plan — отказ без записи в хранилище;
/// 2. no-op — успех без записи в хранилище;
/// 3. marker check: фактическая версия схемы должна совпадать с
///    `plan.fromVersion` — иначе план устарел или данные трогал
///    кто-то ещё;
/// 4. шаги выполняются строго последовательно: следующий начинается
///    только после успешного завершения предыдущего;
/// 5. после каждого успешного `run()` пишется маркер с
///    `step.toVersion` — именно такой порядок, а не наоборот;
/// 6. исключение шага или ошибка записи маркера выходят наружу,
///    следующий шаг не запускается, отката данных нет.
///
/// ## Чему runner НЕ умеет
///
/// * строить план — за него отвечает `ModuleMigrationPlanner`;
/// * читать маркер и планировать сам — разделение ответственности;
/// * делать snapshot/rollback — Этап 9.4;
/// * интегрироваться в update/import/cold-start — тоже 9.4;
/// * глотать исключения миграции — оригинальная причина сохранена;
/// * повторять неудачный шаг — идемпотентность — дело `run()`.
class ModuleMigrationRunner {
  const ModuleMigrationRunner();

  /// Выполняет план переноса данных модуля.
  ///
  /// Возвращает значение только при полном успехе. Любой отказ —
  /// [ModuleMigrationException]: это то же самое разделение, что и в
  /// `ModuleInstallResult`/`ModuleManager`, только для переноса
  /// данных. Вызывающий (Этап 9.4) ловит исключение и принимает
  /// решение — откатывать снимок или предлагать повтор.
  Future<ModuleMigrationResult> run({
    required ModuleMigrationPlan plan,
    required ModuleStorage storage,
  }) async {
    if (!plan.isAccepted) {
      throw ModuleMigrationException.planRejected(
        fromVersion: plan.fromVersion,
        toVersion: plan.toVersion,
        reason: plan.reason ?? plan.violationsText,
      );
    }

    if (plan.steps.isEmpty) {
      return ModuleMigrationResult.noop(plan.toVersion);
    }

    final actual = await ModuleSchemaMarker.read(storage);
    if (actual != plan.fromVersion) {
      throw ModuleMigrationException.markerMismatch(
        actualVersion: actual,
        fromVersion: plan.fromVersion,
        toVersion: plan.toVersion,
      );
    }

    int executed = 0;
    var current = plan.fromVersion;

    for (final step in plan.steps) {
      if (step.fromVersion != current) {
        throw ModuleMigrationException.invalidTransition(
          fromVersion: plan.fromVersion,
          toVersion: plan.toVersion,
          detail: 'шаг ${step.fromVersion} → ${step.toVersion} не '
              'соответствует текущей версии $current — порядок шагов '
              'сломан или план построен неверно',
        );
      }

      try {
        await step.run(storage);
      } catch (error, stack) {
        throw ModuleMigrationException.migrationFailed(
          fromVersion: step.fromVersion,
          toVersion: step.toVersion,
          error: error,
          stackTrace: stack,
        );
      }

      executed++;
      current = step.toVersion;

      try {
        await ModuleSchemaMarker.write(storage, current);
      } catch (error, stack) {
        throw ModuleMigrationException.markerWriteFailed(
          fromVersion: step.fromVersion,
          toVersion: step.toVersion,
          error: error,
          stackTrace: stack,
        );
      }
    }

    return ModuleMigrationResult(
      fromVersion: plan.fromVersion,
      toVersion: plan.toVersion,
      executedSteps: executed,
    );
  }
}
