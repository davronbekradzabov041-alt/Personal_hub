import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation/app_routes.dart';
import 'core/settings/app_settings_controller.dart';
import 'core/settings/app_settings_scope.dart';
import 'core/search/global_search_service.dart';
import 'core/search/search_scope.dart';
import 'core/modules/module_manager.dart';
import 'core/modules/module_manager_scope.dart';

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
  });

  final AppSettingsController settingsController;
  final GlobalSearchService searchService;
  final ModuleManager moduleManager;

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      controller: settingsController,
      child: SearchScope(
        service: searchService,
        child: ModuleManagerScope(
          manager: moduleManager,
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

                // Стартовый экран через routes, не home (чтобы не конфликтовать с '/')
                initialRoute: AppRoutes.home,

                // Именованные маршруты — core/navigation/app_routes.dart
                routes: AppRoutes.routes,
              );
            },
          ),
        ),
      ),
    );
  }
}
