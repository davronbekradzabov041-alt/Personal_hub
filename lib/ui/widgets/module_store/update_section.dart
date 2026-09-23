import 'package:flutter/material.dart';
import '../../../../core/modules/external/external_module_adapter.dart';
import '../../../../core/modules/external/in_memory_module_catalog.dart';
import '../../../../core/modules/external/manifest_parser.dart';
import '../../../../core/modules/module_manager.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../../../core/modules/module_manifest.dart';
import '../../../../core/modules/module_registry.dart';
import '../../../../core/design/design_system.dart';
import 'module_action_runner.dart';
import 'module_card.dart';

/// Раздел «Обновления».
///
/// Для каждой записи каталога, которая УЖЕ установлена: если версия
/// в ModuleRegistry отличается от entry.latestManifestJson — считаем,
/// что доступно обновление. Обновление выполняется через уже
/// существующий ModuleManager.update() (Этап 8) — не реализует
/// собственную логику сравнения/подмены версий заново.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);
    final parser = ManifestParser();

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final updates = <(ModuleCatalogEntry, ModuleManifest, ModuleManifest)>[];

        for (final entry in InMemoryModuleCatalog.entries) {
          if (!manager.isInstalled(entry.id)) continue;

          final installedModule = ModuleRegistry.get(entry.id);
          if (installedModule == null) continue;

          final latest = parser.parse(entry.latestManifestJson);
          if (latest.version != installedModule.manifest.version) {
            updates.add((entry, installedModule.manifest, latest));
          }
        }

        if (updates.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.system_update_alt_outlined,
            title: 'Обновлений нет',
            subtitle: 'Все установленные модули актуальны',
          );
        }

        return Column(
          children: updates.map((u) {
            final (entry, current, latest) = u;
            return ModuleCard(
              icon: Icons.extension_outlined,
              name: latest.name,
              version: current.version,
              author: latest.author,
              permissions: latest.permissions,
              trailingInfo: 'Текущая ${current.version} → новая ${latest.version}',
              actions: [
                AppComponents.filledButton(
                  onPressed: () => _update(context, manager, latest),
                  child: const Text('Обновить'),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  void _update(
    BuildContext context,
    ModuleManager manager,
    ModuleManifest latestManifest,
  ) {
    final adapter = ExternalModuleAdapter(latestManifest);
    runModuleAction(context, () => manager.update(adapter));
  }
}
