import 'package:flutter/material.dart';
import '../../core/constants/app_strings.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_registry.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/design/design_system.dart';

/// Боковое меню (Drawer).
///
/// Верхняя часть — постоянные пункты ядра (Главная, Настройки).
/// Нижняя часть — список модулей из ModuleRegistry.modules.
/// Меню НЕ содержит захардкоженных названий модулей — оно
/// просто отображает то, что зарегистрировано в
/// module_bootstrap.dart. Так подключение/отключение модуля
/// не требует правок этого файла.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = ModuleRegistry.modules;

    return Drawer(
      width: AppBreakpoints.drawerWidth(context),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text(AppStrings.homeTitle),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text(AppStrings.settingsTitle),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(AppRoutes.settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Модули'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(AppRoutes.modules);
              },
            ),
            if (modules.isNotEmpty) ...[
              const Divider(),
              for (final module in modules)
                _ModuleDrawerTile(module: module),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleDrawerTile extends StatelessWidget {
  final Module module;

  const _ModuleDrawerTile({required this.module});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(module.icon),
      title: Text(module.title),
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => module.buildPage(context)),
        );
      },
    );
  }
}
