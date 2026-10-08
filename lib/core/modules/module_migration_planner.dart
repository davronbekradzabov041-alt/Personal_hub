/// Планировщик переноса данных модуля (Этап 9.2).
///
/// ## Что это
///
/// Чистая функция от трёх чисел и списка шагов: «можно ли построить
/// корректную цепочку `ModuleDataMigration` из текущей версии схемы в
/// целевую, и если да — какая». Возвращает [ModuleMigrationPlan] —
/// значение, а не действие: ни один шаг не выполняется, маркер версии
/// не пишется, данные не меняются.
///
/// ## Почему это безопасно делать ДО снимка
///
/// Целевой порядок обновления: validate → build plan → reject if
/// impossible → snapshot → update → execute plan. Планирование стоит
/// перед снимком именно потому, что оно ничего не трогает: если цепочки
/// нет, снимок снимать незачем, а данные уже целы. Отсюда и запрет на
/// любой ввод-вывод здесь — планировщик не читает даже маркер версии,
/// хотя это единственное место, где лежит фактическая форма данных:
/// читать его — значит сделать планирование зависимым от того, что
/// успел сделать мигратор при прошлом запуске.
///
/// ## Чего планировщик не знает
///
/// Ничего, кроме номеров версий и шагов. Ни Isar, ни ModuleStorage, ни
/// файловой системы, ни реестра модулей, ни состояния, ни жизненного
/// цикла, ни версии КОДА модуля (`ModuleManifest.version` /
/// `installedVersion`) — форма данных и версия публикации живут разными
/// шкалами, и смешение их здесь означало бы решение о переносе по
/// денормализованному зеркалу манифеста.
///
/// ## Почему проверка определений здесь, а не в контракте шага
///
/// ModuleDataMigration — это объявление модуля, то есть вход. Ошибку в
/// нём (шаг `1 -> 1`, откат `3 -> 2`, ноль вместо версии) дешевле и
/// надёжнее поймать здесь, единым правилом для всех модулей, чем
/// надеяться, что каждый автор шага проверил себя сам. Поэтому правила
/// определения проверяются для ВСЕХ объявленных шагов, а не только для
/// попавших в цепочку: молча проигнорировать сломанное объявление —
/// значит узнать о нём уже на середине переноса.
library module_migration_planner;

import 'module_data_migration.dart';
import 'module_migration_plan.dart';

/// Строит цепочку переноса данных или объясняет, почему её построить
/// нельзя.
///
/// Экземпляр не хранит состояния, поэтому класс можно создавать
/// константой и передавать куда угодно; состояние живёт в
/// [ModuleMigrationPlan].
class ModuleMigrationPlanner {
  const ModuleMigrationPlanner();

