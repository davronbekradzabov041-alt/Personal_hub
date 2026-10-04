import 'package:flutter/material.dart';
import '../../../core/design/design_system.dart';
import '../../../core/navigation/app_routes.dart';

/// Active Modules Canvas — компактные живые плитки модулей.
///
/// Заменяет старую сетку из 4 больших шорткатов.
/// Показывает только Schedule и Modules (существующая функциональность).
class ActiveModulesCanvas extends StatelessWidget {
  const ActiveModulesCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = AppBreakpoints.isCompact(context);

    final modules = [
      _ModuleTile(
        icon: Icons.schedule_outlined,
        label: 'Расписание',
        subtitle: 'События и календарь',
        color: AppColors.accentAmber,
        route: AppRoutes.schedule,
      ),
      _ModuleTile(
        icon: Icons.extension_outlined,
        label: 'Модули',
        subtitle: 'Установленные и доступные',
        color: AppColors.accentIndigo,
        route: AppRoutes.modules,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Активные модули',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSpacing.space4),
        if (isCompact)
          Column(
            children: modules
                .map((m) => Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.space3),
                      child: _CompactModuleCard(module: m),
                    ))
                .toList(),
          )
        else
          Row(
            children: modules
                .map((m) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: m == modules.first ? 0 : AppSpacing.space3,
                          right: m == modules.last ? 0 : AppSpacing.space3,
                        ),
                        child: _CompactModuleCard(module: m),
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }
}

class _ModuleTile {
  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;
}

class _CompactModuleCard extends StatelessWidget {
  const _CompactModuleCard({required this.module});

  final _ModuleTile module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppComponents.featureCard(
      context: context,
      accentColor: module.color,
      onTap: () => Navigator.of(context).pushNamed(module.route),
      child: Padding(
        padding: AppInsets.cardPaddingMedium,
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(AppSpacing.space3),
              decoration: BoxDecoration(
                color: module.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadiiValues.lg),
              ),
              child: Icon(
                module.icon,
                size: 24,
                color: module.color,
              ),
            ),
            SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    module.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    module.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}