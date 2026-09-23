import 'package:flutter/material.dart';
import '../../../../core/modules/module_permission.dart';
import '../../../../core/design/design_system.dart';

/// Карточка одного модуля — переиспользуется во всех трёх секциях
/// Module Store (Установленные/Доступные/Обновления). Секции сами
/// решают, что показать в state/trailingInfo и какие actions дать —
/// карточка только раскладка, без бизнес-логики.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.icon,
    required this.name,
    required this.version,
    required this.author,
    this.permissions = const [],
    this.stateLabel,
    this.trailingInfo,
    this.actions = const [],
  });

  final IconData icon;
  final String name;
  final String version;
  final String author;
  final List<ModulePermission> permissions;

  /// Например "включён" — для Установленных. null для Доступных.
  final String? stateLabel;

  /// Например "1.0.0 → 1.1.0" — только для Обновлений.
  final String? trailingInfo;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppComponents.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 24),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      'v$version · $author',
                      style: AppTypography.cardMetadata.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (stateLabel != null)
                AppComponents.statusChip(
                  context: context,
                  status: _statusFromLabel(stateLabel!),
                  label: stateLabel,
                ),
            ],
          ),
          if (trailingInfo != null) ...[
            SizedBox(height: AppSpacing.sm),
            Text(
              trailingInfo!,
              style: AppTypography.cardMetadata.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (permissions.isNotEmpty) ...[
            SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: permissions
                  .map((p) => Chip(
                        label: Text(
                          p.id,
                          style: AppTypography.chipLabel,
                        ),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          if (actions.isNotEmpty) ...[
            SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
          ],
        ],
      ),
    );
  }

  ModuleStatus _statusFromLabel(String label) {
    switch (label) {
      case 'включён':
        return ModuleStatus.enabled;
      case 'выключен':
        return ModuleStatus.disabled;
      case 'установлен':
        return ModuleStatus.installed;
      case 'удалён':
        return ModuleStatus.uninstalled;
      default:
        return ModuleStatus.installed;
    }
  }
}
