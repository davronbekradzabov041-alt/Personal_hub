import 'package:flutter/material.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_api.dart';
import '../../core/modules/module_data_migration.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_permission.dart';
import '../../core/modules/module_state.dart';
import 'account_repository.dart';
import 'accounts_search_provider.dart';
import 'category_repository.dart';
import 'game_repository.dart';

/// Модуль Accounts — управление аккаунтами игр и профилями.
///
/// Этап 10.3: интеграция с lifecycle и поиском.
class AccountsModule extends Module {
  static const ModuleManifest _manifest = ModuleManifest(
    id: 'accounts',
    name: 'Аккаунты',
    version: '0.1.0',
    apiVersion: kCoreModuleApiVersion,
    author: 'Personal Hub',
    description: 'Управление аккаунтами игр и профилями (Этап 10.3).',
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

  AccountsSearchProvider? _searchProvider;

  @override
  Future<void> onInstall(ModuleApi api) async {
    // Миграция (если будет) запускается платформой через runPendingMigrations.
  }

  @override
  Future<void> onEnable(ModuleApi api) async {
    final provider = AccountsSearchProvider(
      AccountRepository(api.storage),
      GameRepository(api.storage, AccountRepository(api.storage), CategoryRepository(api.storage)),
      CategoryRepository(api.storage),
    );
    _searchProvider = provider;
    api.registerSearchProvider(provider);
  }

  @override
  Future<void> onDisable(ModuleApi api) async {
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Future<void> onUninstall(ModuleApi api) async {
    // Защитный дубль — см. ExampleModule и ScheduleModule.
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Widget buildPage(BuildContext context) => _AccountsModulePage(module: this);
}

/// Страница модуля Accounts.
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
                'Модуль Accounts (Этап 10.3) — интеграция с lifecycle и поиском.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Функциональность: CRUD аккаунтов, игровые профили, '
                'категории, поиск, Home-секция — реализуются в 10.4–10.8.',
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