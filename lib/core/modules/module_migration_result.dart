/// Результат и ошибка выполнения плана переноса данных (Этап 9.3).
///
/// Отдельный файл от ModuleMigrationRunner — по образцу
/// ModuleInstallResult/ModuleInstallError: то, что возвращает и что
/// бросает операция, живёт рядом, а не внутри её реализации. Побочный
/// плюс — их можно прочитать, не открывая код выполнения.
///
/// ## Почему отказ — исключение, а не значение
///
/// ModuleUpdatePlan/ModuleMigrationPlan отвечают на вопрос «подходит
/// ли» — это решение о входных данных, и там отказ возвращается
/// значением. Здесь отказ означает, что данные уже трогали или сейчас
/// тронут и что-то пошло не так: прерванный перенос, чужой маркер,
/// невозможный шаг. Отправлять это значением значило бы заставить
/// вызывающего проверять успех в каждом месте, а забытое место тихо
/// продолжило бы перенос со сломанными данными. Поэтому всё, что не
/// удалось, — бросок; успех — значение.
library module_migration_result;

/// Причина, по которой план переноса не выполнен.
///
/// Коды — контракт: их значение читает вызывающий (Этап 9.4 развернёт
/// их в сообщение пользователю и в решение — откатывать снимок или
/// предлагать повтор). Тексты — для показа и потому могут меняться.
enum ModuleMigrationFailureCode {
  /// План не был принят планировщиком.
  ///
  /// Исполнять нечего и незачем: план без цепочки шагов — это не
  /// «перенос не нужен», а «перенос невозможен». Причина уже названа в
  /// самом плане, здесь она только переносится.
  planRejected,

  /// Фактическая версия схемы данных не совпадает с началом плана.
  ///
  /// План строится под конкретную исходную форму данных. Если маркер
  /// говорит о другой, то либо план устарел, либо данные трогал кто-то
  /// ещё. Исполнять такой план нельзя: шаг переведёт данные не из той
  /// формы, которую он ждёт. Runner планы не строит и не пересобирает —
  /// это решение вызывающего, у которого есть и план, и маркер.
  markerMismatch,

  /// Шаги плана не образуют заявленный переход.
  ///
  /// Планировщик такого плана не строит, но ModuleMigrationPlan —
  /// значение с публичным конструктором, и «недоверенный» план может
  /// прийти откуда угодно. Проверка выполняется целиком ДО первого
  /// шага, чтобы отказ такого рода не стоил половины выполненного
  /// переноса.
  invalidTransition,

  /// Шаг переноса бросил исключение.
  ///
  /// Оригинальная причина сохранена в [cause]: перенос данных — это
  /// чужой код, и подменять его «ошибка миграции» значило бы
  /// потерять настоящую причину.
  migrationFailed,

  /// Маркер версии не записался после успешного шага.
  ///
  /// Данные перенесены, а версия — нет. Шаг считается
  /// незавершённым: при следующем запуске он выполнится снова, и
  /// спасёт только его идемпотентность. Откат данных runner не делает
  /// и не имеет права делать — обратных переносов в системе нет.
  markerWriteFailed,
}

/// Перенос данных не выполнен.
///
/// Не иерархия типов, а один класс с машинным кодом и сохранённой
/// причиной: различать нужно пять случаев из [ModuleMigrationFailureCode],
/// а наследование для этого не требуется ничего.
class ModuleMigrationException implements Exception {
  /// Что именно не получилось.
  final ModuleMigrationFailureCode code;

  /// Текст для показа и для лога.
  final String message;

  /// Версия формы данных, на которой перенос остановился.
  ///
  /// Для `migrationFailed` и `markerWriteFailed` — `fromVersion`
  /// неудачного шага: данные уже в этой форме, а шаг не довёл её до
  /// нужной. Для остальных кодов — версия, с которой начинался план.
  final int fromVersion;

  /// Версия формы данных, которая достигнута (или должна была быть
  /// достигнута).
  ///
  /// Для `markerWriteFailed` особенно важно: она показывает, что данные
  /// УЖЕ в этой форме, и отличается от версии в маркере — это и есть
  /// суть сбоя.
  final int toVersion;

  /// Оригинальное исключение, если оно было.
  final Object? cause;

  /// Стек оригинального исключения.
  ///
  /// Сохраняется отдельно: переброс [cause] терял бы его, а
  /// «упало где-то у нас» вместо «упало здесь» в миграции модуля —
  /// диагностика, которой не хватает при разборе данных пользователя.
  final StackTrace? causeStackTrace;