  /// Планирует перенос из [currentSchemaVersion] в
  /// [targetSchemaVersion], используя объявленные модулем [migrations].
  ///
  /// Список принимается как есть (а не как `Module`) сознательно:
  /// планировщик не должен знать ни про модули, ни про реестр — на входе
  /// достаточно того, что умеет перечислить `Module.dataMigrations`.
  /// Принимать модуль целиком означало бы связать планирование с тем,
  /// чем оно не пользуется.
  ///
  /// Возвращает значение всегда: и отказ здесь — это результат
  /// планирования, а не ошибка вызывающего. Бросать исключение было бы
  /// неверно по той же причине, по которой ModuleUpdateValidator
  /// возвращает ModuleUpdatePlan, а не бросает: «перенести нельзя» —
  /// это решение о модуле, а не авария приложения.
  ModuleMigrationPlan plan({
    required int currentSchemaVersion,
    required int targetSchemaVersion,
    List<ModuleDataMigration> migrations = const <ModuleDataMigration>[],
  }) {
    // --- Порядок проверок ---
    //
    // Проверки идут от самой грубой к самой тонкой, и порядок здесь
    // содержательный, а не произвольный:
    //
    // 1. Номера версий. Пока они недопустимы, любое сравнение бессмысленно
    //    (`current > target` при current = 0 сказало бы что-то о версиях,
    //    которых не существует), поэтому этот отказ — первый.
    // 2. Направление. Данные впереди цели — не «цепочка не найдена», а
    //    «система не умеет назад». Проверять объявления после этого
    //    бессмысленно: обратный ход запрещён независимо от того, что
    //    модуль наобъявлял.
    // 3. Объявления. Только когда направление возможно, имеет смысл
    //    разбирать, что именно объявлено.
    if (currentSchemaVersion < 1 || targetSchemaVersion < 1) {
      return _reject(
        currentSchemaVersion,
        targetSchemaVersion,
        'номер версии схемы данных недопустим',
        <ModuleMigrationViolation>[
          ModuleMigrationViolation(
            ModuleMigrationViolationCode.invalidSchemaVersion,
            'номер версии схемы данных должен быть не меньше 1, получено '
            '$currentSchemaVersion → $targetSchemaVersion',
          ),
        ],
      );
    }

    if (currentSchemaVersion > targetSchemaVersion) {
      return _reject(
        currentSchemaVersion,
        targetSchemaVersion,
        'система переноса допускает только движение вперёд',
        <ModuleMigrationViolation>[
          ModuleMigrationViolation(
            ModuleMigrationViolationCode.dataSchemaIncompatible,
            'данные в схеме $currentSchemaVersion, а новая версия ждёт '
            'схему $targetSchemaVersion — обратный перенос не поддерживается',
          ),
        ],
      );
    }

    // Канонический порядок объявлений — сортировкой по (from, to),
    // а не по месту в списке: план обязан зависеть от НАБОРА переходов.
    final declared = _canonicallySorted(migrations);

    final invalid = _invalidDefinitions(declared);
    if (invalid.isNotEmpty) {
      return _reject(
        currentSchemaVersion,
        targetSchemaVersion,
        'переходы объявлены неверно',
        invalid,
      );
    }

    // Данные уже в нужной форме. Это успех, а не отсутствие успеха:
    // модуль без переносов — норма, и вызывающий не должен отличать
    // этот случай от «план построен и пуст».
    if (currentSchemaVersion == targetSchemaVersion) {
      return ModuleMigrationPlan.accepted(
        fromVersion: currentSchemaVersion,
        toVersion: targetSchemaVersion,
        steps: const <ModuleDataMigration>[],
      );
    }

    return _search(
      from: currentSchemaVersion,
      to: targetSchemaVersion,
      declared: declared,
    );
  }

  /// Отклонённый план: общая причина плюс список нарушений.
  ///
  /// Нарушений может быть несколько — сломанных объявлений, как правило,
  /// не одно, — и в `_search` оно всегда одно. Общая причина нужна в
  /// любом случае: версии уже названы в подписи, а причина «как класс
  /// отказа» читается по ней, не разбирая тексты.
  ModuleMigrationPlan _reject(
    int from,
    int to,
    String reason,
    List<ModuleMigrationViolation> violations,
  ) {
    return ModuleMigrationPlan.rejected(
      fromVersion: from,
      toVersion: to,
      reason: reason,
      violations: violations,
    );
  }

  /// Сортирует объявления по паре (fromVersion, toVersion).
  ///
  /// Порядок входного списка — это порядок, в котором автор перечислил
  /// шаги, а не правило выбора: тот же набор переходов, перечисленный
  /// иначе, обязан дать тот же план. Сортировкой сравнение приводится к
  /// каноническому виду, и все решения дальше принимаются по нему.
  ///
  /// List.sort в Dart не стабилен, но здесь это безопасно: совпасть
  /// могут только два объявления одной и той же пары, а такое объявление
  /// отвергается как повторное, и обе записи дают ОДИН И ТОТ ЖЕ текст
  /// нарушения.
  static List<ModuleDataMigration> _canonicallySorted(
    List<ModuleDataMigration> migrations,
  ) {
    final sorted = List<ModuleDataMigration>.of(migrations);
    sorted.sort((a, b) {
      final byFrom = a.fromVersion.compareTo(b.fromVersion);
      if (byFrom != 0) return byFrom;
      return a.toVersion.compareTo(b.toVersion);
    });
    return sorted;
  }

