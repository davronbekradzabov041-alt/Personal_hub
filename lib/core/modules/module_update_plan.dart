/// Типизированный результат проверки обновления модуля (Этап 8).
///
/// По образцу ModuleInstallResult (Этап 13): успех/провал с общей
/// причиной и СПИСКОМ отдельных нарушений. Список, а не одна строка,
/// потому что отказов бывает несколько сразу — несовместимый
/// apiVersion И недоступная зависимость, — и показывать их по одному
/// за попытку обновления пользователю нельзя.
///
/// Отличие от ModuleInstallResult — в [ModuleUpdateViolation.code]:
/// у нарушения есть машинный код, а не только текст. UI обновления
/// (Этап 8.1-Б) должен решать по коду, а не разбирать русские строки,
/// иначе любая правка формулировки в проверке тихо ломает экран.
library module_update_plan;

import 'module_version.dart';

/// Причина отказа от обновления.
///
/// Коды — контракт: их значение может читать вызывающий. Тексты — для
/// показа пользователю и потому могут меняться.
enum ModuleUpdateViolationCode {
  /// Модуль не установлен: обновлять нечего.
  moduleNotInstalled,

  /// Новый манифест описывает другой moduleId.
  ///
  /// Отдельный код, а не «невалидный id»: подмена id в обновлении —
  /// это попытка заменить один модуль другим, и молчаливый отказ здесь
  /// опаснее всего остального.
  moduleIdMismatch,

  /// Текущая (установленная) версия не разбирается как X.Y.Z.
  ///
  /// Обновление отказывается: невозможно доказать, что новая версия
  /// новее. Сравнение строк вместо разбора означало бы, что «1.x»
  /// случайно окажется новее «0.9.0».
  invalidCurrentVersion,

  /// Новая версия не разбирается как X.Y.Z.
  invalidNewVersion,

  /// Новая версия равна установленной — обновлять нечего.
  versionNotHigher,

  /// Новая версия МЕНЬШЕ установленной, а политика запрещает откат.
  ///
  /// Откат версии — это не «обновление», а возврат к прошлому, и по
  /// умолчанию он запрещён: у пользователя могут быть данные, которых
  /// старая версия не понимает.
  downgradeNotAllowed,

  /// apiVersion новой версии вне диапазона, который понимает ядро.
  apiVersionNotSupported,

  /// apiVersion новой версии ниже, чем у установленной.
  apiVersionDowngradeNotAllowed,

  /// Зависимость новой версии не установлена.
  dependencyNotInstalled,

  /// Установленная зависимость старше, чем требует новая версия.
  dependencyVersionTooLow,

  /// Граф зависимостей с новой версией содержит цикл.
  dependencyCycle,

  /// Нарушение базовых правил манифеста (id, формат версии, apiVersion).
  manifestInvalid,
}

/// Одно нарушение: код + текст для показа.
class ModuleUpdateViolation {
  final ModuleUpdateViolationCode code;
  final String message;

  const ModuleUpdateViolation(this.code, this.message);

  @override
  String toString() => message;
}

/// План обновления: принят или отклонён.
///
/// Принятый план — это ещё НЕ обновление. Он ничего не меняет и
/// ничего не гарантирует выполнения: между проверкой и swap может
/// измениться всё (см. Этап 8.1-Б, где план используется как
/// разрешение на подготовку, а не как действие).
class ModuleUpdatePlan {
  /// Обновление разрешено.
  final bool isAccepted;

  final String moduleId;

  /// Версия, которая установлена сейчас.
  final ModuleVersion? fromVersion;

  /// Версия, которую предлагают поставить.
  final ModuleVersion? toVersion;

  /// Новая версия строго ниже установленной.
  ///
  /// Отдельный флаг, а не вывод из [fromVersion]/[toVersion]: при
  /// [allowDowngrade] откат разрешён, но вызывающий всё равно обязан
  /// знать, что он именно откатывает.
  final bool isDowngrade;

  /// Нарушения. Пустой список при [isAccepted].
  final List<ModuleUpdateViolation> violations;

  /// Общая причина отказа одной строкой.
  final String? reason;

  const ModuleUpdatePlan._({
    required this.isAccepted,
    required this.moduleId,
    this.fromVersion,
    this.toVersion,
    this.isDowngrade = false,
    this.violations = const [],
    this.reason,
  });

  const ModuleUpdatePlan.accepted({
    required String moduleId,
    required ModuleVersion fromVersion,
    required ModuleVersion toVersion,
    required bool isDowngrade,
  }) : this._(
          isAccepted: true,
          moduleId: moduleId,
          fromVersion: fromVersion,
          toVersion: toVersion,
          isDowngrade: isDowngrade,
        );

  const ModuleUpdatePlan.rejected({
    required String moduleId,
    required String reason,
    required List<ModuleUpdateViolation> violations,
    ModuleVersion? fromVersion,
    ModuleVersion? toVersion,
    bool isDowngrade = false,
  }) : this._(
          isAccepted: false,
          moduleId: moduleId,
          reason: reason,
          violations: violations,
          fromVersion: fromVersion,
          toVersion: toVersion,
          isDowngrade: isDowngrade,
        );

  /// Нарушения, собранные в одну строку через "; " — так же, как
  /// ModuleInstallResult разворачивается в ModuleLifecycleError.
  String get violationsText =>
      violations.map((v) => v.message).join('; ');

  @override
  String toString() => isAccepted
      ? 'ModuleUpdatePlan.accepted($moduleId, $fromVersion → $toVersion)'
      : 'ModuleUpdatePlan.rejected($moduleId, $violationsText)';
}

/// Политика обновлений: что вообще разрешено.
///
/// Вынесена отдельно от валидатора, потому что это РЕШЕНИЕ продукта,
/// а не правило проверки. Значения по умолчанию — запретительные:
/// безопасное поведение должно быть поведением по умолчанию, а не
/// тем, что вызывающий обязан не забыть выключить.
class ModuleUpdatePolicy {
  /// Разрешать откат версии (новая строго ниже установленной).
  ///
  /// Выключено по умолчанию: у пользователя могут быть данные, которых
  /// старая версия не понимает, а «откатить, чтобы заработало» —
  /// это решение, которое принимают осознанно.
  final bool allowDowngrade;

  /// Разрешать понижение apiVersion (контракта Module API).
  ///
  /// Выключено по умолчанию. При allowDowngrade=true понижение версии
  /// модуля всё равно может понизить и apiVersion, если новый пакет
  /// собран под более старый контракт, — этот флаг решает именно это.
  final bool allowApiVersionDowngrade;

  const ModuleUpdatePolicy({
    this.allowDowngrade = false,
    this.allowApiVersionDowngrade = false,
  });
}