import 'package:flutter/material.dart';
import '../../../core/modules/module_lifecycle_error.dart';
import '../../../core/modules/module_state_persistence.dart';
import '../../../core/modules/module_state_persistence_scope.dart';

/// Запускает асинхронное действие над модулем (install/enable/
/// disable/uninstall/update) и показывает ModuleLifecycleError
/// снэкбаром вместо необработанного исключения в консоли.
///
/// Общий для всех секций Module Store — чтобы не дублировать один и
/// тот же try/catch в InstalledSection/AvailableSection/UpdateSection.
///
/// Действие выполняется через
/// [ModuleStatePersistence.runAndFlush], то есть считается завершённым
/// ТОЛЬКО после того, как новое состояние модуля реально записано в
/// хранилище. Без этого `await manager.uninstall(id)` возвращался до
/// записи tombstone: убитый в этот момент процесс приводил к тому,
/// что модуль воскресал при следующем старте. Здесь — единственное
/// место в UI, где lifecycle-операция доводится до записи, поэтому
/// все секции Module Store получают гарантию автоматически.
///
/// Возвращает Future: вызывающий (в том числе тест) может дождаться
/// завершения операции вместе с записью состояния.
Future<void> runModuleAction(
  BuildContext context,
  Future<void> Function() action,
) {
  return _run(context, action);
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    final persistence = ModuleStatePersistenceScope.of(context);
    await persistence.runAndFlush(action);
  } catch (error) {
    if (!context.mounted) return;
    final message = _messageFor(error);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Текст для снэкбара: без стектрейса и внутренних имён исключений.
String _messageFor(Object error) {
  if (error is ModuleLifecycleError) return error.reason;
  if (error is ModuleStatePersistenceException) return error.reason;
  return error.toString();
}

/// Показывает список ошибок валидации (ManifestValidator/ManifestParser)
/// снэкбаром — используется при установке из каталога, когда сбой
/// происходит ДО того, как появляется что-либо, над чем можно было бы
/// вызвать runModuleAction.
void showModuleErrors(BuildContext context, List<String> errors) {
  if (!context.mounted || errors.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(errors.join('; '))),
  );
}
