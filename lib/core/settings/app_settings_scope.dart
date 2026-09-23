import 'package:flutter/material.dart';
import 'app_settings_controller.dart';

/// Даёт доступ к AppSettingsController из любого места в дереве
/// виджетов через AppSettingsScope.of(context), не прокидывая
/// контроллер вручную через конструкторы.
///
/// Использует стандартный InheritedNotifier из Flutter SDK —
/// без дополнительных пакетов управления состоянием.
class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope не найден в дереве виджетов');
    return scope!.notifier!;
  }
}
