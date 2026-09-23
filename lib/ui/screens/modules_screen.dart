import 'package:flutter/material.dart';
import '../../core/design/design_system.dart';
import '../widgets/app_drawer.dart';
import '../widgets/module_store/available_section.dart';
import '../widgets/module_store/installed_section.dart';
import '../widgets/module_store/update_section.dart';

/// Экран управления модулями (Module Store, Этап 12).
///
/// Три раздела — Установленные/Доступные/Обновления — как простые
/// секции одного прокручиваемого списка, а не вкладки: проще и
/// достаточно для того объёма модулей, что есть сейчас (один
/// встроенный + временный каталог из трёх записей).
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Модули')),
      drawer: const AppDrawer(),
      body: ResponsiveBuilder(
        builder: (context, layout) {
          final padding = AppBreakpoints.screenPadding(context);
          return ListView(
            padding: padding,
            children: [
              AppComponents.sectionHeader(
                context: context,
                title: 'Установленные',
              ),
              const InstalledSection(),
              SizedBox(height: AppSpacing.xl),
              AppComponents.sectionHeader(
                context: context,
                title: 'Доступные',
              ),
              const AvailableSection(),
              SizedBox(height: AppSpacing.xl),
              AppComponents.sectionHeader(
                context: context,
                title: 'Обновления',
              ),
              const UpdateSection(),
            ],
          );
        },
      ),
    );
  }
}
