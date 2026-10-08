/// Типизированный результат планирования переноса данных (Этап 9.2).
///
/// По образцу ModuleUpdatePlan (Этап 8): успех/провал с общей причиной
/// и СПИСКОМ нарушений. Список, а не одна строка, потому что отказов
/// бывает несколько сразу — модуль может объявить и шаг `1 -> 1`, и шаг
/// `3 -> 2`, — и показывать их по одному пользователю нельзя.
///
/// Отличие от ModuleUpdatePlan — в предмете. Там версия КОДА модуля
/// (ModuleVersion, строгая X.Y.Z), здесь — целое число: счётчик переносов
/// формы данных. Поэтому здесь нет ни ModuleVersion, ни manifest'а:
/// планировщик работает с числами и шагами, и больше ни с чем.
library module_migration_plan;

import 'module_data_migration.dart';

/// Причина, по которой план переноса не построен.
///
/// Коды — контракт: их значение читает вызывающий, а тексты только
/// показываются человеку и потому могут меняться. UI обновления
/// (Этапы 10/12) обязан выбирать заголовок и действие по коду, а не
/// разбирать русские строки.
enum ModuleMigrationViolationCode {
  /// Непрерывной forward-цепочки из текущей версии в целевую не
  /// существует.
  ///
  /// Данные лежат в форме, которую новый код понять не может, а шага,
  /// который приводит их к ожидаемой форме, модуль не объявил.
  /// Обновление обязано быть отклонено ДО снимка и до любой записи,
  /// потому что начатый перенос без конца — это данные в промежуточной
  /// форме, из которой не выходит ни одна версия кода.
  migrationMissing,

  /// Данные в более новой форме, чем ожидает новая версия модуля.
  ///
  /// Migration System проектировалась только для движения вперёд:
  /// откат формы данных — это не перенос, а чтение уже изменённых
  /// данных старым кодом. Обратных шагов в системе нет, и объявлять
  /// их не предусмотрено.
  dataSchemaIncompatible,

  /// Из одной версии выходит несколько переходов, ведущих к цели.
  ///
  /// Результат зависел бы от порядка элементов в `dataMigrations`, а это
  /// ровно тот вид зависимости, который нельзя оставлять в механизме,
  /// меняющем данные пользователя: тот же модуль, собранный иначе,
  /// переносил бы данные иначе. Поэтому выбор не делается вовсе.
  ambiguousMigrations,

  /// Переход объявлен неверно.
  ///
  /// `toVersion` не больше `fromVersion`: шаг `1 -> 1` не переносит
  /// ничего, а `2 -> 1` — откат, которого в системе нет. Сюда же
  /// попадают неположительные номера версий и повторное объявление
  /// одного и того же перехода.
  invalidMigrationDefinition,

  /// Номер версии схемы на входе планировщика недопустим.
  ///
  /// Отдельный код, а не `invalidMigrationDefinition`: неверна не
  /// декларация модуля, а то, что вызывающий передал планировщику.
  /// `ModuleManifest.fromJson` такое значение уже не пропускает, но
  /// планировщик — публичная точка входа со своим контрактом и
  /// обязан проверить его сам, а не рассчитывать на то, что каждый
  /// вызывающий вспомнил про правило из другого файла.
  invalidSchemaVersion,
}

/// Одно нарушение: машинный код плюс текст для показа.
class ModuleMigrationViolation {
  final ModuleMigrationViolationCode code;
  final String message;

  const ModuleMigrationViolation(this.code, this.message);

  @override
  String toString() => message;
}

/// План переноса данных модуля: построен или отклонён.
///
/// ## План — это ЗНАЧЕНИЕ, а не действие
///
/// Ни один шаг [steps] не выполнен и не будет выполнен при создании
/// плана. Это проверяемое утверждение о том, что цепочка существует и
/// приводит данные к нужной форме, — ровно то, что нужно знать ДО
/// снимка, до обмена песочницы и до первой записи. Исполнитель
/// (Этап 9.3) получит этот список и выполнит его; сам план не знает,
/// кто и когда это сделает.
///
/// ## Порядок шагов значим
///
/// [steps] упорядочен: первый шаг переводит данные из [fromVersion] в
/// версию, которую ждёт второй, и так до [toVersion]. Исполнитель
/// обязан идти ровно в этом порядке, поэтому переупорядочивать список
/// на стороне вызывающего нельзя.
class ModuleMigrationPlan {
  final bool isAccepted;

  /// Версия формы данных, в которой они лежат сейчас.
  final int fromVersion;

  /// Версия формы данных, которой ждёт новая версия модуля.
  final int toVersion;

  /// Упорядоченные шаги. Пуст у успешного no-op.
  final List<ModuleDataMigration> steps;

  /// Нарушения. Пустой список при [isAccepted].
  final List<ModuleMigrationViolation> violations;

  /// Общая причина отказа одной строкой.
  final String? reason;

  const ModuleMigrationPlan._({
    required this.isAccepted,
    required this.fromVersion,
    required this.toVersion,
    required this.steps,
    this.violations = const <ModuleMigrationViolation>[],
    this.reason,
  });

  /// Цепочка найдена и приводит данные из [fromVersion] в [toVersion].
  ///
  /// Пустой [steps] при равных версиях — не «план не построен», а
  /// нормальный успешный ответ: перенос не нужен.
  ModuleMigrationPlan.accepted({
    required int fromVersion,
    required int toVersion,
    required List<ModuleDataMigration> steps,
  }) : this._(
          isAccepted: true,
          fromVersion: fromVersion,
          toVersion: toVersion,
          // Список шагов копируется и замораживается: план переживает
          // вызывающего, и переупорядочивание steps на стороне исполнителя
          // сломало бы порядок, ради которого он и построен.
          steps: List<ModuleDataMigration>.unmodifiable(steps),
        );

  /// Цепочки нет; [violations] обязателен: план без причины отказа
  /// был бы неотличим от успешного.
  ModuleMigrationPlan.rejected({
    required int fromVersion,
    required int toVersion,
    required String reason,
    required List<ModuleMigrationViolation> violations,
  }) : this._(
          isAccepted: false,
          fromVersion: fromVersion,
          toVersion: toVersion,
          steps: const <ModuleDataMigration>[],
          violations: List<ModuleMigrationViolation>.unmodifiable(violations),
          reason: reason,
        );

  /// Нужен ли перенос вообще.
  ///
  /// Отдельный флаг, а не вывод из пустого [steps]: у отклонённого
  /// плана шагов тоже нет, и путать «перенос не нужен» с «перенос
  /// невозможен» нельзя.
  bool get isRequired => isAccepted && steps.isNotEmpty;

  /// Нарушения, собранные в одну строку через "; " — так же, как
  /// ModuleUpdatePlan разворачивается в ModuleLifecycleError.
  String get violationsText =>
      violations.map((v) => v.message).join('; ');

  @override
  String toString() {
    if (!isAccepted) {
      return 'ModuleMigrationPlan.rejected($fromVersion → $toVersion, '
          '$violationsText)';
    }
    if (steps.isEmpty) return 'ModuleMigrationPlan.accepted($fromVersion)';
    final chain = steps
        .map((s) => '${s.fromVersion}→${s.toVersion}')
        .join(', ');
    return 'ModuleMigrationPlan.accepted($fromVersion → $toVersion: $chain)';
  }
}