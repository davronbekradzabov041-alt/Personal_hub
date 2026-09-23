/// Ошибка недопустимого действия над жизненным циклом модуля.
///
/// Бросается ModuleManager: некорректный переход состояния
/// (enable неустановленного, повторный install, uninstall
/// включённого без предварительного disable), конфликт id,
/// отсутствие разрешения и т.п. Один тип ошибки на все такие
/// случаи — вызывающий код (будущий Module Store UI, Этап 12)
/// разбирает причину по `reason`, а не по типу исключения.
class ModuleLifecycleError implements Exception {
  final String moduleId;
  final String reason;

  const ModuleLifecycleError(this.moduleId, this.reason);

  @override
  String toString() => 'ModuleLifecycleError(id: $moduleId): $reason';
}
