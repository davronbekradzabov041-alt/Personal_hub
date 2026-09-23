import 'package:flutter/material.dart';
import '../../../../core/modules/external/external_module_adapter.dart';
import '../../../../core/modules/external/in_memory_module_catalog.dart';
import '../../../../core/modules/external/manifest_parser.dart';
import '../../../../core/modules/external/module_import_result.dart';
import '../../../../core/modules/module_manager.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../../../core/modules/module_registry.dart';
import '../../../../core/design/design_system.dart';
import 'module_action_runner.dart';
import 'module_card.dart';

/// Раздел «Доступные».
///
/// Источник — InMemoryModuleCatalog (Этап 12), НЕ реальные файлы.
/// Показываются только записи, чей id ещё не известен ModuleRegistry
/// — если id уже занят (как у встроенного 'example'), запись не
/// показывается здесь вовсе, потому что установка всё равно будет
/// отклонена на уровне ManifestValidator/ModuleRegistry: нет смысла
/// предлагать действие, которое гарантированно провалится.
class AvailableSection extends StatelessWidget {
  const AvailableSection({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);
    final parser = ManifestParser();

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final available = InMemoryModuleCatalog.entries
            .where((entry) => !ModuleRegistry.contains(entry.id))
            .toList();

        if (available.isEmpty) {
          return AppComponents.emptyState(
            context: context,
            icon: Icons.check_circle_outline,
            title: 'Все модули из каталога уже установлены',
          );
        }

        return Column(
          children: available.map((entry) {
            // Только для отображения карточки — структурный разбор,
            // без валидации существующих id (это происходит заново,
            // отдельно, в момент реальной установки ниже).
            final manifest = parser.parse(entry.installManifestJson);

            return ModuleCard(
              icon: Icons.extension_outlined,
              name: manifest.name,
              version: manifest.version,
              author: manifest.author,
              permissions: manifest.permissions,
              actions: [
                AppComponents.filledButton(
                  onPressed: () => _install(context, manager, entry),
                  child: const Text('Установить'),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  void _install(
    BuildContext context,
    ModuleManager manager,
    ModuleCatalogEntry entry,
  ) {
    final existingIds = ModuleRegistry.modules.map((m) => m.id).toSet();

    final result = ModuleImportResult.from(
      manifestJson: entry.installManifestJson,
      existingModuleIds: existingIds,
    );

    if (!result.isSuccess) {
      showModuleErrors(context, result.errors);
      return;
    }

    final adapter = ExternalModuleAdapter(result.package!.manifest);

    runModuleAction(context, () async {
      ModuleRegistry.register(adapter); // повторная защита на уровне реестра
      await manager.install(adapter.id);
    });
  }
}
