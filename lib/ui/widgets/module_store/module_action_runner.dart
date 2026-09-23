import 'package:flutter/material.dart';
import '../../../core/modules/module_lifecycle_error.dart';

/// Запускает асинхронное действие над модулем (install/enable/
/// disable/uninstall/update) и показывает ModuleLifecycleError
/// снэкбаром вместо необработанного исключения в консоли.
///
/// Общий для всех секций Module Store — чтобы не дублировать один и
/// тот же try/catch в InstalledSection/AvailableSection/UpdateSection.
void runModuleAction(BuildContext context, Future<void> Function() action) {
  action().catchError((Object error) {
    if (!context.mounted) return;
    final message =
        error is ModuleLifecycleError ? error.reason : error.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  });
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
