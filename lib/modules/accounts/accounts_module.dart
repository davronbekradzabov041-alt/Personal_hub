import 'package:flutter/material.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_api.dart';
import '../../core/modules/module_data_migration.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_permission.dart';
import '../../core/modules/module_state.dart';

/// Каркас модуля Accounts — первый полноценный функциональный модуль.
///
/// Этап 10.1: только минимальный скелет для проверки регистрации,
/// lifecycle и интеграции с ModuleManager. CRUD, репозитории,
/// категории и UI реализуются в следующих подэтапах.
class AccountsModule extends Module {
  static const ModuleManifest _manifest = ModuleManifest(
    id: 'accounts',
    name: 'Аккаунты',
    version: '0.1.0',
    apiVersion: kCoreModuleApiVersion,
    author: 'Personal Hub',
    description: 'Управление аккаунтами игр и профилями (каркас Этапа 10.1).',
    schemaVersion: 1,
    permissions: [ModulePermission.coreSearch],
  );

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.account_circle_outlined;

  @override
  int get order => 50;

  @override
  List<ModuleDataMigration> get dataMigrations => const <ModuleDataMigration>[];

  @override
  Future<void> onInstall(ModuleApi api) async {
    // Миграция (если будет) запускается платформой через runPendingMigrations.
  }

  @override
  Future<void> onEnable(ModuleApi api) async {
    // SearchProvider будет добавлен в 10.3.
  }

  @override
  Future<void> onDisable(ModuleApi api) async {
    // Отписка от поиска будет добавлена в 10.3.
  }

  @override
  Future<void> onUninstall(ModuleApi api) async {
    // Защитный дубль — см. ExampleModule.
  }

  @override
  Widget buildPage(BuildContext context) => _AccountsModulePage(module: this);
}

/// Страница-заглушка модуля Accounts.
class _AccountsModulePage extends StatefulWidget {
  const _AccountsModulePage({required this.module});
  final AccountsModule module;

  @override
  State<_AccountsModulePage> createState() => _AccountsModulePageState();
}

class _AccountsModulePageState extends State<_AccountsModulePage> {
  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);
    final id = widget.module.id;

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final state = manager.stateOf(id);

        return Scaffold(
          appBar: AppBar(title: Text(widget.module.title)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Состояние модуля: ${_stateLabel(state)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Версия ${widget.module.manifest.version} · '
                'API ${widget.module.manifest.apiVersion} · '
                'Schema ${widget.module.manifest.schemaVersion}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Модуль Accounts (Этап 10.1) — каркас для проверки '
                'регистрации, lifecycle и интеграции с ModuleManager.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Функциональность: CRUD аккаунтов, игровые профили, '
                'категории, поиск, Home-секция — реализуются в 10.2–10.8.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _stateLabel(ModuleState? state) {
    switch (state) {
      case null:
        return 'не установлен';
      case ModuleState.installed:
        return 'установлен';
      case ModuleState.enabled:
        return 'включён';
      case ModuleState.disabled:
        return 'выключен';
      case ModuleState.uninstalled:
        return 'удалён';
    }
  }
}