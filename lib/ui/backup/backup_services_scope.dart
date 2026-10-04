/// Доступ экранов Backup к сервисам backup.
library backup_services_scope;

import 'package:flutter/material.dart';

import 'backup_file_service.dart';
import 'backup_gateway.dart';

/// Раздаёт [BackupGateway] и [BackupFileService] по дереву виджетов.
///
/// По образцу существующих scope проекта (ModuleManagerScope,
/// AppSettingsScope). Нужен по той же причине: экран backup не должен
/// сам конструировать менеджеры core, а тесты должны подставлять фейки
/// без Isar.
class BackupServicesScope extends InheritedWidget {
  const BackupServicesScope({
    super.key,
    required this.gateway,
    required this.fileService,
    required super.child,
  });

  final BackupGateway gateway;
  final BackupFileService fileService;

  static BackupGateway gatewayOf(BuildContext context) {
    return _scopeOf(context).gateway;
  }

  static BackupFileService fileServiceOf(BuildContext context) {
    return _scopeOf(context).fileService;
  }

  static BackupServicesScope _scopeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<BackupServicesScope>();
    assert(scope != null, 'BackupServicesScope не найден в дереве виджетов');
    return scope!;
  }

  @override
  bool updateShouldNotify(BackupServicesScope oldWidget) {
    return gateway != oldWidget.gateway ||
        fileService != oldWidget.fileService;
  }
}