  /// Проверяет объявленные переходы и возвращает нарушения в
  /// каноническом порядке.
  ///
  /// Требуемое правило одно: `from >= 1` и `to > from`. Всё остальное —
  /// следствия. Откат (`to < from`) и пустой шаг (`to == from`)
  /// запрещены; версия `0` или меньше не является номером версии схемы
  /// (та же граница, что и в ModuleManifest.schemaVersion); повторное
  /// объявление одной пары сделало бы выбор шага зависимым от порядка
  /// списка.
  ///
  /// Циклов здесь не проверяется отдельно, и это не упущение: условие
  /// `to > from` делает граф ориентированным по возрастанию числа, а
  /// значит ациклическим по построению. Цикл из одних только возрастающих
  /// рёбер невозможен, поэтому отдельный обход графа был бы проверкой
  /// невозможного.
  static List<ModuleMigrationViolation> _invalidDefinitions(
    List<ModuleDataMigration> declared,
  ) {
    final violations = <ModuleMigrationViolation>[];
    final seen = <String>{};

    for (final step in declared) {
      final from = step.fromVersion;
      final to = step.toVersion;

      if (from < 1 || to < 1) {
        violations.add(ModuleMigrationViolation(
          ModuleMigrationViolationCode.invalidMigrationDefinition,
          'номер версии в переходе $from → $to должен быть не меньше 1',
        ));
        continue;
      }

      if (to == from) {
        violations.add(ModuleMigrationViolation(
          ModuleMigrationViolationCode.invalidMigrationDefinition,
          'переход $from → $to ничего не переносит',
        ));
        continue;
      }

      if (to < from) {
        violations.add(ModuleMigrationViolation(
          ModuleMigrationViolationCode.invalidMigrationDefinition,
          'переход $from → $to уводит данные назад, а система переноса '
          'допускает только движение вперёд',
        ));
        continue;
      }

      if (!seen.add('$from→$to')) {
        violations.add(ModuleMigrationViolation(
          ModuleMigrationViolationCode.invalidMigrationDefinition,
          'переход $from → $to объявлен дважды',
        ));
      }
    }

    return violations;
  }

  /// Ищет цепочку из [from] в [to] по уже проверенным [declared].
  ///
  /// Шаг за шагом, без перебора путей: из текущей версии берётся
  /// единственный доступный переход, не перескакивающий мимо цели.
  /// Единственный — потому что при нескольких подходящих планирование
  /// прерывается как неоднозначное, а не выбирает одно из них.
  ///
  /// Поиск обязан завершиться, и завершается он по построению: версия
  /// строго растёт на каждом шаге и не может превысить [to] (переходы,
  /// ведущие выше, отсекаются при отборе), поэтому число итераций не
  /// больше `to - from`. Никакого графа в общем случае тут не нужно.
  ModuleMigrationPlan _search({
    required int from,
    required int to,
    required List<ModuleDataMigration> declared,
  }) {
    // Переходы, годящиеся в цепочку. Шаг, перескакивающий мимо целевой
    // версии (`1 -> 5` при цели 4), не отбрасывается как ошибочный —
    // объявление само по себе законное, — но в цепочку не входит: после
    // него версия формы данных уже никогда не станет равной 4.
    final usable = <int, List<ModuleDataMigration>>{};
    for (final step in declared) {
      if (step.toVersion > to) continue;
      (usable[step.fromVersion] ??= <ModuleDataMigration>[]).add(step);
    }

    // Достижимость цели: можно ли дойти из версии V до `to`.
    //
    // Считается обходом вершин ПО УБЫВАНИЮ: каждое ребро ведёт в
    // строго большую версию, поэтому нужный ответ для `toVersion` к этому
    // моменту уже известен. Ничего не перебирается и ничего не
    // пересчитывается — один проход по отсортированному списку ключей.
    //
    // Нужна ровно там, где переходов из версии несколько: с одним
    // переходом выбора нет, и спрашивать «ведёт ли он к цели» незачем.
    final canReachTarget = <int, bool>{to: true};
    final versions = usable.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final version in versions) {
      canReachTarget[version] = usable[version]!
          .any((step) => canReachTarget[step.toVersion] ?? false);
    }

    final steps = <ModuleDataMigration>[];
    var version = from;

