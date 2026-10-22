/// Экран Backup: создание и восстановление резервных копий.
library backup_screen;

import 'package:flutter/material.dart';

import '../../core/design/design_system.dart';
import '../backup/backup_gateway.dart';
import '../backup/backup_operation_controller.dart';
import '../backup/backup_services_scope.dart';
import '../widgets/backup/global_backup_section.dart';
import '../widgets/backup/module_backup_section.dart';
import '../widgets/backup/restore_section.dart';

/// Экран резервного копирования.
///
/// Три независимые секции — глобальный backup, backup модуля,
/// восстановление. У каждой свой контроллер операций: запуск одной
/// операции не должен затирать сообщение о другой.
///
/// Экран ничего не знает про формат архивов и про хранилище — вся
/// работа с backup делегирована [BackupGateway] из
/// [BackupServicesScope].
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupOperationController _globalController;
  late final BackupOperationController _moduleController;
  late final BackupOperationController _globalRestoreController;
  late final BackupOperationController _moduleRestoreController;

  late BackupGateway _gateway;
  List<String> _installedModuleIds = const [];
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gateway = BackupServicesScope.gatewayOf(context);
    if (_controllersReady) return;

    // Контроллеры создаются один раз за жизнь экрана: didChangeDependencies
    // вызывается и при смене наследников, и при изменении темы.
    _controllersReady = true;
    _globalController = BackupOperationController(
      gateway: _gateway,
      fileService: BackupServicesScope.fileServiceOf(context),
    );
    _moduleController = BackupOperationController(
      gateway: _gateway,
      fileService: BackupServicesScope.fileServiceOf(context),
    );
    _globalRestoreController = BackupOperationController(
      gateway: _gateway,
      fileService: BackupServicesScope.fileServiceOf(context),
    );
    _moduleRestoreController = BackupOperationController(
      gateway: _gateway,
      fileService: BackupServicesScope.fileServiceOf(context),
    );
    _loadInstalledModules();
  }

  bool _controllersReady = false;

  Future<void> _loadInstalledModules() async {
    final ids = await _gateway.installedModuleIds();
    if (!mounted) return;
    setState(() {
      _installedModuleIds = ids;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _globalController.dispose();
    _moduleController.dispose();
    _globalRestoreController.dispose();
    _moduleRestoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: AppComponents.loadingIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Резервные копии'),
      ),
      body: ListView(
        padding: AppInsets.screenBody(context),
        children: [
          GlobalBackupSection(
            controller: _globalController,
            installedModuleIds: _installedModuleIds,
            displayNameOf: _gateway.displayNameOf,
          ),
          SizedBox(height: AppSpacing.lg),
          ModuleBackupSection(
            controller: _moduleController,
            installedModuleIds: _installedModuleIds,
            displayNameOf: _gateway.displayNameOf,
          ),
          SizedBox(height: AppSpacing.lg),
          RestoreSection(
            globalController: _globalRestoreController,
            moduleController: _moduleRestoreController,
            installedModuleIds: _installedModuleIds,
            displayNameOf: _gateway.displayNameOf,
          ),
        ],
      ),
    );
  }
}
