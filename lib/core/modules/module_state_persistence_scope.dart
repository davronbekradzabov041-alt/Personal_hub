import 'package:flutter/material.dart';
import 'module_state_persistence.dart';

/// Даёт доступ к существующему экземпляру ModuleStatePersistence из
/// любого места в дереве виджетов — по образцу ModuleManagerScope.
///
/// Зачем это нужно. ModuleManager.notifyListeners() синхронен, а запись
/// состояния в Isar — асинхронна, поэтому `await manager.uninstall(id)`
/// возвращался раньше, чем tombstone попадал в базу. Между этими
/// моментами процесс можно завершить, и модуль воскресает при
/// следующем старте. Чтобы операция считалась выполненной только
/// после сохранения состояния, вызывающий ждёт
/// `ModuleStatePersistence.runAndFlush(...)` — и для этого ему нужен
/// тот же самый экземпляр, который уже подписан на менеджер в
/// main.dart.
///
/// Это НЕ новый сервис и не singleton: экземпляр по-прежнему создаётся
/// один раз в main.dart, здесь он лишь передаётся по дереву. Новые
/// подписки на менеджер не создаются.
class ModuleStatePersistenceScope extends InheritedWidget {
  const ModuleStatePersistenceScope({
    super.key,
    required this.persistence,
    required super.child,
  });

  final ModuleStatePersistence persistence;

  /// Экземпляр не подменяется на лету: дерево строится один раз, а
  /// пересоздавать InheritedWidget ради той же ссылки незачем.
  @override
  bool updateShouldNotify(ModuleStatePersistenceScope oldWidget) =>
      oldWidget.persistence != persistence;

  static ModuleStatePersistence of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ModuleStatePersistenceScope>();
    assert(
      scope != null,
      'ModuleStatePersistenceScope не найден в дереве виджетов — '
      'без него состояние модулей не дожидается записи',
    );
    return scope!.persistence;
  }
}