    while (version < to) {
      final available = usable[version] ?? const <ModuleDataMigration>[];

      if (available.isEmpty) {
        return _missing(from: from, to: to, stuckAt: version,
            declared: declared);
      }

      var chosen = available;
      if (available.length > 1) {
        // Несколько переходов из одной версии: оставить можно только
        // те, из которых цель достижима. Если таких нет — обрыв здесь,
        // если их несколько — выбирать нельзя.
        final viable = available
            .where((step) => canReachTarget[step.toVersion] ?? false)
            .toList();
        if (viable.isEmpty) {
          return _missing(from: from, to: to, stuckAt: version,
              declared: declared);
        }
        if (viable.length > 1) {
          return _ambiguous(from: from, to: to, at: version,
              candidates: viable);
        }
        chosen = viable;
      }

      // Единственный переход из версии берётся без проверки достижимости:
      // выбора всё равно нет, а пройти по нему позволяет сообщить об
      // обрыве на ТОЙ версии, где он и случился. Отказ с указанием
      // предыдущей версии («из схемы 1 нет перехода») при этом читался бы
      // неверно: переход из неё есть, он просто ведёт в никуда.
      steps.add(chosen.single);
      version = chosen.single.toVersion;
    }

    return ModuleMigrationPlan.accepted(
      fromVersion: from,
      toVersion: to,
      steps: steps,
    );
  }

  /// Отказ `migrationMissing`: цепочки нет, и версия обрыва названа.
  ModuleMigrationPlan _missing({
    required int from,
    required int to,
    required int stuckAt,
    required List<ModuleDataMigration> declared,
  }) {
    return _reject(
      from,
      to,
      'цепочка переноса не найдена',
      <ModuleMigrationViolation>[
        ModuleMigrationViolation(
          ModuleMigrationViolationCode.migrationMissing,
          _missingMessage(
            from: from,
            to: to,
            stuckAt: stuckAt,
            declared: declared,
          ),
        ),
      ],
    );
  }

  /// Отказ `ambiguousMigrations`: подходящих переходов больше одного.
  ModuleMigrationPlan _ambiguous({
    required int from,
    required int to,
    required int at,
    required List<ModuleDataMigration> candidates,
  }) {
    return _reject(
      from,
      to,
      'цепочка переноса неоднозначна',
      <ModuleMigrationViolation>[
        ModuleMigrationViolation(
          ModuleMigrationViolationCode.ambiguousMigrations,
          'из схемы $at объявлено ${candidates.length} перехода, ведущих '
          'к схеме $to: ${_describe(candidates)} — выбрать один '
          'произвольно нельзя',
        ),
      ],
    );
  }

  /// Объяснение для `migrationMissing` с указанием версии, на которой
  /// цепочка оборвалась, и — если таковая есть — шага, который её
  /// перескочил.
  ///
  /// Сама причина и её код от этого не меняются: переход выше целевой
  /// версии не делает план возможным, а отдельный код ради одного
  /// случая заводить не стоит. Но сказать пользователю «нет перехода из
  /// схемы 1» там, где модуль объявил `1 → 5`, — значит оставить его
  /// гадать, что именно объявлено не так.
  static String _missingMessage({
    required int from,
    required int to,
    required int stuckAt,
    required List<ModuleDataMigration> declared,
  }) {
    final overshooting = declared
        .where((step) =>
            step.fromVersion == stuckAt && step.toVersion > to)
        .toList();

    final detail = overshooting.isEmpty
        ? ''
        : ' (объявлены переходы мимо цели: ${_describe(overshooting)})';
    return 'из схемы $stuckAt нет перехода, доводящего данные до схемы $to'
        ' (перенос из $from)$detail';
  }

  /// Перечисление переходов одной строкой: `1 → 2, 1 → 3`.
  static String _describe(List<ModuleDataMigration> steps) {
    final sorted = List<ModuleDataMigration>.of(steps)
      ..sort((a, b) {
        final byFrom = a.fromVersion.compareTo(b.fromVersion);
        return byFrom != 0 ? byFrom : a.toVersion.compareTo(b.toVersion);
      });
    return sorted.map((s) => '${s.fromVersion} → ${s.toVersion}').join(', ');
  }
}