  ModuleMigrationException._({
    required this.code,
    required this.message,
    required this.fromVersion,
    required this.toVersion,
    this.cause,
    this.causeStackTrace,
  });

  /// План отклонён планировщиком — до исполнения, до записи в хранилище.
  factory ModuleMigrationException.planRejected({
    required int fromVersion,
    required int toVersion,
    required String reason,
  }) {
    return ModuleMigrationException._(
      code: ModuleMigrationFailureCode.planRejected,
      message: 'план переноса отклонён: $reason',
      fromVersion: fromVersion,
      toVersion: toVersion,
    );
  }

  /// Маркер в хранилище говорит не о той форме данных, с которой
  /// начинался план.
  factory ModuleMigrationException.markerMismatch({
    required int actualVersion,
    required int fromVersion,
    required int toVersion,
  }) {
    return ModuleMigrationException._(
      code: ModuleMigrationFailureCode.markerMismatch,
      message: 'данные в схеме $actualVersion, а план переноса начинается '
          'со схемы $fromVersion — план устарел или данные переписаны',
      fromVersion: fromVersion,
      toVersion: toVersion,
    );
  }

  /// Шаги плана не образуют заявленный переход [fromVersion] → [toVersion].
  factory ModuleMigrationException.invalidTransition({
    required int fromVersion,
    required int toVersion,
    required String detail,
  }) {
    return ModuleMigrationException._(
      code: ModuleMigrationFailureCode.invalidTransition,
      message: 'шаги плана не образуют переход $fromVersion → $toVersion: '
          '$detail',
      fromVersion: fromVersion,
      toVersion: toVersion,
    );
  }

  /// Шаг переноса данных бросил [error].
  factory ModuleMigrationException.migrationFailed({
    required int fromVersion,
    required int toVersion,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return ModuleMigrationException._(
      code: ModuleMigrationFailureCode.migrationFailed,
      message: 'перенос данных $fromVersion → $toVersion не удался: $error',
      fromVersion: fromVersion,
      toVersion: toVersion,
      cause: error,
      causeStackTrace: stackTrace,
    );
  }

  /// Маркер версии не записался после успешного шага $fromVersion → [toVersion].
  factory ModuleMigrationException.markerWriteFailed({
    required int fromVersion,
    required int toVersion,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return ModuleMigrationException._(
      code: ModuleMigrationFailureCode.markerWriteFailed,
      message: 'данные перенесены в схему $toVersion, но маркер версии не '
          'записан: $error — перенос считается незавершённым и будет '
          'повторён',
      fromVersion: fromVersion,
      toVersion: toVersion,
      cause: error,
      causeStackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'ModuleMigrationException.${code.name}'
      '($fromVersion → $toVersion): $message';
}

/// Что сделал ModuleMigrationRunner.
///
/// Только успех: любой отказ — исключение, поэтому у результата нет
/// полей «ошибка» и «успех». Три числа и выведенный из них признак
/// no-op — это всё, что вызывающему действительно нужно знать.
class ModuleMigrationResult {
  /// Версия схемы данных до выполнения.
  final int fromVersion;

  /// Версия схемы данных после выполнения.
  ///
  /// Равна [toVersion] плана: исполнитель доводит именно до цели,
  /// промежуточная версия — это состояние прерванного переноса, а не
  /// результат.
  final int toVersion;

  /// Сколько шагов выполнено.
  ///
  /// Ноль у no-op. Больше нуля — перенос шёл; ровно столько же, сколько
  /// было в плане, значит выполнены все.
  final int executedSteps;

  const ModuleMigrationResult({
    required this.fromVersion,
    required this.toVersion,
    required this.executedSteps,
  });

  /// Данные уже в нужной форме: ни одного шага, ни одной записи.
  const ModuleMigrationResult.noop(int version)
      : this(fromVersion: version, toVersion: version, executedSteps: 0);

  /// Перенос не потребовался.
  ///
  /// Отдельный признак, а не вывод из нулевого [executedSteps]: у
  /// отклонённого переноса шагов тоже нет, и путать «нечего было
  /// делать» с «сделать не удалось» нельзя. Отказов здесь не бывает —
  /// они исключениями.
  bool get isNoop => executedSteps == 0;

  @override
  String toString() => isNoop
      ? 'ModuleMigrationResult.noop($toVersion)'
      : 'ModuleMigrationResult($fromVersion → $toVersion, шагов $executedSteps)';
}