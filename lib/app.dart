import 'package:flutter/material.dart';
import 'core/navigation/app_shell.dart';
import 'core/navigation/app_routes.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/settings/app_settings_scope.dart';
import 'core/search/global_search_service.dart';
import 'core/search/search_scope.dart';
import 'core/modules/module_manager.dart';
import 'core/modules/module_manager_scope.dart';
import 'core/modules/module_state_persistence.dart';
import 'core/modules/module_state_persistence_scope.dart';
import 'core/theme/app_theme.dart';
import 'ui/backup/backup_file_service.dart';
import 'ui/backup/backup_gateway.dart';
import 'ui/backup/backup_services_scope.dart';

/// Корневой виджет приложения.
///
/// Отвечает только за сборку MaterialApp: подключает тему
/// (core/theme), таблицу маршрутов (core/navigation), настройки
/// (AppSettingsScope), глобальный поиск (SearchScope) и менеджер
/// модулей (ModuleManagerScope, Этап 10), чтобы любой экран — в том
/// числе страница самого модуля — мог получить к ним доступ через
/// context.
class PersonalHubApp extends StatelessWidget {
  const PersonalHubApp({
    super.key,
    required this.settingsController,
    required this.searchService,
    required this.moduleManager,
    required this.backupGateway,
    required this.statePersistence,
  });

  final AppSettingsController settingsController;
  final GlobalSearchService searchService;
  final ModuleManager moduleManager;

  /// Операции backup для UI. Передаётся снаружи, чтобы экран не
  /// собирал core-менеджеры сам, а тесты подставляли фейки.
  final BackupGateway backupGateway;

  /// Persist-слой состояния модулей — тот же экземпляр, что подписан
  /// на ModuleManager в main.dart. Передаётся в дерево, чтобы
  /// операции install/enable/disable/uninstall дожидались записи
  /// состояния (см. ModuleStatePersistence.runAndFlush).
  final ModuleStatePersistence statePersistence;

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      controller: settingsController,
      child: SearchScope(
        service: searchService,
        child: ModuleManagerScope(
          manager: moduleManager,
          child: ModuleStatePersistenceScope(
            persistence: statePersistence,
            child: BackupServicesScope(
              gateway: backupGateway,
              fileService: const PickerBackupFileService(),
              child: ListenableBuilder(
                listenable: settingsController,
                builder: (context, _) {
                  return MaterialApp(
                    title: 'Personal Hub',
                    debugShowCheckedModeBanner: false,

                    // Тема оформления (Material 3, светлая/тёмная) — core/theme/app_theme.dart
                    theme: AppTheme.light,
                    darkTheme: AppTheme.dark,
                    // Управляется настройками пользователя (Этап 4), а не системой напрямую.
                    themeMode: settingsController.themeMode,

                    // Navigation Shell (Stage C1) — responsive navigation frame
                    home: const AppShell(),

                    // Именованные маршруты (AppRoutes). Без onGenerateRoute
                    // pushNamed(AppRoutes.settings) не находит ничего и
                    // роняет навигатор.
                    onGenerateRoute: AppRoutes.onGenerateRoute,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
