/// Единый типизированный результат установки модуля (Этап 13).
///
/// До этого этапа ModuleManager.install() сообщал об ошибке только
/// через исключение (ModuleLifecycleError) — рабочий, но не тот
/// типизированный результат, который задание Этапа 13 просит для
/// установки: success/failure с причиной И списком отдельных
/// нарушений (несовместимый apiVersion, невыполненные зависимости,
/// циклы — их может быть несколько сразу).
///
/// `ModuleManager.install()` не убран и не сломан — он остаётся
/// тонкой обёрткой над `tryInstall()`, разворачивающей этот результат
/// обратно в исключение для уже существующих вызывающих (Этапы 8/10/12,
/// которые ловят ModuleLifecycleError). Новые вызывающие могут
/// использовать `tryInstall()` напрямую и работать с обычным
/// значением, а не try/catch.
class ModuleInstallResult {
  final bool isSuccess;
  final String moduleId;

  /// Общая причина отказа (для отображения одной строкой).
  final String? reason;

  /// Отдельные нарушения — может быть несколько сразу (например,
  /// несовместимая apiVersion И невыполненная зависимость одновременно).
  final List<String> violations;

  const ModuleInstallResult._({
    required this.isSuccess,
    required this.moduleId,
    this.reason,
    this.violations = const [],
  });

  const ModuleInstallResult.success(String moduleId)
      : this._(isSuccess: true, moduleId: moduleId);

  const ModuleInstallResult.failure(
    String moduleId, {
    required String reason,
    List<String> violations = const [],
  }) : this._(
          isSuccess: false,
          moduleId: moduleId,
          reason: reason,
          violations: violations,
        );
}
