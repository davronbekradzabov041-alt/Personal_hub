import 'package:flutter/material.dart';
import 'module_manager.dart';

/// Даёт доступ к единственному ModuleManager из любого места в дереве
/// виджетов через ModuleManagerScope.of(context) — по образцу
/// AppSettingsScope (Этап 4). Модуль читает через него своё текущее
/// состояние и получает ModuleApi для своих настроек (Этап 10),
/// не имея собственной ссылки на менеджер.
class ModuleManagerScope extends InheritedNotifier<ModuleManager> {
  const ModuleManagerScope({
    super.key,
    required ModuleManager manager,
    required super.child,
  }) : super(notifier: manager);

  static ModuleManager of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ModuleManagerScope>();
    assert(scope != null, 'ModuleManagerScope не найден в дереве виджетов');
    return scope!.notifier!;
  }
}
