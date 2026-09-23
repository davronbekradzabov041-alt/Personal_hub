import 'package:flutter/material.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../../../core/modules/module_registry.dart';
import '../../../../core/modules/module_state.dart';
import '../../../../core/design/design_system.dart';
import 'module_action_runner.dart';
import 'module_card.dart';

/// Раздел «Установленные».
///
/// Показывает модули, для которых ModuleManager отслеживает состояние
/// installed/enabled/disabled — не просто всё, что есть в
/// ModuleRegistry (полностью удалённые модули туда не попадают, см.
/// README, раздел Этапа 12, "известное ограничение").
class InstalledSection extends StatelessWidget {
  const InstalledSection({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final installed = ModuleRegistry.modules
            .where((module) => manager.isInstalled(module.id))
            .toList();

        if (installed.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.install_mobile_outlined,
            title: 'Нет установленных модулей',
          );
        }

        return Column(
          children: installed.map((module) {
            final state = manager.stateOf(module.id)!;
            return ModuleCard(
              icon: module.icon,
              name: module.title,
              version: module.manifest.version,
              author: module.manifest.author,
              permissions: module.manifest.permissions,
              stateLabel: _stateLabel(state),
              actions: [
                AppComponents.outlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: module.buildPage),
                  ),
                  child: const Text('Открыть'),
                ),
                if (state == ModuleState.installed ||
                    state == ModuleState.disabled)
                  AppComponents.filledButton(
                    onPressed: () => runModuleAction(
                      context,
                      () => manager.enable(module.id),
                    ),
                    child: const Text('Включить'),
                  ),
                if (state == ModuleState.enabled)
                  AppComponents.outlinedButton(
                    onPressed: () => runModuleAction(
                      context,
                      () => manager.disable(module.id),
                    ),
                    child: const Text('Выключить'),
                  ),
                if (state == ModuleState.installed ||
                    state == ModuleState.disabled)
                  AppComponents.textButton(
                    onPressed: () => runModuleAction(
                      context,
                      () => manager.uninstall(module.id),
                    ),
                    child: const Text('Удалить'),
                  ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  String _stateLabel(ModuleState state) {
    switch (state) {
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
